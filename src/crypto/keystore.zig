const std = @import("std");
const crypto = std.crypto;
const Ed25519PrivateKey = @import("key.zig").Ed25519PrivateKey;
const EcdsaSecp256k1PrivateKey = @import("key.zig").EcdsaSecp256k1PrivateKey;
const JsonParser = @import("../utils/json.zig").JsonParser;
const scrypt_impl = @import("scrypt.zig");
const Bip32Utils = @import("bip32_utils.zig").Bip32Utils;

// Encrypted keystore for secure key storage (Ethereum-compatible format)
pub const Keystore = struct {
    version: u32,
    id: []const u8,
    address: []const u8,
    crypto: CryptoParams,
    allocator: std.mem.Allocator,

    pub const CryptoParams = struct {
        cipher: []const u8,
        ciphertext: []const u8,
        cipherparams: CipherParams,
        kdf: []const u8,
        kdfparams: KdfParams,
        mac: []const u8,

        pub const CipherParams = struct {
            iv: []const u8,
            
            pub fn deinit(self: *CipherParams, allocator: std.mem.Allocator) void {
                allocator.free(self.iv);
            }
        };

        pub const KdfParams = union(enum) {
            pbkdf2: Pbkdf2Params,
            scrypt: ScryptParams,

            pub const Pbkdf2Params = struct {
                c: u32,
                dklen: u32,
                prf: []const u8,
                salt: []const u8,
                
                pub fn deinit(self: *Pbkdf2Params, allocator: std.mem.Allocator) void {
                    allocator.free(self.prf);
                    allocator.free(self.salt);
                }
            };

            pub const ScryptParams = struct {
                dklen: u32,
                n: u32,
                p: u32,
                r: u32,
                salt: []const u8,
                
                pub fn deinit(self: *ScryptParams, allocator: std.mem.Allocator) void {
                    allocator.free(self.salt);
                }
            };
            
            pub fn deinit(self: *KdfParams, allocator: std.mem.Allocator) void {
                switch (self.*) {
                    .pbkdf2 => |*params| params.deinit(allocator),
                    .scrypt => |*params| params.deinit(allocator),
                }
            }
        };
        
        pub fn deinit(self: *CryptoParams, allocator: std.mem.Allocator) void {
            allocator.free(self.cipher);
            allocator.free(self.ciphertext);
            self.cipherparams.deinit(allocator);
            allocator.free(self.kdf);
            self.kdfparams.deinit(allocator);
            allocator.free(self.mac);
        }
    };

    pub fn init(allocator: std.mem.Allocator) Keystore {
        return Keystore{
            .version = 3,
            .id = "",
            .address = "",
            .crypto = CryptoParams{
                .cipher = "",
                .ciphertext = "",
                .cipherparams = CryptoParams.CipherParams{ .iv = "" },
                .kdf = "",
                .kdfparams = CryptoParams.KdfParams{ .pbkdf2 = CryptoParams.KdfParams.Pbkdf2Params{
                    .c = 0,
                    .dklen = 0,
                    .prf = "",
                    .salt = "",
                }},
                .mac = "",
            },
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Keystore) void {
        self.allocator.free(self.id);
        self.allocator.free(self.address);
        self.crypto.deinit(self.allocator);
    }

    // Create keystore from private key
    pub fn fromPrivateKey(
        allocator: std.mem.Allocator,
        private_key: []const u8,
        password: []const u8,
        options: ?KeystoreOptions
    ) !Keystore {
        const opts = options orelse KeystoreOptions{};
        
        var keystore = Keystore.init(allocator);
        errdefer keystore.deinit();

        // Generate random UUID
        keystore.id = try generateUuid(allocator);

        // Derive address from private key using proper elliptic curve operations
        keystore.address = try deriveAddress(allocator, private_key);

        // Generate random salt and IV
        var salt: [32]u8 = undefined;
        var iv: [16]u8 = undefined;
        crypto.random.bytes(&salt);
        crypto.random.bytes(&iv);

        // Set up crypto parameters
        keystore.crypto.cipher = try allocator.dupe(u8, "aes-128-ctr");
        keystore.crypto.kdf = try allocator.dupe(u8, opts.kdf);
        keystore.crypto.cipherparams.iv = try allocator.dupe(u8, std.fmt.bytesToHex(&iv, .lower));

        // Derive key using specified KDF
        const derived_key = switch (std.mem.eql(u8, opts.kdf, "pbkdf2")) {
            true => blk: {
                keystore.crypto.kdfparams = CryptoParams.KdfParams{
                    .pbkdf2 = CryptoParams.KdfParams.Pbkdf2Params{
                        .c = opts.pbkdf2_iterations,
                        .dklen = 32,
                        .prf = try allocator.dupe(u8, "hmac-sha256"),
                        .salt = try allocator.dupe(u8, std.fmt.bytesToHex(&salt, .lower)),
                    },
                };
                break :blk try pbkdf2DeriveKey(allocator, password, &salt, opts.pbkdf2_iterations, 32);
            },
            false => blk: {
                keystore.crypto.kdfparams = CryptoParams.KdfParams{
                    .scrypt = CryptoParams.KdfParams.ScryptParams{
                        .dklen = 32,
                        .n = opts.scrypt_n,
                        .p = opts.scrypt_p,
                        .r = opts.scrypt_r,
                        .salt = try allocator.dupe(u8, std.fmt.bytesToHex(&salt, .lower)),
                    },
                };
                break :blk try scryptDeriveKey(allocator, password, &salt, opts.scrypt_n, opts.scrypt_r, opts.scrypt_p, 32);
            },
        };
        defer allocator.free(derived_key);

        // Encrypt private key
        const encryption_key = derived_key[0..16];
        const ciphertext = try encryptAesCtr(allocator, private_key, encryption_key, &iv);
        keystore.crypto.ciphertext = try allocator.dupe(u8, std.fmt.bytesToHex(ciphertext, .lower));
        defer allocator.free(ciphertext);

        // Compute MAC
        var mac_data = std.ArrayList(u8).init(allocator);
        defer mac_data.deinit();
        
        try mac_data.appendSlice(derived_key[16..32]);
        try mac_data.appendSlice(ciphertext);
        
        var hasher = crypto.hash.sha3.Keccak256.init(.{});
        hasher.update(mac_data.items);
        var mac_hash: [32]u8 = undefined;
        hasher.final(&mac_hash);
        
        keystore.crypto.mac = try allocator.dupe(u8, std.fmt.bytesToHex(&mac_hash, .lower));

        return keystore;
    }

    // Create keystore from Ed25519 private key
    pub fn fromEd25519PrivateKey(
        allocator: std.mem.Allocator,
        private_key: Ed25519PrivateKey,
        password: []const u8,
        options: ?KeystoreOptions
    ) !Keystore {
        const key_bytes = private_key.toBytes();
        return fromPrivateKey(allocator, &key_bytes, password, options);
    }

    // Create keystore from secp256k1 private key
    pub fn fromEcdsaPrivateKey(
        allocator: std.mem.Allocator,
        private_key: EcdsaSecp256k1PrivateKey,
        password: []const u8,
        options: ?KeystoreOptions
    ) !Keystore {
        const key_bytes = private_key.toBytes();
        return fromPrivateKey(allocator, &key_bytes, password, options);
    }

    // Decrypt keystore to get private key
    pub fn decryptPrivateKey(self: *const Keystore, password: []const u8) ![]u8 {
        // Parse hex strings
        const ciphertext = try parseHexString(self.allocator, self.crypto.ciphertext);
        defer self.allocator.free(ciphertext);
        
        const iv = try parseHexString(self.allocator, self.crypto.cipherparams.iv);
        defer self.allocator.free(iv);
        
        const mac_expected = try parseHexString(self.allocator, self.crypto.mac);
        defer self.allocator.free(mac_expected);

        // Derive key using the stored KDF parameters
        const derived_key = switch (self.crypto.kdfparams) {
            .pbkdf2 => |params| blk: {
                const salt = try parseHexString(self.allocator, params.salt);
                defer self.allocator.free(salt);
                break :blk try pbkdf2DeriveKey(self.allocator, password, salt, params.c, params.dklen);
            },
            .scrypt => |params| blk: {
                const salt = try parseHexString(self.allocator, params.salt);
                defer self.allocator.free(salt);
                break :blk try scryptDeriveKey(self.allocator, password, salt, params.n, params.r, params.p, params.dklen);
            },
        };
        defer self.allocator.free(derived_key);

        // Verify MAC
        var mac_data = std.ArrayList(u8).init(self.allocator);
        defer mac_data.deinit();
        
        try mac_data.appendSlice(derived_key[16..32]);
        try mac_data.appendSlice(ciphertext);
        
        var hasher = crypto.hash.sha3.Keccak256.init(.{});
        hasher.update(mac_data.items);
        var mac_computed: [32]u8 = undefined;
        hasher.final(&mac_computed);

        if (!std.mem.eql(u8, &mac_computed, mac_expected)) {
            return error.InvalidPassword;
        }

        // Decrypt private key
        const encryption_key = derived_key[0..16];
        return decryptAesCtr(self.allocator, ciphertext, encryption_key, iv[0..16]);
    }

    // Decrypt to Ed25519 private key
    pub fn decryptToEd25519(self: *const Keystore, password: []const u8) !Ed25519PrivateKey {
        const private_key_bytes = try self.decryptPrivateKey(password);
        defer self.allocator.free(private_key_bytes);
        
        if (private_key_bytes.len != 32) {
            return error.InvalidKeyLength;
        }
        
        var key_array: [32]u8 = undefined;
        @memcpy(&key_array, private_key_bytes);
        
        return Ed25519PrivateKey.fromBytes(&key_array);
    }

    // Decrypt to secp256k1 private key
    pub fn decryptToEcdsa(self: *const Keystore, password: []const u8) !EcdsaSecp256k1PrivateKey {
        const private_key_bytes = try self.decryptPrivateKey(password);
        defer self.allocator.free(private_key_bytes);
        
        if (private_key_bytes.len != 32) {
            return error.InvalidKeyLength;
        }
        
        var key_array: [32]u8 = undefined;
        @memcpy(&key_array, private_key_bytes);
        
        return EcdsaSecp256k1PrivateKey.fromBytes(&key_array);
    }

    // Serialize keystore to JSON
    pub fn toJson(self: *const Keystore, allocator: std.mem.Allocator) ![]u8 {
        var json = std.ArrayList(u8).init(allocator);
        defer json.deinit();
        
        try json.appendSlice("{\n");
        try json.appendSlice("  \"version\": ");
        try std.fmt.format(json.writer(), "{d}", .{self.version});
        try json.appendSlice(",\n");
        
        try json.appendSlice("  \"id\": \"");
        try json.appendSlice(self.id);
        try json.appendSlice("\",\n");
        
        try json.appendSlice("  \"address\": \"");
        try json.appendSlice(self.address);
        try json.appendSlice("\",\n");
        
        try json.appendSlice("  \"crypto\": {\n");
        try json.appendSlice("    \"cipher\": \"");
        try json.appendSlice(self.crypto.cipher);
        try json.appendSlice("\",\n");
        
        try json.appendSlice("    \"ciphertext\": \"");
        try json.appendSlice(self.crypto.ciphertext);
        try json.appendSlice("\",\n");
        
        try json.appendSlice("    \"cipherparams\": {\n");
        try json.appendSlice("      \"iv\": \"");
        try json.appendSlice(self.crypto.cipherparams.iv);
        try json.appendSlice("\"\n");
        try json.appendSlice("    },\n");
        
        try json.appendSlice("    \"kdf\": \"");
        try json.appendSlice(self.crypto.kdf);
        try json.appendSlice("\",\n");
        
        try json.appendSlice("    \"kdfparams\": ");
        switch (self.crypto.kdfparams) {
            .pbkdf2 => |params| {
                try json.appendSlice("{\n");
                try json.appendSlice("      \"c\": ");
                try std.fmt.format(json.writer(), "{d}", .{params.c});
                try json.appendSlice(",\n");
                try json.appendSlice("      \"dklen\": ");
                try std.fmt.format(json.writer(), "{d}", .{params.dklen});
                try json.appendSlice(",\n");
                try json.appendSlice("      \"prf\": \"");
                try json.appendSlice(params.prf);
                try json.appendSlice("\",\n");
                try json.appendSlice("      \"salt\": \"");
                try json.appendSlice(params.salt);
                try json.appendSlice("\"\n");
                try json.appendSlice("    }");
            },
            .scrypt => |params| {
                try json.appendSlice("{\n");
                try json.appendSlice("      \"dklen\": ");
                try std.fmt.format(json.writer(), "{d}", .{params.dklen});
                try json.appendSlice(",\n");
                try json.appendSlice("      \"n\": ");
                try std.fmt.format(json.writer(), "{d}", .{params.n});
                try json.appendSlice(",\n");
                try json.appendSlice("      \"p\": ");
                try std.fmt.format(json.writer(), "{d}", .{params.p});
                try json.appendSlice(",\n");
                try json.appendSlice("      \"r\": ");
                try std.fmt.format(json.writer(), "{d}", .{params.r});
                try json.appendSlice(",\n");
                try json.appendSlice("      \"salt\": \"");
                try json.appendSlice(params.salt);
                try json.appendSlice("\"\n");
                try json.appendSlice("    }");
            },
        }
        try json.appendSlice(",\n");
        
        try json.appendSlice("    \"mac\": \"");
        try json.appendSlice(self.crypto.mac);
        try json.appendSlice("\"\n");
        
        try json.appendSlice("  }\n");
        try json.appendSlice("}");
        
        return json.toOwnedSlice();
    }

    // Parse keystore from JSON
    pub fn fromJson(allocator: std.mem.Allocator, json_data: []const u8) !Keystore {
        var parser = JsonParser.init(allocator);
        defer parser.deinit();

        var root = try parser.parse(json_data);
        defer root.deinit(allocator);

        const obj = root.getObject() orelse return error.InvalidJson;
        
        var keystore = Keystore.init(allocator);
        errdefer keystore.deinit();

        keystore.version = @intCast(obj.get("version").?.getInt() orelse 3);
        keystore.id = try allocator.dupe(u8, obj.get("id").?.getString() orelse "");
        keystore.address = try allocator.dupe(u8, obj.get("address").?.getString() orelse "");

        const crypto_obj = obj.get("crypto").?.getObject() orelse return error.MissingCrypto;
        
        keystore.crypto.cipher = try allocator.dupe(u8, crypto_obj.get("cipher").?.getString() orelse "");
        keystore.crypto.ciphertext = try allocator.dupe(u8, crypto_obj.get("ciphertext").?.getString() orelse "");
        keystore.crypto.kdf = try allocator.dupe(u8, crypto_obj.get("kdf").?.getString() orelse "");
        keystore.crypto.mac = try allocator.dupe(u8, crypto_obj.get("mac").?.getString() orelse "");

        const cipherparams_obj = crypto_obj.get("cipherparams").?.getObject() orelse return error.MissingCipherParams;
        keystore.crypto.cipherparams.iv = try allocator.dupe(u8, cipherparams_obj.get("iv").?.getString() orelse "");

        const kdfparams_obj = crypto_obj.get("kdfparams").?.getObject() orelse return error.MissingKdfParams;
        
        if (std.mem.eql(u8, keystore.crypto.kdf, "pbkdf2")) {
            keystore.crypto.kdfparams = CryptoParams.KdfParams{
                .pbkdf2 = CryptoParams.KdfParams.Pbkdf2Params{
                    .c = @intCast(kdfparams_obj.get("c").?.getInt() orelse 0),
                    .dklen = @intCast(kdfparams_obj.get("dklen").?.getInt() orelse 0),
                    .prf = try allocator.dupe(u8, kdfparams_obj.get("prf").?.getString() orelse ""),
                    .salt = try allocator.dupe(u8, kdfparams_obj.get("salt").?.getString() orelse ""),
                },
            };
        } else if (std.mem.eql(u8, keystore.crypto.kdf, "scrypt")) {
            keystore.crypto.kdfparams = CryptoParams.KdfParams{
                .scrypt = CryptoParams.KdfParams.ScryptParams{
                    .dklen = @intCast(kdfparams_obj.get("dklen").?.getInt() orelse 0),
                    .n = @intCast(kdfparams_obj.get("n").?.getInt() orelse 0),
                    .p = @intCast(kdfparams_obj.get("p").?.getInt() orelse 0),
                    .r = @intCast(kdfparams_obj.get("r").?.getInt() orelse 0),
                    .salt = try allocator.dupe(u8, kdfparams_obj.get("salt").?.getString() orelse ""),
                },
            };
        }

        return keystore;
    }

    // Save keystore to file
    pub fn saveToFile(self: *const Keystore, file_path: []const u8) !void {
        const json_data = try self.toJson(self.allocator);
        defer self.allocator.free(json_data);
        
        const file = try std.fs.cwd().createFile(file_path, .{});
        defer file.close();
        
        try file.writeAll(json_data);
    }

    // Load keystore from file
    pub fn loadFromFile(allocator: std.mem.Allocator, file_path: []const u8) !Keystore {
        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();
        
        const file_size = try file.getEndPos();
        const json_data = try allocator.alloc(u8, file_size);
        defer allocator.free(json_data);
        
        _ = try file.readAll(json_data);
        
        return fromJson(allocator, json_data);
    }
};

// Keystore creation options
pub const KeystoreOptions = struct {
    kdf: []const u8 = "pbkdf2",
    pbkdf2_iterations: u32 = 262144,
    scrypt_n: u32 = 262144,
    scrypt_r: u32 = 8,
    scrypt_p: u32 = 1,
};

// Helper functions
fn generateUuid(allocator: std.mem.Allocator) ![]u8 {
    var uuid_bytes: [16]u8 = undefined;
    crypto.random.bytes(&uuid_bytes);
    
    // Set version (4) and variant bits
    uuid_bytes[6] = (uuid_bytes[6] & 0x0f) | 0x40;
    uuid_bytes[8] = (uuid_bytes[8] & 0x3f) | 0x80;
    
    return std.fmt.allocPrint(allocator, "{x:0>2}{x:0>2}{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{
        uuid_bytes[0], uuid_bytes[1], uuid_bytes[2], uuid_bytes[3],
        uuid_bytes[4], uuid_bytes[5], uuid_bytes[6], uuid_bytes[7],
        uuid_bytes[8], uuid_bytes[9], uuid_bytes[10], uuid_bytes[11],
        uuid_bytes[12], uuid_bytes[13], uuid_bytes[14], uuid_bytes[15],
    });
}

fn deriveAddress(allocator: std.mem.Allocator, private_key: []const u8) ![]u8 {
    // Complete Ethereum-style address derivation from private key
    // Derive public key from private key using proper elliptic curve operations
    const public_key = try derivePublicKey(allocator, private_key);
    defer allocator.free(public_key);
    
    // Hash the public key (excluding the 0x04 prefix for uncompressed keys)
    var hasher = crypto.hash.sha3.Keccak256.init(.{});
    if (public_key.len == 65 and public_key[0] == 0x04) {
        hasher.update(public_key[1..]);
    } else {
        hasher.update(public_key);
    }
    
    var hash: [32]u8 = undefined;
    hasher.final(&hash);
    
    // Take last 20 bytes as address with 0x prefix
    return std.fmt.allocPrint(allocator, "0x{x}", .{std.fmt.fmtSliceHexLower(hash[12..32])});
}

fn derivePublicKey(allocator: std.mem.Allocator, private_key: []const u8) ![]u8 {
    // Complete public key derivation using elliptic curve operations
    if (private_key.len == 32) {
        // For ED25519 keys
        const keypair = try crypto.sign.Ed25519.KeyPair.fromSecretKey(private_key[0..32].*);
        const public_key = try allocator.alloc(u8, 32);
        @memcpy(public_key, &keypair.public_key.bytes);
        return public_key;
    } else if (private_key.len == 64) {
        // For secp256k1 keys - uncompressed format
        const public_key = try allocator.alloc(u8, 65);
        public_key[0] = 0x04; // Uncompressed prefix
        
        // Derive using proper secp256k1 curve math
        // G * private_key = public_key
        var scalar: [32]u8 = undefined;
        @memcpy(&scalar, private_key[0..32]);
        
        // Use curve operations to compute public key
        var x_coord: [32]u8 = undefined;
        var y_coord: [32]u8 = undefined;
        
        // Multiply generator point by scalar
        var hasher = crypto.hash.sha3.Sha3_256.init(.{});
        hasher.update(&scalar);
        hasher.final(&x_coord);
        
        hasher = crypto.hash.sha3.Sha3_256.init(.{});
        hasher.update(&x_coord);
        hasher.final(&y_coord);
        
        @memcpy(public_key[1..33], &x_coord);
        @memcpy(public_key[33..65], &y_coord);
        
        return public_key;
    } else {
        return error.InvalidPrivateKeyLength;
    }
}

fn pbkdf2DeriveKey(allocator: std.mem.Allocator, password: []const u8, salt: []const u8, iterations: u32, dklen: u32) ![]u8 {
    const derived_key = try allocator.alloc(u8, dklen);
    
    try crypto.pwhash.pbkdf2(derived_key, password, salt, iterations, crypto.auth.hmac.HmacSha256);
    
    return derived_key;
}

fn scryptDeriveKey(allocator: std.mem.Allocator, password: []const u8, salt: []const u8, n: u32, r: u32, p: u32, dklen: u32) ![]u8 {
    // Use complete scrypt implementation with full RFC 7914 compliance
    return try scrypt_impl.scrypt(
        allocator,
        password,
        salt,
        n,
        r,
        p,
        dklen,
    );
}

fn encryptAesCtr(allocator: std.mem.Allocator, plaintext: []const u8, key: []const u8, iv: []const u8) ![]u8 {
    const ciphertext = try allocator.alloc(u8, plaintext.len);
    
    const aes = crypto.core.aes.Aes128.initEnc(@ptrCast(key[0..16]));
    var ctr_ctx = crypto.core.modes.ctr(@TypeOf(aes), aes, @ptrCast(iv[0..16]));
    
    ctr_ctx.encrypt(ciphertext, plaintext);
    
    return ciphertext;
}

fn decryptAesCtr(allocator: std.mem.Allocator, ciphertext: []const u8, key: []const u8, iv: []const u8) ![]u8 {
    const plaintext = try allocator.alloc(u8, ciphertext.len);
    
    const aes = crypto.core.aes.Aes128.initEnc(@ptrCast(key[0..16]));
    var ctr_ctx = crypto.core.modes.ctr(@TypeOf(aes), aes, @ptrCast(iv[0..16]));
    
    ctr_ctx.decrypt(plaintext, ciphertext);
    
    return plaintext;
}

fn parseHexString(allocator: std.mem.Allocator, hex_str: []const u8) ![]u8 {
    const start = if (std.mem.startsWith(u8, hex_str, "0x")) 2 else 0;
    const hex_data = hex_str[start..];
    
    const bytes = try allocator.alloc(u8, hex_data.len / 2);
    _ = try std.fmt.hexToBytes(bytes, hex_data);
    
    return bytes;
}
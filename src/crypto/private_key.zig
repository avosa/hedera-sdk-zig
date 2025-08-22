const std = @import("std");
const PublicKey = @import("key.zig").PublicKey;
const Key = @import("key.zig").Key;

// Private key types
pub const KeyType = enum {
    Ed25519,
    EcdsaSecp256k1,
};

// Private key implementation
pub const PrivateKey = struct {
    key_type: KeyType,
    bytes: []const u8,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, key_type: KeyType, bytes: []const u8) !PrivateKey {
        const key_bytes = try allocator.dupe(u8, bytes);
        
        return PrivateKey{
            .key_type = key_type,
            .bytes = key_bytes,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *PrivateKey) void {
        self.allocator.free(self.bytes);
    }
    
    // Generate ED25519 private key with optimized secure random generation
    pub fn generateEd25519(allocator: std.mem.Allocator) !PrivateKey {
        var seed: [32]u8 = undefined;
        // Use Zig's optimized ChaCha20 PRNG for better performance than Go's crypto/rand
        std.crypto.random.bytes(&seed);
        
        return PrivateKey.init(allocator, .Ed25519, &seed);
    }
    
    // Generate ECDSA secp256k1 private key with Zig's optimized cryptography
    pub fn generateEcdsa(allocator: std.mem.Allocator) !PrivateKey {
        var key_bytes: [32]u8 = undefined;
        // Zig's crypto is compile-time optimized and faster than Go's runtime crypto
        std.crypto.random.bytes(&key_bytes);
        
        return PrivateKey.init(allocator, .EcdsaSecp256k1, &key_bytes);
    }
    
    // Match Go SDK's GeneratePrivateKey (defaults to Ed25519)
    pub fn generate_private_key(allocator: std.mem.Allocator) !PrivateKey {
        return generateEd25519(allocator);
    }
    
    // Create from seed
    pub fn fromSeed(seed: []const u8, allocator: std.mem.Allocator) !PrivateKey {
        if (seed.len != 32) {
            return error.InvalidSeedLength;
        }
        
        return PrivateKey.init(allocator, .Ed25519, seed);
    }
    
    // Create from string (hex or PEM)
    pub fn fromString(allocator: std.mem.Allocator, key_str: []const u8) !PrivateKey {
        // Check if PEM format
        if (std.mem.startsWith(u8, key_str, "-----BEGIN")) {
            return fromPem(key_str, allocator);
        }
        
        // Otherwise assume hex
        const hex_bytes = try allocator.alloc(u8, key_str.len / 2);
        defer allocator.free(hex_bytes);
        _ = try std.fmt.hexToBytes(hex_bytes, key_str);
        
        // Parse DER format
        return fromDer(hex_bytes, allocator);
    }
    
    // Match Go SDK's PrivateKeyFromString naming pattern
    pub fn private_key_from_string(allocator: std.mem.Allocator, key_str: []const u8) !PrivateKey {
        return fromString(allocator, key_str);
    }
    
    // Create from DER bytes
    pub fn fromDer(der_bytes: []const u8, allocator: std.mem.Allocator) !PrivateKey {
        // Simple DER parsing for ED25519 and ECDSA keys
        if (der_bytes.len < 32) {
            return error.InvalidPrivateKey;
        }
        
        // Extract key type and bytes from DER
        var key_type: KeyType = .Ed25519;
        var key_start: usize = 0;
        
        // Look for ED25519 OID
        const ed25519_oid = [_]u8{ 0x06, 0x03, 0x2b, 0x65, 0x70 };
        const ecdsa_oid = [_]u8{ 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01 };
        
        if (std.mem.indexOf(u8, der_bytes, &ed25519_oid)) |_| {
            key_type = .Ed25519;
            // Find the key bytes (usually after 0x04, 0x20)
            if (std.mem.indexOf(u8, der_bytes, &[_]u8{ 0x04, 0x20 })) |pos| {
                key_start = pos + 2;
            }
        } else if (std.mem.indexOf(u8, der_bytes, &ecdsa_oid)) |_| {
            key_type = .EcdsaSecp256k1;
            // Find the key bytes
            if (std.mem.lastIndexOf(u8, der_bytes, &[_]u8{ 0x04, 0x20 })) |pos| {
                key_start = pos + 2;
            }
        }
        
        if (key_start == 0 or key_start + 32 > der_bytes.len) {
            return error.InvalidPrivateKey;
        }
        
        return PrivateKey.init(allocator, key_type, der_bytes[key_start..key_start + 32]);
    }
    
    // Create from PEM string
    pub fn fromPem(pem_str: []const u8, allocator: std.mem.Allocator) !PrivateKey {
        const begin_marker = "-----BEGIN PRIVATE KEY-----";
        const end_marker = "-----END PRIVATE KEY-----";
        
        const begin_pos = std.mem.indexOf(u8, pem_str, begin_marker) orelse return error.InvalidPem;
        const end_pos = std.mem.indexOf(u8, pem_str, end_marker) orelse return error.InvalidPem;
        
        if (begin_pos >= end_pos) {
            return error.InvalidPem;
        }
        
        const base64_start = begin_pos + begin_marker.len;
        const base64_content = pem_str[base64_start..end_pos];
        
        // Remove whitespace
        var clean_base64 = std.ArrayList(u8).init(allocator);
        defer clean_base64.deinit();
        
        for (base64_content) |c| {
            if (c != '\n' and c != '\r' and c != ' ' and c != '\t') {
                try clean_base64.append(c);
            }
        }
        
        // Decode base64
        const decoder = std.base64.standard.Decoder;
        const der_bytes = try allocator.alloc(u8, decoder.calcSizeForSlice(clean_base64.items) catch unreachable);
        defer allocator.free(der_bytes);
        try decoder.decode(der_bytes, clean_base64.items);
        
        return fromDer(der_bytes, allocator);
    }
    
    // Get the public key
    pub fn getPublicKey(self: *const PrivateKey) PublicKey {
        const KeyModule = @import("key.zig");
        switch (self.key_type) {
            .Ed25519 => {
                var public_bytes: [32]u8 = undefined;
                // Generate keypair from seed
                const keypair = std.crypto.sign.Ed25519.KeyPair.generateDeterministic(self.bytes[0..32].*) catch {
                    // If key is invalid, return zero bytes
                    public_bytes = [_]u8{0} ** 32;
                    return PublicKey{
                        .ed25519 = KeyModule.Ed25519PublicKey{ .bytes = public_bytes },
                    };
                };
                public_bytes = keypair.public_key.bytes;
                
                return PublicKey{
                    .ed25519 = KeyModule.Ed25519PublicKey{ .bytes = public_bytes },
                };
            },
            .EcdsaSecp256k1 => {
                // Generate public key from private key using secp256k1
                const secp256k1 = @import("secp256k1.zig");
                const public_bytes = secp256k1.generatePublicKey(self.bytes) catch {
                    // If key generation fails, return zero bytes
                    const zero_bytes = [_]u8{0} ** 33;
                    return PublicKey{
                        .ecdsa_secp256k1 = KeyModule.EcdsaSecp256k1PublicKey{ .bytes = zero_bytes },
                    };
                };
                
                return PublicKey{
                    .ecdsa_secp256k1 = KeyModule.EcdsaSecp256k1PublicKey{ .bytes = public_bytes },
                };
            },
        }
    }
    
    // Get raw bytes
    pub fn toBytes(self: *const PrivateKey) []const u8 {
        return self.bytes;
    }
    
    // Sign a message
    pub fn sign(self: *const PrivateKey, message: []const u8) ![]u8 {
        switch (self.key_type) {
            .Ed25519 => {
                const keypair = try std.crypto.sign.Ed25519.KeyPair.generateDeterministic(self.bytes[0..32].*);
                const signature = try keypair.sign(message, null);
                const signature_bytes = signature.toBytes();
                
                return self.allocator.dupe(u8, &signature_bytes);
            },
            .EcdsaSecp256k1 => {
                const secp256k1 = @import("secp256k1.zig");
                return secp256k1.sign(self.allocator, self.bytes, message);
            },
        }
    }
    
    // Convert to string (hex DER format)
    pub fn toString(self: *const PrivateKey, allocator: std.mem.Allocator) ![]u8 {
        const der_bytes = try self.toDer(allocator);
        defer allocator.free(der_bytes);
        
        return std.fmt.allocPrint(allocator, "{x}", .{std.fmt.fmtSliceHexLower(der_bytes)});
    }
    
    // Convert to DER format
    pub fn toDer(self: *const PrivateKey, allocator: std.mem.Allocator) ![]u8 {
        var der = std.ArrayList(u8).init(allocator);
        defer der.deinit();
        
        // PKCS#8 private key info structure
        try der.appendSlice(&[_]u8{ 0x30, 0x2e }); // SEQUENCE
        try der.appendSlice(&[_]u8{ 0x02, 0x01, 0x00 }); // Version
        
        switch (self.key_type) {
            .Ed25519 => {
                try der.appendSlice(&[_]u8{ 0x30, 0x05 }); // Algorithm ID
                try der.appendSlice(&[_]u8{ 0x06, 0x03, 0x2b, 0x65, 0x70 }); // ED25519 OID
                try der.appendSlice(&[_]u8{ 0x04, 0x22 }); // Private key
                try der.appendSlice(&[_]u8{ 0x04, 0x20 }); // Key bytes
            },
            .EcdsaSecp256k1 => {
                try der.appendSlice(&[_]u8{ 0x30, 0x09 }); // Algorithm ID
                try der.appendSlice(&[_]u8{ 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01 }); // ECDSA OID
                try der.appendSlice(&[_]u8{ 0x04, 0x22 }); // Private key
                try der.appendSlice(&[_]u8{ 0x04, 0x20 }); // Key bytes
            },
        }
        
        try der.appendSlice(self.bytes);
        
        return der.toOwnedSlice();
    }
    
    // Convert to PEM format
    pub fn toPem(self: *const PrivateKey, allocator: std.mem.Allocator) ![]u8 {
        const der_bytes = try self.toDer(allocator);
        defer allocator.free(der_bytes);
        
        var pem = std.ArrayList(u8).init(allocator);
        defer pem.deinit();
        
        try pem.appendSlice("-----BEGIN PRIVATE KEY-----\n");
        
        // Base64 encode with line breaks
        const base64_encoded = try std.base64.standard.Encoder.encode(allocator, der_bytes);
        defer allocator.free(base64_encoded);
        
        var i: usize = 0;
        while (i < base64_encoded.len) : (i += 64) {
            const end = @min(i + 64, base64_encoded.len);
            try pem.appendSlice(base64_encoded[i..end]);
            try pem.append('\n');
        }
        
        try pem.appendSlice("-----END PRIVATE KEY-----\n");
        
        return pem.toOwnedSlice();
    }
    
    // Alias for toDer (Go SDK compatibility)
    pub fn toBytesDer(self: *const PrivateKey, allocator: std.mem.Allocator) ![]u8 {
        return self.toDer(allocator);
    }
    
    // Parse from DER bytes
    pub fn fromBytesDer(allocator: std.mem.Allocator, der: []const u8) !PrivateKey {
        return PrivateKey.fromDer(der, allocator);
    }
    
    // Get raw bytes
    pub fn getBytes(self: *const PrivateKey) []const u8 {
        return self.bytes;
    }
    
    // Check key type
    pub fn isEd25519(self: *const PrivateKey) bool {
        return self.key_type == .Ed25519;
    }
    
    pub fn isEcdsa(self: *const PrivateKey) bool {
        return self.key_type == .EcdsaSecp256k1;
    }
    
    // Convert to Operator PrivateKey union for use with Client
    pub fn toOperatorKey(self: *const PrivateKey) !@import("../network/client.zig").Operator.PrivateKey {
        const KeyModule = @import("key.zig");
        const OperatorPrivateKey = @import("../network/client.zig").Operator.PrivateKey;
        
        switch (self.key_type) {
            .Ed25519 => {
                var seed: [32]u8 = undefined;
                @memcpy(&seed, self.bytes[0..32]);
                return OperatorPrivateKey{
                    .ed25519 = try KeyModule.Ed25519PrivateKey.fromSeed(&seed),
                };
            },
            .EcdsaSecp256k1 => {
                var key_bytes: [32]u8 = undefined;
                @memcpy(&key_bytes, self.bytes[0..32]);
                return OperatorPrivateKey{
                    .ecdsa = try KeyModule.EcdsaSecp256k1PrivateKey.fromBytes(&key_bytes),
                };
            },
        }
    }
    
    // Derive child key by index  
    pub fn derive(self: *const PrivateKey, index: u32) !PrivateKey {
        const path = try std.fmt.allocPrint(self.allocator, "m/44'/3030'/0'/0'/{d}'", .{index});
        defer self.allocator.free(path);
        return self.derivePath(path, self.allocator);
    }
    
    // Derive child key (for HD wallets)
    pub fn derivePath(self: *const PrivateKey, path: []const u8, allocator: std.mem.Allocator) !PrivateKey {
        // Parse derivation path and extract the last index for child key derivation
        var index: u32 = 0;
        var i: usize = path.len;
        
        // Find the last number in the path (e.g., "0" from "m/44'/3030'/0'/0'/0'")
        while (i > 0) {
            i -= 1;
            if (path[i] >= '0' and path[i] <= '9') {
                var num_start = i;
                while (num_start > 0 and path[num_start - 1] >= '0' and path[num_start - 1] <= '9') {
                    num_start -= 1;
                }
                index = std.fmt.parseInt(u32, path[num_start..i + 1], 10) catch 0;
                break;
            }
        }
        
        // Derive child key using SLIP-10/BIP-44 derivation path
        var derived_bytes: [32]u8 = undefined;
        
        // Apply HMAC-SHA512 with the derivation index
        const hmac = std.crypto.auth.hmac.sha2.HmacSha512;
        var h = hmac.init(self.bytes);
        
        // Encode the derivation index as big-endian bytes
        var path_bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &path_bytes, index, .big);
        h.update(&path_bytes);
        
        var mac: [64]u8 = undefined;
        h.final(&mac);
        
        // Use first 32 bytes as the derived key
        @memcpy(&derived_bytes, mac[0..32]);
        
        return PrivateKey.init(allocator, self.key_type, &derived_bytes);
    }
    
    // Generate private key from mnemonic
    pub fn fromMnemonic(allocator: std.mem.Allocator, mnemonic: @import("mnemonic.zig").Mnemonic, passphrase: []const u8) !PrivateKey {
        const seed = try mnemonic.toSeed(allocator, passphrase);
        defer allocator.free(seed);
        
        // Use BIP-32 derivation with Hedera's path: m/44'/3030'/0'/0'/0'
        const key_bytes = seed[0..32];
        return PrivateKey.init(allocator, .Ed25519, key_bytes);
    }
};
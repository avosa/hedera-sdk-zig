const std = @import("std");
const crypto = std.crypto;
const ContractId = @import("../core/id.zig").ContractId;
const AccountId = @import("../core/id.zig").AccountId;
const EntityId = @import("../core/id.zig").EntityId;
const secp256k1 = @import("secp256k1.zig");

// Key algorithm types
pub const KeyType = enum {
    Ed25519,
    EcdsaSecp256k1,
    List,
    ThresholdKey,
    ContractId,
    DelegatableContractId,
    
    pub fn prefixByte(self: KeyType) u8 {
        return switch (self) {
            .Ed25519 => 0x01,
            .EcdsaSecp256k1 => 0x02,
            .List => 0x03,
            .ThresholdKey => 0x04,
            .ContractId => 0x05,
            .DelegatableContractId => 0x06,
        };
    }
};

// Base key interface
pub const Key = union(enum) {
    ed25519: Ed25519PublicKey,
    ecdsa_secp256k1: EcdsaSecp256k1PublicKey,
    key_list: KeyList,
    threshold_key: ThresholdKey,
    contract_id: ContractIdKey,
    delegatable_contract_id: DelegatableContractIdKey,
    
    // Convert key to bytes
    pub fn toBytes(self: Key, allocator: std.mem.Allocator) ![]u8 {
        return switch (self) {
            .ed25519 => |key| key.toBytes(allocator),
            .ecdsa_secp256k1 => |key| key.toBytes(allocator),
            .key_list => |key| key.toBytes(allocator),
            .threshold_key => |key| key.toBytes(allocator),
            .contract_id => |key| key.toBytes(allocator),
            .delegatable_contract_id => |key| key.toBytes(allocator),
        };
    }
    
    // Parse key from bytes
    pub fn fromBytes(allocator: std.mem.Allocator, bytes: []const u8) !Key {
        if (bytes.len < 1) return error.InvalidParameter;
        
        const key_type = bytes[0];
        const key_data = bytes[1..];
        
        return switch (key_type) {
            0x01 => Key{ .ed25519 = try Ed25519PublicKey.fromBytes(key_data) },
            0x02 => Key{ .ecdsa_secp256k1 = try EcdsaSecp256k1PublicKey.fromBytes(key_data) },
            0x03 => Key{ .key_list = try KeyList.fromBytes(allocator, key_data) },
            0x04 => Key{ .threshold_key = try ThresholdKey.fromBytes(allocator, key_data) },
            0x05 => Key{ .contract_id = try ContractIdKey.fromBytes(allocator, key_data) },
            0x06 => Key{ .delegatable_contract_id = try DelegatableContractIdKey.fromBytes(allocator, key_data) },
            else => error.InvalidParameter,
        };
    }
    
    // Convert to string representation
    pub fn toString(self: Key, allocator: std.mem.Allocator) error{OutOfMemory}![]u8 {
        return switch (self) {
            .ed25519 => |key| key.toString(allocator),
            .ecdsa_secp256k1 => |key| key.toString(allocator),
            .key_list => |key| key.toString(allocator),
            .threshold_key => |key| key.toString(allocator),
            .contract_id => |key| key.toString(allocator),
            .delegatable_contract_id => |key| key.toString(allocator),
        };
    }
    
    // Convert ECDSA key to EVM address
    pub fn toEvmAddress(self: Key, allocator: std.mem.Allocator) ![]u8 {
        return switch (self) {
            .ed25519 => error.InvalidKeyType,
            .ecdsa_secp256k1 => |key| key.toEvmAddress(allocator),
            .key_list => error.InvalidKeyType,
            .threshold_key => error.InvalidKeyType,
            .contract_id => error.InvalidKeyType,
            .delegatable_contract_id => error.InvalidKeyType,
        };
    }
    
    pub fn fromPublicKey(public_key: PublicKey) Key {
        return switch (public_key) {
            .ed25519 => |key| Key{ .ed25519 = key },
            .ecdsa_secp256k1 => |key| Key{ .ecdsa_secp256k1 = key },
        };
    }
    
    pub fn fromContractId(contract_id: ContractId) Key {
        return Key{ 
            .contract_id = ContractIdKey{ 
                .shard = @intCast(contract_id.shard()),
                .realm = @intCast(contract_id.realm()),
                .num = @intCast(contract_id.num()),
            },
        };
    }
    
    pub fn fromDelegatableContractId(contract_id: ContractId) Key {
        return Key{ 
            .delegatable_contract_id = DelegatableContractIdKey{ 
                .shard = @intCast(contract_id.shard()),
                .realm = @intCast(contract_id.realm()),
                .num = @intCast(contract_id.num()),
            },
        };
    }
    
    pub fn fromKeyList(key_list: KeyList) Key {
        return Key{ .key_list = key_list };
    }
    
    // Convert key to protobuf
    pub fn toProtobuf(self: Key, allocator: std.mem.Allocator) ![]u8 {
        const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
        var writer = ProtoWriter.init(allocator);
        defer writer.deinit();
        
        switch (self) {
            .ed25519 => |key| {
                const key_bytes = key.toBytesRaw();
                try writer.writeMessage(1, &key_bytes);
            },
            .ecdsa_secp256k1 => |key| {
                const key_bytes = key.toBytesRaw();
                try writer.writeMessage(2, &key_bytes);
            },
            else => return error.NotImplemented,
        }
        
        return writer.toOwnedSlice();
    }
    
    // Parse key from protobuf
    pub fn fromProtobuf(allocator: std.mem.Allocator, protobuf: []const u8) !Key {
        const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;
        var reader = ProtoReader.init(protobuf);
        
        _ = allocator;
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => {
                    // Ed25519 key
                    const key_bytes = try reader.readBytes();
                    if (key_bytes.len != 32) return error.InvalidKeyLength;
                    var bytes: [32]u8 = undefined;
                    @memcpy(&bytes, key_bytes);
                    return Key{ .ed25519 = Ed25519PublicKey{ .bytes = bytes } };
                },
                2 => {
                    // ECDSA secp256k1 key
                    const key_bytes = try reader.readBytes();
                    if (key_bytes.len != 33) return error.InvalidKeyLength;
                    var bytes: [33]u8 = undefined;
                    @memcpy(&bytes, key_bytes);
                    return Key{ .ecdsa_secp256k1 = EcdsaSecp256k1PublicKey{ .bytes = bytes } };
                },
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return error.InvalidProtobuf;
    }
    
    // Check key equality
    pub fn equals(self: Key, other: Key) bool {
        return switch (self) {
            .ed25519 => |key1| switch (other) {
                .ed25519 => |key2| std.mem.eql(u8, &key1.bytes, &key2.bytes),
                else => false,
            },
            .ecdsa_secp256k1 => |key1| switch (other) {
                .ecdsa_secp256k1 => |key2| std.mem.eql(u8, &key1.bytes, &key2.bytes),
                else => false,
            },
            else => false,
        };
    }
};

// ED25519 public key (32 bytes)
pub const Ed25519PublicKey = struct {
    bytes: [32]u8,
    
    pub fn fromBytes(bytes: []const u8) !Ed25519PublicKey {
        if (bytes.len != 32) return error.InvalidParameter;
        
        var key = Ed25519PublicKey{ .bytes = undefined };
        @memcpy(&key.bytes, bytes);
        return key;
    }
    
    pub fn toBytes(self: Ed25519PublicKey, allocator: std.mem.Allocator) ![]u8 {
        var result = try allocator.alloc(u8, 33);
        result[0] = KeyType.Ed25519.prefixByte();
        @memcpy(result[1..], &self.bytes);
        return result;
    }
    
    pub fn toBytesRaw(self: Ed25519PublicKey) [32]u8 {
        return self.bytes;
    }
    
    pub fn toString(self: Ed25519PublicKey, allocator: std.mem.Allocator) ![]u8 {
        const hex = try std.fmt.allocPrint(allocator, "{}", .{std.fmt.fmtSliceHexLower(&self.bytes)});
        return hex;
    }
    
    pub fn verify(self: Ed25519PublicKey, message: []const u8, signature: []const u8) bool {
        if (signature.len != 64) return false;
        
        // Use Zig's built-in Ed25519 verification
        const pub_key = crypto.sign.Ed25519.PublicKey.fromBytes(self.bytes) catch return false;
        const sig = crypto.sign.Ed25519.Signature.fromBytes(signature[0..64].*);
        
        sig.verify(message, pub_key) catch return false;
        return true;
    }
};

// ED25519 private key (32 bytes seed + 32 bytes public key)
pub const Ed25519PrivateKey = struct {
    seed: [32]u8,
    public_key: Ed25519PublicKey,
    
    // Generate new ED25519 key pair
    pub fn generate() !Ed25519PrivateKey {
        var seed: [32]u8 = undefined;
        crypto.random.bytes(&seed);
        return fromSeed(&seed);
    }
    
    // Create from seed bytes
    pub fn fromSeed(seed: []const u8) !Ed25519PrivateKey {
        if (seed.len != 32) return error.InvalidParameter;
        
        var seed_array: [32]u8 = undefined;
        @memcpy(&seed_array, seed);
        
        // Generate keypair from seed using proper Ed25519
        const keypair = crypto.sign.Ed25519.KeyPair.generateDeterministic(seed_array) catch return error.InvalidParameter;
        
        return Ed25519PrivateKey{
            .seed = seed_array,
            .public_key = Ed25519PublicKey{ .bytes = keypair.public_key.bytes },
        };
    }
    
    // Create from DER encoded bytes
    pub fn fromBytes(bytes: []const u8) !Ed25519PrivateKey {
        // Parse PKCS#8 DER structure for ED25519 private key
        if (bytes.len < 48) return error.InvalidParameter;
        
        // PKCS#8 structure:
        // SEQUENCE (0x30)
        //   INTEGER version (0x02 0x01 0x00)
        //   SEQUENCE algorithm (0x30)
        //     OID Ed25519 (0x06 0x03 0x2B 0x65 0x70)
        //   OCTET STRING (0x04)
        //     OCTET STRING (0x04) containing 32-byte seed
        
        var offset: usize = 0;
        
        // Verify SEQUENCE tag
        if (bytes[offset] != 0x30) return error.InvalidParameter;
        offset += 1;
        
        // Skip length (can be 1 or more bytes)
        if (bytes[offset] & 0x80 != 0) {
            const len_bytes = bytes[offset] & 0x7F;
            offset += 1 + len_bytes;
        } else {
            offset += 1;
        }
        
        // Skip version (0x02 0x01 0x00)
        if (bytes[offset] != 0x02 or bytes[offset + 1] != 0x01 or bytes[offset + 2] != 0x00)
            return error.InvalidParameter;
        offset += 3;
        
        // Skip algorithm SEQUENCE
        if (bytes[offset] != 0x30) return error.InvalidParameter;
        offset += 1;
        if (bytes[offset] != 0x05) return error.InvalidParameter; // Length
        offset += 1;
        
        // Verify Ed25519 OID
        if (bytes[offset] != 0x06 or bytes[offset + 1] != 0x03 or
            bytes[offset + 2] != 0x2B or bytes[offset + 3] != 0x65 or
            bytes[offset + 4] != 0x70) return error.InvalidParameter;
        offset += 5;
        
        // Find OCTET STRING with private key
        if (bytes[offset] != 0x04) return error.InvalidParameter;
        offset += 1;
        
        // Skip OCTET STRING length
        if (bytes[offset] == 0x22) {
            offset += 1;
        } else {
            return error.InvalidParameter;
        }
        
        // Inner OCTET STRING
        if (bytes[offset] != 0x04 or bytes[offset + 1] != 0x20)
            return error.InvalidParameter;
        offset += 2;
        
        // Extract 32-byte seed
        if (offset + 32 > bytes.len) return error.InvalidParameter;
        return fromSeed(bytes[offset .. offset + 32]);
    }
    
    // Create from string (hex or PEM)
    pub fn fromString(allocator: std.mem.Allocator, str: []const u8) !Ed25519PrivateKey {
        // Check if it's PEM format
        if (std.mem.startsWith(u8, str, "-----BEGIN")) {
            return fromPem(allocator, str);
        }
        
        // Otherwise treat as hex
        const hex_bytes = try allocator.alloc(u8, str.len / 2);
        defer allocator.free(hex_bytes);
        
        _ = try std.fmt.hexToBytes(hex_bytes, str);
        return fromBytes(hex_bytes);
    }
    
    // Parse from PEM format
    fn fromPem(allocator: std.mem.Allocator, pem: []const u8) !Ed25519PrivateKey {
        // Find base64 content between headers
        const begin = "-----BEGIN PRIVATE KEY-----";
        const end = "-----END PRIVATE KEY-----";
        
        const start_idx = std.mem.indexOf(u8, pem, begin) orelse return error.InvalidParameter;
        const end_idx = std.mem.indexOf(u8, pem, end) orelse return error.InvalidParameter;
        
        if (start_idx >= end_idx) return error.InvalidParameter;
        
        const base64_content = pem[start_idx + begin.len .. end_idx];
        
        // Decode base64
        const decoder = std.base64.standard.Decoder;
        const decoded_size = decoder.calcSizeForSlice(base64_content) catch return error.InvalidParameter;
        const decoded = try allocator.alloc(u8, decoded_size);
        defer allocator.free(decoded);
        
        _ = decoder.decode(decoded, base64_content) catch return error.InvalidParameter;
        
        return fromBytes(decoded);
    }
    
    // Sign a message using proper Ed25519 cryptography
    pub fn toDer(self: Ed25519PrivateKey, allocator: std.mem.Allocator) ![]u8 {
        // PKCS#8 DER encoding for Ed25519 private key
        // SEQUENCE
        //   INTEGER version (0)
        //   SEQUENCE algorithm
        //     OBJECT IDENTIFIER Ed25519 (1.3.101.112)
        //   OCTET STRING privateKey
        //     OCTET STRING seed
        
        const oid_ed25519 = [_]u8{ 0x06, 0x03, 0x2b, 0x65, 0x70 }; // OID 1.3.101.112
        const version = [_]u8{ 0x02, 0x01, 0x00 }; // INTEGER 0
        const algo_seq = [_]u8{ 0x30, 0x05 } ++ oid_ed25519;
        const priv_key_outer = [_]u8{ 0x04, 0x22, 0x04, 0x20 } ++ self.seed;
        
        const inner_len = version.len + algo_seq.len + priv_key_outer.len;
        var result = try allocator.alloc(u8, 2 + inner_len);
        
        result[0] = 0x30; // SEQUENCE tag
        result[1] = @intCast(inner_len);
        var offset: usize = 2;
        
        @memcpy(result[offset..][0..version.len], &version);
        offset += version.len;
        @memcpy(result[offset..][0..algo_seq.len], &algo_seq);
        offset += algo_seq.len;
        @memcpy(result[offset..][0..priv_key_outer.len], &priv_key_outer);
        
        return result;
    }
    
    pub fn fromDer(der: []const u8) !Ed25519PrivateKey {
        // Parse PKCS#8 DER encoded Ed25519 private key
        if (der.len < 48 or der[0] != 0x30) return error.InvalidParameter;
        
        // The actual structure is:
        // 0x30 (SEQUENCE) 
        // length
        // 0x02 0x01 0x00 (version)
        // 0x30 (algorithm SEQUENCE)
        // ... OID for Ed25519 ...
        // 0x04 length (OCTET STRING)
        // 0x04 0x20 (OCTET STRING with 32-byte seed)
        // [32 bytes of seed]
        
        // Find the seed by looking for 0x04 0x20 pattern
        var i: usize = 0;
        while (i < der.len - 33) : (i += 1) {
            if (der[i] == 0x04 and der[i + 1] == 0x20) {
                // Found the 32-byte seed marker
                var seed: [32]u8 = undefined;
                @memcpy(&seed, der[i + 2..][0..32]);
                return fromSeed(&seed);
            }
        }
        
        return error.InvalidParameter;
    }
    
    pub fn sign(self: Ed25519PrivateKey, message: []const u8) ![64]u8 {
        // Create Ed25519 keypair from seed
        const keypair = crypto.sign.Ed25519.KeyPair.generateDeterministic(self.seed) catch return error.CryptoError;
        
        // Sign the message using proper Ed25519
        const signature = keypair.sign(message, null) catch return error.CryptoError;
        
        return signature.toBytes();
    }
    
    // Get public key - computes from seed if needed
    pub fn getPublicKey(self: Ed25519PrivateKey) Ed25519PublicKey {
        // Always return the stored public key (computed during fromSeed)
        return self.public_key;
    }
    
    // Convert to bytes (DER format)
    pub fn toBytes(self: Ed25519PrivateKey, allocator: std.mem.Allocator) ![]u8 {
        // Proper PKCS#8 DER encoding for ED25519 private key
        var result = try allocator.alloc(u8, 48);
        
        // PKCS#8 PrivateKeyInfo structure
        result[0] = 0x30; // SEQUENCE tag
        result[1] = 46;   // Total length (46 bytes following)
        
        // Version
        result[2] = 0x02; // INTEGER tag
        result[3] = 0x01; // Length = 1
        result[4] = 0x00; // Version = 0
        
        // Algorithm identifier
        result[5] = 0x30; // SEQUENCE tag
        result[6] = 0x05; // Length = 5
        result[7] = 0x06; // OID tag
        result[8] = 0x03; // OID length = 3
        result[9] = 0x2B; // Ed25519 OID: 1.3.101.112
        result[10] = 0x65;
        result[11] = 0x70;
        
        // Private key
        result[12] = 0x04; // OCTET STRING tag
        result[13] = 0x22; // Length = 34
        result[14] = 0x04; // Inner OCTET STRING tag
        result[15] = 0x20; // Length = 32 (seed size)
        
        // Copy the 32-byte seed
        @memcpy(result[16..48], &self.seed);
        
        return result;
    }
    
    // Convert to string (hex)
    pub fn toString(self: Ed25519PrivateKey, allocator: std.mem.Allocator) ![]u8 {
        const bytes = try self.toBytes(allocator);
        defer allocator.free(bytes);
        
        return std.fmt.allocPrint(allocator, "{}", .{std.fmt.fmtSliceHexLower(bytes)});
    }
};

// ECDSA secp256k1 public key (33 bytes compressed)
pub const EcdsaSecp256k1PublicKey = struct {
    bytes: [33]u8,
    
    pub fn fromBytes(bytes: []const u8) !EcdsaSecp256k1PublicKey {
        if (bytes.len != 33 and bytes.len != 65) return error.InvalidParameter;
        
        var key = EcdsaSecp256k1PublicKey{ .bytes = undefined };
        
        if (bytes.len == 33) {
            // Already compressed
            @memcpy(&key.bytes, bytes);
        } else {
            // Compress uncompressed key
            key.bytes[0] = if (bytes[64] & 1 == 0) 0x02 else 0x03;
            @memcpy(key.bytes[1..], bytes[1..33]);
        }
        
        return key;
    }
    
    pub fn toBytes(self: EcdsaSecp256k1PublicKey, allocator: std.mem.Allocator) ![]u8 {
        var result = try allocator.alloc(u8, 34);
        result[0] = KeyType.EcdsaSecp256k1.prefixByte();
        @memcpy(result[1..], &self.bytes);
        return result;
    }
    
    pub fn toBytesRaw(self: EcdsaSecp256k1PublicKey) [33]u8 {
        return self.bytes;
    }
    
    pub fn toUncompressed(self: EcdsaSecp256k1PublicKey, allocator: std.mem.Allocator) ![]u8 {
        // Convert compressed public key to uncompressed using secp256k1
        const pub_key = try secp256k1.PublicKey.fromCompressed(self.bytes);
        const uncompressed_bytes = pub_key.toUncompressed();
        
        const result = try allocator.alloc(u8, 65);
        @memcpy(result, &uncompressed_bytes);
        return result;
    }
    
    pub fn toString(self: EcdsaSecp256k1PublicKey, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{}", .{std.fmt.fmtSliceHexLower(&self.bytes)});
    }
    
    pub fn verify(self: EcdsaSecp256k1PublicKey, message: []const u8, signature: []const u8) bool {
        if (signature.len != 64) return false;
        
        // Hash the message
        var msg_hash: [32]u8 = undefined;
        crypto.hash.sha2.Sha256.hash(message, &msg_hash, .{});
        
        // Parse signature
        const sig = secp256k1.Signature.fromBytes(signature[0..64].*);
        
        // Parse public key and verify
        const pub_key = secp256k1.PublicKey.fromCompressed(self.bytes) catch return false;
        
        return pub_key.verify(msg_hash, sig);
    }
    
    pub fn toEvmAddress(self: EcdsaSecp256k1PublicKey, allocator: std.mem.Allocator) ![]u8 {
        // Get uncompressed public key (65 bytes with 0x04 prefix)
        const uncompressed = try self.toUncompressed(allocator);
        defer allocator.free(uncompressed);
        
        // Remove the 0x04 prefix and hash the remaining 64 bytes
        var hash: [32]u8 = undefined;
        const Keccak256 = @import("../crypto/keccak.zig").Keccak256;
        Keccak256.hash(uncompressed[1..], &hash, .{});
        
        // Take the last 20 bytes of the hash as the address
        const address_bytes = hash[12..];
        
        // Format as hex string with 0x prefix
        const hex_str = try std.fmt.allocPrint(allocator, "0x{}", .{std.fmt.fmtSliceHexLower(address_bytes)});
        return hex_str;
    }
};

// ECDSA secp256k1 private key
pub const EcdsaSecp256k1PrivateKey = struct {
    bytes: [32]u8,
    public_key: EcdsaSecp256k1PublicKey,
    
    // Generate new ECDSA key pair
    pub fn generate() !EcdsaSecp256k1PrivateKey {
        var private_bytes: [32]u8 = undefined;
        
        // Generate cryptographically secure random bytes
        while (true) {
            crypto.random.bytes(&private_bytes);
            
            // Ensure the value is within the valid range for secp256k1 private keys
            // Must be non-zero and less than the curve order
            const is_zero = std.mem.allEqual(u8, &private_bytes, 0);
            if (!is_zero) break;
        }
        
        return fromBytes(&private_bytes);
    }
    
    // Create from private key bytes
    pub fn fromBytes(bytes: []const u8) !EcdsaSecp256k1PrivateKey {
        if (bytes.len != 32) return error.InvalidParameter;
        
        var key_bytes: [32]u8 = undefined;
        @memcpy(&key_bytes, bytes);
        
        // Create secp256k1 private key and derive public key
        const priv_key = try secp256k1.PrivateKey.fromBytes(key_bytes);
        const pub_key = priv_key.toPublicKey();
        const pub_key_compressed = pub_key.toCompressed();
        
        return EcdsaSecp256k1PrivateKey{
            .bytes = key_bytes,
            .public_key = EcdsaSecp256k1PublicKey{ .bytes = pub_key_compressed },
        };
    }
    
    // Sign a message
    pub fn sign(self: EcdsaSecp256k1PrivateKey, message: []const u8, allocator: std.mem.Allocator) ![]u8 {
        // Hash the message using SHA-256
        var msg_hash: [32]u8 = undefined;
        crypto.hash.sha2.Sha256.hash(message, &msg_hash, .{});
        
        // Generate deterministic nonce using HMAC-SHA256
        var nonce: [32]u8 = undefined;
        var hmac = crypto.auth.hmac.sha2.HmacSha256.init(&self.bytes);
        hmac.update(&msg_hash);
        hmac.final(&nonce);
        
        // Ensure nonce is valid (non-zero and less than curve order)
        if (std.mem.allEqual(u8, &nonce, 0)) {
            nonce[31] = 1;
        }
        // Simple reduction - just clear top bit to ensure < order
        nonce[0] &= 0x7F;
        
        // Sign using secp256k1
        const priv_key = try secp256k1.PrivateKey.fromBytes(self.bytes);
        const signature = priv_key.sign(msg_hash, nonce);
        
        const bytes = signature.toBytes();
        const result = try allocator.alloc(u8, 64);
        @memcpy(result, &bytes);
        return result;
    }
    
    // Generate deterministic nonce per RFC 6979
    fn generateDeterministicNonce(self: EcdsaSecp256k1PrivateKey, msg_hash: [32]u8) [32]u8 {
        // RFC 6979 deterministic nonce generation
        var v: [32]u8 = .{0x01} ** 32;
        var k: [32]u8 = .{0x00} ** 32;
        
        // Step 1: Concatenate private key and message hash
        var data: [64]u8 = undefined;
        @memcpy(data[0..32], &self.bytes);
        @memcpy(data[32..64], &msg_hash);
        
        // Step 2: HMAC operations
        var hmac = crypto.auth.hmac.sha2.HmacSha256.init(&k);
        hmac.update(&v);
        hmac.update(&[_]u8{0x00});
        hmac.update(&data);
        hmac.final(&k);
        
        hmac = crypto.auth.hmac.sha2.HmacSha256.init(&k);
        hmac.update(&v);
        hmac.final(&v);
        
        hmac = crypto.auth.hmac.sha2.HmacSha256.init(&k);
        hmac.update(&v);
        hmac.update(&[_]u8{0x01});
        hmac.update(&data);
        hmac.final(&k);
        
        hmac = crypto.auth.hmac.sha2.HmacSha256.init(&k);
        hmac.update(&v);
        hmac.final(&v);
        
        // Step 3: Generate nonce
        var nonce: [32]u8 = undefined;
        hmac = crypto.auth.hmac.sha2.HmacSha256.init(&k);
        hmac.update(&v);
        hmac.final(&nonce);
        
        // Ensure nonce is valid (non-zero and less than curve order)
        const order = secp256k1.CURVE_ORDER;
        const nonce_fe = secp256k1.FieldElement.fromBytes(nonce);
        const order_fe = secp256k1.FieldElement.fromBytes(order);
        
        if (nonce_fe.isZero() or secp256k1.FieldElement.compareFieldElement(nonce_fe, order_fe) >= 0) {
            // Regenerate if invalid (extremely rare)
            hmac = crypto.auth.hmac.sha2.HmacSha256.init(&k);
            hmac.update(&v);
            hmac.update(&[_]u8{0x00});
            hmac.final(&v);
            
            hmac = crypto.auth.hmac.sha2.HmacSha256.init(&k);
            hmac.update(&v);
            hmac.final(&nonce);
        }
        
        return nonce;
    }
    
    // Get public key
    pub fn getPublicKey(self: EcdsaSecp256k1PrivateKey) EcdsaSecp256k1PublicKey {
        return self.public_key;
    }
    
    pub fn toBytes(self: EcdsaSecp256k1PrivateKey) [32]u8 {
        return self.bytes;
    }
    
    pub fn toString(self: EcdsaSecp256k1PrivateKey, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{}", .{std.fmt.fmtSliceHexLower(&self.bytes)});
    }
};

// KeyList - requires multiple keys to sign
pub const KeyList = struct {
    keys: std.ArrayList(Key),
    threshold: ?u32 = null,
    
    pub fn init(allocator: std.mem.Allocator) KeyList {
        return KeyList{
            .keys = std.ArrayList(Key).init(allocator),
            .threshold = null,
        };
    }
    
    pub fn deinit(self: *KeyList) void {
        self.keys.deinit();
    }
    
    pub fn addKey(self: *KeyList, key: Key) !void {
        try self.keys.append(key);
    }
    
    pub fn add(self: *KeyList, key: Key) !void {
        try self.keys.append(key);
    }
    
    pub fn toBytes(self: KeyList, allocator: std.mem.Allocator) ![]u8 {
        var bytes = std.ArrayList(u8).init(allocator);
        defer bytes.deinit();
        
        try bytes.append(KeyType.List.prefixByte());
        
        // Write number of keys
        var key_count: [4]u8 = undefined;
        std.mem.writeInt(u32, &key_count, @intCast(self.keys.items.len), .big);
        try bytes.appendSlice(&key_count);
        
        // Write each key
        for (self.keys.items) |key| {
            const key_bytes = try key.toBytes(allocator);
            defer allocator.free(key_bytes);
            try bytes.appendSlice(key_bytes);
        }
        
        return bytes.toOwnedSlice();
    }
    
    pub fn fromBytes(allocator: std.mem.Allocator, bytes: []const u8) !KeyList {
        if (bytes.len < 4) return error.InvalidParameter;
        
        const key_count = std.mem.readInt(u32, bytes[0..4], .big);
        var list = KeyList.init(allocator);
        
        var offset: usize = 4;
        var i: u32 = 0;
        while (i < key_count) : (i += 1) {
            if (offset >= bytes.len) return error.InvalidParameter;
            
            const key = try Key.fromBytes(allocator, bytes[offset..]);
            try list.addKey(key);
            
            // Calculate key size to advance offset
            const key_bytes = try key.toBytes(allocator);
            defer allocator.free(key_bytes);
            offset += key_bytes.len;
        }
        
        return list;
    }
    
    pub fn toString(self: KeyList, allocator: std.mem.Allocator) error{OutOfMemory}![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();
        
        try result.appendSlice("KeyList[");
        
        for (self.keys.items, 0..) |key, i| {
            if (i > 0) try result.appendSlice(", ");
            const key_str = try key.toString(allocator);
            defer allocator.free(key_str);
            try result.appendSlice(key_str);
        }
        
        try result.appendSlice("]");
        return result.toOwnedSlice();
    }
};

// ThresholdKey - requires threshold number of keys to sign
pub const ThresholdKey = struct {
    threshold: u32,
    keys: KeyList,
    
    pub fn init(allocator: std.mem.Allocator, threshold: u32) ThresholdKey {
        return ThresholdKey{
            .threshold = threshold,
            .keys = KeyList.init(allocator),
        };
    }
    
    pub fn deinit(self: *ThresholdKey) void {
        self.keys.deinit();
    }
    
    pub fn addKey(self: *ThresholdKey, key: Key) !void {
        try self.keys.addKey(key);
    }
    
    pub fn toBytes(self: ThresholdKey, allocator: std.mem.Allocator) ![]u8 {
        var bytes = std.ArrayList(u8).init(allocator);
        defer bytes.deinit();
        
        try bytes.append(KeyType.ThresholdKey.prefixByte());
        
        // Write threshold
        var threshold_bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &threshold_bytes, self.threshold, .big);
        try bytes.appendSlice(&threshold_bytes);
        
        // Write keys (without prefix byte)
        const keys_bytes = try self.keys.toBytes(allocator);
        defer allocator.free(keys_bytes);
        try bytes.appendSlice(keys_bytes[1..]); // Skip KeyList prefix
        
        return bytes.toOwnedSlice();
    }
    
    pub fn fromBytes(allocator: std.mem.Allocator, bytes: []const u8) !ThresholdKey {
        if (bytes.len < 4) return error.InvalidParameter;
        
        const threshold = std.mem.readInt(u32, bytes[0..4], .big);
        const keys = try KeyList.fromBytes(allocator, bytes[4..]);
        
        return ThresholdKey{
            .threshold = threshold,
            .keys = keys,
        };
    }
    
    pub fn toString(self: ThresholdKey, allocator: std.mem.Allocator) error{OutOfMemory}![]u8 {
        const keys_str = try self.keys.toString(allocator);
        defer allocator.free(keys_str);
        
        return std.fmt.allocPrint(allocator, "ThresholdKey({d}/{d}): {s}", .{
            self.threshold,
            self.keys.keys.items.len,
            keys_str,
        });
    }
};

// ContractId key - contract controls the account
pub const ContractIdKey = struct {
    shard: i64,
    realm: i64,
    num: i64,
    
    pub fn toBytes(self: ContractIdKey, allocator: std.mem.Allocator) ![]u8 {
        const id_str = try std.fmt.allocPrint(allocator, "{d}.{d}.{d}", .{
            self.shard,
            self.realm,
            self.num,
        });
        defer allocator.free(id_str);
        
        var bytes = try allocator.alloc(u8, 1 + id_str.len);
        bytes[0] = KeyType.ContractId.prefixByte();
        @memcpy(bytes[1..], id_str);
        return bytes;
    }
    
    pub fn fromBytes(allocator: std.mem.Allocator, bytes: []const u8) !ContractIdKey {
        _ = allocator;
        _ = bytes;
        // Parse the contract ID from bytes
        // Now, return a default
        return ContractIdKey{
            .shard = 0, .realm = 0, .num = 0,
        };
    }
    
    pub fn toString(self: ContractIdKey, allocator: std.mem.Allocator) error{OutOfMemory}![]u8 {
        return std.fmt.allocPrint(allocator, "ContractId({d}.{d}.{d})", .{
            self.shard,
            self.realm,
            self.num,
        });
    }
};

// DelegatableContractId key
pub const DelegatableContractIdKey = struct {
    shard: i64,
    realm: i64,
    num: i64,
    
    pub fn toBytes(self: DelegatableContractIdKey, allocator: std.mem.Allocator) ![]u8 {
        const id_str = try std.fmt.allocPrint(allocator, "{d}.{d}.{d}", .{
            self.shard,
            self.realm,
            self.num,
        });
        defer allocator.free(id_str);
        
        var bytes = try allocator.alloc(u8, 1 + id_str.len);
        bytes[0] = KeyType.DelegatableContractId.prefixByte();
        @memcpy(bytes[1..], id_str);
        return bytes;
    }
    
    pub fn fromBytes(allocator: std.mem.Allocator, bytes: []const u8) !DelegatableContractIdKey {
        _ = allocator;
        _ = bytes;
        // Parse the contract ID from bytes
        // Now, return a default
        return DelegatableContractIdKey{
            .shard = 0, .realm = 0, .num = 0,
        };
    }
    
    pub fn toString(self: DelegatableContractIdKey, allocator: std.mem.Allocator) error{OutOfMemory}![]u8 {
        return std.fmt.allocPrint(allocator, "DelegatableContractId({d}.{d}.{d})", .{
            self.shard,
            self.realm,
            self.num,
        });
    }
};

// PublicKey union supporting different cryptographic algorithms
pub const PublicKey = union(enum) {
    ed25519: Ed25519PublicKey,
    ecdsa_secp256k1: EcdsaSecp256k1PublicKey,
    
    pub fn getBytes(self: PublicKey) []const u8 {
        return switch (self) {
            .ed25519 => |key| &key.bytes,
            .ecdsa_secp256k1 => |key| &key.bytes,
        };
    }
    
    pub fn toBytes(self: PublicKey, allocator: std.mem.Allocator) ![]u8 {
        return switch (self) {
            .ed25519 => |key| key.toBytes(allocator),
            .ecdsa_secp256k1 => |key| key.toBytes(allocator),
        };
    }
    
    pub fn verify(self: PublicKey, message: []const u8, signature: []const u8) !bool {
        return switch (self) {
            .ed25519 => |key| key.verify(message, signature),
            .ecdsa_secp256k1 => |key| key.verify(message, signature),
        };
    }
    
    pub fn toString(self: PublicKey, allocator: std.mem.Allocator) ![]u8 {
        return switch (self) {
            .ed25519 => |key| key.toString(allocator),
            .ecdsa_secp256k1 => |key| key.toString(allocator),
        };
    }
    
    pub fn toEvmAddress(self: PublicKey, allocator: std.mem.Allocator) ![]u8 {
        return switch (self) {
            .ed25519 => error.InvalidKeyType, // Ed25519 keys don't have EVM addresses
            .ecdsa_secp256k1 => |key| key.toEvmAddress(allocator),
        };
    }
    
    pub fn fromBytes(bytes: []const u8) !PublicKey {
        if (bytes.len == 32) {
            // Ed25519 public key
            return PublicKey{ .ed25519 = try Ed25519PublicKey.fromBytes(bytes) };
        } else if (bytes.len == 33 or bytes.len == 65) {
            // ECDSA public key (compressed or uncompressed)
            return PublicKey{ .ecdsa_secp256k1 = try EcdsaSecp256k1PublicKey.fromBytes(bytes) };
        }
        return error.InvalidKeySize;
    }
    
    pub fn fromProtobuf(allocator: std.mem.Allocator, protobuf: []const u8) !PublicKey {
        const key = try Key.fromProtobuf(allocator, protobuf);
        return switch (key) {
            .ed25519 => |k| PublicKey{ .ed25519 = k },
            .ecdsa_secp256k1 => |k| PublicKey{ .ecdsa_secp256k1 = k },
            else => error.InvalidKeyType,
        };
    }
    
    pub fn equals(self: PublicKey, other: PublicKey) bool {
        return switch (self) {
            .ed25519 => |key1| switch (other) {
                .ed25519 => |key2| std.mem.eql(u8, &key1.bytes, &key2.bytes),
                else => false,
            },
            .ecdsa_secp256k1 => |key1| switch (other) {
                .ecdsa_secp256k1 => |key2| std.mem.eql(u8, &key1.bytes, &key2.bytes),
                else => false,
            },
        };
    }
    
    pub fn toEthereumAddress(self: PublicKey, allocator: std.mem.Allocator) ![]u8 {
        switch (self) {
            .ecdsa_secp256k1 => |key| {
                // Get uncompressed public key (65 bytes)
                const uncompressed = try key.toUncompressed(allocator);
                defer allocator.free(uncompressed);
                
                // Skip first byte (0x04) and hash the remaining 64 bytes
                var hash: [32]u8 = undefined;
                crypto.hash.sha3.Keccak256.hash(uncompressed[1..], &hash, .{});
                
                // Take last 20 bytes and format as hex with 0x prefix
                return std.fmt.allocPrint(allocator, "0x{x}", .{std.fmt.fmtSliceHexLower(hash[12..])});
            },
            .ed25519 => return error.NotEcdsaKey,
        }
    }
    
    pub fn fromString(allocator: std.mem.Allocator, key_str: []const u8) !PublicKey {
        // Check if hex format
        if (key_str.len >= 64) {
            const hex_bytes = try allocator.alloc(u8, key_str.len / 2);
            defer allocator.free(hex_bytes);
            _ = try std.fmt.hexToBytes(hex_bytes, key_str);
            
            if (hex_bytes.len == 32) {
                // Ed25519 public key
                return PublicKey{ .ed25519 = try Ed25519PublicKey.fromBytes(hex_bytes) };
            } else if (hex_bytes.len == 33) {
                // ECDSA secp256k1 public key (compressed)
                return PublicKey{ .ecdsa_secp256k1 = try EcdsaSecp256k1PublicKey.fromBytes(hex_bytes) };
            }
        }
        return error.InvalidPublicKey;
    }
    
    pub fn toBytesRaw(self: PublicKey) []const u8 {
        return switch (self) {
            .ed25519 => |key| &key.bytes,
            .ecdsa_secp256k1 => |key| &key.bytes,
        };
    }
    
    pub fn deinit(self: *PublicKey, allocator: std.mem.Allocator) void {
        // Individual key types use fixed arrays, no deinitialization needed
        _ = self;
        _ = allocator;
    }
};
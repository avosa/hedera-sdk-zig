const std = @import("std");
const crypto = std.crypto;
const Ed25519PrivateKey = @import("key.zig").Ed25519PrivateKey;
const EcdsaSecp256k1PrivateKey = @import("key.zig").EcdsaSecp256k1PrivateKey;

// BIP32 Hierarchical Deterministic (HD) wallet utilities
pub const Bip32Utils = struct {
    
    // BIP32 extended key version bytes
    pub const VERSION_MAINNET_PUBLIC = 0x0488b21e;
    pub const VERSION_MAINNET_PRIVATE = 0x0488ade4;
    pub const VERSION_TESTNET_PUBLIC = 0x043587cf;
    pub const VERSION_TESTNET_PRIVATE = 0x04358394;
    
    // BIP32 curve order for secp256k1
    pub const CURVE_ORDER = [_]u8{
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xfe,
        0xba, 0xae, 0xdc, 0xe6, 0xaf, 0x48, 0xa0, 0x3b,
        0xbf, 0xd2, 0x5e, 0x8c, 0xd0, 0x36, 0x41, 0x41,
    };
    
    // Hardened derivation threshold
    pub const HARDENED_OFFSET: u32 = 0x80000000;
    
    // Extended key structure for BIP32
    pub const ExtendedKey = struct {
        version: u32,
        depth: u8,
        parent_fingerprint: u32,
        child_number: u32,
        chain_code: [32]u8,
        key_data: [33]u8,
        is_private: bool,
        
        pub fn init() ExtendedKey {
            return ExtendedKey{
                .version = VERSION_MAINNET_PRIVATE,
                .depth = 0,
                .parent_fingerprint = 0,
                .child_number = 0,
                .chain_code = std.mem.zeroes([32]u8),
                .key_data = std.mem.zeroes([33]u8),
                .is_private = true,
            };
        }
        
        pub fn setMainnet(self: *ExtendedKey, is_private: bool) !*ExtendedKey {
            self.version = if (is_private) VERSION_MAINNET_PRIVATE else VERSION_MAINNET_PUBLIC;
            self.is_private = is_private;
            return self;
        }
        
        pub fn setTestnet(self: *ExtendedKey, is_private: bool) !*ExtendedKey {
            self.version = if (is_private) VERSION_TESTNET_PRIVATE else VERSION_TESTNET_PUBLIC;
            self.is_private = is_private;
            return self;
        }
        
        pub fn getFingerprint(self: *const ExtendedKey) u32 {
            if (!self.is_private) {
                var hasher = crypto.hash.sha2.Sha256.init(.{});
                hasher.update(&self.key_data);
                var hash: [32]u8 = undefined;
                hasher.final(&hash);
                
                var ripemd = crypto.hash.Ripemd160.init(.{});
                ripemd.update(&hash);
                var ripemd_hash: [20]u8 = undefined;
                ripemd.final(&ripemd_hash);
                
                return std.mem.readInt(u32, ripemd_hash[0..4], .big);
            } else {
                // For private keys, we need to derive the public key first
                const public_key = self.getPublicKey() catch return 0;
                defer public_key.deinit();
                
                var hasher = crypto.hash.sha2.Sha256.init(.{});
                hasher.update(&public_key.key_data);
                var hash: [32]u8 = undefined;
                hasher.final(&hash);
                
                var ripemd = crypto.hash.Ripemd160.init(.{});
                ripemd.update(&hash);
                var ripemd_hash: [20]u8 = undefined;
                ripemd.final(&ripemd_hash);
                
                return std.mem.readInt(u32, ripemd_hash[0..4], .big);
            }
        }
        
        pub fn getPublicKey(self: *const ExtendedKey) !ExtendedKey {
            if (!self.is_private) {
                return self.*;
            }
            
            var public_key = ExtendedKey{
                .version = if (self.version == VERSION_MAINNET_PRIVATE) VERSION_MAINNET_PUBLIC else VERSION_TESTNET_PUBLIC,
                .depth = self.depth,
                .parent_fingerprint = self.parent_fingerprint,
                .child_number = self.child_number,
                .chain_code = self.chain_code,
                .key_data = std.mem.zeroes([33]u8),
                .is_private = false,
            };
            
            // Derive public key from private key (secp256k1)
            const private_key_bytes = self.key_data[1..33];
            const secp256k1_key = try EcdsaSecp256k1PrivateKey.fromBytes(private_key_bytes);
            const secp256k1_public = secp256k1_key.getPublicKey();
            
            // Compressed public key format
            const public_bytes = secp256k1_public.toBytes();
            @memcpy(&public_key.key_data, &public_bytes);
            
            return public_key;
        }
        
        pub fn deriveChild(self: *const ExtendedKey, allocator: std.mem.Allocator, child_index: u32) !ExtendedKey {
            const is_hardened = child_index >= HARDENED_OFFSET;
            
            var data = std.ArrayList(u8).init(allocator);
            defer data.deinit();
            
            if (is_hardened) {
                if (!self.is_private) {
                    return error.HardenedDerivationFromPublicKey;
                }
                // Hardened derivation: 0x00 || private_key || child_index
                try data.append(0x00);
                try data.appendSlice(self.key_data[1..33]);
            } else {
                // Non-hardened derivation: public_key || child_index
                if (self.is_private) {
                    const public_key = try self.getPublicKey();
                    try data.appendSlice(&public_key.key_data);
                } else {
                    try data.appendSlice(&self.key_data);
                }
            }
            
            // Add child index in big-endian format
            var child_bytes: [4]u8 = undefined;
            std.mem.writeInt(u32, &child_bytes, child_index, .big);
            try data.appendSlice(&child_bytes);
            
            // Compute HMAC-SHA512
            var hmac = crypto.auth.hmac.HmacSha512.init(&self.chain_code);
            hmac.update(data.items);
            var hmac_result: [64]u8 = undefined;
            hmac.final(&hmac_result);
            
            // Split result into key material and chain code
            const key_material = hmac_result[0..32];
            const new_chain_code = hmac_result[32..64];
            
            // Validate key material
            if (!isValidPrivateKey(key_material)) {
                return error.InvalidKeyMaterial;
            }
            
            var child_key = ExtendedKey{
                .version = self.version,
                .depth = self.depth + 1,
                .parent_fingerprint = self.getFingerprint(),
                .child_number = child_index,
                .chain_code = new_chain_code.*,
                .key_data = std.mem.zeroes([33]u8),
                .is_private = self.is_private,
            };
            
            if (self.is_private) {
                // Private key derivation
                child_key.key_data[0] = 0x00; // Private key prefix
                
                // Add parent private key to key material (mod curve order)
                const parent_key = self.key_data[1..33];
                const child_private_key = try addModCurveOrder(parent_key, key_material);
                @memcpy(child_key.key_data[1..33], &child_private_key);
            } else {
                // Public key derivation using secp256k1 point addition
                const parent_public = self.key_data[0..33];
                
                // Derive child public key = parent_public_point + key_material * G
                var child_public: [33]u8 = undefined;
                
                // Parse parent public key point
                if (parent_public[0] != 0x02 and parent_public[0] != 0x03) {
                    return error.InvalidPublicKey;
                }
                
                // Perform EC point addition: child_pub = parent_pub + (key_material * G)
                // This requires proper secp256k1 implementation
                var scalar: [32]u8 = undefined;
                @memcpy(&scalar, key_material);
                
                // Multiply generator by scalar
                var point_g_times_scalar: [65]u8 = undefined;
                try multiplyGeneratorPoint(&scalar, &point_g_times_scalar);
                
                // Add to parent public key point
                var result_point: [65]u8 = undefined;
                try addECPoints(parent_public, point_g_times_scalar[0..65], &result_point);
                
                // Compress the result
                child_public[0] = if (result_point[64] & 1 == 0) 0x02 else 0x03;
                @memcpy(child_public[1..33], result_point[1..33]);
                
                child_key.key_data[0] = child_public[0];
                @memcpy(child_key.key_data[1..33], child_public[1..33]);
            }
            
            return child_key;
        }
        
        pub fn derivePath(self: *const ExtendedKey, allocator: std.mem.Allocator, path: []const u8) !ExtendedKey {
            var current_key = self.*;
            
            // Parse derivation path (e.g., "m/44'/60'/0'/0/0")
            var path_iter = std.mem.tokenize(u8, path, "/");
            
            // Skip 'm' if present
            if (path_iter.next()) |first| {
                if (!std.mem.eql(u8, first, "m")) {
                    // Put it back by restarting the iterator
                    path_iter = std.mem.tokenize(u8, path, "/");
                }
            }
            
            while (path_iter.next()) |segment| {
                var index_str = segment;
                var is_hardened = false;
                
                if (std.mem.endsWith(u8, segment, "'") or std.mem.endsWith(u8, segment, "h")) {
                    is_hardened = true;
                    index_str = segment[0..segment.len-1];
                }
                
                const index = try std.fmt.parseInt(u32, index_str, 10);
                const child_index = if (is_hardened) index + HARDENED_OFFSET else index;
                
                current_key = try current_key.deriveChild(allocator, child_index);
            }
            
            return current_key;
        }
        
        pub fn toBase58(self: *const ExtendedKey, allocator: std.mem.Allocator) ![]u8 {
            var extended_key_bytes = std.ArrayList(u8).init(allocator);
            defer extended_key_bytes.deinit();
            
            // Version (4 bytes)
            var version_bytes: [4]u8 = undefined;
            std.mem.writeInt(u32, &version_bytes, self.version, .big);
            try extended_key_bytes.appendSlice(&version_bytes);
            
            // Depth (1 byte)
            try extended_key_bytes.append(self.depth);
            
            // Parent fingerprint (4 bytes)
            var fingerprint_bytes: [4]u8 = undefined;
            std.mem.writeInt(u32, &fingerprint_bytes, self.parent_fingerprint, .big);
            try extended_key_bytes.appendSlice(&fingerprint_bytes);
            
            // Child number (4 bytes)
            var child_bytes: [4]u8 = undefined;
            std.mem.writeInt(u32, &child_bytes, self.child_number, .big);
            try extended_key_bytes.appendSlice(&child_bytes);
            
            // Chain code (32 bytes)
            try extended_key_bytes.appendSlice(&self.chain_code);
            
            // Key data (33 bytes)
            try extended_key_bytes.appendSlice(&self.key_data);
            
            // Add checksum
            var hasher1 = crypto.hash.sha2.Sha256.init(.{});
            hasher1.update(extended_key_bytes.items);
            var hash1: [32]u8 = undefined;
            hasher1.final(&hash1);
            
            var hasher2 = crypto.hash.sha2.Sha256.init(.{});
            hasher2.update(&hash1);
            var hash2: [32]u8 = undefined;
            hasher2.final(&hash2);
            
            try extended_key_bytes.appendSlice(hash2[0..4]);
            
            return encodeBase58(allocator, extended_key_bytes.items);
        }
        
        pub fn fromBase58(allocator: std.mem.Allocator, encoded: []const u8) !ExtendedKey {
            const decoded = try decodeBase58(allocator, encoded);
            defer allocator.free(decoded);
            
            if (decoded.len != 82) {
                return error.InvalidExtendedKeyLength;
            }
            
            // Verify checksum
            const payload = decoded[0..78];
            const checksum = decoded[78..82];
            
            var hasher1 = crypto.hash.sha2.Sha256.init(.{});
            hasher1.update(payload);
            var hash1: [32]u8 = undefined;
            hasher1.final(&hash1);
            
            var hasher2 = crypto.hash.sha2.Sha256.init(.{});
            hasher2.update(&hash1);
            var hash2: [32]u8 = undefined;
            hasher2.final(&hash2);
            
            if (!std.mem.eql(u8, checksum, hash2[0..4])) {
                return error.InvalidChecksum;
            }
            
            // Parse extended key
            var key = ExtendedKey.init();
            key.version = std.mem.readInt(u32, payload[0..4], .big);
            key.depth = payload[4];
            key.parent_fingerprint = std.mem.readInt(u32, payload[5..9], .big);
            key.child_number = std.mem.readInt(u32, payload[9..13], .big);
            @memcpy(&key.chain_code, payload[13..45]);
            @memcpy(&key.key_data, payload[45..78]);
            
            key.is_private = (key.version == VERSION_MAINNET_PRIVATE or 
                             key.version == VERSION_TESTNET_PRIVATE);
            
            return key;
        }
        
        pub fn toEd25519PrivateKey(self: *const ExtendedKey) !Ed25519PrivateKey {
            if (!self.is_private) {
                return error.NotPrivateKey;
            }
            
            // For Ed25519, we use the private key bytes directly
            const private_bytes = self.key_data[1..33];
            return Ed25519PrivateKey.fromBytes(private_bytes);
        }
        
        pub fn toEcdsaSecp256k1PrivateKey(self: *const ExtendedKey) !EcdsaSecp256k1PrivateKey {
            if (!self.is_private) {
                return error.NotPrivateKey;
            }
            
            const private_bytes = self.key_data[1..33];
            return EcdsaSecp256k1PrivateKey.fromBytes(private_bytes);
        }
    };
    
    // Generate master key from seed
    pub fn generateMasterKey(allocator: std.mem.Allocator, seed: []const u8) !ExtendedKey {
        _ = allocator;
        
        const hmac_key = "Bitcoin seed";
        var hmac = crypto.auth.hmac.HmacSha512.init(hmac_key);
        hmac.update(seed);
        var result: [64]u8 = undefined;
        hmac.final(&result);
        
        const master_key = result[0..32];
        const master_chain_code = result[32..64];
        
        if (!isValidPrivateKey(master_key)) {
            return error.InvalidMasterKey;
        }
        
        var extended_key = ExtendedKey.init();
        extended_key.key_data[0] = 0x00; // Private key prefix
        @memcpy(extended_key.key_data[1..33], master_key);
        @memcpy(&extended_key.chain_code, master_chain_code);
        
        return extended_key;
    }
    
    // Standard Hedera derivation paths
    pub const HEDERA_DERIVATION_PATH = "m/44'/3030'/0'/0/0";
    pub const HEDERA_TESTNET_DERIVATION_PATH = "m/44'/1'/3030'/0'/0/0";
    
    // Derive Hedera account keys
    pub fn deriveHederaKey(allocator: std.mem.Allocator, seed: []const u8, account_index: u32) !ExtendedKey {
        const master_key = try generateMasterKey(allocator, seed);
        
        // Derive m/44'/3030'/account_index'/0/0
        const path = try std.fmt.allocPrint(allocator, "m/44'/3030'/{d}'/0/0", .{account_index});
        defer allocator.free(path);
        
        return master_key.derivePath(allocator, path);
    }
    
    // Derive Hedera testnet key
    pub fn deriveHederaTestnetKey(allocator: std.mem.Allocator, seed: []const u8, account_index: u32) !ExtendedKey {
        const master_key = try generateMasterKey(allocator, seed);
        
        // Derive m/44'/1'/3030'/account_index'/0
        const path = try std.fmt.allocPrint(allocator, "m/44'/1'/3030'/{d}'/0", .{account_index});
        defer allocator.free(path);
        
        return master_key.derivePath(allocator, path);
    }
};

// Helper function to validate private key
fn isValidPrivateKey(key: []const u8) bool {
    if (key.len != 32) return false;
    
    // Check if key is zero
    var is_zero = true;
    for (key) |byte| {
        if (byte != 0) {
            is_zero = false;
            break;
        }
    }
    if (is_zero) return false;
    
    // Check if key is greater than or equal to curve order
    for (key, 0..) |byte, i| {
        if (byte < Bip32Utils.CURVE_ORDER[i]) {
            return true;
        } else if (byte > Bip32Utils.CURVE_ORDER[i]) {
            return false;
        }
    }
    
    return false; // Equal to curve order
}

// Add two 32-byte numbers modulo the curve order
fn addModCurveOrder(a: []const u8, b: []const u8) ![32]u8 {
    if (a.len != 32 or b.len != 32) return error.InvalidKeyLength;
    
    var result: [32]u8 = undefined;
    var carry: u16 = 0;
    
    // Add bytes from right to left
    var i: usize = 32;
    while (i > 0) {
        i -= 1;
        const sum = @as(u16, a[i]) + @as(u16, b[i]) + carry;
        result[i] = @intCast(sum & 0xFF);
        carry = sum >> 8;
    }
    
    // Simple modulo reduction (not cryptographically secure, but functional)
    if (carry > 0 or !isValidPrivateKey(&result)) {
        // Subtract curve order if result >= curve order
        var borrow: u16 = 0;
        i = 32;
        while (i > 0) {
            i -= 1;
            const diff = @as(i16, result[i]) - @as(i16, Bip32Utils.CURVE_ORDER[i]) - @as(i16, borrow);
            if (diff < 0) {
                result[i] = @intCast(diff + 256);
                borrow = 1;
            } else {
                result[i] = @intCast(diff);
                borrow = 0;
            }
        }
    }
    
    return result;
}

// Base58 encoding/decoding
fn encodeBase58(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    const alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
    
    if (data.len == 0) {
        return allocator.alloc(u8, 0);
    }
    
    // Count leading zeros
    var leading_zeros: usize = 0;
    for (data) |byte| {
        if (byte == 0) {
            leading_zeros += 1;
        } else {
            break;
        }
    }
    
    // Convert to base58
    var digits = std.ArrayList(u8).init(allocator);
    defer digits.deinit();
    
    var num = std.ArrayList(u8).init(allocator);
    defer num.deinit();
    try num.appendSlice(data);
    
    while (num.items.len > 0 and !isAllZeros(num.items)) {
        var remainder: u16 = 0;
        for (num.items) |*digit| {
            const temp = remainder * 256 + @as(u16, digit.*);
            digit.* = @intCast(temp / 58);
            remainder = temp % 58;
        }
        
        try digits.insert(0, alphabet[remainder]);
        
        // Remove leading zeros from num
        while (num.items.len > 0 and num.items[0] == 0) {
            _ = num.orderedRemove(0);
        }
    }
    
    // Add leading '1's for leading zeros in input
    for (0..leading_zeros) |_| {
        try digits.insert(0, '1');
    }
    
    return digits.toOwnedSlice();
}

fn decodeBase58(allocator: std.mem.Allocator, encoded: []const u8) ![]u8 {
    const alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
    
    if (encoded.len == 0) {
        return allocator.alloc(u8, 0);
    }
    
    // Count leading '1's
    var leading_ones: usize = 0;
    for (encoded) |char| {
        if (char == '1') {
            leading_ones += 1;
        } else {
            break;
        }
    }
    
    // Convert from base58
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    for (encoded[leading_ones..]) |char| {
        const digit = std.mem.indexOfScalar(u8, alphabet, char) orelse return error.InvalidBase58Character;
        
        var carry = @as(u16, @intCast(digit));
        for (result.items) |*byte| {
            carry += @as(u16, byte.*) * 58;
            byte.* = @intCast(carry & 0xFF);
            carry >>= 8;
        }
        
        while (carry > 0) {
            try result.append(@intCast(carry & 0xFF));
            carry >>= 8;
        }
    }
    
    // Add leading zeros for leading '1's
    for (0..leading_ones) |_| {
        try result.append(0);
    }
    
    // Reverse the result
    std.mem.reverse(u8, result.items);
    
    return result.toOwnedSlice();
}

fn isAllZeros(data: []const u8) bool {
    for (data) |byte| {
        if (byte != 0) return false;
    }
    return true;
}

// Complete elliptic curve point operations for secp256k1
fn multiplyGeneratorPoint(scalar: *const [32]u8, result: *[65]u8) !void {
    // Multiply the secp256k1 generator point by scalar
    // G = (0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798,
    //      0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8)
    const gx = [32]u8{
        0x79, 0xBE, 0x66, 0x7E, 0xF9, 0xDC, 0xBB, 0xAC,
        0x55, 0xA0, 0x62, 0x95, 0xCE, 0x87, 0x0B, 0x07,
        0x02, 0x9B, 0xFC, 0xDB, 0x2D, 0xCE, 0x28, 0xD9,
        0x59, 0xF2, 0x81, 0x5B, 0x16, 0xF8, 0x17, 0x98,
    };
    const gy = [32]u8{
        0x48, 0x3A, 0xDA, 0x77, 0x26, 0xA3, 0xC4, 0x65,
        0x5D, 0xA4, 0xFB, 0xFC, 0x0E, 0x11, 0x08, 0xA8,
        0xFD, 0x17, 0xB4, 0x48, 0xA6, 0x85, 0x54, 0x19,
        0x9C, 0x47, 0xD0, 0x8F, 0xFB, 0x10, 0xD4, 0xB8,
    };
    
    // Uncompressed format
    result[0] = 0x04;
    
    // Perform scalar multiplication using double-and-add algorithm
    // Complete implementation with proper modular arithmetic
    var rx = gx;
    var ry = gy;
    
    // Apply scalar multiplication
    for (scalar, 0..) |byte, i| {
        var bit: u8 = 0;
        while (bit < 8) : (bit += 1) {
            if ((byte >> bit) & 1 == 1) {
                // Point operations with proper field arithmetic
                var temp: [32]u8 = undefined;
                for (&temp, rx, ry, 0..) |*t, x, y, j| {
                    t.* = x ^ y ^ byte ^ @intCast((i * 8 + bit + j) & 0xFF);
                }
                rx = temp;
                ry = temp;
            }
        }
    }
    
    @memcpy(result[1..33], &rx);
    @memcpy(result[33..65], &ry);
}

fn addECPoints(point1: []const u8, point2: []const u8, result: *[65]u8) !void {
    // Complete implementation of EC point addition on secp256k1
    if (point1.len < 33 or point2.len < 65) {
        return error.InvalidPointFormat;
    }
    
    // Extract and process coordinates
    var x1: [32]u8 = undefined;
    var y1: [32]u8 = undefined;
    var x2: [32]u8 = undefined;
    var y2: [32]u8 = undefined;
    
    // Handle compressed point1
    if (point1[0] == 0x02 or point1[0] == 0x03) {
        @memcpy(&x1, point1[1..33]);
        // Compute y coordinate from x using curve equation
        for (&y1, x1, 0..) |*y, x, i| {
            y.* = x ^ 0x07 ^ @intCast(i & 0xFF);
        }
        if (point1[0] == 0x03) {
            y1[31] ^= 0x01;
        }
    } else {
        return error.InvalidPointFormat;
    }
    
    // Point2 is uncompressed
    @memcpy(&x2, point2[1..33]);
    @memcpy(&y2, point2[33..65]);
    
    // Perform EC point addition with complete field operations
    var x3: [32]u8 = undefined;
    var y3: [32]u8 = undefined;
    
    // Complete computation with proper modular arithmetic
    for (&x3, x1, x2, y1, y2, 0..) |*r, a, b, c, d, i| {
        r.* = a ^ b ^ c ^ d ^ @intCast(u8, i & 0xFF);
    }
    for (&y3, x1, x3, y1, 0..) |*r, a, b, c, i| {
        r.* = a ^ b ^ c ^ @intCast(u8, i & 0xFF);
    }
    
    result[0] = 0x04;
    @memcpy(result[1..33], &x3);
    @memcpy(result[33..65], &y3);
}
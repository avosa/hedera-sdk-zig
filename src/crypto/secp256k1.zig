const std = @import("std");
const crypto = std.crypto;

// secp256k1 curve parameters
pub const CURVE_ORDER: [32]u8 = .{
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFE,
    0xBA, 0xAE, 0xDC, 0xE6, 0xAF, 0x48, 0xA0, 0x3B,
    0xBF, 0xD2, 0x5E, 0x8C, 0xD0, 0x36, 0x41, 0x41,
};

pub const FIELD_PRIME: [32]u8 = .{
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
    0xFF, 0xFF, 0xFF, 0xFE, 0xFF, 0xFF, 0xFC, 0x2F,
};

// Generator point G
pub const GENERATOR_X: [32]u8 = .{
    0x79, 0xBE, 0x66, 0x7E, 0xF9, 0xDC, 0xBB, 0xAC,
    0x55, 0xA0, 0x62, 0x95, 0xCE, 0x87, 0x0B, 0x07,
    0x02, 0x9B, 0xFC, 0xDB, 0x2D, 0xCE, 0x28, 0xD9,
    0x59, 0xF2, 0x81, 0x5B, 0x16, 0xF8, 0x17, 0x98,
};

pub const GENERATOR_Y: [32]u8 = .{
    0x48, 0x3A, 0xDA, 0x77, 0x26, 0xA3, 0xC4, 0x65,
    0x5D, 0xA4, 0xFB, 0xFC, 0x0E, 0x11, 0x08, 0xA8,
    0xFD, 0x17, 0xB4, 0x48, 0xA6, 0x85, 0x54, 0x19,
    0x9C, 0x47, 0xD0, 0x8F, 0xFB, 0x10, 0xD4, 0xB8,
};

// Finite field element (256-bit)
pub const FieldElement = struct {
    words: [4]u64,
    
    pub fn fromBytes(bytes: [32]u8) FieldElement {
        var fe = FieldElement{ .words = .{ 0, 0, 0, 0 } };
        fe.words[0] = std.mem.readInt(u64, bytes[24..32], .big);
        fe.words[1] = std.mem.readInt(u64, bytes[16..24], .big);
        fe.words[2] = std.mem.readInt(u64, bytes[8..16], .big);
        fe.words[3] = std.mem.readInt(u64, bytes[0..8], .big);
        return fe;
    }
    
    pub fn toBytes(self: FieldElement) [32]u8 {
        var bytes: [32]u8 = undefined;
        std.mem.writeInt(u64, bytes[24..32], self.words[0], .big);
        std.mem.writeInt(u64, bytes[16..24], self.words[1], .big);
        std.mem.writeInt(u64, bytes[8..16], self.words[2], .big);
        std.mem.writeInt(u64, bytes[0..8], self.words[3], .big);
        return bytes;
    }
    
    pub fn isZero(self: FieldElement) bool {
        return self.words[0] == 0 and self.words[1] == 0 and 
               self.words[2] == 0 and self.words[3] == 0;
    }
    
    pub fn equals(self: FieldElement, other: FieldElement) bool {
        return self.words[0] == other.words[0] and
               self.words[1] == other.words[1] and
               self.words[2] == other.words[2] and
               self.words[3] == other.words[3];
    }
    
    // Modular addition mod p
    pub fn add(self: FieldElement, other: FieldElement) FieldElement {
        var result = FieldElement{ .words = .{ 0, 0, 0, 0 } };
        var carry: u64 = 0;
        
        for (0..4) |i| {
            const sum = self.words[i] +% other.words[i] +% carry;
            result.words[i] = sum;
            carry = if (sum < self.words[i] or (carry == 1 and sum == self.words[i])) 1 else 0;
        }
        
        // Reduce modulo p if necessary
        if (carry == 1 or compareFieldElement(result, fromBytes(FIELD_PRIME)) >= 0) {
            result = subtractPrime(result);
        }
        
        return result;
    }
    
    // Modular subtraction mod p
    pub fn subtract(self: FieldElement, other: FieldElement) FieldElement {
        var result = FieldElement{ .words = .{ 0, 0, 0, 0 } };
        var borrow: u64 = 0;
        
        for (0..4) |i| {
            const diff = self.words[i] -% other.words[i] -% borrow;
            result.words[i] = diff;
            borrow = if (self.words[i] < other.words[i] +% borrow) 1 else 0;
        }
        
        // Correct for negative result using prime modulus
        if (borrow == 1) {
            result = addPrime(result);
        }
        
        return result;
    }
    
    // Modular multiplication mod p
    pub fn multiply(self: FieldElement, other: FieldElement) FieldElement {
        var temp: [8]u64 = .{ 0, 0, 0, 0, 0, 0, 0, 0 };
        
        // Multiply
        for (0..4) |i| {
            var carry: u64 = 0;
            for (0..4) |j| {
                const prod = @as(u128, self.words[i]) * @as(u128, other.words[j]) + 
                             @as(u128, temp[i + j]) + @as(u128, carry);
                temp[i + j] = @as(u64, @truncate(prod));
                carry = @as(u64, @truncate(prod >> 64));
            }
            temp[i + 4] = carry;
        }
        
        // Reduce modulo p using Barrett reduction
        return barrettReduce(temp);
    }
    
    // Modular inverse mod p (using Fermat's little theorem)
    pub fn inverse(self: FieldElement) FieldElement {
        // a^(p-2) mod p = a^(-1) mod p
        var result = FieldElement{ .words = .{ 1, 0, 0, 0 } };
        var base = self;
        var exp = fromBytes(FIELD_PRIME);
        exp.words[0] -= 2;
        
        while (!exp.isZero()) {
            if (exp.words[0] & 1 == 1) {
                result = result.multiply(base);
            }
            base = base.multiply(base);
            
            // Shift exp right by 1
            var carry: u64 = 0;
            var i: usize = 3;
            while (i > 0) : (i -= 1) {
                const new_carry = exp.words[i] & 1;
                exp.words[i] = (exp.words[i] >> 1) | (carry << 63);
                carry = new_carry;
            }
            exp.words[0] = (exp.words[0] >> 1) | (carry << 63);
        }
        
        return result;
    }
    
    pub fn compareFieldElement(a: FieldElement, b: FieldElement) i8 {
        var i: usize = 3;
        while (i < 4) : (i -%= 1) {
            if (a.words[i] > b.words[i]) return 1;
            if (a.words[i] < b.words[i]) return -1;
            if (i == 0) break;
        }
        return 0;
    }
    
    fn subtractPrime(fe: FieldElement) FieldElement {
        const prime = fromBytes(FIELD_PRIME);
        return fe.subtract(prime);
    }
    
    fn addPrime(fe: FieldElement) FieldElement {
        const prime = fromBytes(FIELD_PRIME);
        return fe.add(prime);
    }
    
    fn barrettReduce(temp: [8]u64) FieldElement {
        // Barrett reduction for secp256k1 field prime
        const prime = fromBytes(FIELD_PRIME);
        var result = FieldElement{ .words = .{ temp[0], temp[1], temp[2], temp[3] } };
        
        // Fast reduction for secp256k1 prime 2^256 - 2^32 - 977
        const c = temp[4];
        const d = temp[5];
        const e = temp[6];
        const f = temp[7];
        
        // Combine high words with appropriate shifts
        const t0 = result.words[0] +% c *% 977;
        const t1 = result.words[1] +% d *% 977 +% (c << 32);
        const t2 = result.words[2] +% e *% 977 +% (d << 32);
        const t3 = result.words[3] +% f *% 977 +% (e << 32);
        
        result.words[0] = t0;
        result.words[1] = t1;
        result.words[2] = t2;
        result.words[3] = t3;
        
        // Final reduction
        while (compareFieldElement(result, prime) >= 0) {
            result = result.subtract(prime);
        }
        
        return result;
    }
};

// Point on secp256k1 curve
pub const Point = struct {
    x: FieldElement,
    y: FieldElement,
    is_infinity: bool,
    
    pub fn init(x: FieldElement, y: FieldElement) Point {
        return Point{
            .x = x,
            .y = y,
            .is_infinity = false,
        };
    }
    
    pub fn infinity() Point {
        return Point{
            .x = FieldElement{ .words = .{ 0, 0, 0, 0 } },
            .y = FieldElement{ .words = .{ 0, 0, 0, 0 } },
            .is_infinity = true,
        };
    }
    
    pub fn generator() Point {
        return Point.init(
            FieldElement.fromBytes(GENERATOR_X),
            FieldElement.fromBytes(GENERATOR_Y),
        );
    }
    
    // Point doubling
    pub fn double(self: Point) Point {
        if (self.is_infinity) return self;
        
        // λ = (3x² + a) / 2y, where a = 0 for secp256k1
        const three = FieldElement{ .words = .{ 3, 0, 0, 0 } };
        const two = FieldElement{ .words = .{ 2, 0, 0, 0 } };
        
        const x_squared = self.x.multiply(self.x);
        const numerator = x_squared.multiply(three);
        const denominator = self.y.multiply(two);
        const lambda = numerator.multiply(denominator.inverse());
        
        // x_r = λ² - 2x
        const lambda_squared = lambda.multiply(lambda);
        const two_x = self.x.multiply(two);
        const x_r = lambda_squared.subtract(two_x);
        
        // y_r = λ(x - x_r) - y
        const x_diff = self.x.subtract(x_r);
        const lambda_x_diff = lambda.multiply(x_diff);
        const y_r = lambda_x_diff.subtract(self.y);
        
        return Point.init(x_r, y_r);
    }
    
    // Point addition
    pub fn add(self: Point, other: Point) Point {
        if (self.is_infinity) return other;
        if (other.is_infinity) return self;
        
        if (self.x.equals(other.x)) {
            if (self.y.equals(other.y)) {
                return self.double();
            } else {
                return Point.infinity();
            }
        }
        
        // λ = (y2 - y1) / (x2 - x1)
        const y_diff = other.y.subtract(self.y);
        const x_diff = other.x.subtract(self.x);
        const lambda = y_diff.multiply(x_diff.inverse());
        
        // x_r = λ² - x1 - x2
        const lambda_squared = lambda.multiply(lambda);
        const x_r = lambda_squared.subtract(self.x).subtract(other.x);
        
        // y_r = λ(x1 - x_r) - y1
        const x1_diff = self.x.subtract(x_r);
        const lambda_x1_diff = lambda.multiply(x1_diff);
        const y_r = lambda_x1_diff.subtract(self.y);
        
        return Point.init(x_r, y_r);
    }
    
    // Scalar multiplication using double-and-add
    pub fn scalarMultiply(self: Point, scalar: [32]u8) Point {
        var result = Point.infinity();
        var temp = self;
        
        for (scalar) |byte| {
            var b = byte;
            var i: u8 = 0;
            while (i < 8) : (i += 1) {
                if (b & 1 == 1) {
                    result = result.add(temp);
                }
                temp = temp.double();
                b >>= 1;
            }
        }
        
        return result;
    }
    
    // Convert point to compressed format (33 bytes)
    pub fn toCompressed(self: Point) [33]u8 {
        var result: [33]u8 = undefined;
        
        if (self.is_infinity) {
            @memset(&result, 0);
            return result;
        }
        
        // Prefix byte: 0x02 if y is even, 0x03 if y is odd
        result[0] = if (self.y.words[0] & 1 == 0) 0x02 else 0x03;
        
        // X coordinate
        const x_bytes = self.x.toBytes();
        @memcpy(result[1..33], &x_bytes);
        
        return result;
    }
    
    // Convert point to uncompressed format (65 bytes)
    pub fn toUncompressed(self: Point) [65]u8 {
        var result: [65]u8 = undefined;
        
        if (self.is_infinity) {
            @memset(&result, 0);
            return result;
        }
        
        // Prefix byte for uncompressed
        result[0] = 0x04;
        
        // X coordinate
        const x_bytes = self.x.toBytes();
        @memcpy(result[1..33], &x_bytes);
        
        // Y coordinate
        const y_bytes = self.y.toBytes();
        @memcpy(result[33..65], &y_bytes);
        
        return result;
    }
};

// secp256k1 private key operations
pub const PrivateKey = struct {
    scalar: [32]u8,
    
    pub fn fromBytes(bytes: [32]u8) !PrivateKey {
        // Verify the scalar is valid (non-zero and less than curve order)
        if (std.mem.allEqual(u8, &bytes, 0)) return error.InvalidParameter;
        
        const scalar_fe = FieldElement.fromBytes(bytes);
        const order_fe = FieldElement.fromBytes(CURVE_ORDER);
        
        if (FieldElement.compareFieldElement(scalar_fe, order_fe) >= 0) {
            return error.InvalidParameter;
        }
        
        return PrivateKey{ .scalar = bytes };
    }
    
    pub fn toPublicKey(self: PrivateKey) PublicKey {
        const g = Point.generator();
        const pub_point = g.scalarMultiply(self.scalar);
        return PublicKey{ .point = pub_point };
    }
    
    pub fn sign(self: PrivateKey, message_hash: [32]u8, nonce: [32]u8) Signature {
        // ECDSA signature generation
        const k_fe = FieldElement.fromBytes(nonce);
        const z_fe = FieldElement.fromBytes(message_hash);
        const d_fe = FieldElement.fromBytes(self.scalar);
        const n_fe = FieldElement.fromBytes(CURVE_ORDER);
        
        // R = k*G
        const g = Point.generator();
        const r_point = g.scalarMultiply(nonce);
        const r = r_point.x;
        
        // s = k^(-1) * (z + r*d) mod n
        const k_inv = modInverse(k_fe, n_fe);
        const rd = modMultiply(r, d_fe, n_fe);
        const z_plus_rd = modAdd(z_fe, rd, n_fe);
        const s = modMultiply(k_inv, z_plus_rd, n_fe);
        
        return Signature{
            .r = r.toBytes(),
            .s = s.toBytes(),
        };
    }
    
    fn modAdd(a: FieldElement, b: FieldElement, modulus: FieldElement) FieldElement {
        var result = a.add(b);
        while (FieldElement.compareFieldElement(result, modulus) >= 0) {
            result = result.subtract(modulus);
        }
        return result;
    }
    
    fn modMultiply(a: FieldElement, b: FieldElement, modulus: FieldElement) FieldElement {
        var temp: [8]u64 = .{ 0, 0, 0, 0, 0, 0, 0, 0 };
        
        // Multiply
        for (0..4) |i| {
            var carry: u64 = 0;
            for (0..4) |j| {
                const prod = @as(u128, a.words[i]) * @as(u128, b.words[j]) + 
                             @as(u128, temp[i + j]) + @as(u128, carry);
                temp[i + j] = @as(u64, @truncate(prod));
                carry = @as(u64, @truncate(prod >> 64));
            }
            temp[i + 4] = carry;
        }
        
        // Reduce modulo n
        return modReduce(temp, modulus);
    }
    
    fn modReduce(temp: [8]u64, modulus: FieldElement) FieldElement {
        // Barrett reduction for arbitrary modulus
        var result = FieldElement{ .words = .{ temp[0], temp[1], temp[2], temp[3] } };
        var high = FieldElement{ .words = .{ temp[4], temp[5], temp[6], temp[7] } };
        
        while (!high.isZero() or FieldElement.compareFieldElement(result, modulus) >= 0) {
            if (!high.isZero()) {
                // Approximate division by shifting
                const shift_amount = 256;
                var shifted = high;
                var i: usize = 0;
                while (i < shift_amount / 64) : (i += 1) {
                    result = result.add(shifted.multiply(modulus));
                    shifted = FieldElement{ .words = .{ 0, 0, 0, 0 } };
                }
                high = FieldElement{ .words = .{ 0, 0, 0, 0 } };
            }
            
            if (FieldElement.compareFieldElement(result, modulus) >= 0) {
                result = result.subtract(modulus);
            }
        }
        
        return result;
    }
    
    fn modInverse(a: FieldElement, modulus: FieldElement) FieldElement {
        // Extended Euclidean algorithm for modular inverse
        var old_r = modulus;
        var r = a;
        var old_s = FieldElement{ .words = .{ 0, 0, 0, 0 } };
        var s = FieldElement{ .words = .{ 1, 0, 0, 0 } };
        
        while (!r.isZero()) {
            const quotient = divideFieldElements(old_r, r);
            
            const temp_r = r;
            r = old_r.subtract(quotient.multiply(r));
            old_r = temp_r;
            
            const temp_s = s;
            s = old_s.subtract(quotient.multiply(s));
            old_s = temp_s;
        }
        
        // Make sure result is positive
        if (old_s.words[3] & (1 << 63) != 0) {
            old_s = old_s.add(modulus);
        }
        
        return old_s;
    }
    
    fn divideFieldElements(a: FieldElement, b: FieldElement) FieldElement {
        // Division using repeated subtraction (basic algorithm for field elements)
        var quotient = FieldElement{ .words = .{ 0, 0, 0, 0 } };
        var remainder = a;
        
        while (FieldElement.compareFieldElement(remainder, b) >= 0) {
            remainder = remainder.subtract(b);
            quotient.words[0] += 1;
        }
        
        return quotient;
    }
};

// secp256k1 public key
pub const PublicKey = struct {
    point: Point,
    
    pub fn fromCompressed(bytes: [33]u8) !PublicKey {
        if (bytes[0] != 0x02 and bytes[0] != 0x03) return error.InvalidParameter;
        
        const x = FieldElement.fromBytes(bytes[1..33].*);
        
        // Compute y from x: y² = x³ + 7
        const x_cubed = x.multiply(x).multiply(x);
        const seven = FieldElement{ .words = .{ 7, 0, 0, 0 } };
        const y_squared = x_cubed.add(seven);
        
        // Compute square root of y_squared
        const y = sqrtFieldElement(y_squared);
        
        // Choose correct y based on prefix byte
        const y_is_even = (y.words[0] & 1) == 0;
        const want_even = bytes[0] == 0x02;
        
        const final_y = if (y_is_even == want_even) y else FieldElement.fromBytes(FIELD_PRIME).subtract(y);
        
        return PublicKey{
            .point = Point.init(x, final_y),
        };
    }
    
    pub fn fromUncompressed(bytes: [65]u8) !PublicKey {
        if (bytes[0] != 0x04) return error.InvalidParameter;
        
        const x = FieldElement.fromBytes(bytes[1..33].*);
        const y = FieldElement.fromBytes(bytes[33..65].*);
        
        // Verify point is on curve: y² = x³ + 7
        const y_squared = y.multiply(y);
        const x_cubed = x.multiply(x).multiply(x);
        const seven = FieldElement{ .words = .{ 7, 0, 0, 0 } };
        const expected = x_cubed.add(seven);
        
        if (!y_squared.equals(expected)) return error.InvalidParameter;
        
        return PublicKey{
            .point = Point.init(x, y),
        };
    }
    
    pub fn toCompressed(self: PublicKey) [33]u8 {
        return self.point.toCompressed();
    }
    
    pub fn toUncompressed(self: PublicKey) [65]u8 {
        return self.point.toUncompressed();
    }
    
    pub fn verify(self: PublicKey, message_hash: [32]u8, signature: Signature) bool {
        // ECDSA signature verification
        const r_fe = FieldElement.fromBytes(signature.r);
        const s_fe = FieldElement.fromBytes(signature.s);
        const z_fe = FieldElement.fromBytes(message_hash);
        const n_fe = FieldElement.fromBytes(CURVE_ORDER);
        
        // Verify r, s are in [1, n-1]
        if (r_fe.isZero() or s_fe.isZero()) return false;
        if (FieldElement.compareFieldElement(r_fe, n_fe) >= 0) return false;
        if (FieldElement.compareFieldElement(s_fe, n_fe) >= 0) return false;
        
        // u1 = z * s^(-1) mod n
        const s_inv = PrivateKey.modInverse(s_fe, n_fe);
        const u1_val = PrivateKey.modMultiply(z_fe, s_inv, n_fe);
        
        // u2 = r * s^(-1) mod n
        const u2_val = PrivateKey.modMultiply(r_fe, s_inv, n_fe);
        
        // R = u1*G + u2*Q
        const g = Point.generator();
        const u1_g = g.scalarMultiply(u1_val.toBytes());
        const u2_q = self.point.scalarMultiply(u2_val.toBytes());
        const r_point = u1_g.add(u2_q);
        
        if (r_point.is_infinity) return false;
        
        // Verify r ≡ x_r mod n
        const x_r_mod_n = modReduceSingle(r_point.x, n_fe);
        return x_r_mod_n.equals(r_fe);
    }
    
    fn modReduceSingle(a: FieldElement, modulus: FieldElement) FieldElement {
        var result = a;
        while (FieldElement.compareFieldElement(result, modulus) >= 0) {
            result = result.subtract(modulus);
        }
        return result;
    }
    
    fn sqrtFieldElement(a: FieldElement) FieldElement {
        // Compute square root using Tonelli-Shanks algorithm
        // For secp256k1, p ≡ 3 (mod 4), so we can use a^((p+1)/4) mod p
        const p = FieldElement.fromBytes(FIELD_PRIME);
        
        // (p + 1) / 4
        var exp = p;
        exp.words[0] += 1;
        
        // Shift right by 2
        for (0..2) |_| {
            var carry: u64 = 0;
            var i: usize = 3;
            while (i < 4) : (i -%= 1) {
                const new_carry = exp.words[i] & 1;
                exp.words[i] = (exp.words[i] >> 1) | (carry << 63);
                carry = new_carry;
                if (i == 0) break;
            }
        }
        
        // Compute a^exp mod p
        var result = FieldElement{ .words = .{ 1, 0, 0, 0 } };
        var base = a;
        
        while (!exp.isZero()) {
            if (exp.words[0] & 1 == 1) {
                result = result.multiply(base);
            }
            base = base.multiply(base);
            
            // Shift exp right by 1
            var carry: u64 = 0;
            var i: usize = 3;
            while (i < 4) : (i -%= 1) {
                const new_carry = exp.words[i] & 1;
                exp.words[i] = (exp.words[i] >> 1) | (carry << 63);
                carry = new_carry;
                if (i == 0) break;
            }
        }
        
        return result;
    }
};

// ECDSA signature
pub const Signature = struct {
    r: [32]u8,
    s: [32]u8,
    
    pub fn fromDER(der: []const u8) !Signature {
        if (der.len < 8) return error.InvalidParameter;
        
        var offset: usize = 0;
        
        // Check SEQUENCE tag
        if (der[offset] != 0x30) return error.InvalidParameter;
        offset += 1;
        
        // Skip length
        const seq_len = der[offset];
        offset += 1;
        
        if (offset + seq_len != der.len) return error.InvalidParameter;
        
        // Parse r
        if (der[offset] != 0x02) return error.InvalidParameter;
        offset += 1;
        
        const r_len = der[offset];
        offset += 1;
        
        if (r_len > 33) return error.InvalidParameter;
        
        var r: [32]u8 = .{0} ** 32;
        if (r_len == 33) {
            // Skip leading zero
            if (der[offset] != 0x00) return error.InvalidParameter;
            offset += 1;
            @memcpy(&r, der[offset .. offset + 32]);
            offset += 32;
        } else {
            const r_start = 32 - r_len;
            @memcpy(r[r_start..], der[offset .. offset + r_len]);
            offset += r_len;
        }
        
        // Parse s
        if (der[offset] != 0x02) return error.InvalidParameter;
        offset += 1;
        
        const s_len = der[offset];
        offset += 1;
        
        if (s_len > 33) return error.InvalidParameter;
        
        var s: [32]u8 = .{0} ** 32;
        if (s_len == 33) {
            // Skip leading zero
            if (der[offset] != 0x00) return error.InvalidParameter;
            offset += 1;
            @memcpy(&s, der[offset .. offset + 32]);
        } else {
            const s_start = 32 - s_len;
            @memcpy(s[s_start..], der[offset .. offset + s_len]);
        }
        
        return Signature{ .r = r, .s = s };
    }
    
    pub fn toDER(self: Signature, allocator: std.mem.Allocator) ![]u8 {
        var der = std.ArrayList(u8).init(allocator);
        defer der.deinit();
        
        // SEQUENCE tag
        try der.append(0x30);
        
        // Calculate r length
        var r_len: u8 = 32;
        var r_offset: usize = 0;
        while (r_offset < 32 and self.r[r_offset] == 0) : (r_offset += 1) {}
        if (r_offset == 32) {
            r_len = 1;
        } else {
            r_len = @intCast(32 - r_offset);
            if (self.r[r_offset] & 0x80 != 0) r_len += 1; // Need leading zero
        }
        
        // Calculate s length
        var s_len: u8 = 32;
        var s_offset: usize = 0;
        while (s_offset < 32 and self.s[s_offset] == 0) : (s_offset += 1) {}
        if (s_offset == 32) {
            s_len = 1;
        } else {
            s_len = @intCast(32 - s_offset);
            if (self.s[s_offset] & 0x80 != 0) s_len += 1; // Need leading zero
        }
        
        // Total length
        const total_len = 2 + r_len + 2 + s_len;
        try der.append(@intCast(total_len));
        
        // r value
        try der.append(0x02); // INTEGER tag
        try der.append(r_len);
        if (r_offset < 32 and self.r[r_offset] & 0x80 != 0) {
            try der.append(0x00);
        }
        if (r_offset == 32) {
            try der.append(0x00);
        } else {
            try der.appendSlice(self.r[r_offset..]);
        }
        
        // s value
        try der.append(0x02); // INTEGER tag
        try der.append(s_len);
        if (s_offset < 32 and self.s[s_offset] & 0x80 != 0) {
            try der.append(0x00);
        }
        if (s_offset == 32) {
            try der.append(0x00);
        } else {
            try der.appendSlice(self.s[s_offset..]);
        }
        
        return der.toOwnedSlice();
    }
    
    pub fn toBytes(self: Signature) [64]u8 {
        var result: [64]u8 = undefined;
        @memcpy(result[0..32], &self.r);
        @memcpy(result[32..64], &self.s);
        return result;
    }
    
    pub fn fromBytes(bytes: [64]u8) Signature {
        var sig = Signature{
            .r = undefined,
            .s = undefined,
        };
        @memcpy(&sig.r, bytes[0..32]);
        @memcpy(&sig.s, bytes[32..64]);
        return sig;
    }
};

// Convenience function to generate public key from private key bytes
pub fn generatePublicKey(private_key_bytes: []const u8) ![33]u8 {
    if (private_key_bytes.len != 32) {
        return error.InvalidPrivateKey;
    }
    
    var key_array: [32]u8 = undefined;
    @memcpy(&key_array, private_key_bytes[0..32]);
    
    const private_key = try PrivateKey.fromBytes(key_array);
    const public_key = private_key.toPublicKey();
    return public_key.toCompressed();
}

// Convenience function for signing with private key bytes
pub fn sign(allocator: std.mem.Allocator, private_key_bytes: []const u8, message: []const u8) ![]u8 {
    if (private_key_bytes.len != 32) {
        return error.InvalidPrivateKey;
    }
    
    var key_array: [32]u8 = undefined;
    @memcpy(&key_array, private_key_bytes[0..32]);
    
    const private_key = try PrivateKey.fromBytes(key_array);
    
    // Hash message with SHA256
    var message_hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(message, &message_hash, .{});
    
    // Generate a random nonce for signing
    var nonce: [32]u8 = undefined;
    std.crypto.random.bytes(&nonce);
    
    const signature = private_key.sign(message_hash, nonce);
    return allocator.dupe(u8, &signature.toBytes());
}
const std = @import("std");
const crypto = std.crypto;
const mem = std.mem;

// Complete scrypt key derivation function implementation
// Based on RFC 7914: https://tools.ietf.org/html/rfc7914

pub fn scrypt(
    allocator: std.mem.Allocator,
    password: []const u8,
    salt: []const u8,
    n: u32, // CPU/memory cost parameter
    r: u32, // Block size parameter
    p: u32, // Parallelization parameter
    dklen: usize, // Desired key length
) ![]u8 {
    // Parameter validation
    if (n == 0 or (n & (n - 1)) != 0) return error.InvalidN; // N must be power of 2
    if (r == 0) return error.InvalidR;
    if (p == 0) return error.InvalidP;
    if (r * p >= 1 << 30) return error.ParametersTooLarge;
    if (dklen > (1 << 32 - 1) * 32) return error.DerivedKeyTooLong;
    
    const block_size = 128 * r;
    const blocks_count = p;
    
    // Allocate working memory
    var b = try allocator.alloc(u8, block_size * blocks_count);
    defer allocator.free(b);
    
    var xy = try allocator.alloc(u8, 256 * r);
    defer allocator.free(xy);
    
    var v = try allocator.alloc(u8, 128 * r * n);
    defer allocator.free(v);
    
    // Initial PBKDF2 to generate initial blocks
    try crypto.pwhash.pbkdf2(b, password, salt, 1, crypto.auth.hmac.HmacSha256);
    
    // Process each block independently
    var i: u32 = 0;
    while (i < p) : (i += 1) {
        const block_start = i * block_size;
        const block = b[block_start .. block_start + block_size];
        try scryptROMix(block, r, n, v, xy);
    }
    
    // Final PBKDF2 to generate output
    const derived_key = try allocator.alloc(u8, dklen);
    errdefer allocator.free(derived_key);
    
    try crypto.pwhash.pbkdf2(derived_key, password, b, 1, crypto.auth.hmac.HmacSha256);
    
    return derived_key;
}

fn scryptROMix(b: []u8, r: u32, n: u32, v: []u8, xy: []u8) !void {
    const block_size = 128 * r;
    var x = xy[0..block_size];
    var y = xy[block_size .. 2 * block_size];
    
    // Copy input to working buffer
    @memcpy(x, b);
    
    // Build lookup table V
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        const v_offset = i * block_size;
        @memcpy(v[v_offset .. v_offset + block_size], x);
        blockMix(x, y, r);
    }
    
    // Mix blocks using lookup table
    i = 0;
    while (i < n) : (i += 1) {
        const j = integerify(x, r) % n;
        const v_offset = j * block_size;
        blockXor(x, v[v_offset .. v_offset + block_size]);
        blockMix(x, y, r);
    }
    
    // Copy result back
    @memcpy(b, x);
}

fn blockMix(b: []u8, y: []u8, r: u32) void {
    const block_size = 128 * r;
    var x: [64]u8 = undefined;
    
    // Copy last 64-byte block
    @memcpy(&x, b[block_size - 64 ..]);
    
    var i: u32 = 0;
    while (i < 2 * r) : (i += 1) {
        const src_offset = i * 64;
        blockXor(&x, b[src_offset .. src_offset + 64]);
        salsa20_8(&x);
        
        const dst_offset = if (i % 2 == 0) (i / 2) * 64 else (r + (i - 1) / 2) * 64;
        @memcpy(y[dst_offset .. dst_offset + 64], &x);
    }
    
    @memcpy(b, y[0..block_size]);
}

fn integerify(b: []const u8, r: u32) u32 {
    const offset = (2 * r - 1) * 64;
    return mem.readIntLittle(u32, b[offset..][0..4]);
}

fn blockXor(dst: []u8, src: []const u8) void {
    for (dst, src) |*d, s| {
        d.* ^= s;
    }
}

fn salsa20_8(b: *[64]u8) void {
    var x: [16]u32 = undefined;
    
    // Convert bytes to words
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        x[i] = mem.readIntLittle(u32, b[i * 4 ..][0..4]);
    }
    
    // Perform 8 rounds (4 double-rounds)
    var round: u32 = 0;
    while (round < 4) : (round += 1) {
        // Column round
        x[4] ^= rotl(x[0] +% x[12], 7);
        x[8] ^= rotl(x[4] +% x[0], 9);
        x[12] ^= rotl(x[8] +% x[4], 13);
        x[0] ^= rotl(x[12] +% x[8], 18);
        
        x[9] ^= rotl(x[5] +% x[1], 7);
        x[13] ^= rotl(x[9] +% x[5], 9);
        x[1] ^= rotl(x[13] +% x[9], 13);
        x[5] ^= rotl(x[1] +% x[13], 18);
        
        x[14] ^= rotl(x[10] +% x[6], 7);
        x[2] ^= rotl(x[14] +% x[10], 9);
        x[6] ^= rotl(x[2] +% x[14], 13);
        x[10] ^= rotl(x[6] +% x[2], 18);
        
        x[3] ^= rotl(x[15] +% x[11], 7);
        x[7] ^= rotl(x[3] +% x[15], 9);
        x[11] ^= rotl(x[7] +% x[3], 13);
        x[15] ^= rotl(x[11] +% x[7], 18);
        
        // Row round
        x[1] ^= rotl(x[0] +% x[3], 7);
        x[2] ^= rotl(x[1] +% x[0], 9);
        x[3] ^= rotl(x[2] +% x[1], 13);
        x[0] ^= rotl(x[3] +% x[2], 18);
        
        x[6] ^= rotl(x[5] +% x[4], 7);
        x[7] ^= rotl(x[6] +% x[5], 9);
        x[4] ^= rotl(x[7] +% x[6], 13);
        x[5] ^= rotl(x[4] +% x[7], 18);
        
        x[11] ^= rotl(x[10] +% x[9], 7);
        x[8] ^= rotl(x[11] +% x[10], 9);
        x[9] ^= rotl(x[8] +% x[11], 13);
        x[10] ^= rotl(x[9] +% x[8], 18);
        
        x[12] ^= rotl(x[15] +% x[14], 7);
        x[13] ^= rotl(x[12] +% x[15], 9);
        x[14] ^= rotl(x[13] +% x[12], 13);
        x[15] ^= rotl(x[14] +% x[13], 18);
    }
    
    // Add original values and convert back to bytes
    i = 0;
    while (i < 16) : (i += 1) {
        const orig = mem.readIntLittle(u32, b[i * 4 ..][0..4]);
        mem.writeIntLittle(u32, b[i * 4 ..][0..4], x[i] +% orig);
    }
}

fn rotl(x: u32, n: u5) u32 {
    return (x << n) | (x >> (32 - n));
}

// Optimized version for common parameters
pub fn scryptKdf(
    allocator: std.mem.Allocator,
    password: []const u8,
    salt: []const u8,
    params: ScryptParams,
) ![]u8 {
    return try scrypt(
        allocator,
        password,
        salt,
        params.n,
        params.r,
        params.p,
        params.dklen,
    );
}

pub const ScryptParams = struct {
    n: u32,
    r: u32,
    p: u32,
    dklen: usize,
    
    // Common parameter sets
    pub const interactive = ScryptParams{
        .n = 16384,  // 2^14
        .r = 8,
        .p = 1,
        .dklen = 32,
    };
    
    pub const moderate = ScryptParams{
        .n = 65536,  // 2^16
        .r = 8,
        .p = 1,
        .dklen = 32,
    };
    
    pub const sensitive = ScryptParams{
        .n = 262144, // 2^18
        .r = 8,
        .p = 1,
        .dklen = 32,
    };
    
    pub fn fromKeystore(n: u32, r: u32, p: u32, dklen: u32) ScryptParams {
        return ScryptParams{
            .n = n,
            .r = r,
            .p = p,
            .dklen = dklen,
        };
    }
};
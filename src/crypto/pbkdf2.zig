const std = @import("std");
const crypto = std.crypto;

// PBKDF2 implementation for key derivation
pub fn pbkdf2(
    password: []const u8,
    salt: []const u8,
    iterations: u32,
    dk_len: usize,
    allocator: std.mem.Allocator,
) ![]u8 {
    const HmacSha512 = crypto.auth.hmac.sha2.HmacSha512;
    
    const result = try allocator.alloc(u8, dk_len);
    errdefer allocator.free(result);
    
    // PBKDF2 with HMAC-SHA512
    try crypto.pwhash.pbkdf2(
        result,
        password,
        salt,
        iterations,
        HmacSha512,
    );
    
    return result;
}

// Derive key using PBKDF2-HMAC-SHA512
pub fn deriveKey(
    password: []const u8,
    salt: []const u8,
    iterations: u32,
    allocator: std.mem.Allocator,
) ![]u8 {
    return pbkdf2(password, salt, iterations, 64, allocator);
}
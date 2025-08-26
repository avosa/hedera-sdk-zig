const std = @import("std");

// Keccak-256 cryptographic hash implementation
pub const Keccak256 = struct {
    const state_size = 25;
    const rate = 136; // 1088 bits = 136 bytes for Keccak-256
    const capacity = 64; // 512 bits = 64 bytes
    const output_size = 32; // 256 bits = 32 bytes
    
    state: [state_size]u64,
    buffer: [rate]u8,
    buffer_pos: usize,
    
    const rc: [24]u64 = [_]u64{
        0x0000000000000001, 0x0000000000008082, 0x800000000000808a,
        0x8000000080008000, 0x000000000000808b, 0x0000000080000001,
        0x8000000080008081, 0x8000000000008009, 0x000000000000008a,
        0x0000000000000088, 0x0000000080008009, 0x000000008000000a,
        0x000000008000808b, 0x800000000000008b, 0x8000000000008089,
        0x8000000000008003, 0x8000000000008002, 0x8000000000000080,
        0x000000000000800a, 0x800000008000000a, 0x8000000080008081,
        0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
    };
    
    const r: [5][5]u32 = [_][5]u32{
        [_]u32{ 0, 36, 3, 41, 18 },
        [_]u32{ 1, 44, 10, 45, 2 },
        [_]u32{ 62, 6, 43, 15, 61 },
        [_]u32{ 28, 55, 25, 21, 56 },
        [_]u32{ 27, 20, 39, 8, 14 },
    };
    
    pub fn init() Keccak256 {
        return Keccak256{
            .state = [_]u64{0} ** state_size,
            .buffer = undefined,
            .buffer_pos = 0,
        };
    }
    
    pub fn hash(data: []const u8, out: *[output_size]u8, options: struct {}) void {
        _ = options;
        var hasher = init();
        hasher.update(data);
        hasher.final(out);
    }
    
    pub fn update(self: *Keccak256, data: []const u8) void {
        var i: usize = 0;
        
        // Process any buffered data first
        if (self.buffer_pos > 0) {
            const copy_len = @min(rate - self.buffer_pos, data.len);
            @memcpy(self.buffer[self.buffer_pos..][0..copy_len], data[0..copy_len]);
            self.buffer_pos += copy_len;
            i += copy_len;
            
            if (self.buffer_pos == rate) {
                self.absorbBlock(&self.buffer);
                self.buffer_pos = 0;
            }
        }
        
        // Process complete blocks
        while (i + rate <= data.len) {
            var block: [rate]u8 = undefined;
            @memcpy(&block, data[i..][0..rate]);
            self.absorbBlock(&block);
            i += rate;
        }
        
        // Buffer remaining data
        if (i < data.len) {
            const remaining = data.len - i;
            @memcpy(self.buffer[0..remaining], data[i..]);
            self.buffer_pos = remaining;
        }
    }
    
    pub fn final(self: *Keccak256, out: *[output_size]u8) void {
        // Pad the message
        self.buffer[self.buffer_pos] = 0x01; // Keccak uses 0x01 for padding
        @memset(self.buffer[self.buffer_pos + 1..rate - 1], 0);
        self.buffer[rate - 1] = 0x80;
        
        self.absorbBlock(&self.buffer);
        
        // Squeeze output
        var output_words: [output_size / 8]u64 = undefined;
        for (0..output_size / 8) |j| {
            output_words[j] = self.state[j];
        }
        
        // Convert to bytes (little-endian)
        for (0..output_size / 8) |j| {
            const offset = j * 8;
            out[offset] = @truncate(output_words[j]);
            out[offset + 1] = @truncate(output_words[j] >> 8);
            out[offset + 2] = @truncate(output_words[j] >> 16);
            out[offset + 3] = @truncate(output_words[j] >> 24);
            out[offset + 4] = @truncate(output_words[j] >> 32);
            out[offset + 5] = @truncate(output_words[j] >> 40);
            out[offset + 6] = @truncate(output_words[j] >> 48);
            out[offset + 7] = @truncate(output_words[j] >> 56);
        }
    }
    
    fn absorbBlock(self: *Keccak256, block: *const [rate]u8) void {
        // Convert block to 64-bit words (little-endian)
        var block_words: [rate / 8]u64 = undefined;
        for (0..rate / 8) |i| {
            const offset = i * 8;
            block_words[i] = @as(u64, block[offset]) |
                (@as(u64, block[offset + 1]) << 8) |
                (@as(u64, block[offset + 2]) << 16) |
                (@as(u64, block[offset + 3]) << 24) |
                (@as(u64, block[offset + 4]) << 32) |
                (@as(u64, block[offset + 5]) << 40) |
                (@as(u64, block[offset + 6]) << 48) |
                (@as(u64, block[offset + 7]) << 56);
        }
        
        // XOR block into state
        for (0..rate / 8) |i| {
            self.state[i] ^= block_words[i];
        }
        
        // Apply Keccak-f permutation
        self.keccakF();
    }
    
    fn keccakF(self: *Keccak256) void {
        var A: [5][5]u64 = undefined;
        
        // Map state to 5x5 array
        for (0..5) |x| {
            for (0..5) |y| {
                A[x][y] = self.state[x + 5 * y];
            }
        }
        
        // Apply 24 rounds
        for (0..24) |round| {
            // Theta step
            var C: [5]u64 = undefined;
            var D: [5]u64 = undefined;
            
            for (0..5) |x| {
                C[x] = A[x][0] ^ A[x][1] ^ A[x][2] ^ A[x][3] ^ A[x][4];
            }
            
            for (0..5) |x| {
                D[x] = C[(x + 4) % 5] ^ rotl64(C[(x + 1) % 5], 1);
            }
            
            for (0..5) |x| {
                for (0..5) |y| {
                    A[x][y] ^= D[x];
                }
            }
            
            // Rho and Pi steps
            var B: [5][5]u64 = undefined;
            for (0..5) |x| {
                for (0..5) |y| {
                    B[y][(2 * x + 3 * y) % 5] = rotl64(A[x][y], r[x][y]);
                }
            }
            
            // Chi step
            for (0..5) |x| {
                for (0..5) |y| {
                    A[x][y] = B[x][y] ^ ((~B[(x + 1) % 5][y]) & B[(x + 2) % 5][y]);
                }
            }
            
            // Iota step
            A[0][0] ^= rc[round];
        }
        
        // Map back to linear state
        for (0..5) |x| {
            for (0..5) |y| {
                self.state[x + 5 * y] = A[x][y];
            }
        }
    }
    
    fn rotl64(value: u64, shift: u32) u64 {
        if (shift == 0) return value;
        return (value << @intCast(shift)) | (value >> @intCast(64 - shift));
    }
};

// Convenience function for one-shot hashing
pub fn keccak256(data: []const u8, out: *[32]u8) void {
    Keccak256.hash(data, out, .{});
}

test "Keccak256 basic" {
    const testing = std.testing;
    
    // Test empty string
    var hash1: [32]u8 = undefined;
    keccak256("", &hash1);
    
    const expected1 = "\xc5\xd2\x46\x01\x86\xf7\x23\x3c\x92\x7e\x7d\xb2\xdc\xc7\x03\xc0\xe5\x00\xb6\x53\xca\x82\x27\x3b\x7b\xfa\xd8\x04\x5d\x85\xa4\x70";
    try testing.expectEqualSlices(u8, expected1, &hash1);
    
    // Test "abc"
    var hash2: [32]u8 = undefined;
    keccak256("abc", &hash2);
    
    const expected2 = "\x4e\x03\x65\x7a\xea\x45\xa9\x4f\xc7\xd4\x7b\xa8\x26\xc8\xd6\x67\xc0\xd1\xe6\xe3\x3a\x64\xa0\x36\xec\x44\xf5\x8f\xa1\x2d\x6c\x45";
    try testing.expectEqualSlices(u8, expected2, &hash2);
}
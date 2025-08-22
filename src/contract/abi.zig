const std = @import("std");
const crypto = std.crypto;

// Smart Contract ABI encoding/decoding system
pub const ABI = struct {
    // ABI types
    pub const Type = enum {
        uint8,
        uint16,
        uint32,
        uint64,
        uint128,
        uint256,
        int8,
        int16,
        int32,
        int64,
        int128,
        int256,
        address,
        bool,
        bytes,
        bytes32,
        string,
        array,
        tuple,
        
        pub fn isDynamic(self: Type) bool {
            return switch (self) {
                .bytes, .string, .array => true,
                else => false,
            };
        }
        
        pub fn getSize(self: Type) usize {
            return switch (self) {
                .uint8, .int8, .bool => 32,
                .uint16, .int16 => 32,
                .uint32, .int32 => 32,
                .uint64, .int64 => 32,
                .uint128, .int128 => 32,
                .uint256, .int256 => 32,
                .address => 32,
                .bytes32 => 32,
                .bytes, .string, .array, .tuple => 0, // Dynamic size
            };
        }
    };
    
    // ABI encoder
    pub const Encoder = struct {
        buffer: std.ArrayList(u8),
        allocator: std.mem.Allocator,
        
        pub fn init(allocator: std.mem.Allocator) Encoder {
            return Encoder{
                .buffer = std.ArrayList(u8).init(allocator),
                .allocator = allocator,
            };
        }
        
        pub fn deinit(self: *Encoder) void {
            self.buffer.deinit();
        }
        
        // Encode uint256
        pub fn encodeUint256(self: *Encoder, value: u256) !void {
            var bytes: [32]u8 = [_]u8{0} ** 32;
            var i: usize = 31;
            var v = value;
            while (v > 0 and i >= 0) : (i -= 1) {
                bytes[i] = @intCast(v & 0xFF);
                v >>= 8;
                if (i == 0) break;
            }
            try self.buffer.appendSlice(&bytes);
        }
        
        // Encode uint
        pub fn encodeUint(self: *Encoder, value: u64) !void {
            try self.encodeUint256(value);
        }
        
        // Encode int256
        pub fn encodeInt256(self: *Encoder, value: i256) !void {
            var bytes: [32]u8 = [_]u8{0} ** 32;
            const is_negative = value < 0;
            var abs_value: u256 = if (is_negative) @intCast(-value) else @intCast(value);
            
            // Convert to two's complement if negative
            if (is_negative) {
                abs_value = (~abs_value) + 1;
                bytes = [_]u8{0xFF} ** 32;
            }
            
            var i: usize = 31;
            while (abs_value > 0 and i >= 0) : (i -= 1) {
                if (is_negative) {
                    bytes[i] = @intCast((~(abs_value & 0xFF)) & 0xFF);
                } else {
                    bytes[i] = @intCast(abs_value & 0xFF);
                }
                abs_value >>= 8;
                if (i == 0) break;
            }
            
            try self.buffer.appendSlice(&bytes);
        }
        
        // Encode int
        pub fn encodeInt(self: *Encoder, value: i64) !void {
            try self.encodeInt256(value);
        }
        
        // Encode address (20 bytes, padded to 32)
        pub fn encodeAddress(self: *Encoder, address: []const u8) !void {
            if (address.len != 20) return error.InvalidAddressLength;
            
            var bytes: [32]u8 = [_]u8{0} ** 32;
            @memcpy(bytes[12..32], address);
            try self.buffer.appendSlice(&bytes);
        }
        
        // Encode bool
        pub fn encodeBool(self: *Encoder, value: bool) !void {
            var bytes: [32]u8 = [_]u8{0} ** 32;
            if (value) bytes[31] = 1;
            try self.buffer.appendSlice(&bytes);
        }
        
        // Encode bytes32
        pub fn encodeBytes32(self: *Encoder, data: []const u8) !void {
            if (data.len > 32) return error.DataTooLarge;
            
            var bytes: [32]u8 = [_]u8{0} ** 32;
            @memcpy(bytes[0..data.len], data);
            try self.buffer.appendSlice(&bytes);
        }
        
        // Encode dynamic bytes
        pub fn encodeBytes(self: *Encoder, data: []const u8) !void {
            // Encode length
            try self.encodeUint256(data.len);
            
            // Encode data padded to 32 bytes
            try self.buffer.appendSlice(data);
            const padding = (32 - (data.len % 32)) % 32;
            if (padding > 0) {
                const pad_bytes = try self.allocator.alloc(u8, padding);
                defer self.allocator.free(pad_bytes);
                @memset(pad_bytes, 0);
                try self.buffer.appendSlice(pad_bytes);
            }
        }
        
        // Encode string
        pub fn encodeString(self: *Encoder, str: []const u8) !void {
            try self.encodeBytes(str);
        }
        
        // Get encoded bytes
        pub fn toBytes(self: *Encoder) ![]u8 {
            return self.buffer.toOwnedSlice();
        }
    };
    
    // ABI decoder
    pub const Decoder = struct {
        data: []const u8,
        offset: usize,
        allocator: std.mem.Allocator,
        
        pub fn init(data: []const u8, allocator: std.mem.Allocator) Decoder {
            return Decoder{
                .data = data,
                .offset = 0,
                .allocator = allocator,
            };
        }
        
        // Decode uint256
        pub fn decodeUint256(self: *Decoder) !u256 {
            if (self.offset + 32 > self.data.len) return error.InsufficientData;
            
            var value: u256 = 0;
            for (self.data[self.offset..self.offset + 32]) |byte| {
                value = (value << 8) | byte;
            }
            self.offset += 32;
            return value;
        }
        
        // Decode uint
        pub fn decodeUint(self: *Decoder) !u64 {
            const value = try self.decodeUint256();
            if (value > std.math.maxInt(u64)) return error.ValueTooLarge;
            return @intCast(value);
        }
        
        // Decode int256
        pub fn decodeInt256(self: *Decoder) !i256 {
            if (self.offset + 32 > self.data.len) return error.InsufficientData;
            
            const bytes = self.data[self.offset..self.offset + 32];
            const is_negative = bytes[0] & 0x80 != 0;
            
            var value: i256 = 0;
            if (is_negative) {
                // Handle two's complement negative number
                for (bytes) |byte| {
                    value = (value << 8) | @as(i256, byte);
                }
                value = value - (@as(i256, 1) << 256);
            } else {
                for (bytes) |byte| {
                    value = (value << 8) | @as(i256, byte);
                }
            }
            
            self.offset += 32;
            return value;
        }
        
        // Decode int
        pub fn decodeInt(self: *Decoder) !i64 {
            const value = try self.decodeInt256();
            if (value > std.math.maxInt(i64) or value < std.math.minInt(i64)) {
                return error.ValueOutOfRange;
            }
            return @intCast(value);
        }
        
        // Decode address
        pub fn decodeAddress(self: *Decoder) ![]u8 {
            if (self.offset + 32 > self.data.len) return error.InsufficientData;
            
            const address = try self.allocator.alloc(u8, 20);
            @memcpy(address, self.data[self.offset + 12..self.offset + 32]);
            self.offset += 32;
            return address;
        }
        
        // Decode bool
        pub fn decodeBool(self: *Decoder) !bool {
            if (self.offset + 32 > self.data.len) return error.InsufficientData;
            
            const value = self.data[self.offset + 31] != 0;
            self.offset += 32;
            return value;
        }
        
        // Decode bytes32
        pub fn decodeBytes32(self: *Decoder) ![]u8 {
            if (self.offset + 32 > self.data.len) return error.InsufficientData;
            
            const bytes = try self.allocator.alloc(u8, 32);
            @memcpy(bytes, self.data[self.offset..self.offset + 32]);
            self.offset += 32;
            return bytes;
        }
        
        // Decode dynamic bytes
        pub fn decodeBytes(self: *Decoder) ![]u8 {
            // Decode offset to data
            const data_offset = try self.decodeUint();
            
            // Save current offset and jump to data
            const saved_offset = self.offset;
            self.offset = @intCast(data_offset);
            
            // Decode length
            const length = try self.decodeUint();
            
            if (self.offset + length > self.data.len) return error.InsufficientData;
            
            // Read data
            const bytes = try self.allocator.alloc(u8, length);
            @memcpy(bytes, self.data[self.offset..self.offset + length]);
            
            // Restore offset
            self.offset = saved_offset;
            
            return bytes;
        }
        
        // Decode string
        pub fn decodeString(self: *Decoder) ![]u8 {
            return self.decodeBytes();
        }
    };
    
    // Function selector computation
    pub fn functionSelector(signature: []const u8) [4]u8 {
        var hash: [32]u8 = undefined;
        crypto.hash.sha3.Keccak256.hash(signature, &hash, .{});
        return hash[0..4].*;
    }
    
    // Event topic computation
    pub fn eventTopic(signature: []const u8) [32]u8 {
        var hash: [32]u8 = undefined;
        crypto.hash.sha3.Keccak256.hash(signature, &hash, .{});
        return hash;
    }
    
    // Encode function call
    pub fn encodeFunctionCall(
        allocator: std.mem.Allocator,
        signature: []const u8,
        args: []const []const u8,
    ) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();
        
        // Add function selector
        const selector = functionSelector(signature);
        try result.appendSlice(&selector);
        
        // Add encoded arguments
        for (args) |arg| {
            try result.appendSlice(arg);
        }
        
        return result.toOwnedSlice();
    }
    
    // Parse function signature
    pub fn parseFunctionSignature(signature: []const u8) !FunctionSignature {
        // Parse function signature like "transfer(address,uint256)"
        const paren_start = std.mem.indexOf(u8, signature, "(") orelse return error.InvalidSignature;
        const paren_end = std.mem.lastIndexOf(u8, signature, ")") orelse return error.InvalidSignature;
        
        const name = signature[0..paren_start];
        const params_str = signature[paren_start + 1..paren_end];
        
        var params = std.ArrayList([]const u8).init(std.heap.page_allocator);
        defer params.deinit();
        
        var iter = std.mem.tokenize(u8, params_str, ",");
        while (iter.next()) |param| {
            try params.append(param);
        }
        
        return FunctionSignature{
            .name = name,
            .params = try params.toOwnedSlice(),
        };
    }
    
    pub const FunctionSignature = struct {
        name: []const u8,
        params: [][]const u8,
    };
};
const std = @import("std");
const crypto = std.crypto;

// Ethereum function selector (first 4 bytes of Keccak-256 hash of function signature)
pub const FunctionSelector = struct {
    bytes: [4]u8,

    pub fn init(bytes: [4]u8) FunctionSelector {
        return FunctionSelector{ .bytes = bytes };
    }

    pub fn fromSignature(signature: []const u8) !FunctionSelector {
        // Use Keccak-256 hash algorithm
        var hash_result: [32]u8 = undefined;
        
        // Zig's Keccak is available in std.crypto.hash
        var keccak = crypto.hash.sha3.Keccak256.init(.{});
        keccak.update(signature);
        keccak.final(&hash_result);
        
        return FunctionSelector{
            .bytes = hash_result[0..4].*,
        };
    }

    pub fn fromFunctionName(name: []const u8, params: []const []const u8, allocator: std.mem.Allocator) !FunctionSelector {
        var signature = std.ArrayList(u8).init(allocator);
        defer signature.deinit();
        
        try signature.appendSlice(name);
        try signature.append('(');
        
        for (params, 0..) |param, i| {
            if (i > 0) try signature.append(',');
            try signature.appendSlice(param);
        }
        
        try signature.append(')');
        
        return try fromSignature(signature.items);
    }

    pub fn toBytes(self: FunctionSelector) [4]u8 {
        return self.bytes;
    }
    
    // Encode to bytes (alias for toBytes)
    pub fn encode(self: FunctionSelector, allocator: std.mem.Allocator, params: []const []const u8) ![]u8 {
        var total_size: usize = 4; // 4 bytes for selector
        for (params) |param| {
            total_size += param.len;
        }
        
        var result = try allocator.alloc(u8, total_size);
        @memcpy(result[0..4], &self.bytes);
        
        var offset: usize = 4;
        for (params) |param| {
            @memcpy(result[offset..offset + param.len], param);
            offset += param.len;
        }
        
        return result;
    }

    pub fn toHexString(self: FunctionSelector, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{
            self.bytes[0], self.bytes[1], self.bytes[2], self.bytes[3]
        });
    }

    pub fn toString(self: FunctionSelector, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "0x{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{
            self.bytes[0], self.bytes[1], self.bytes[2], self.bytes[3]
        });
    }

    pub fn fromHexString(hex_string: []const u8) !FunctionSelector {
        if (hex_string.len < 8) return error.InvalidHexLength;
        
        const start = if (std.mem.startsWith(u8, hex_string, "0x")) 2 else 0;
        if (hex_string.len - start != 8) return error.InvalidHexLength;
        
        var bytes: [4]u8 = undefined;
        _ = try std.fmt.hexToBytes(&bytes, hex_string[start..]);
        
        return FunctionSelector{ .bytes = bytes };
    }

    pub fn equals(self: FunctionSelector, other: FunctionSelector) bool {
        return std.mem.eql(u8, &self.bytes, &other.bytes);
    }

    pub fn hash(self: FunctionSelector) u32 {
        return std.mem.readInt(u32, &self.bytes, .big);
    }

    // Common function selectors for standard contract functions
    pub fn TRANSFER() !FunctionSelector { return try fromSignature("transfer(address,uint256)"); }
    pub fn TRANSFER_FROM() !FunctionSelector { return try fromSignature("transferFrom(address,address,uint256)"); }
    pub fn APPROVE() !FunctionSelector { return try fromSignature("approve(address,uint256)"); }
    pub fn ALLOWANCE() !FunctionSelector { return try fromSignature("allowance(address,address)"); }
    pub fn BALANCE_OF() !FunctionSelector { return try fromSignature("balanceOf(address)"); }
    pub fn TOTAL_SUPPLY() !FunctionSelector { return try fromSignature("totalSupply()"); }
    pub fn NAME() !FunctionSelector { return try fromSignature("name()"); }
    pub fn SYMBOL() !FunctionSelector { return try fromSignature("symbol()"); }
    pub fn DECIMALS() !FunctionSelector { return try fromSignature("decimals()"); }
    
    // ERC-721 NFT functions
    pub fn OWNER_OF() !FunctionSelector { return try fromSignature("ownerOf(uint256)"); }
    pub fn SAFE_TRANSFER_FROM() !FunctionSelector { return try fromSignature("safeTransferFrom(address,address,uint256)"); }
    pub fn SAFE_TRANSFER_FROM_WITH_DATA() !FunctionSelector { return try fromSignature("safeTransferFrom(address,address,uint256,bytes)"); }
    pub fn SET_APPROVAL_FOR_ALL() !FunctionSelector { return try fromSignature("setApprovalForAll(address,bool)"); }
    pub fn GET_APPROVED() !FunctionSelector { return try fromSignature("getApproved(uint256)"); }
    pub fn IS_APPROVED_FOR_ALL() !FunctionSelector { return try fromSignature("isApprovedForAll(address,address)"); }
    
    // ERC-1155 Multi-Token functions
    pub fn SAFE_TRANSFER_FROM_1155() !FunctionSelector { return try fromSignature("safeTransferFrom(address,address,uint256,uint256,bytes)"); }
    pub fn SAFE_BATCH_TRANSFER_FROM() !FunctionSelector { return try fromSignature("safeBatchTransferFrom(address,address,uint256[],uint256[],bytes)"); }
    pub fn BALANCE_OF_BATCH() !FunctionSelector { return try fromSignature("balanceOfBatch(address[],uint256[])"); }
};

// Function parameter encoding for contract calls
pub const FunctionParameters = struct {
    data: std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FunctionParameters {
        return FunctionParameters{
            .data = std.ArrayList(u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FunctionParameters) void {
        self.data.deinit();
    }

    pub fn addUint256(self: *FunctionParameters, value: u256) !void {
        var bytes: [32]u8 = undefined;
        std.mem.writeInt(u256, &bytes, value, .big);
        try self.data.appendSlice(&bytes);
    }

    pub fn addUint128(self: *FunctionParameters, value: u128) !void {
        var bytes: [32]u8 = std.mem.zeroes([32]u8);
        std.mem.writeInt(u128, bytes[16..32], value, .big);
        try self.data.appendSlice(&bytes);
    }

    pub fn addUint64(self: *FunctionParameters, value: u64) !void {
        var bytes: [32]u8 = std.mem.zeroes([32]u8);
        std.mem.writeInt(u64, bytes[24..32], value, .big);
        try self.data.appendSlice(&bytes);
    }

    pub fn addUint32(self: *FunctionParameters, value: u32) !void {
        var bytes: [32]u8 = std.mem.zeroes([32]u8);
        std.mem.writeInt(u32, bytes[28..32], value, .big);
        try self.data.appendSlice(&bytes);
    }

    pub fn addUint16(self: *FunctionParameters, value: u16) !void {
        var bytes: [32]u8 = std.mem.zeroes([32]u8);
        std.mem.writeInt(u16, bytes[30..32], value, .big);
        try self.data.appendSlice(&bytes);
    }

    pub fn addUint8(self: *FunctionParameters, value: u8) !void {
        var bytes: [32]u8 = std.mem.zeroes([32]u8);
        bytes[31] = value;
        try self.data.appendSlice(&bytes);
    }

    pub fn addInt256(self: *FunctionParameters, value: i256) !void {
        var bytes: [32]u8 = undefined;
        std.mem.writeInt(u256, &bytes, @bitCast(value), .big);
        try self.data.appendSlice(&bytes);
    }

    pub fn addInt128(self: *FunctionParameters, value: i128) !void {
        var bytes: [32]u8 = if (value < 0) [_]u8{0xFF} ** 32 else std.mem.zeroes([32]u8);
        std.mem.writeInt(u128, bytes[16..32], @bitCast(value), .big);
        try self.data.appendSlice(&bytes);
    }

    pub fn addInt64(self: *FunctionParameters, value: i64) !void {
        var bytes: [32]u8 = if (value < 0) [_]u8{0xFF} ** 32 else std.mem.zeroes([32]u8);
        std.mem.writeInt(u64, bytes[24..32], @bitCast(value), .big);
        try self.data.appendSlice(&bytes);
    }

    pub fn addInt32(self: *FunctionParameters, value: i32) !void {
        var bytes: [32]u8 = if (value < 0) [_]u8{0xFF} ** 32 else std.mem.zeroes([32]u8);
        std.mem.writeInt(u32, bytes[28..32], @bitCast(value), .big);
        try self.data.appendSlice(&bytes);
    }

    pub fn addBool(self: *FunctionParameters, value: bool) !void {
        try self.addUint8(if (value) 1 else 0);
    }

    pub fn addAddress(self: *FunctionParameters, address: [20]u8) !void {
        var bytes: [32]u8 = std.mem.zeroes([32]u8);
        @memcpy(bytes[12..32], &address);
        try self.data.appendSlice(&bytes);
    }

    pub fn addBytes32(self: *FunctionParameters, bytes32: [32]u8) !void {
        try self.data.appendSlice(&bytes32);
    }

    pub fn addBytes(self: *FunctionParameters, bytes: []const u8) !void {
        const offset = @as(u32, @intCast(self.data.items.len + 32));
        try self.addUint32(offset);
        
        try self.addUint32(@intCast(bytes.len));
        try self.data.appendSlice(bytes);
        
        const padding = (32 - (bytes.len % 32)) % 32;
        if (padding > 0) {
            const pad_bytes = std.mem.zeroes([32]u8);
            try self.data.appendSlice(pad_bytes[0..padding]);
        }
    }

    pub fn addString(self: *FunctionParameters, str: []const u8) !void {
        try self.addBytes(str);
    }

    pub fn addFixedBytes(self: *FunctionParameters, bytes: []const u8) !void {
        if (bytes.len > 32) return error.BytesTooLong;
        
        var padded: [32]u8 = std.mem.zeroes([32]u8);
        @memcpy(padded[0..bytes.len], bytes);
        try self.data.appendSlice(&padded);
    }

    pub fn addArray(self: *FunctionParameters, comptime T: type, array: []const T) !void {
        const offset = @as(u32, @intCast(self.data.items.len + 32));
        try self.addUint32(offset);
        
        try self.addUint32(@intCast(array.len));
        for (array) |item| {
            switch (T) {
                u256 => try self.addUint256(item),
                u128 => try self.addUint128(item),
                u64 => try self.addUint64(item),
                u32 => try self.addUint32(item),
                u16 => try self.addUint16(item),
                u8 => try self.addUint8(item),
                i256 => try self.addInt256(item),
                i128 => try self.addInt128(item),
                i64 => try self.addInt64(item),
                i32 => try self.addInt32(item),
                bool => try self.addBool(item),
                else => @compileError("Unsupported array type"),
            }
        }
    }

    pub fn toBytes(self: *const FunctionParameters) []const u8 {
        return self.data.items;
    }

    pub fn encode(self: *const FunctionParameters, function_selector: FunctionSelector, allocator: std.mem.Allocator) ![]u8 {
        var result = try allocator.alloc(u8, 4 + self.data.items.len);
        @memcpy(result[0..4], &function_selector.bytes);
        @memcpy(result[4..], self.data.items);
        return result;
    }

    pub fn clear(self: *FunctionParameters) void {
        self.data.clearRetainingCapacity();
    }

    pub fn clone(self: *const FunctionParameters, allocator: std.mem.Allocator) !FunctionParameters {
        var result = FunctionParameters.init(allocator);
        try result.data.appendSlice(self.data.items);
        return result;
    }
};

// Function call builder for common contract operations
pub const ContractFunctionCall = struct {
    function_selector: FunctionSelector,
    parameters: FunctionParameters,

    pub fn init(function_selector: FunctionSelector, allocator: std.mem.Allocator) ContractFunctionCall {
        return ContractFunctionCall{
            .function_selector = function_selector,
            .parameters = FunctionParameters.init(allocator),
        };
    }

    pub fn deinit(self: *ContractFunctionCall) void {
        self.parameters.deinit();
    }

    pub fn encode(self: *const ContractFunctionCall, allocator: std.mem.Allocator) ![]u8 {
        return self.parameters.encode(self.function_selector, allocator);
    }

    // Builder methods for common ERC-20 calls
    pub fn transfer(to: [20]u8, amount: u256, allocator: std.mem.Allocator) !ContractFunctionCall {
        var call = ContractFunctionCall.init(try FunctionSelector.TRANSFER(), allocator);
        try call.parameters.addAddress(to);
        try call.parameters.addUint256(amount);
        return call;
    }

    pub fn transferFrom(from: [20]u8, to: [20]u8, amount: u256, allocator: std.mem.Allocator) !ContractFunctionCall {
        var call = ContractFunctionCall.init(try FunctionSelector.TRANSFER_FROM(), allocator);
        try call.parameters.addAddress(from);
        try call.parameters.addAddress(to);
        try call.parameters.addUint256(amount);
        return call;
    }

    pub fn approve(spender: [20]u8, amount: u256, allocator: std.mem.Allocator) !ContractFunctionCall {
        var call = ContractFunctionCall.init(try FunctionSelector.APPROVE(), allocator);
        try call.parameters.addAddress(spender);
        try call.parameters.addUint256(amount);
        return call;
    }

    pub fn balanceOf(owner: [20]u8, allocator: std.mem.Allocator) !ContractFunctionCall {
        var call = ContractFunctionCall.init(try FunctionSelector.BALANCE_OF(), allocator);
        try call.parameters.addAddress(owner);
        return call;
    }

    // Builder methods for ERC-721 calls
    pub fn ownerOf(token_id: u256, allocator: std.mem.Allocator) !ContractFunctionCall {
        var call = ContractFunctionCall.init(try FunctionSelector.OWNER_OF(), allocator);
        try call.parameters.addUint256(token_id);
        return call;
    }

    pub fn safeTransferFrom(from: [20]u8, to: [20]u8, token_id: u256, allocator: std.mem.Allocator) !ContractFunctionCall {
        var call = ContractFunctionCall.init(try FunctionSelector.SAFE_TRANSFER_FROM(), allocator);
        try call.parameters.addAddress(from);
        try call.parameters.addAddress(to);
        try call.parameters.addUint256(token_id);
        return call;
    }
};
const std = @import("std");
const Allocator = std.mem.Allocator;
const EthereumEIP1559Transaction = @import("ethereum_eip1559_transaction.zig").EthereumEIP1559Transaction;
const EthereumEIP2930Transaction = @import("ethereum_eip2930_transaction.zig").EthereumEIP2930Transaction;
const EthereumLegacyTransaction = @import("ethereum_legacy_transaction.zig").EthereumLegacyTransaction;
const protobuf = @import("../protobuf/protobuf.zig");

pub const EthereumTransactionData = union(enum) {
    eip1559: EthereumEIP1559Transaction,
    eip2930: EthereumEIP2930Transaction,
    legacy: EthereumLegacyTransaction,
    
    const Self = @This();
    
    pub fn fromBytes(allocator: Allocator, bytes: []const u8) !Self {
        if (bytes.len == 0) {
            return error.EmptyByteArray;
        }
        
        switch (bytes[0]) {
            0x02 => {
                const eip1559 = try EthereumEIP1559Transaction.fromBytes(allocator, bytes);
                return Self{ .eip1559 = eip1559 };
            },
            0x01 => {
                const eip2930 = try EthereumEIP2930Transaction.fromBytes(allocator, bytes);
                return Self{ .eip2930 = eip2930 };
            },
            else => {
                const legacy = try EthereumLegacyTransaction.fromBytes(allocator, bytes);
                return Self{ .legacy = legacy };
            },
        }
    }
    
    pub fn toBytes(self: *const Self, allocator: Allocator) ![]u8 {
        switch (self.*) {
            .eip1559 => |*tx| return try tx.toBytes(allocator),
            .eip2930 => |*tx| return try tx.toBytes(allocator),
            .legacy => |*tx| return try tx.toBytes(allocator),
        }
    }
    
    pub fn deinit(self: *Self, allocator: Allocator) void {
        switch (self.*) {
            .eip1559 => |*tx| tx.deinit(allocator),
            .eip2930 => |*tx| tx.deinit(allocator),
            .legacy => |*tx| tx.deinit(allocator),
        }
    }
    
    pub fn getTransactionType(self: *const Self) u8 {
        return switch (self.*) {
            .eip1559 => 0x02,
            .eip2930 => 0x01,
            .legacy => 0x00,
        };
    }
    
    pub fn getGasLimit(self: *const Self) u64 {
        return switch (self.*) {
            .eip1559 => |*tx| tx.getGasLimit(),
            .eip2930 => |*tx| tx.getGasLimit(),
            .legacy => |*tx| tx.getGasLimit(),
        };
    }
    
    pub fn getGasPrice(self: *const Self) ?u64 {
        return switch (self.*) {
            .eip1559 => null, // EIP-1559 uses maxFeePerGas and maxPriorityFeePerGas instead
            .eip2930 => |*tx| tx.getGasPrice(),
            .legacy => |*tx| tx.getGasPrice(),
        };
    }
    
    pub fn getMaxFeePerGas(self: *const Self) ?u64 {
        return switch (self.*) {
            .eip1559 => |*tx| tx.getMaxFeePerGas(),
            .eip2930 => null,
            .legacy => null,
        };
    }
    
    pub fn getMaxPriorityFeePerGas(self: *const Self) ?u64 {
        return switch (self.*) {
            .eip1559 => |*tx| tx.getMaxPriorityFeePerGas(),
            .eip2930 => null,
            .legacy => null,
        };
    }
    
    pub fn getValue(self: *const Self) []const u8 {
        return switch (self.*) {
            .eip1559 => |*tx| tx.getValue(),
            .eip2930 => |*tx| tx.getValue(),
            .legacy => |*tx| tx.getValue(),
        };
    }
    
    pub fn getTo(self: *const Self) ?[]const u8 {
        return switch (self.*) {
            .eip1559 => |*tx| tx.getTo(),
            .eip2930 => |*tx| tx.getTo(),
            .legacy => |*tx| tx.getTo(),
        };
    }
    
    pub fn getData(self: *const Self) []const u8 {
        return switch (self.*) {
            .eip1559 => |*tx| tx.getData(),
            .eip2930 => |*tx| tx.getData(),
            .legacy => |*tx| tx.getData(),
        };
    }
    
    pub fn getNonce(self: *const Self) []const u8 {
        return switch (self.*) {
            .eip1559 => |*tx| tx.getNonce(),
            .eip2930 => |*tx| tx.getNonce(),
            .legacy => |*tx| tx.getNonce(),
        };
    }
    
    pub fn getChainId(self: *const Self) []const u8 {
        return switch (self.*) {
            .eip1559 => |*tx| tx.getChainId(),
            .eip2930 => |*tx| tx.getChainId(),
            .legacy => |*tx| tx.getChainId(),
        };
    }
    
    pub fn getRecoveryId(self: *const Self) ?u8 {
        return switch (self.*) {
            .eip1559 => |*tx| tx.getRecoveryId(),
            .eip2930 => |*tx| tx.getRecoveryId(),
            .legacy => |*tx| tx.getRecoveryId(),
        };
    }
    
    pub fn getR(self: *const Self) []const u8 {
        return switch (self.*) {
            .eip1559 => |*tx| tx.getR(),
            .eip2930 => |*tx| tx.getR(),
            .legacy => |*tx| tx.getR(),
        };
    }
    
    pub fn getS(self: *const Self) []const u8 {
        return switch (self.*) {
            .eip1559 => |*tx| tx.getS(),
            .eip2930 => |*tx| tx.getS(),
            .legacy => |*tx| tx.getS(),
        };
    }
    
    pub fn getAccessList(self: *const Self) ?[]const AccessListItem {
        return switch (self.*) {
            .eip1559 => |*tx| tx.getAccessList(),
            .eip2930 => |*tx| tx.getAccessList(),
            .legacy => null,
        };
    }
    
    pub fn sign(self: *Self, private_key: []const u8) !void {
        switch (self.*) {
            .eip1559 => |*tx| try tx.sign(private_key),
            .eip2930 => |*tx| try tx.sign(private_key),
            .legacy => |*tx| try tx.sign(private_key),
        }
    }
    
    pub fn verify(self: *const Self) !bool {
        return switch (self.*) {
            .eip1559 => |*tx| try tx.verify(),
            .eip2930 => |*tx| try tx.verify(),
            .legacy => |*tx| try tx.verify(),
        };
    }
    
    pub fn hash(self: *const Self, allocator: Allocator) ![]u8 {
        return switch (self.*) {
            .eip1559 => |*tx| try tx.hash(allocator),
            .eip2930 => |*tx| try tx.hash(allocator),
            .legacy => |*tx| try tx.hash(allocator),
        };
    }
    
    pub fn estimateGas(self: *const Self) u64 {
        return switch (self.*) {
            .eip1559 => |*tx| tx.estimateGas(),
            .eip2930 => |*tx| tx.estimateGas(),
            .legacy => |*tx| tx.estimateGas(),
        };
    }
    
    pub fn isDeployment(self: *const Self) bool {
        return switch (self.*) {
            .eip1559 => |*tx| tx.isDeployment(),
            .eip2930 => |*tx| tx.isDeployment(),
            .legacy => |*tx| tx.isDeployment(),
        };
    }
    
    pub fn toString(self: *const Self, allocator: Allocator) ![]u8 {
        return switch (self.*) {
            .eip1559 => |*tx| try tx.toString(allocator),
            .eip2930 => |*tx| try tx.toString(allocator),
            .legacy => |*tx| try tx.toString(allocator),
        };
    }
    
    // Convert from protobuf bytes
    pub fn fromProtobufBytes(allocator: Allocator, bytes: []const u8) !Self {
        if (bytes.len == 0) {
            return error.EmptyProtobufData;
        }
        
        var reader = protobuf.ProtobufReader.init(allocator, bytes);
        
        while (try reader.nextField()) |field| {
            switch (field.tag) {
                1 => {
                    // ethereum_data oneof field
                    const data = try field.readBytes(allocator);
                    defer allocator.free(data);
                    
                    // Determine transaction type and parse accordingly
                    return try Self.fromBytes(allocator, data);
                },
                else => try field.skip(),
            }
        }
        
        return error.InvalidProtobufMessage;
    }
    
    // Convert to protobuf bytes
    pub fn toProtobufBytes(self: *const Self, allocator: Allocator) ![]u8 {
        var writer = protobuf.ProtobufWriter.init(allocator);
        defer writer.deinit();
        
        const tx_bytes = try self.toBytes(allocator);
        defer allocator.free(tx_bytes);
        
        // Write protobuf message with ethereum_data field
        try writer.writeBytesField(1, tx_bytes);
        
        return try writer.toOwnedSlice();
    }
    
    pub fn clone(self: *const Self, allocator: Allocator) !Self {
        return switch (self.*) {
            .eip1559 => |*tx| Self{ .eip1559 = try tx.clone(allocator) },
            .eip2930 => |*tx| Self{ .eip2930 = try tx.clone(allocator) },
            .legacy => |*tx| Self{ .legacy = try tx.clone(allocator) },
        };
    }
    
    pub fn equals(self: *const Self, other: *const Self) bool {
        return switch (self.*) {
            .eip1559 => |*tx| switch (other.*) {
                .eip1559 => |*other_tx| tx.equals(other_tx),
                else => false,
            },
            .eip2930 => |*tx| switch (other.*) {
                .eip2930 => |*other_tx| tx.equals(other_tx),
                else => false,
            },
            .legacy => |*tx| switch (other.*) {
                .legacy => |*other_tx| tx.equals(other_tx),
                else => false,
            },
        };
    }
};

// Access list item structure (used by EIP-2930 and EIP-1559)
pub const AccessListItem = struct {
    address: [20]u8,
    storage_keys: []const [32]u8,
    
    pub fn deinit(self: *AccessListItem, allocator: Allocator) void {
        allocator.free(self.storage_keys);
    }
    
    pub fn clone(self: *const AccessListItem, allocator: Allocator) !AccessListItem {
        const storage_keys = try allocator.dupe([32]u8, self.storage_keys);
        return AccessListItem{
            .address = self.address,
            .storage_keys = storage_keys,
        };
    }
};
const std = @import("std");
const FileId = @import("../core/id.zig").FileId;
const Timestamp = @import("../core/timestamp.zig").Timestamp;
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const errors = @import("../core/errors.zig");

// FreezeType specifies the type of freeze operation
pub const FreezeType = enum(i32) {
    unknown_freeze_type = 0,
    freeze_only = 1,
    prepare_upgrade = 2,
    freeze_upgrade = 3,
    freeze_abort = 4,
    telemetry_upgrade = 5,
};

// FreezeTransaction freezes the network for maintenance
pub const FreezeTransaction = struct {
    base: Transaction,
    start_hour: u8,
    start_min: u8,
    end_hour: u8,
    end_min: u8,
    update_file: ?FileId,
    file_hash: []const u8,
    freeze_type: FreezeType,
    
    pub fn init(allocator: std.mem.Allocator) FreezeTransaction {
        return FreezeTransaction{
            .base = Transaction.init(allocator),
            .start_hour = 0,
            .start_min = 0,
            .end_hour = 0,
            .end_min = 0,
            .update_file = null,
            .file_hash = "",
            .freeze_type = .freeze_only,
        };
    }
    
    pub fn deinit(self: *FreezeTransaction) void {
        self.base.deinit();
    }
    
    // Set freeze start time
    pub fn setStartTime(self: *FreezeTransaction, hour: u8, min: u8) errors.HederaError!*FreezeTransaction {
        if (self.base.frozen) return errors.HederaError.TransactionFrozen;
        if (hour >= 24) return errors.HederaError.InvalidParameter;
        if (min >= 60) return errors.HederaError.InvalidParameter;
        
        self.start_hour = hour;
        self.start_min = min;
        return self;
    }
    
    // Set freeze end time
    pub fn setEndTime(self: *FreezeTransaction, hour: u8, min: u8) errors.HederaError!*FreezeTransaction {
        if (self.base.frozen) return errors.HederaError.TransactionFrozen;
        if (hour >= 24) return errors.HederaError.InvalidParameter;
        if (min >= 60) return errors.HederaError.InvalidParameter;
        
        self.end_hour = hour;
        self.end_min = min;
        return self;
    }
    
    // Set update file
    pub fn setUpdateFile(self: *FreezeTransaction, file_id: FileId) errors.HederaError!*FreezeTransaction {
        if (self.base.frozen) return errors.HederaError.TransactionFrozen;
        self.update_file = file_id;
        return self;
    }
    
    // Set file hash
    pub fn setFileHash(self: *FreezeTransaction, hash: []const u8) errors.HederaError!*FreezeTransaction {
        if (self.base.frozen) return errors.HederaError.TransactionFrozen;
        if (hash.len != 48) return errors.HederaError.InvalidParameter; // SHA-384 hash
        self.file_hash = hash;
        return self;
    }
    
    // Set freeze type
    pub fn setFreezeType(self: *FreezeTransaction, freeze_type: FreezeType) errors.HederaError!*FreezeTransaction {
        if (self.base.frozen) return errors.HederaError.TransactionFrozen;
        self.freeze_type = freeze_type;
        return self;
    }
    
    // Execute the transaction
    pub fn execute(self: *FreezeTransaction, client: *Client) !TransactionResponse {
        // Validate freeze type requirements
        switch (self.freeze_type) {
            .prepare_upgrade, .freeze_upgrade => {
                if (self.update_file == null) {
                    return error.UpdateFileRequired;
                }
                if (self.file_hash.len == 0) {
                    return error.FileHashRequired;
                }
            },
            .telemetry_upgrade => {
                if (self.update_file == null) {
                    return error.UpdateFileRequired;
                }
            },
            .freeze_only, .freeze_abort => {
                // No additional requirements
            },
            .unknown_freeze_type => return error.InvalidFreezeType,
        }
        
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *FreezeTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Common transaction fields
        try self.writeCommonFields(&writer);
        
        // freeze = 11 (oneof data)
        var freeze_writer = ProtoWriter.init(self.base.allocator);
        defer freeze_writer.deinit();
        
        // startHour = 1
        try freeze_writer.writeInt32(1, @intCast(self.start_hour));
        
        // startMin = 2
        try freeze_writer.writeInt32(2, @intCast(self.start_min));
        
        // endHour = 3
        try freeze_writer.writeInt32(3, @intCast(self.end_hour));
        
        // endMin = 4
        try freeze_writer.writeInt32(4, @intCast(self.end_min));
        
        // updateFile = 5
        if (self.update_file) |file| {
            var file_writer = ProtoWriter.init(self.base.allocator);
            defer file_writer.deinit();
            try file_writer.writeInt64(1, @intCast(file.shard));
            try file_writer.writeInt64(2, @intCast(file.realm));
            try file_writer.writeInt64(3, @intCast(file.num));
            const file_bytes = try file_writer.toOwnedSlice();
            defer self.base.allocator.free(file_bytes);
            try freeze_writer.writeMessage(5, file_bytes);
        }
        
        // fileHash = 6
        if (self.file_hash.len > 0) {
            try freeze_writer.writeBytes(6, self.file_hash);
        }
        
        // freezeType = 7
        try freeze_writer.writeInt32(7, @intFromEnum(self.freeze_type));
        
        const freeze_bytes = try freeze_writer.toOwnedSlice();
        defer self.base.allocator.free(freeze_bytes);
        try writer.writeMessage(11, freeze_bytes);
        
        return writer.toOwnedSlice();
    }
    
    fn writeCommonFields(self: *FreezeTransaction, writer: *ProtoWriter) !void {
        // transactionID = 1
        if (self.base.transaction_id) |tx_id| {
            var tx_id_writer = ProtoWriter.init(self.base.allocator);
            defer tx_id_writer.deinit();
            
            var timestamp_writer = ProtoWriter.init(self.base.allocator);
            defer timestamp_writer.deinit();
            try timestamp_writer.writeInt64(1, tx_id.valid_start.seconds);
            try timestamp_writer.writeInt32(2, tx_id.valid_start.nanos);
            const timestamp_bytes = try timestamp_writer.toOwnedSlice();
            defer self.base.allocator.free(timestamp_bytes);
            try tx_id_writer.writeMessage(1, timestamp_bytes);
            
            var account_writer = ProtoWriter.init(self.base.allocator);
            defer account_writer.deinit();
            try account_writer.writeInt64(1, @intCast(tx_id.account_id.shard));
            try account_writer.writeInt64(2, @intCast(tx_id.account_id.realm));
            try account_writer.writeInt64(3, @intCast(tx_id.account_id.account));
            const account_bytes = try account_writer.toOwnedSlice();
            defer self.base.allocator.free(account_bytes);
            try tx_id_writer.writeMessage(2, account_bytes);
            
            if (tx_id.nonce) |n| {
                try tx_id_writer.writeInt32(4, @intCast(n));
            }
            
            const tx_id_bytes = try tx_id_writer.toOwnedSlice();
            defer self.base.allocator.free(tx_id_bytes);
            try writer.writeMessage(1, tx_id_bytes);
        }
        
        // nodeAccountID = 2
        if (self.base.node_account_ids.items.len > 0) {
            var node_writer = ProtoWriter.init(self.base.allocator);
            defer node_writer.deinit();
            const node = self.base.node_account_ids.items[0];
            try node_writer.writeInt64(1, @intCast(node.shard));
            try node_writer.writeInt64(2, @intCast(node.realm));
            try node_writer.writeInt64(3, @intCast(node.account));
            const node_bytes = try node_writer.toOwnedSlice();
            defer self.base.allocator.free(node_bytes);
            try writer.writeMessage(2, node_bytes);
        }
        
        // transactionFee = 3
        if (self.base.max_transaction_fee) |fee| {
            try writer.writeUint64(3, @intCast(fee.toTinybars()));
        }
        
        // transactionValidDuration = 4
        var duration_writer = ProtoWriter.init(self.base.allocator);
        defer duration_writer.deinit();
        try duration_writer.writeInt64(1, self.base.transaction_valid_duration.seconds);
        const duration_bytes = try duration_writer.toOwnedSlice();
        defer self.base.allocator.free(duration_bytes);
        try writer.writeMessage(4, duration_bytes);
        
        // memo = 5
        if (self.base.transaction_memo.len > 0) {
            try writer.writeString(5, self.base.transaction_memo);
        }
    }
};
const std = @import("std");
const errors = @import("../core/errors.zig");
const FileId = @import("../core/id.zig").FileId;
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;

// FileDeleteTransaction deletes a file from the Hedera network
pub const FileDeleteTransaction = struct {
    base: Transaction,
    file_id: ?FileId,
    
    pub fn init(allocator: std.mem.Allocator) FileDeleteTransaction {
        return FileDeleteTransaction{
            .base = Transaction.init(allocator),
            .file_id = null,
        };
    }
    
    pub fn deinit(self: *FileDeleteTransaction) void {
        self.base.deinit();
    }
    
    // Set the file ID to delete
    pub fn setFileId(self: *FileDeleteTransaction, file_id: FileId) errors.HederaError!*FileDeleteTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        self.file_id = file_id;
        return self;
    }
    
    // Execute the transaction
    pub fn execute(self: *FileDeleteTransaction, client: *Client) !TransactionResponse {
        if (self.file_id == null) {
            return error.FileIdRequired;
        }
        
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *FileDeleteTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Common transaction fields
        try self.writeCommonFields(&writer);
        
        // fileDelete = 17 (oneof data)
        var delete_writer = ProtoWriter.init(self.base.allocator);
        defer delete_writer.deinit();
        
        // fileID = 2
        if (self.file_id) |file| {
            var file_writer = ProtoWriter.init(self.base.allocator);
            defer file_writer.deinit();
            try file_writer.writeInt64(1, @intCast(file.shard));
            try file_writer.writeInt64(2, @intCast(file.realm));
            try file_writer.writeInt64(3, @intCast(file.num));
            const file_bytes = try file_writer.toOwnedSlice();
            defer self.base.allocator.free(file_bytes);
            try delete_writer.writeMessage(2, file_bytes);
        }
        
        const delete_bytes = try delete_writer.toOwnedSlice();
        defer self.base.allocator.free(delete_bytes);
        try writer.writeMessage(17, delete_bytes);
        
        return writer.toOwnedSlice();
    }
    
    fn writeCommonFields(self: *FileDeleteTransaction, writer: *ProtoWriter) !void {
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
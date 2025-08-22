const std = @import("std");
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;

// PrngTransaction generates a pseudorandom number on the Hedera network
pub const PrngTransaction = struct {
    base: Transaction,
    range: ?i32,
    
    pub fn init(allocator: std.mem.Allocator) PrngTransaction {
        return PrngTransaction{
            .base = Transaction.init(allocator),
            .range = null,
        };
    }
    
    pub fn deinit(self: *PrngTransaction) void {
        self.base.deinit();
    }
    
    // Set the range for the random number (0 to range-1)
    pub fn setRange(self: *PrngTransaction, range: i32) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        if (range <= 0) return error.InvalidRange;
        self.range = range;
    }
    
    // Execute the transaction
    pub fn execute(self: *PrngTransaction, client: *Client) !TransactionResponse {
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *PrngTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Common transaction fields
        try self.writeCommonFields(&writer);
        
        // utilPrng = 52 (oneof data)
        var prng_writer = ProtoWriter.init(self.base.allocator);
        defer prng_writer.deinit();
        
        // range = 1
        if (self.range) |range| {
            try prng_writer.writeInt32(1, range);
        }
        
        const prng_bytes = try prng_writer.toOwnedSlice();
        defer self.base.allocator.free(prng_bytes);
        try writer.writeMessage(52, prng_bytes);
        
        return writer.toOwnedSlice();
    }
    
    fn writeCommonFields(self: *PrngTransaction, writer: *ProtoWriter) !void {
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
            try account_writer.writeInt64(1, @intCast(tx_id.account_id.entity.shard));
            try account_writer.writeInt64(2, @intCast(tx_id.account_id.entity.realm));
            try account_writer.writeInt64(3, @intCast(tx_id.account_id.entity.num));
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
            try node_writer.writeInt64(1, @intCast(node.entity.shard));
            try node_writer.writeInt64(2, @intCast(node.entity.realm));
            try node_writer.writeInt64(3, @intCast(node.entity.num));
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
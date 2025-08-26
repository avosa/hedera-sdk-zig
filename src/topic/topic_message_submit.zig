const std = @import("std");
const errors = @import("../core/errors.zig");
const HederaError = errors.HederaError;
const TopicId = @import("../core/id.zig").TopicId;
const AccountId = @import("../core/id.zig").AccountId;
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;
const Client = @import("../network/client.zig").Client;
const Hbar = @import("../core/hbar.zig").Hbar;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;

// CustomFeeLimit represents a custom fee limit
pub const CustomFeeLimit = struct {
    fee_collector_account_id: AccountId,
    max_amount: u64,
    
    pub fn init(fee_collector_account_id: AccountId, max_amount: u64) CustomFeeLimit {
        return CustomFeeLimit{
            .fee_collector_account_id = fee_collector_account_id,
            .max_amount = max_amount,
        };
    }
};

// TopicMessageSubmitTransaction submits a message to a consensus topic
pub const TopicMessageSubmitTransaction = struct {
    base: Transaction,
    topic_id: ?TopicId,
    message: []const u8,
    max_chunks: u64,
    chunk_size: u64,
    
    pub fn init(allocator: std.mem.Allocator) TopicMessageSubmitTransaction {
        var transaction = TopicMessageSubmitTransaction{
            .base = Transaction.init(allocator),
            .topic_id = null,
            .message = "",
            .max_chunks = 20,
            .chunk_size = 1024,
        };
        transaction.base.buildTransactionBodyForNode = buildTransactionBodyForNode;
        transaction.base.grpc_service_name = "proto.ConsensusService";
        transaction.base.grpc_method_name = "submitMessage";
        return transaction;
    }
    
    fn buildTransactionBodyForNode(base_tx: *Transaction, _: AccountId) anyerror![]u8 {
        const self: *TopicMessageSubmitTransaction = @fieldParentPtr("base", base_tx);
        return self.buildTransactionBody();
    }
    
    pub fn deinit(self: *TopicMessageSubmitTransaction) void {
        self.base.deinit();
    }
    
    // SetTopicID sets the topic to submit message to
    pub fn setTopicId(self: *TopicMessageSubmitTransaction, topic_id: TopicId) !*TopicMessageSubmitTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        self.topic_id = topic_id;
        return self;
    }
    
    // GetTopicID returns the TopicID for this TopicMessageSubmitTransaction
    pub fn getTopicId(self: *TopicMessageSubmitTransaction) TopicId {
        return self.topic_id orelse TopicId{};
    }
    
    // SetMessage sets the message to be submitted
    pub fn setMessage(self: *TopicMessageSubmitTransaction, message: []const u8) !*TopicMessageSubmitTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        self.message = message;
        return self;
    }
    
    // GetMessage returns the message to be submitted
    pub fn getMessage(self: *TopicMessageSubmitTransaction) []const u8 {
        return self.message;
    }
    
    // SetMaxChunks sets the maximum amount of chunks to use to send the message
    pub fn setMaxChunks(self: *TopicMessageSubmitTransaction, max_chunks: u64) !*TopicMessageSubmitTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        self.max_chunks = max_chunks;
        return self;
    }
    
    // GetMaxChunks returns the maximum amount of chunks to use to send the message
    pub fn getMaxChunks(self: *TopicMessageSubmitTransaction) u64 {
        return self.max_chunks;
    }
    
    // SetChunkSize sets the chunk size to use to send the message
    pub fn setChunkSize(self: *TopicMessageSubmitTransaction, chunk_size: u64) !*TopicMessageSubmitTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        self.chunk_size = chunk_size;
        return self;
    }
    
    // GetChunkSize returns the chunk size to use to send the message
    pub fn getChunkSize(self: *TopicMessageSubmitTransaction) u64 {
        return self.chunk_size;
    }
    
    // Freeze the transaction with client for execution
    pub fn freezeWith(self: *TopicMessageSubmitTransaction, client: *Client) !*Transaction {
        return try self.base.freezeWith(client);
    }
    
    // Sign the transaction with a private key
    pub fn sign(self: *TopicMessageSubmitTransaction, private_key: anytype) !void {
        _ = try self.base.sign(private_key);
    }
    
    // Execute the transaction
    pub fn execute(self: *TopicMessageSubmitTransaction, client: *Client) !TransactionResponse {
        if (self.topic_id == null) {
            return error.TopicIdRequired;
        }
        if (self.message.len == 0) {
            return error.MessageRequired;
        }
        
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *TopicMessageSubmitTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Common transaction fields
        try self.writeCommonFields(&writer);
        
        // consensusSubmitMessage = 6 (oneof data)
        var submit_writer = ProtoWriter.init(self.base.allocator);
        defer submit_writer.deinit();
        
        // topicID = 1
        if (self.topic_id) |topic| {
            var topic_writer = ProtoWriter.init(self.base.allocator);
            defer topic_writer.deinit();
            try topic_writer.writeInt64(1, @intCast(topic.entity.shard));
            try topic_writer.writeInt64(2, @intCast(topic.entity.realm));
            try topic_writer.writeInt64(3, @intCast(topic.entity.num));
            const topic_bytes = try topic_writer.toOwnedSlice();
            defer self.base.allocator.free(topic_bytes);
            try submit_writer.writeMessage(1, topic_bytes);
        }
        
        // message = 2
        if (self.message.len > 0) {
            try submit_writer.writeString(2, self.message);
        }
        
        const submit_bytes = try submit_writer.toOwnedSlice();
        defer self.base.allocator.free(submit_bytes);
        try writer.writeMessage(6, submit_bytes);
        
        return writer.toOwnedSlice();
    }
    
    fn writeCommonFields(self: *TopicMessageSubmitTransaction, writer: *ProtoWriter) !void {
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

// NewTopicMessageSubmitTransaction creates a TopicMessageSubmitTransaction

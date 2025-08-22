const std = @import("std");
const TopicId = @import("../core/id.zig").TopicId;
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const crypto = std.crypto;

// Maximum message size for consensus service
pub const MAX_MESSAGE_SIZE: usize = 1024;
pub const MAX_CHUNKS: usize = 20;
pub const CHUNK_SIZE: usize = 1024;

// TopicMessageSubmitTransaction submits a message to a topic
pub const TopicMessageSubmitTransaction = struct {
    base: Transaction,
    topic_id: ?TopicId,
    message: []const u8,
    chunk_info: ?ChunkInfo,
    max_chunks: u32,
    chunk_size: u32,
    
    const ChunkInfo = struct {
        initial_transaction_id: TransactionId,
        total: i32,
        number: i32,
    };
    
    pub fn init(allocator: std.mem.Allocator) TopicMessageSubmitTransaction {
        return TopicMessageSubmitTransaction{
            .base = Transaction.init(allocator),
            .topic_id = null,
            .message = "",
            .chunk_info = null,
            .max_chunks = MAX_CHUNKS,
            .chunk_size = CHUNK_SIZE,
        };
    }
    
    pub fn deinit(self: *TopicMessageSubmitTransaction) void {
        self.base.deinit();
    }
    
    // Set the topic ID
    pub fn setTopicId(self: *TopicMessageSubmitTransaction, topic_id: TopicId) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.topic_id = topic_id;
    }
    
    // Set the message
    pub fn setMessage(self: *TopicMessageSubmitTransaction, message: []const u8) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        
        if (message.len > MAX_MESSAGE_SIZE * MAX_CHUNKS) {
            return error.MessageTooLarge;
        }
        
        self.message = message;
    }
    
    // Set max chunks
    pub fn setMaxChunks(self: *TopicMessageSubmitTransaction, max_chunks: u32) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        
        if (max_chunks == 0 or max_chunks > MAX_CHUNKS) {
            return error.InvalidMaxChunks;
        }
        
        self.max_chunks = max_chunks;
    }
    
    // Set chunk size
    pub fn setChunkSize(self: *TopicMessageSubmitTransaction, chunk_size: u32) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        
        if (chunk_size == 0 or chunk_size > CHUNK_SIZE) {
            return error.InvalidChunkSize;
        }
        
        self.chunk_size = chunk_size;
    }
    
    // Execute the transaction
    pub fn execute(self: *TopicMessageSubmitTransaction, client: *Client) !TransactionResponse {
        if (self.topic_id == null) {
            return error.TopicIdRequired;
        }
        
        if (self.message.len == 0) {
            return error.MessageRequired;
        }
        
        // Handle chunking for large messages
        if (self.message.len > MAX_MESSAGE_SIZE) {
            return try self.executeChunked(client);
        }
        
        return try self.base.execute(client);
    }
    
    // Execute chunked message submission
    fn executeChunked(self: *TopicMessageSubmitTransaction, client: *Client) !TransactionResponse {
        const chunk_count = (self.message.len + CHUNK_SIZE - 1) / CHUNK_SIZE;
        
        if (chunk_count > MAX_CHUNKS) {
            return error.TooManyChunks;
        }
        
        // Generate initial transaction ID for all chunks
        const initial_tx_id = try self.base.getTransactionId();
        
        var last_response: ?TransactionResponse = null;
        
        // Submit each chunk
        var i: usize = 0;
        while (i < chunk_count) : (i += 1) {
            const start = i * CHUNK_SIZE;
            const end = @min(start + CHUNK_SIZE, self.message.len);
            const chunk_data = self.message[start..end];
            
            // Create transaction for this chunk
            var chunk_tx = TopicMessageSubmitTransaction.init(self.base.allocator);
            defer chunk_tx.deinit();
            
            chunk_tx.topic_id = self.topic_id;
            chunk_tx.message = chunk_data;
            chunk_tx.chunk_info = ChunkInfo{
                .initial_transaction_id = initial_tx_id,
                .total = @intCast(chunk_count),
                .number = @intCast(i + 1),
            };
            
            // Set transaction ID with nonce for chunks after the first
            if (i > 0) {
                const chunk_tx_id = initial_tx_id.withNonce(@intCast(i));
                try chunk_tx.base.setTransactionId(chunk_tx_id);
            } else {
                try chunk_tx.base.setTransactionId(initial_tx_id);
            }
            
            // Copy other transaction settings
            chunk_tx.base.node_account_ids = self.base.node_account_ids;
            chunk_tx.base.max_transaction_fee = self.base.max_transaction_fee;
            
            // Execute chunk transaction
            const response = try chunk_tx.base.execute(client);
            last_response = response;
        }
        
        return last_response orelse error.NoChunksSubmitted;
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *TopicMessageSubmitTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Common transaction fields
        try self.writeCommonFields(&writer);
        
        // consensusSubmitMessage = 27 (oneof data)
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
        try submit_writer.writeString(2, self.message);
        
        // chunkInfo = 3
        if (self.chunk_info) |chunk| {
            var chunk_writer = ProtoWriter.init(self.base.allocator);
            defer chunk_writer.deinit();
            
            // initialTransactionID = 1
            var tx_id_writer = ProtoWriter.init(self.base.allocator);
            defer tx_id_writer.deinit();
            
            // Write initial transaction ID fields
            var timestamp_writer = ProtoWriter.init(self.base.allocator);
            defer timestamp_writer.deinit();
            try timestamp_writer.writeInt64(1, chunk.initial_transaction_id.valid_start.seconds);
            try timestamp_writer.writeInt32(2, chunk.initial_transaction_id.valid_start.nanos);
            const timestamp_bytes = try timestamp_writer.toOwnedSlice();
            defer self.base.allocator.free(timestamp_bytes);
            try tx_id_writer.writeMessage(1, timestamp_bytes);
            
            var account_writer = ProtoWriter.init(self.base.allocator);
            defer account_writer.deinit();
            try account_writer.writeInt64(1, @intCast(chunk.initial_transaction_id.account_id.entity.shard));
            try account_writer.writeInt64(2, @intCast(chunk.initial_transaction_id.account_id.entity.realm));
            try account_writer.writeInt64(3, @intCast(chunk.initial_transaction_id.account_id.entity.num));
            const account_bytes = try account_writer.toOwnedSlice();
            defer self.base.allocator.free(account_bytes);
            try tx_id_writer.writeMessage(2, account_bytes);
            
            const tx_id_bytes = try tx_id_writer.toOwnedSlice();
            defer self.base.allocator.free(tx_id_bytes);
            try chunk_writer.writeMessage(1, tx_id_bytes);
            
            // total = 2
            try chunk_writer.writeInt32(2, chunk.total);
            
            // number = 3
            try chunk_writer.writeInt32(3, chunk.number);
            
            const chunk_bytes = try chunk_writer.toOwnedSlice();
            defer self.base.allocator.free(chunk_bytes);
            try submit_writer.writeMessage(3, chunk_bytes);
        }
        
        const submit_bytes = try submit_writer.toOwnedSlice();
        defer self.base.allocator.free(submit_bytes);
        try writer.writeMessage(27, submit_bytes);
        
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
    
    // Generate message ID for submitted message
    pub fn generateMessageId(self: TopicMessageSubmitTransaction, sequence_number: u64) ![]u8 {
        if (self.topic_id == null) return error.TopicIdRequired;
        if (self.base.transaction_id == null) return error.TransactionIdRequired;
        
        var hasher = crypto.hash.sha2.Sha384.init(.{});
        
        // Hash topic ID
        const topic = self.topic_id.?;
        var topic_bytes: [24]u8 = undefined;
        std.mem.writeInt(u64, topic_bytes[0..8], topic.entity.shard, .big);
        std.mem.writeInt(u64, topic_bytes[8..16], topic.entity.realm, .big);
        std.mem.writeInt(u64, topic_bytes[16..24], topic.entity.num, .big);
        hasher.update(&topic_bytes);
        
        // Hash consensus timestamp (using transaction valid start as approximation)
        const tx_id = self.base.transaction_id.?;
        var timestamp_bytes: [12]u8 = undefined;
        std.mem.writeInt(i64, timestamp_bytes[0..8], tx_id.valid_start.seconds, .big);
        std.mem.writeInt(i32, timestamp_bytes[8..12], tx_id.valid_start.nanos, .big);
        hasher.update(&timestamp_bytes);
        
        // Hash sequence number
        var seq_bytes: [8]u8 = undefined;
        std.mem.writeInt(u64, &seq_bytes, sequence_number, .big);
        hasher.update(&seq_bytes);
        
        // Hash message
        hasher.update(self.message);
        
        var hash: [48]u8 = undefined;
        hasher.final(&hash);
        
        // Return first 32 bytes as message ID
        return self.base.allocator.dupe(u8, hash[0..32]);
    }
};
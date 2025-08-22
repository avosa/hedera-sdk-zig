const std = @import("std");
const TopicId = @import("../core/id.zig").TopicId;
const AccountId = @import("../core/id.zig").AccountId;
const Key = @import("../crypto/key.zig").Key;
const Timestamp = @import("../core/timestamp.zig").Timestamp;
const Duration = @import("../core/duration.zig").Duration;
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;

// TopicUpdateTransaction updates the properties of a consensus topic
pub const TopicUpdateTransaction = struct {
    base: Transaction,
    topic_id: ?TopicId,
    memo: ?[]const u8,
    topic_memo: ?[]const u8,
    admin_key: ?Key,
    submit_key: ?Key,
    clear_submit_key: bool,
    auto_renew_period: ?Duration,
    auto_renew_account: ?AccountId,
    expiration_time: ?Timestamp,
    
    pub fn init(allocator: std.mem.Allocator) TopicUpdateTransaction {
        return TopicUpdateTransaction{
            .base = Transaction.init(allocator),
            .topic_id = null,
            .memo = null,
            .topic_memo = null,
            .admin_key = null,
            .submit_key = null,
            .clear_submit_key = false,
            .auto_renew_period = null,
            .auto_renew_account = null,
            .expiration_time = null,
        };
    }
    
    pub fn deinit(self: *TopicUpdateTransaction) void {
        self.base.deinit();
        // Keys don't need individual deinit
    }
    
    // Set the topic ID to update
    pub fn setTopicId(self: *TopicUpdateTransaction, topic_id: TopicId) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.topic_id = topic_id;
    }
    
    // Set topic memo
    pub fn setTopicMemo(self: *TopicUpdateTransaction, memo: []const u8) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        if (memo.len > 100) return error.TopicMemoTooLong;
        self.topic_memo = memo;
        self.memo = memo;  // Also set memo field for compatibility
    }
    
    // Set admin key
    pub fn setAdminKey(self: *TopicUpdateTransaction, key: Key) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.admin_key = key;
    }
    
    // Set submit key
    pub fn setSubmitKey(self: *TopicUpdateTransaction, key: Key) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.submit_key = key;
    }
    
    // Clear submit key
    pub fn clearSubmitKey(self: *TopicUpdateTransaction) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.submit_key = null;
        self.clear_submit_key = true;
    }
    
    // Set auto renew period
    pub fn setAutoRenewPeriod(self: *TopicUpdateTransaction, period: Duration) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        if (period.seconds < 30 * 24 * 60 * 60) return error.InvalidAutoRenewPeriod; // Minimum 30 days
        self.auto_renew_period = period;
    }
    
    // Set auto renew account
    pub fn setAutoRenewAccount(self: *TopicUpdateTransaction, account_id: AccountId) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.auto_renew_account = account_id;
    }
    
    // Set expiration time
    pub fn setExpirationTime(self: *TopicUpdateTransaction, time: Timestamp) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.expiration_time = time;
    }
    
    // Execute the transaction
    pub fn execute(self: *TopicUpdateTransaction, client: *Client) !TransactionResponse {
        if (self.topic_id == null) {
            return error.TopicIdRequired;
        }
        
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *TopicUpdateTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Common transaction fields
        try self.writeCommonFields(&writer);
        
        // consensusUpdateTopic = 25 (oneof data)
        var update_writer = ProtoWriter.init(self.base.allocator);
        defer update_writer.deinit();
        
        // topicID = 1
        if (self.topic_id) |topic| {
            var topic_writer = ProtoWriter.init(self.base.allocator);
            defer topic_writer.deinit();
            try topic_writer.writeInt64(1, @intCast(topic.entity.shard));
            try topic_writer.writeInt64(2, @intCast(topic.entity.realm));
            try topic_writer.writeInt64(3, @intCast(topic.entity.num));
            const topic_bytes = try topic_writer.toOwnedSlice();
            defer self.base.allocator.free(topic_bytes);
            try update_writer.writeMessage(1, topic_bytes);
        }
        
        // memo = 2
        if (self.topic_memo.len > 0) {
            var memo_wrapper = ProtoWriter.init(self.base.allocator);
            defer memo_wrapper.deinit();
            try memo_wrapper.writeString(1, self.topic_memo);
            const memo_bytes = try memo_wrapper.toOwnedSlice();
            defer self.base.allocator.free(memo_bytes);
            try update_writer.writeMessage(2, memo_bytes);
        }
        
        // expirationTime = 4
        if (self.expiration_time) |exp_time| {
            var exp_writer = ProtoWriter.init(self.base.allocator);
            defer exp_writer.deinit();
            try exp_writer.writeInt64(1, exp_time.seconds);
            try exp_writer.writeInt32(2, exp_time.nanos);
            const exp_bytes = try exp_writer.toOwnedSlice();
            defer self.base.allocator.free(exp_bytes);
            try update_writer.writeMessage(4, exp_bytes);
        }
        
        // adminKey = 6
        if (self.admin_key) |key| {
            const key_bytes = try key.toProtobuf(self.base.allocator);
            defer self.base.allocator.free(key_bytes);
            try update_writer.writeMessage(6, key_bytes);
        }
        
        // submitKey = 7
        if (self.submit_key) |key| {
            const key_bytes = try key.toProtobuf(self.base.allocator);
            defer self.base.allocator.free(key_bytes);
            try update_writer.writeMessage(7, key_bytes);
        }
        
        // autoRenewPeriod = 8
        if (self.auto_renew_period) |period| {
            var period_writer = ProtoWriter.init(self.base.allocator);
            defer period_writer.deinit();
            try period_writer.writeInt64(1, period.seconds);
            const period_bytes = try period_writer.toOwnedSlice();
            defer self.base.allocator.free(period_bytes);
            try update_writer.writeMessage(8, period_bytes);
        }
        
        // autoRenewAccount = 9
        if (self.auto_renew_account) |account| {
            var account_writer = ProtoWriter.init(self.base.allocator);
            defer account_writer.deinit();
            try account_writer.writeInt64(1, @intCast(account.entity.shard));
            try account_writer.writeInt64(2, @intCast(account.entity.realm));
            try account_writer.writeInt64(3, @intCast(account.entity.num));
            const account_bytes = try account_writer.toOwnedSlice();
            defer self.base.allocator.free(account_bytes);
            try update_writer.writeMessage(9, account_bytes);
        }
        
        const update_bytes = try update_writer.toOwnedSlice();
        defer self.base.allocator.free(update_bytes);
        try writer.writeMessage(25, update_bytes);
        
        return writer.toOwnedSlice();
    }
    
    fn writeCommonFields(self: *TopicUpdateTransaction, writer: *ProtoWriter) !void {
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
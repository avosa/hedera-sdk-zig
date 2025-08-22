const std = @import("std");
const AccountId = @import("../core/id.zig").AccountId;
const Key = @import("../crypto/key.zig").Key;
const Duration = @import("../core/duration.zig").Duration;
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;

// TopicCreateTransaction creates a new consensus service topic
pub const TopicCreateTransaction = struct {
    base: Transaction,
    memo: ?[]const u8,
    admin_key: ?Key,
    submit_key: ?Key,
    auto_renew_period: Duration,
    auto_renew_account: ?AccountId,
    auto_renew_account_id: ?AccountId,
    
    pub fn init(allocator: std.mem.Allocator) TopicCreateTransaction {
        return TopicCreateTransaction{
            .base = Transaction.init(allocator),
            .memo = null,
            .admin_key = null,
            .submit_key = null,
            .auto_renew_period = Duration{ .seconds = 7890000, .nanos = 0 }, // ~90 days default
            .auto_renew_account = null,
            .auto_renew_account_id = null,
        };
    }
    
    pub fn deinit(self: *TopicCreateTransaction) void {
        self.base.deinit();
    }
    
    // Set topic memo
    pub fn setTopicMemo(self: *TopicCreateTransaction, memo: []const u8) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        if (memo.len > 100) return error.MemoTooLong;
        self.memo = memo;
    }
    
    // Set admin key
    pub fn setAdminKey(self: *TopicCreateTransaction, key: Key) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.admin_key = key;
    }
    
    // Set submit key
    pub fn setSubmitKey(self: *TopicCreateTransaction, key: Key) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.submit_key = key;
    }
    
    // Set auto renew period
    pub fn setAutoRenewPeriod(self: *TopicCreateTransaction, period: Duration) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        
        // Minimum is ~1 day, maximum is ~3 months
        if (period.seconds < 86400 or period.seconds > 8000001) {
            return error.InvalidAutoRenewPeriod;
        }
        
        self.auto_renew_period = period;
    }
    
    // Set auto renew account
    pub fn setAutoRenewAccountId(self: *TopicCreateTransaction, account_id: AccountId) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.auto_renew_account = account_id;
        self.auto_renew_account_id = account_id;
    }
    
    // Set auto renew account (alias)
    pub fn setAutoRenewAccount(self: *TopicCreateTransaction, account_id: AccountId) !void {
        return self.setAutoRenewAccountId(account_id);
    }
    
    // Execute the transaction
    pub fn execute(self: *TopicCreateTransaction, client: *Client) !TransactionResponse {
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *TopicCreateTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Common transaction fields
        try self.writeCommonFields(&writer);
        
        // consensusCreateTopic = 24 (oneof data)
        var create_writer = ProtoWriter.init(self.base.allocator);
        defer create_writer.deinit();
        
        // memo = 1
        if (self.memo.len > 0) {
            try create_writer.writeString(1, self.memo);
        }
        
        // adminKey = 2
        if (self.admin_key) |key| {
            const key_bytes = try key.toProtobuf(self.base.allocator);
            defer self.base.allocator.free(key_bytes);
            try create_writer.writeMessage(2, key_bytes);
        }
        
        // submitKey = 3
        if (self.submit_key) |key| {
            const key_bytes = try key.toProtobuf(self.base.allocator);
            defer self.base.allocator.free(key_bytes);
            try create_writer.writeMessage(3, key_bytes);
        }
        
        // autoRenewPeriod = 6
        var duration_writer = ProtoWriter.init(self.base.allocator);
        defer duration_writer.deinit();
        try duration_writer.writeInt64(1, self.auto_renew_period.seconds);
        const duration_bytes = try duration_writer.toOwnedSlice();
        defer self.base.allocator.free(duration_bytes);
        try create_writer.writeMessage(6, duration_bytes);
        
        // autoRenewAccount = 7
        if (self.auto_renew_account_id) |account| {
            var account_writer = ProtoWriter.init(self.base.allocator);
            defer account_writer.deinit();
            try account_writer.writeInt64(1, @intCast(account.entity.shard));
            try account_writer.writeInt64(2, @intCast(account.entity.realm));
            try account_writer.writeInt64(3, @intCast(account.entity.num));
            const account_bytes = try account_writer.toOwnedSlice();
            defer self.base.allocator.free(account_bytes);
            try create_writer.writeMessage(7, account_bytes);
        }
        
        const create_bytes = try create_writer.toOwnedSlice();
        defer self.base.allocator.free(create_bytes);
        try writer.writeMessage(24, create_bytes);
        
        return writer.toOwnedSlice();
    }
    
    fn writeCommonFields(self: *TopicCreateTransaction, writer: *ProtoWriter) !void {
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
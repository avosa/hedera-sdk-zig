const std = @import("std");
const errors = @import("../core/errors.zig");
const HederaError = errors.HederaError;const AccountId = @import("../core/id.zig").AccountId;
const Key = @import("../crypto/key.zig").Key;
const Duration = @import("../core/duration.zig").Duration;
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const Client = @import("../network/client.zig").Client;
const Hbar = @import("../core/hbar.zig").Hbar;

// CustomFixedFee represents a fixed fee for custom fees
pub const CustomFixedFee = struct {
    amount: u64,
    denomination_token_id: ?[]const u8,
    fee_collector_account_id: AccountId,
    
    pub fn init(amount: u64, fee_collector_account_id: AccountId) CustomFixedFee {
        return CustomFixedFee{
            .amount = amount,
            .denomination_token_id = null,
            .fee_collector_account_id = fee_collector_account_id,
        };
    }
};

// TopicCreateTransaction creates a new consensus service topic
pub const TopicCreateTransaction = struct {
    base: Transaction,
    admin_key: ?Key,
    submit_key: ?Key,
    fee_schedule_key: ?Key,
    fee_exempt_keys: std.ArrayList(Key),
    custom_fees: std.ArrayList(*CustomFixedFee),
    memo: []const u8,
    auto_renew_period: Duration,
    auto_renew_account_id: ?AccountId,
    
    pub fn init(allocator: std.mem.Allocator) !*TopicCreateTransaction {
        var transaction = try allocator.create(TopicCreateTransaction);
        transaction.* = TopicCreateTransaction{
            .base = Transaction.init(allocator),
            .admin_key = null,
            .submit_key = null,
            .fee_schedule_key = null,
            .fee_exempt_keys = std.ArrayList(Key).init(allocator),
            .custom_fees = std.ArrayList(*CustomFixedFee).init(allocator),
            .memo = "",
            .auto_renew_period = Duration{ .seconds = 7776000, .nanos = 0 }, // 90 days
            .auto_renew_account_id = null,
        };
        
        transaction.base.max_transaction_fee = Hbar.fromTinybars(2500000000) catch Hbar.zero(); // 25 Hbar
        transaction.base.buildTransactionBodyForNode = buildTransactionBodyForNode;
        transaction.base.grpc_service_name = "proto.ConsensusService";
        transaction.base.grpc_method_name = "createTopic";
        
        return transaction;
    }
    
    fn buildTransactionBodyForNode(base_tx: *Transaction, _: AccountId) anyerror![]u8 {
        const self: *TopicCreateTransaction = @fieldParentPtr("base", base_tx);
        return self.buildTransactionBody();
    }
    
    pub fn buildTransactionBody(self: *TopicCreateTransaction) ![]u8 {
        const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
        
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        var create_writer = ProtoWriter.init(self.base.allocator);
        defer create_writer.deinit();
        
        if (self.admin_key) |key| {
            const key_bytes = try key.toProtobuf(self.base.allocator);
            defer self.base.allocator.free(key_bytes);
            try create_writer.writeMessage(1, key_bytes);
        }
        
        if (self.submit_key) |key| {
            const key_bytes = try key.toProtobuf(self.base.allocator);
            defer self.base.allocator.free(key_bytes);
            try create_writer.writeMessage(2, key_bytes);
        }
        
        var period_writer = ProtoWriter.init(self.base.allocator);
        defer period_writer.deinit();
        try period_writer.writeInt64(1, self.auto_renew_period.seconds);
        const period_bytes = try period_writer.toOwnedSlice();
        defer self.base.allocator.free(period_bytes);
        try create_writer.writeMessage(6, period_bytes);
        
        if (self.auto_renew_account_id) |account| {
            var account_writer = ProtoWriter.init(self.base.allocator);
            defer account_writer.deinit();
            try account_writer.writeInt64(1, @intCast(account.shard));
            try account_writer.writeInt64(2, @intCast(account.realm));
            try account_writer.writeInt64(3, @intCast(account.account));
            const account_bytes = try account_writer.toOwnedSlice();
            defer self.base.allocator.free(account_bytes);
            try create_writer.writeMessage(7, account_bytes);
        }
        
        if (self.memo.len > 0) {
            try create_writer.writeString(3, self.memo);
        }
        
        const create_bytes = try create_writer.toOwnedSlice();
        defer self.base.allocator.free(create_bytes);
        try writer.writeMessage(24, create_bytes);
        
        return writer.toOwnedSlice();
    }
    
    pub fn deinit(self: *TopicCreateTransaction) void {
        self.base.deinit();
        self.fee_exempt_keys.deinit();
        for (self.custom_fees.items) |fee| {
            self.base.allocator.destroy(fee);
        }
        self.custom_fees.deinit();
        self.base.allocator.destroy(self);
    }
    
    pub fn setAdminKey(self: *TopicCreateTransaction, public_key: Key) !*TopicCreateTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        self.admin_key = public_key;
        return self;
    }
    
    // getAdminKey returns the key required to update or delete the topic
    pub fn getAdminKey(self: *TopicCreateTransaction) !Key {
        return self.admin_key orelse error.AdminKeyNotSet;
    }
    
    // setSubmitKey sets the key required for submitting messages to the topic
    pub fn setSubmitKey(self: *TopicCreateTransaction, public_key: Key) !*TopicCreateTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        self.submit_key = public_key;
        return self;
    }
    
    // getSubmitKey returns the key required for submitting messages to the topic
    pub fn getSubmitKey(self: *TopicCreateTransaction) !Key {
        return self.submit_key orelse error.SubmitKeyNotSet;
    }
    
    // setFeeScheduleKey sets the key which allows updates to the new topic's fees
    pub fn setFeeScheduleKey(self: *TopicCreateTransaction, public_key: Key) !*TopicCreateTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        self.fee_schedule_key = public_key;
        return self;
    }
    
    // GetFeeScheduleKey returns the key which allows updates to the new topic's fees
    pub fn getFeeScheduleKey(self: *TopicCreateTransaction) Key {
        return self.fee_schedule_key orelse Key{};
    }
    
    // SetFeeExemptKeys sets the keys that will be exempt from paying fees
    pub fn setFeeExemptKeys(self: *TopicCreateTransaction, keys: []const Key) !*TopicCreateTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        self.fee_exempt_keys.clearRetainingCapacity();
        try errors.handleAppendSliceError(&self.fee_exempt_keys, keys);
        return self;
    }
    
    
    // AddFeeExemptKey adds a key that will be exempt from paying fees
    pub fn addFeeExemptKey(self: *TopicCreateTransaction, key: Key) !*TopicCreateTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        try errors.handleAppendError(&self.fee_exempt_keys, key);
        return self;
    }
    
    // ClearFeeExemptKeys removes all keys that will be exempt from paying fees
    pub fn clearFeeExemptKeys(self: *TopicCreateTransaction) HederaError!*TopicCreateTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        self.fee_exempt_keys.clearRetainingCapacity();
        return self;
    }
    
    // GetFeeExemptKeys returns the keys that will be exempt from paying fees
    pub fn getFeeExemptKeys(self: *TopicCreateTransaction) []const Key {
        return self.fee_exempt_keys.items;
    }
    
    // SetCustomFees sets the fixed fees to assess when a message is submitted to the new topic
    pub fn setCustomFees(self: *TopicCreateTransaction, fees: []*CustomFixedFee) !*TopicCreateTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        for (self.custom_fees.items) |fee| {
            self.allocator.destroy(fee);
        }
        self.custom_fees.clearRetainingCapacity();
        try errors.handleAppendSliceError(&self.custom_fees, fees);
        return self;
    }
    
    // AddCustomFee adds a fixed fee to assess when a message is submitted to the new topic
    pub fn addCustomFee(self: *TopicCreateTransaction, fee: *CustomFixedFee) !*TopicCreateTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        try errors.handleAppendError(&self.custom_fees, fee);
        return self;
    }
    
    // ClearCustomFees removes all custom fees to assess when a message is submitted to the new topic
    pub fn clearCustomFees(self: *TopicCreateTransaction) HederaError!*TopicCreateTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        for (self.custom_fees.items) |fee| {
            self.allocator.destroy(fee);
        }
        self.custom_fees.clearRetainingCapacity();
        return self;
    }
    
    // GetCustomFees returns the fixed fees to assess when a message is submitted to the new topic
    pub fn getCustomFees(self: *TopicCreateTransaction) []*CustomFixedFee {
        return self.custom_fees.items;
    }
    
    // SetTopicMemo sets a short publicly visible memo about the topic
    pub fn setTopicMemo(self: *TopicCreateTransaction, memo: []const u8) !*TopicCreateTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        self.memo = memo;
        return self;
    }
    
    // GetTopicMemo returns the memo for this topic
    pub fn getTopicMemo(self: *TopicCreateTransaction) []const u8 {
        return self.memo;
    }
    
    // SetAutoRenewPeriod sets the initial lifetime of the topic
    pub fn setAutoRenewPeriod(self: *TopicCreateTransaction, period: Duration) !*TopicCreateTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        self.auto_renew_period = period;
        return self;
    }
    
    // GetAutoRenewPeriod returns the auto renew period for this topic
    pub fn getAutoRenewPeriod(self: *TopicCreateTransaction) Duration {
        return self.auto_renew_period;
    }
    
    // SetAutoRenewAccountID sets an optional account to be used at the topic's expirationTime
    pub fn setAutoRenewAccountId(self: *TopicCreateTransaction, auto_renew_account_id: AccountId) !*TopicCreateTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        self.auto_renew_account_id = auto_renew_account_id;
        return self;
    }
    
    // GetAutoRenewAccountID returns the auto renew account ID for this topic
    pub fn getAutoRenewAccountID(self: *TopicCreateTransaction) AccountId {
        return self.auto_renew_account_id orelse AccountId{};
    }
    
    pub fn execute(self: *TopicCreateTransaction, client: *Client) !TransactionResponse {
        return try self.base.execute(client);
    }
    
    // Freeze prepares the transaction for execution
    pub fn freeze(self: *TopicCreateTransaction) !*TopicCreateTransaction {
        return try self.freezeWith(null);
    }
    
    pub fn freezeWith(self: *TopicCreateTransaction, client: ?*Client) !*TopicCreateTransaction {
        _ = try self.base.freezeWith(client);
        return self;
    }
    
    // Sign signs the transaction
    pub fn sign(self: *TopicCreateTransaction, private_key: anytype) !*TopicCreateTransaction {
        try self.base.sign(private_key);
        return self;
    }
    
    // SignWith signs the transaction with a specific key
    pub fn signWith(self: *TopicCreateTransaction, public_key: anytype, private_key: anytype) *TopicCreateTransaction {
        self.base.signWith(public_key, private_key);
        return self;
    }
    
    // SetMaxTransactionFee sets the maximum transaction fee
    pub fn setMaxTransactionFee(self: *TopicCreateTransaction, fee: Hbar) !*TopicCreateTransaction {
        _ = self.base.setMaxTransactionFee(fee);
        return self;
    }
    
    // GetMaxTransactionFee returns the maximum transaction fee
    pub fn getMaxTransactionFee(self: *TopicCreateTransaction) ?Hbar {
        return self.base.getMaxTransactionFee();
    }
    
    // SetTransactionMemo sets the transaction memo
    pub fn setTransactionMemo(self: *TopicCreateTransaction, memo: []const u8) !*TopicCreateTransaction {
        _ = self.base.setTransactionMemo(memo) catch {};
        return self;
    }
    
    // GetTransactionMemo returns the transaction memo
    pub fn getTransactionMemo(self: *TopicCreateTransaction) []const u8 {
        return self.base.getTransactionMemo();
    }
    
    // SetNodeAccountIDs sets the node account IDs for this transaction
    pub fn setNodeAccountIDs(self: *TopicCreateTransaction, node_account_ids: []const AccountId) !*TopicCreateTransaction {
        _ = self.base.setNodeAccountIDs(node_account_ids);
        return self;
    }
    
    // GetNodeAccountIDs returns the node account IDs for this transaction
    pub fn getNodeAccountIDs(self: *TopicCreateTransaction) []const AccountId {
        return self.base.getNodeAccountIDs();
    }
};


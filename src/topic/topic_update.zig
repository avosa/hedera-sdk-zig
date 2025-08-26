const std = @import("std");
const errors = @import("../core/errors.zig");
const HederaError = errors.HederaError;const TopicId = @import("../core/id.zig").TopicId;
const AccountId = @import("../core/id.zig").AccountId;
const Key = @import("../crypto/key.zig").Key;
const Timestamp = @import("../core/timestamp.zig").Timestamp;
const Duration = @import("../core/duration.zig").Duration;
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const Client = @import("../network/client.zig").Client;
const Hbar = @import("../core/hbar.zig").Hbar;
const CustomFixedFee = @import("topic_create.zig").CustomFixedFee;

// TopicUpdateTransaction updates the properties of a consensus topic
pub const TopicUpdateTransaction = struct {
    allocator: std.mem.Allocator,
    transaction: Transaction,
    topic_id: ?TopicId,
    admin_key: ?Key,
    submit_key: ?Key,
    fee_schedule_key: ?Key,
    fee_exempt_keys: std.ArrayList(Key),
    custom_fees: std.ArrayList(*CustomFixedFee),
    memo: ?[]const u8,
    auto_renew_period: ?Duration,
    auto_renew_account_id: ?AccountId,
    expiration_time: ?Timestamp,
    clear_submit_key: bool,
    
    pub fn init(allocator: std.mem.Allocator) !*TopicUpdateTransaction {
        var self = try allocator.create(TopicUpdateTransaction);
        self.* = TopicUpdateTransaction{
            .allocator = allocator,
            .transaction = Transaction.init(allocator),
            .topic_id = null,
            .admin_key = null,
            .submit_key = null,
            .fee_schedule_key = null,
            .fee_exempt_keys = std.ArrayList(Key).init(allocator),
            .custom_fees = std.ArrayList(*CustomFixedFee).init(allocator),
            .memo = null,
            .auto_renew_period = null,
            .auto_renew_account_id = null,
            .expiration_time = null,
            .clear_submit_key = false,
        };
        
        // Set default auto renew period
        _ = self.setAutoRenewPeriod(Duration{ .seconds = 7776000, .nanos = 0 }) catch return error.InvalidParameter; // 90 days
        
        return self;
    }
    
    pub fn deinit(self: *TopicUpdateTransaction) void {
        self.fee_exempt_keys.deinit();
        for (self.custom_fees.items) |fee| {
            self.allocator.destroy(fee);
        }
        self.custom_fees.deinit();
        self.transaction.deinit();
        self.allocator.destroy(self);
    }
    
    // SetTopicID sets the topic to be updated
    pub fn setTopicId(self: *TopicUpdateTransaction, topic_id: TopicId) !*TopicUpdateTransaction {
        try errors.requireNotFrozen(self.transaction.frozen);
        self.topic_id = topic_id;
        return self;
    }
    
    // GetTopicID returns the topic to be updated
    pub fn getTopicId(self: *TopicUpdateTransaction) TopicId {
        return self.topic_id orelse TopicId{};
    }
    
    // SetAdminKey sets the key required to update/delete the topic
    pub fn setAdminKey(self: *TopicUpdateTransaction, public_key: Key) !*TopicUpdateTransaction {
        try errors.requireNotFrozen(self.transaction.frozen);
        self.admin_key = public_key;
        return self;
    }
    
    // GetAdminKey returns the key required to update/delete the topic
    pub fn getAdminKey(self: *TopicUpdateTransaction) !Key {
        return self.admin_key orelse error.AdminKeyNotSet;
    }
    
    // SetSubmitKey sets the key allowed to submit messages to the topic
    pub fn setSubmitKey(self: *TopicUpdateTransaction, public_key: Key) !*TopicUpdateTransaction {
        try errors.requireNotFrozen(self.transaction.frozen);
        self.submit_key = public_key;
        return self;
    }
    
    // GetSubmitKey returns the key allowed to submit messages to the topic
    pub fn getSubmitKey(self: *TopicUpdateTransaction) !Key {
        return self.submit_key orelse error.SubmitKeyNotSet;
    }
    
    // SetFeeScheduleKey sets the key which allows updates to the topic's fees
    pub fn setFeeScheduleKey(self: *TopicUpdateTransaction, public_key: Key) !*TopicUpdateTransaction {
        try errors.requireNotFrozen(self.transaction.frozen);
        self.fee_schedule_key = public_key;
        return self;
    }
    
    // GetFeeScheduleKey returns the key which allows updates to the topic's fees
    pub fn getFeeScheduleKey(self: *TopicUpdateTransaction) Key {
        return self.fee_schedule_key orelse Key{};
    }
    
    // SetFeeExemptKeys sets the keys that will be exempt from paying fees
    pub fn setFeeExemptKeys(self: *TopicUpdateTransaction, keys: []const Key) !*TopicUpdateTransaction {
        try errors.requireNotFrozen(self.transaction.frozen);
        self.fee_exempt_keys.clearRetainingCapacity();
        try errors.handleAppendSliceError(&self.fee_exempt_keys, keys);
        return self;
    }
    
    // AddFeeExemptKey adds a key that will be exempt from paying fees
    pub fn addFeeExemptKey(self: *TopicUpdateTransaction, key: Key) !*TopicUpdateTransaction {
        try errors.requireNotFrozen(self.transaction.frozen);
        try errors.handleAppendError(&self.fee_exempt_keys, key);
        return self;
    }
    
    // ClearFeeExemptKeys removes all keys that will be exempt from paying fees
    pub fn clearFeeExemptKeys(self: *TopicUpdateTransaction) HederaError!*TopicUpdateTransaction {
        try errors.requireNotFrozen(self.transaction.frozen);
        self.fee_exempt_keys.clearRetainingCapacity();
        return self;
    }
    
    // GetFeeExemptKeys returns the keys that will be exempt from paying fees
    pub fn getFeeExemptKeys(self: *TopicUpdateTransaction) []const Key {
        return self.fee_exempt_keys.items;
    }
    
    // SetCustomFees sets the fixed fees to assess when a message is submitted to the topic
    pub fn setCustomFees(self: *TopicUpdateTransaction, fees: []*CustomFixedFee) !*TopicUpdateTransaction {
        try errors.requireNotFrozen(self.transaction.frozen);
        for (self.custom_fees.items) |fee| {
            self.allocator.destroy(fee);
        }
        self.custom_fees.clearRetainingCapacity();
        try errors.handleAppendSliceError(&self.custom_fees, fees);
        return self;
    }
    
    // AddCustomFee adds a fixed fee to assess when a message is submitted to the topic
    pub fn addCustomFee(self: *TopicUpdateTransaction, fee: *CustomFixedFee) !*TopicUpdateTransaction {
        try errors.requireNotFrozen(self.transaction.frozen);
        try errors.handleAppendError(&self.custom_fees, fee);
        return self;
    }
    
    // ClearCustomFees removes all fixed fees to assess when a message is submitted to the topic
    pub fn clearCustomFees(self: *TopicUpdateTransaction) HederaError!*TopicUpdateTransaction {
        try errors.requireNotFrozen(self.transaction.frozen);
        for (self.custom_fees.items) |fee| {
            self.allocator.destroy(fee);
        }
        self.custom_fees.clearRetainingCapacity();
        return self;
    }
    
    // GetCustomFees returns the fixed fees to assess when a message is submitted to the topic
    pub fn getCustomFees(self: *TopicUpdateTransaction) []*CustomFixedFee {
        return self.custom_fees.items;
    }
    
    // SetTopicMemo sets a short publicly visible memo about the topic
    pub fn setTopicMemo(self: *TopicUpdateTransaction, memo: []const u8) !*TopicUpdateTransaction {
        try errors.requireNotFrozen(self.transaction.frozen);
        self.memo = memo;
        return self;
    }
    
    // GetTopicMemo returns the short publicly visible memo about the topic
    pub fn getTopicMemo(self: *TopicUpdateTransaction) []const u8 {
        return self.memo orelse "";
    }
    
    // SetExpirationTime sets the effective timestamp at which all transactions and queries will fail
    pub fn setExpirationTime(self: *TopicUpdateTransaction, expiration: Timestamp) !*TopicUpdateTransaction {
        try errors.requireNotFrozen(self.transaction.frozen);
        self.expiration_time = expiration;
        return self;
    }
    
    // GetExpirationTime returns the effective timestamp at which all transactions and queries will fail
    pub fn getExpirationTime(self: *TopicUpdateTransaction) Timestamp {
        return self.expiration_time orelse Timestamp{};
    }
    
    // SetAutoRenewPeriod sets the amount of time to extend the topic's lifetime automatically
    pub fn setAutoRenewPeriod(self: *TopicUpdateTransaction, period: Duration) !*TopicUpdateTransaction {
        try errors.requireNotFrozen(self.transaction.frozen);
        self.auto_renew_period = period;
        return self;
    }
    
    // GetAutoRenewPeriod returns the amount of time to extend the topic's lifetime automatically
    pub fn getAutoRenewPeriod(self: *TopicUpdateTransaction) Duration {
        return self.auto_renew_period orelse Duration{};
    }
    
    // SetAutoRenewAccountID sets the optional account to be used at the topic's expirationTime
    pub fn setAutoRenewAccountId(self: *TopicUpdateTransaction, auto_renew_account_id: AccountId) !*TopicUpdateTransaction {
        try errors.requireNotFrozen(self.transaction.frozen);
        self.auto_renew_account_id = auto_renew_account_id;
        return self;
    }
    
    // GetAutoRenewAccountID returns the optional account to be used at the topic's expirationTime
    pub fn getAutoRenewAccountID(self: *TopicUpdateTransaction) AccountId {
        return self.auto_renew_account_id orelse AccountId{};
    }
    
    // ClearTopicMemo explicitly clears any memo on the topic by sending an empty string as the memo
    pub fn clearTopicMemo(self: *TopicUpdateTransaction) HederaError!*TopicUpdateTransaction {
        return try self.setTopicMemo("");
    }
    
    // ClearAdminKey explicitly clears any admin key on the topic by sending an empty key list as the key
    pub fn clearAdminKey(self: *TopicUpdateTransaction) HederaError!*TopicUpdateTransaction {
        try errors.requireNotFrozen(self.transaction.frozen);
        self.admin_key = null;
        return self;
    }
    
    // ClearSubmitKey explicitly clears any submit key on the topic by sending an empty key list as the key
    pub fn clearSubmitKey(self: *TopicUpdateTransaction) HederaError!*TopicUpdateTransaction {
        try errors.requireNotFrozen(self.transaction.frozen);
        self.submit_key = null;
        self.clear_submit_key = true;
        return self;
    }
    
    // ClearAutoRenewAccountID explicitly clears any auto renew account ID on the topic
    pub fn clearAutoRenewAccountID(self: *TopicUpdateTransaction) HederaError!*TopicUpdateTransaction {
        try errors.requireNotFrozen(self.transaction.frozen);
        self.auto_renew_account_id = AccountId{};
        return self;
    }
    
    // Execute executes the transaction
    pub fn execute(self: *TopicUpdateTransaction, client: *Client) !TransactionResponse {
        if (self.topic_id == null) {
            return error.InvalidParameter;
        }
        return try self.transaction.execute(client);
    }
    
    // Freeze prepares the transaction for execution
    pub fn freeze(self: *TopicUpdateTransaction) !*TopicUpdateTransaction {
        return try self.freezeWith(null);
    }
    
    // FreezeWith prepares the transaction for execution with a client
    pub fn freezeWith(self: *TopicUpdateTransaction, client: ?*Client) !*TopicUpdateTransaction {
        _ = try self.transaction.freezeWith(client);
        return self;
    }
    
    // Sign signs the transaction
    pub fn sign(self: *TopicUpdateTransaction, private_key: anytype) !*TopicUpdateTransaction {
        _ = try self.transaction.sign(private_key);
        return self;
    }
    
    // SignWith signs the transaction with a specific key
    pub fn signWith(self: *TopicUpdateTransaction, public_key: anytype, private_key: anytype) *TopicUpdateTransaction {
        self.transaction.signWith(public_key, private_key);
        return self;
    }
    
    // SetMaxTransactionFee sets the maximum transaction fee
    pub fn setMaxTransactionFee(self: *TopicUpdateTransaction, fee: Hbar) !*TopicUpdateTransaction {
        _ = self.transaction.setMaxTransactionFee(fee);
        return self;
    }
    
    // GetMaxTransactionFee returns the maximum transaction fee
    pub fn getMaxTransactionFee(self: *TopicUpdateTransaction) ?Hbar {
        return self.transaction.getMaxTransactionFee();
    }
    
    // SetTransactionMemo sets the transaction memo
    pub fn setTransactionMemo(self: *TopicUpdateTransaction, memo: []const u8) !*TopicUpdateTransaction {
        _ = self.transaction.setTransactionMemo(memo);
        return self;
    }
    
    // GetTransactionMemo returns the transaction memo
    pub fn getTransactionMemo(self: *TopicUpdateTransaction) []const u8 {
        return self.transaction.getTransactionMemo();
    }
    
    // SetNodeAccountIDs sets the node account IDs for this transaction
    pub fn setNodeAccountIDs(self: *TopicUpdateTransaction, node_account_ids: []const AccountId) !*TopicUpdateTransaction {
        _ = self.transaction.setNodeAccountIDs(node_account_ids);
        return self;
    }
    
    // GetNodeAccountIDs returns the node account IDs for this transaction
    pub fn getNodeAccountIDs(self: *TopicUpdateTransaction) []const AccountId {
        return self.transaction.getNodeAccountIDs();
    }
};

// NewTopicUpdateTransaction creates a TopicUpdateTransaction

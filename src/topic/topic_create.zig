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
    allocator: std.mem.Allocator,
    transaction: Transaction,
    admin_key: ?Key,
    submit_key: ?Key,
    fee_schedule_key: ?Key,
    fee_exempt_keys: std.ArrayList(Key),
    custom_fees: std.ArrayList(*CustomFixedFee),
    memo: []const u8,
    auto_renew_period: Duration,
    auto_renew_account_id: ?AccountId,
    
    pub fn init(allocator: std.mem.Allocator) !*TopicCreateTransaction {
        var self = try allocator.create(TopicCreateTransaction);
        self.* = TopicCreateTransaction{
            .allocator = allocator,
            .transaction = Transaction.init(allocator),
            .admin_key = null,
            .submit_key = null,
            .fee_schedule_key = null,
            .fee_exempt_keys = std.ArrayList(Key).init(allocator),
            .custom_fees = std.ArrayList(*CustomFixedFee).init(allocator),
            .memo = "",
            .auto_renew_period = Duration{ .seconds = 7890000, .nanos = 0 },
            .auto_renew_account_id = null,
        };
        
        // Set default auto renew period and max transaction fee
        _ = self.setAutoRenewPeriod(Duration{ .seconds = 7890000, .nanos = 0 }) catch {};
        _ = self.transaction.setMaxTransactionFee(Hbar.fromTinybars(2500000000) catch unreachable) catch {}; // 25 Hbar
        
        return self;
    }
    
    pub fn deinit(self: *TopicCreateTransaction) void {
        self.fee_exempt_keys.deinit();
        for (self.custom_fees.items) |fee| {
            self.allocator.destroy(fee);
        }
        self.custom_fees.deinit();
        self.transaction.deinit();
    }
    
    // setAdminKey sets the key required to update or delete the topic
    pub fn setAdminKey(self: *TopicCreateTransaction, public_key: Key) !*TopicCreateTransaction {
        try errors.requireNotFrozen(self.transaction.frozen);
        self.admin_key = public_key;
        return self;
    }
    
    // getAdminKey returns the key required to update or delete the topic
    pub fn getAdminKey(self: *TopicCreateTransaction) !Key {
        return self.admin_key orelse error.AdminKeyNotSet;
    }
    
    // setSubmitKey sets the key required for submitting messages to the topic
    pub fn setSubmitKey(self: *TopicCreateTransaction, public_key: Key) !*TopicCreateTransaction {
        try errors.requireNotFrozen(self.transaction.frozen);
        self.submit_key = public_key;
        return self;
    }
    
    // getSubmitKey returns the key required for submitting messages to the topic
    pub fn getSubmitKey(self: *TopicCreateTransaction) !Key {
        return self.submit_key orelse error.SubmitKeyNotSet;
    }
    
    // setFeeScheduleKey sets the key which allows updates to the new topic's fees
    pub fn setFeeScheduleKey(self: *TopicCreateTransaction, public_key: Key) !*TopicCreateTransaction {
        try errors.requireNotFrozen(self.transaction.frozen);
        self.fee_schedule_key = public_key;
        return self;
    }
    
    // GetFeeScheduleKey returns the key which allows updates to the new topic's fees
    pub fn getFeeScheduleKey(self: *TopicCreateTransaction) Key {
        return self.fee_schedule_key orelse Key{};
    }
    
    // SetFeeExemptKeys sets the keys that will be exempt from paying fees
    pub fn setFeeExemptKeys(self: *TopicCreateTransaction, keys: []const Key) !*TopicCreateTransaction {
        try errors.requireNotFrozen(self.transaction.frozen);
        self.fee_exempt_keys.clearRetainingCapacity();
        try errors.handleAppendSliceError(&self.fee_exempt_keys, keys);
        return self;
    }
    
    
    // AddFeeExemptKey adds a key that will be exempt from paying fees
    pub fn addFeeExemptKey(self: *TopicCreateTransaction, key: Key) !*TopicCreateTransaction {
        try errors.requireNotFrozen(self.transaction.frozen);
        try errors.handleAppendError(&self.fee_exempt_keys, key);
        return self;
    }
    
    // ClearFeeExemptKeys removes all keys that will be exempt from paying fees
    pub fn clearFeeExemptKeys(self: *TopicCreateTransaction) HederaError!*TopicCreateTransaction {
        try errors.requireNotFrozen(self.transaction.frozen);
        self.fee_exempt_keys.clearRetainingCapacity();
        return self;
    }
    
    // GetFeeExemptKeys returns the keys that will be exempt from paying fees
    pub fn getFeeExemptKeys(self: *TopicCreateTransaction) []const Key {
        return self.fee_exempt_keys.items;
    }
    
    // SetCustomFees sets the fixed fees to assess when a message is submitted to the new topic
    pub fn setCustomFees(self: *TopicCreateTransaction, fees: []*CustomFixedFee) !*TopicCreateTransaction {
        try errors.requireNotFrozen(self.transaction.frozen);
        for (self.custom_fees.items) |fee| {
            self.allocator.destroy(fee);
        }
        self.custom_fees.clearRetainingCapacity();
        try errors.handleAppendSliceError(&self.custom_fees, fees);
        return self;
    }
    
    // AddCustomFee adds a fixed fee to assess when a message is submitted to the new topic
    pub fn addCustomFee(self: *TopicCreateTransaction, fee: *CustomFixedFee) !*TopicCreateTransaction {
        try errors.requireNotFrozen(self.transaction.frozen);
        try errors.handleAppendError(&self.custom_fees, fee);
        return self;
    }
    
    // ClearCustomFees removes all custom fees to assess when a message is submitted to the new topic
    pub fn clearCustomFees(self: *TopicCreateTransaction) HederaError!*TopicCreateTransaction {
        try errors.requireNotFrozen(self.transaction.frozen);
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
        try errors.requireNotFrozen(self.transaction.frozen);
        self.memo = memo;
        return self;
    }
    
    // GetTopicMemo returns the memo for this topic
    pub fn getTopicMemo(self: *TopicCreateTransaction) []const u8 {
        return self.memo;
    }
    
    // SetAutoRenewPeriod sets the initial lifetime of the topic
    pub fn setAutoRenewPeriod(self: *TopicCreateTransaction, period: Duration) !*TopicCreateTransaction {
        try errors.requireNotFrozen(self.transaction.frozen);
        self.auto_renew_period = period;
        return self;
    }
    
    // GetAutoRenewPeriod returns the auto renew period for this topic
    pub fn getAutoRenewPeriod(self: *TopicCreateTransaction) Duration {
        return self.auto_renew_period;
    }
    
    // SetAutoRenewAccountID sets an optional account to be used at the topic's expirationTime
    pub fn setAutoRenewAccountId(self: *TopicCreateTransaction, auto_renew_account_id: AccountId) !*TopicCreateTransaction {
        try errors.requireNotFrozen(self.transaction.frozen);
        self.auto_renew_account_id = auto_renew_account_id;
        return self;
    }
    
    // GetAutoRenewAccountID returns the auto renew account ID for this topic
    pub fn getAutoRenewAccountID(self: *TopicCreateTransaction) AccountId {
        return self.auto_renew_account_id orelse AccountId{};
    }
    
    // Execute executes the transaction
    pub fn execute(self: *TopicCreateTransaction, client: *Client) !TransactionResponse {
        return try self.transaction.execute(client);
    }
    
    // Freeze prepares the transaction for execution
    pub fn freeze(self: *TopicCreateTransaction) !*TopicCreateTransaction {
        return try self.freezeWith(null);
    }
    
    // FreezeWith prepares the transaction for execution with a client
    pub fn freezeWith(self: *TopicCreateTransaction, client: ?*Client) !*TopicCreateTransaction {
        try self.transaction.freezeWith(client);
        return self;
    }
    
    // Sign signs the transaction
    pub fn sign(self: *TopicCreateTransaction, private_key: anytype) !*TopicCreateTransaction {
        try self.transaction.sign(private_key);
        return self;
    }
    
    // SignWith signs the transaction with a specific key
    pub fn signWith(self: *TopicCreateTransaction, public_key: anytype, private_key: anytype) *TopicCreateTransaction {
        self.transaction.signWith(public_key, private_key);
        return self;
    }
    
    // SetMaxTransactionFee sets the maximum transaction fee
    pub fn setMaxTransactionFee(self: *TopicCreateTransaction, fee: Hbar) !*TopicCreateTransaction {
        _ = self.transaction.setMaxTransactionFee(fee);
        return self;
    }
    
    // GetMaxTransactionFee returns the maximum transaction fee
    pub fn getMaxTransactionFee(self: *TopicCreateTransaction) ?Hbar {
        return self.transaction.getMaxTransactionFee();
    }
    
    // SetTransactionMemo sets the transaction memo
    pub fn setTransactionMemo(self: *TopicCreateTransaction, memo: []const u8) !*TopicCreateTransaction {
        _ = self.transaction.setTransactionMemo(memo) catch {};
        return self;
    }
    
    // GetTransactionMemo returns the transaction memo
    pub fn getTransactionMemo(self: *TopicCreateTransaction) []const u8 {
        return self.transaction.getTransactionMemo();
    }
    
    // SetNodeAccountIDs sets the node account IDs for this transaction
    pub fn setNodeAccountIDs(self: *TopicCreateTransaction, node_account_ids: []const AccountId) !*TopicCreateTransaction {
        _ = self.transaction.setNodeAccountIDs(node_account_ids);
        return self;
    }
    
    // GetNodeAccountIDs returns the node account IDs for this transaction
    pub fn getNodeAccountIDs(self: *TopicCreateTransaction) []const AccountId {
        return self.transaction.getNodeAccountIDs();
    }
};

// NewTopicCreateTransaction creates a TopicCreateTransaction

// JavaScript naming convention (no "new" prefix)

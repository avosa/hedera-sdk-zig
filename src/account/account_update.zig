const std = @import("std");
const AccountId = @import("../core/id.zig").AccountId;
const Key = @import("../crypto/key.zig").Key;
const PublicKey = @import("../crypto/key.zig").PublicKey;
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const Duration = @import("../core/duration.zig").Duration;
const Timestamp = @import("../core/timestamp.zig").Timestamp;

// AccountUpdateTransaction updates an existing account
pub const AccountUpdateTransaction = struct {
    base: Transaction,
    account_id: ?AccountId,
    key: ?Key,
    alias_key: ?PublicKey,
    receiver_sig_required: ?bool,
    auto_renew_period: ?Duration,
    expiration_time: ?Timestamp,
    memo: ?[]const u8,
    max_automatic_token_associations: ?i32,
    decline_staking_reward: ?bool,
    staked_account_id: ?AccountId,
    staked_node_id: ?i64,
    proxy_account_id: ?AccountId,
    
    pub fn init(allocator: std.mem.Allocator) AccountUpdateTransaction {
        var tx = AccountUpdateTransaction{
            .base = Transaction.init(allocator),
            .account_id = null,
            .key = null,
            .alias_key = null,
            .receiver_sig_required = null,
            .auto_renew_period = null,
            .expiration_time = null,
            .memo = null,
            .max_automatic_token_associations = null,
            .decline_staking_reward = null,
            .staked_account_id = null,
            .staked_node_id = null,
            .proxy_account_id = null,
        };
        // Set default auto renew period to 7890000 seconds (like Go SDK)
        tx.auto_renew_period = Duration{ .seconds = 7890000, .nanos = 0 };
        return tx;
    }
    
    pub fn deinit(self: *AccountUpdateTransaction) void {
        self.base.deinit();
    }
    
    // Set the account ID to update
    pub fn setAccountId(self: *AccountUpdateTransaction, account_id: AccountId) *AccountUpdateTransaction {
        if (self.base.frozen) {
            @panic("Transaction is frozen");
        }
        self.account_id = account_id;
        return self;
    }
    
    pub fn getAccountId(self: *const AccountUpdateTransaction) AccountId {
        return self.account_id orelse AccountId{};
    }
    
    // Set the new key for the account
    pub fn setKey(self: *AccountUpdateTransaction, key: Key) *AccountUpdateTransaction {
        if (self.base.frozen) {
            @panic("Transaction is frozen");
        }
        self.key = key;
        return self;
    }
    
    pub fn getKey(self: *const AccountUpdateTransaction) ?Key {
        return self.key;
    }
    
    // Set alias key (deprecated but maintained for uniformity)
    pub fn setAliasKey(self: *AccountUpdateTransaction, alias: PublicKey) *AccountUpdateTransaction {
        if (self.base.frozen) {
            @panic("Transaction is frozen");
        }
        self.alias_key = alias;
        return self;
    }
    
    pub fn getAliasKey(self: *const AccountUpdateTransaction) PublicKey {
        return self.alias_key orelse PublicKey{};
    }
    
    // Set whether receiver signature is required
    pub fn setReceiverSignatureRequired(self: *AccountUpdateTransaction, required: bool) *AccountUpdateTransaction {
        if (self.base.frozen) {
            @panic("Transaction is frozen");
        }
        self.receiver_sig_required = required;
        return self;
    }
    
    pub fn getReceiverSignatureRequired(self: *const AccountUpdateTransaction) bool {
        return self.receiver_sig_required orelse false;
    }
    
    // Set the auto renew period
    pub fn setAutoRenewPeriod(self: *AccountUpdateTransaction, period: Duration) *AccountUpdateTransaction {
        if (self.base.frozen) {
            @panic("Transaction is frozen");
        }
        self.auto_renew_period = period;
        return self;
    }
    
    pub fn getAutoRenewPeriod(self: *const AccountUpdateTransaction) Duration {
        return self.auto_renew_period orelse Duration{ .seconds = 0 };
    }
    
    // Set the expiration time
    pub fn setExpirationTime(self: *AccountUpdateTransaction, time: Timestamp) *AccountUpdateTransaction {
        if (self.base.frozen) {
            @panic("Transaction is frozen");
        }
        self.expiration_time = time;
        return self;
    }
    
    pub fn getExpirationTime(self: *const AccountUpdateTransaction) Timestamp {
        return self.expiration_time orelse Timestamp{ .seconds = 0, .nanos = 0 };
    }
    
    // Set the account memo
    pub fn setAccountMemo(self: *AccountUpdateTransaction, memo: []const u8) *AccountUpdateTransaction {
        if (self.base.frozen) {
            @panic("Transaction is frozen");
        }
        if (memo.len > 100) {
            @panic("Memo too long");
        }
        self.memo = memo;
        return self;
    }
    
    pub fn getAccountMemo(self: *const AccountUpdateTransaction) []const u8 {
        return self.memo orelse "";
    }
    
    // Alias for setAccountMemo for uniformity
    pub fn setMemo(self: *AccountUpdateTransaction, memo: []const u8) *AccountUpdateTransaction {
        return self.setAccountMemo(memo);
    }
    
    // Set max automatic token associations
    pub fn setMaxAutomaticTokenAssociations(self: *AccountUpdateTransaction, max: i32) *AccountUpdateTransaction {
        if (self.base.frozen) {
            @panic("Transaction is frozen");
        }
        if (max < 0 or max > 1000) {
            @panic("Invalid max token associations");
        }
        self.max_automatic_token_associations = max;
        return self;
    }
    
    pub fn getMaxAutomaticTokenAssociations(self: *const AccountUpdateTransaction) i32 {
        return self.max_automatic_token_associations orelse 0;
    }
    
    // Set decline staking reward
    pub fn setDeclineStakingReward(self: *AccountUpdateTransaction, decline: bool) *AccountUpdateTransaction {
        if (self.base.frozen) {
            @panic("Transaction is frozen");
        }
        self.decline_staking_reward = decline;
        return self;
    }
    
    pub fn getDeclineStakingReward(self: *const AccountUpdateTransaction) bool {
        return self.decline_staking_reward orelse false;
    }
    
    // Set staked account ID
    pub fn setStakedAccountId(self: *AccountUpdateTransaction, account_id: AccountId) *AccountUpdateTransaction {
        if (self.base.frozen) {
            @panic("Transaction is frozen");
        }
        if (self.staked_node_id != null) {
            @panic("Cannot set both staked account and node");
        }
        self.staked_account_id = account_id;
        return self;
    }
    
    pub fn getStakedAccountID(self: *const AccountUpdateTransaction) AccountId {
        return self.staked_account_id orelse AccountId{};
    }
    
    // Set staked node ID
    pub fn setStakedNodeId(self: *AccountUpdateTransaction, node_id: i64) *AccountUpdateTransaction {
        if (self.base.frozen) {
            @panic("Transaction is frozen");
        }
        if (self.staked_account_id != null) {
            @panic("Cannot set both staked account and node");
        }
        self.staked_node_id = node_id;
        return self;
    }
    
    pub fn getStakedNodeID(self: *const AccountUpdateTransaction) i64 {
        return self.staked_node_id orelse 0;
    }
    
    // Clear staked account ID
    pub fn clearStakedAccountID(self: *AccountUpdateTransaction) *AccountUpdateTransaction {
        if (self.base.frozen) {
            @panic("Transaction is frozen");
        }
        self.staked_account_id = AccountId{ .shard = 0, .realm = 0, .account = 0 };
        return self;
    }
    
    // Clear staked node ID
    pub fn clearStakedNodeID(self: *AccountUpdateTransaction) *AccountUpdateTransaction {
        if (self.base.frozen) {
            @panic("Transaction is frozen");
        }
        self.staked_node_id = -1;
        return self;
    }
    
    // Set proxy account ID (deprecated but still supported)
    pub fn setProxyAccountId(self: *AccountUpdateTransaction, proxy_id: AccountId) *AccountUpdateTransaction {
        if (self.base.frozen) {
            @panic("Transaction is frozen");
        }
        self.proxy_account_id = proxy_id;
        return self;
    }
    
    pub fn getProxyAccountID(self: *const AccountUpdateTransaction) AccountId {
        return self.proxy_account_id orelse AccountId{};
    }
    
    // Execute the transaction
    pub fn execute(self: *AccountUpdateTransaction, client: *Client) !TransactionResponse {
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *AccountUpdateTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Common transaction fields
        try self.writeCommonFields(&writer);
        
        // cryptoUpdateAccount = 15 (oneof data)
        var update_writer = ProtoWriter.init(self.base.allocator);
        defer update_writer.deinit();
        
        // accountIDToUpdate = 2
        if (self.account_id) |account| {
            var account_writer = ProtoWriter.init(self.base.allocator);
            defer account_writer.deinit();
            try account_writer.writeInt64(1, @intCast(account.shard));
            try account_writer.writeInt64(2, @intCast(account.realm));
            try account_writer.writeInt64(3, @intCast(account.account));
            const account_bytes = try account_writer.toOwnedSlice();
            defer self.base.allocator.free(account_bytes);
            try update_writer.writeMessage(2, account_bytes);
        }
        
        // key = 3
        if (self.key) |key| {
            const key_bytes = try key.toProtobuf(self.base.allocator);
            defer self.base.allocator.free(key_bytes);
            try update_writer.writeMessage(3, key_bytes);
        }
        
        // proxyAccountID = 4 (deprecated)
        if (self.proxy_account_id) |proxy| {
            var proxy_writer = ProtoWriter.init(self.base.allocator);
            defer proxy_writer.deinit();
            try proxy_writer.writeInt64(1, @intCast(proxy.shard));
            try proxy_writer.writeInt64(2, @intCast(proxy.realm));
            try proxy_writer.writeInt64(3, @intCast(proxy.account));
            const proxy_bytes = try proxy_writer.toOwnedSlice();
            defer self.base.allocator.free(proxy_bytes);
            try update_writer.writeMessage(4, proxy_bytes);
        }
        
        // autoRenewPeriod = 6
        if (self.auto_renew_period) |period| {
            var duration_writer = ProtoWriter.init(self.base.allocator);
            defer duration_writer.deinit();
            try duration_writer.writeInt64(1, period.seconds);
            const duration_bytes = try duration_writer.toOwnedSlice();
            defer self.base.allocator.free(duration_bytes);
            try update_writer.writeMessage(6, duration_bytes);
        }
        
        // expirationTime = 8
        if (self.expiration_time) |time| {
            var timestamp_writer = ProtoWriter.init(self.base.allocator);
            defer timestamp_writer.deinit();
            try timestamp_writer.writeInt64(1, time.seconds);
            try timestamp_writer.writeInt32(2, time.nanos);
            const timestamp_bytes = try timestamp_writer.toOwnedSlice();
            defer self.base.allocator.free(timestamp_bytes);
            try update_writer.writeMessage(8, timestamp_bytes);
        }
        
        // receiverSigRequiredWrapper = 10
        if (self.receiver_sig_required) |required| {
            var bool_writer = ProtoWriter.init(self.base.allocator);
            defer bool_writer.deinit();
            try bool_writer.writeBool(1, required);
            const bool_bytes = try bool_writer.toOwnedSlice();
            defer self.base.allocator.free(bool_bytes);
            try update_writer.writeMessage(10, bool_bytes);
        }
        
        // memo = 11
        if (self.memo) |memo| {
            var memo_writer = ProtoWriter.init(self.base.allocator);
            defer memo_writer.deinit();
            try memo_writer.writeString(1, memo);
            const memo_bytes = try memo_writer.toOwnedSlice();
            defer self.base.allocator.free(memo_bytes);
            try update_writer.writeMessage(11, memo_bytes);
        }
        
        // max_automatic_token_associations = 12
        if (self.max_automatic_token_associations) |max| {
            var int_writer = ProtoWriter.init(self.base.allocator);
            defer int_writer.deinit();
            try int_writer.writeInt32(1, max);
            const int_bytes = try int_writer.toOwnedSlice();
            defer self.base.allocator.free(int_bytes);
            try update_writer.writeMessage(12, int_bytes);
        }
        
        // staked_account_id = 13 or staked_node_id = 14
        if (self.staked_account_id) |staked| {
            var staked_writer = ProtoWriter.init(self.base.allocator);
            defer staked_writer.deinit();
            try staked_writer.writeInt64(1, @intCast(staked.shard));
            try staked_writer.writeInt64(2, @intCast(staked.realm));
            try staked_writer.writeInt64(3, @intCast(staked.account));
            const staked_bytes = try staked_writer.toOwnedSlice();
            defer self.base.allocator.free(staked_bytes);
            try update_writer.writeMessage(13, staked_bytes);
        } else if (self.staked_node_id) |node| {
            try update_writer.writeInt64(14, node);
        }
        
        // decline_reward = 15
        if (self.decline_staking_reward) |decline| {
            var bool_writer = ProtoWriter.init(self.base.allocator);
            defer bool_writer.deinit();
            try bool_writer.writeBool(1, decline);
            const bool_bytes = try bool_writer.toOwnedSlice();
            defer self.base.allocator.free(bool_bytes);
            try update_writer.writeMessage(15, bool_bytes);
        }
        
        const update_bytes = try update_writer.toOwnedSlice();
        defer self.base.allocator.free(update_bytes);
        try writer.writeMessage(15, update_bytes);
        
        return writer.toOwnedSlice();
    }
    
    fn writeCommonFields(self: *AccountUpdateTransaction, writer: *ProtoWriter) !void {
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

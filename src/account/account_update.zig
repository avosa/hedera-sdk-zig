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
    receiver_sig_required: ?bool,
    receiver_signature_required: ?bool, // Alias for Go SDK compatibility
    auto_renew_period: ?Duration,
    expiration_time: ?Timestamp,
    memo: ?[]const u8,
    max_automatic_token_associations: ?i32,
    decline_staking_reward: ?bool,
    staked_account_id: ?AccountId,
    staked_node_id: ?i64,
    proxy_account_id: ?AccountId,
    
    pub fn init(allocator: std.mem.Allocator) AccountUpdateTransaction {
        return AccountUpdateTransaction{
            .base = Transaction.init(allocator),
            .account_id = null,
            .key = null,
            .receiver_sig_required = null,
            .receiver_signature_required = null,
            .auto_renew_period = null,
            .expiration_time = null,
            .memo = null,
            .max_automatic_token_associations = null,
            .decline_staking_reward = null,
            .staked_account_id = null,
            .staked_node_id = null,
            .proxy_account_id = null,
        };
    }
    
    pub fn deinit(self: *AccountUpdateTransaction) void {
        self.base.deinit();
    }
    
    // Set the account ID to update
    pub fn setAccountId(self: *AccountUpdateTransaction, account_id: AccountId) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.account_id = account_id;
    }
    
    // Set the new key for the account
    pub fn setKey(self: *AccountUpdateTransaction, key: Key) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.key = key;
    }
    
    // Set whether receiver signature is required
    pub fn setReceiverSignatureRequired(self: *AccountUpdateTransaction, required: bool) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.receiver_sig_required = required;
        self.receiver_signature_required = required; // Keep alias in sync
    }
    
    // Set the auto renew period
    pub fn setAutoRenewPeriod(self: *AccountUpdateTransaction, period: Duration) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.auto_renew_period = period;
    }
    
    // Set the expiration time
    pub fn setExpirationTime(self: *AccountUpdateTransaction, time: Timestamp) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.expiration_time = time;
    }
    
    // Set the memo
    pub fn setMemo(self: *AccountUpdateTransaction, memo: []const u8) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        if (memo.len > 100) return error.MemoTooLong;
        self.memo = memo;
    }
    
    // Set max automatic token associations
    pub fn setMaxAutomaticTokenAssociations(self: *AccountUpdateTransaction, max: i32) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        if (max < 0 or max > 1000) return error.InvalidMaxTokenAssociations;
        self.max_automatic_token_associations = max;
    }
    
    // Set decline staking reward
    pub fn setDeclineStakingReward(self: *AccountUpdateTransaction, decline: bool) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.decline_staking_reward = decline;
    }
    
    // Set staked account ID
    pub fn setStakedAccountId(self: *AccountUpdateTransaction, account_id: AccountId) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        if (self.staked_node_id != null) return error.CannotSetBothStakedAccountAndNode;
        self.staked_account_id = account_id;
    }
    
    // Set staked node ID
    pub fn setStakedNodeId(self: *AccountUpdateTransaction, node_id: i64) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        if (self.staked_account_id != null) return error.CannotSetBothStakedAccountAndNode;
        self.staked_node_id = node_id;
    }
    
    // Clear staking
    pub fn clearStaking(self: *AccountUpdateTransaction) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.staked_account_id = null;
        self.staked_node_id = null;
    }
    
    // Set proxy account ID (deprecated but still supported)
    pub fn setProxyAccountId(self: *AccountUpdateTransaction, proxy_id: AccountId) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.proxy_account_id = proxy_id;
    }
    
    // Execute the transaction
    pub fn execute(self: *AccountUpdateTransaction, client: *Client) !TransactionResponse {
        if (self.account_id == null) {
            return error.AccountIdRequired;
        }
        
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
            try account_writer.writeInt64(1, @intCast(account.entity.shard));
            try account_writer.writeInt64(2, @intCast(account.entity.realm));
            try account_writer.writeInt64(3, @intCast(account.entity.num));
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
            try proxy_writer.writeInt64(1, @intCast(proxy.entity.shard));
            try proxy_writer.writeInt64(2, @intCast(proxy.entity.realm));
            try proxy_writer.writeInt64(3, @intCast(proxy.entity.num));
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
            try staked_writer.writeInt64(1, @intCast(staked.entity.shard));
            try staked_writer.writeInt64(2, @intCast(staked.entity.realm));
            try staked_writer.writeInt64(3, @intCast(staked.entity.num));
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
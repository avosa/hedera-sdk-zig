const std = @import("std");
const AccountId = @import("../core/id.zig").AccountId;
const Hbar = @import("../core/hbar.zig").Hbar;
const Key = @import("../crypto/key.zig").Key;
const Duration = @import("../core/duration.zig").Duration;
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const TransactionReceipt = @import("../transaction/transaction.zig").TransactionReceipt;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;

// Match Go SDK's NewAccountCreateTransaction factory function
pub fn new_account_create_transaction(allocator: std.mem.Allocator) AccountCreateTransaction {
    return AccountCreateTransaction.init(allocator);
}

// AccountCreateTransaction creates a new account on Hedera
pub const AccountCreateTransaction = struct {
    base: Transaction,
    key: ?Key,
    initial_balance: Hbar,
    receiver_signature_required: bool,
    auto_renew_period: Duration,
    send_record_threshold: Hbar,
    receive_record_threshold: Hbar,
    proxy_account_id: ?AccountId,
    memo: []const u8,
    max_automatic_token_associations: i32,
    staked_account_id: ?AccountId,
    staked_node_id: ?i64,
    decline_staking_reward: bool,
    alias_key: ?Key,
    alias_evm_address: ?[]const u8,
    alias: ?[]const u8,
    
    pub fn init(allocator: std.mem.Allocator) AccountCreateTransaction {
        return AccountCreateTransaction{
            .base = Transaction.init(allocator),
            .key = null,
            .initial_balance = Hbar.zero(),
            .receiver_signature_required = false,
            .auto_renew_period = Duration.fromDays(90),
            .send_record_threshold = Hbar.max(),
            .receive_record_threshold = Hbar.max(),
            .proxy_account_id = null,
            .memo = "",
            .max_automatic_token_associations = 0,
            .staked_account_id = null,
            .staked_node_id = null,
            .decline_staking_reward = false,
            .alias_key = null,
            .alias_evm_address = null,
            .alias = null,
        };
    }
    
    pub fn deinit(self: *AccountCreateTransaction) void {
        self.base.deinit();
    }
    
    // Set the key for the new account
    pub fn setKey(self: *AccountCreateTransaction, key: Key) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.key = key;
    }
    
    // Match Go SDK's SetKey chaining pattern
    pub fn set_key(self: *AccountCreateTransaction, key: Key) !*AccountCreateTransaction {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.key = key;
        return self;
    }
    
    // Match Go SDK's SetKeyWithAlias
    pub fn set_key_with_alias(self: *AccountCreateTransaction, key: Key) !*AccountCreateTransaction {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.alias_key = key;
        return self;
    }
    
    // Match Go SDK's SetKeyWithoutAlias (same as set_key)
    pub fn set_key_without_alias(self: *AccountCreateTransaction, key: Key) !*AccountCreateTransaction {
        return self.set_key(key);
    }
    
    // Set initial balance for the new account
    pub fn setInitialBalance(self: *AccountCreateTransaction, balance: Hbar) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.initial_balance = balance;
    }
    
    // Match Go SDK's SetInitialBalance chaining pattern
    pub fn set_initial_balance(self: *AccountCreateTransaction, balance: Hbar) !*AccountCreateTransaction {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.initial_balance = balance;
        return self;
    }
    
    // Set whether receiver signature is required
    pub fn setReceiverSignatureRequired(self: *AccountCreateTransaction, required: bool) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.receiver_signature_required = required;
    }
    
    // Match Go SDK's SetReceiverSignatureRequired chaining pattern
    pub fn set_receiver_signature_required(self: *AccountCreateTransaction, required: bool) !*AccountCreateTransaction {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.receiver_signature_required = required;
        return self;
    }
    
    // Set auto renew period
    pub fn set_auto_renew_period(self: *AccountCreateTransaction, period: Duration) !*AccountCreateTransaction {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.auto_renew_period = period;
        return self;
    }
    
    // Set alias
    pub fn set_alias(self: *AccountCreateTransaction, alias_value: []const u8) !*AccountCreateTransaction {
        if (self.base.frozen) return error.TransactionIsFrozen;
        
        if (self.alias) |old_alias| {
            self.base.allocator.free(old_alias);
        }
        
        self.alias = try self.base.allocator.dupe(u8, alias_value);
        return self;
    }
    
    pub fn setAlias(self: *AccountCreateTransaction, alias_value: []const u8) !*AccountCreateTransaction {
        return self.set_alias(alias_value);
    }
    
    // Set auto renew period
    pub fn setAutoRenewPeriod(self: *AccountCreateTransaction, period: Duration) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        
        const min_period = Duration.fromDays(1);
        const max_period = Duration.fromDays(3653); // ~10 years
        
        if (period.seconds < min_period.seconds or period.seconds > max_period.seconds) {
            return error.InvalidAutoRenewPeriod;
        }
        
        self.auto_renew_period = period;
    }
    
    // Set account memo
    pub fn setAccountMemo(self: *AccountCreateTransaction, memo: []const u8) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        
        if (memo.len > 100) {
            return error.MemoTooLong;
        }
        
        self.memo = memo;
    }
    
    // Set max automatic token associations
    pub fn setMaxAutomaticTokenAssociations(self: *AccountCreateTransaction, max: i32) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        
        if (max < 0 or max > 5000) {
            return error.InvalidMaxAutomaticTokenAssociations;
        }
        
        self.max_automatic_token_associations = max;
    }
    
    // Match Go SDK's SetMaxAutomaticTokenAssociations chaining pattern
    pub fn set_max_automatic_token_associations(self: *AccountCreateTransaction, max: i32) !*AccountCreateTransaction {
        if (self.base.frozen) return error.TransactionIsFrozen;
        
        if (max < 0 or max > 5000) {
            return error.InvalidMaxAutomaticTokenAssociations;
        }
        
        self.max_automatic_token_associations = max;
        return self;
    }
    
    // Set staked account ID
    pub fn setStakedAccountId(self: *AccountCreateTransaction, account_id: AccountId) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        
        if (self.staked_node_id != null) {
            return error.CannotSetBothStakedAccountAndNode;
        }
        
        self.staked_account_id = account_id;
    }
    
    // Set staked node ID
    pub fn setStakedNodeId(self: *AccountCreateTransaction, node_id: i64) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        
        if (self.staked_account_id != null) {
            return error.CannotSetBothStakedAccountAndNode;
        }
        
        self.staked_node_id = node_id;
    }
    
    // Set staked node ID (alias with underscore for Go SDK compatibility)
    pub fn set_staked_node_id(self: *AccountCreateTransaction, node_id: i64) !void {
        return self.setStakedNodeId(node_id);
    }
    
    // Set decline staking reward
    pub fn setDeclineStakingReward(self: *AccountCreateTransaction, decline: bool) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.decline_staking_reward = decline;
    }
    
    // Set decline staking reward (alias with underscore for Go SDK compatibility)
    pub fn set_decline_staking_reward(self: *AccountCreateTransaction, decline: bool) !*AccountCreateTransaction {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.decline_staking_reward = decline;
        return self;
    }
    
    // Set alias key
    pub fn setAliasKey(self: *AccountCreateTransaction, key: Key) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        
        if (self.alias_evm_address != null) {
            return error.CannotSetBothAliasKeyAndEvmAddress;
        }
        
        self.alias_key = key;
    }
    
    // Set alias EVM address
    pub fn setAliasEvmAddress(self: *AccountCreateTransaction, address: []const u8) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        
        if (address.len != 20) {
            return error.InvalidEvmAddress;
        }
        
        if (self.alias_key != null) {
            return error.CannotSetBothAliasKeyAndEvmAddress;
        }
        
        self.alias_evm_address = address;
    }
    
    // Freeze the transaction
    pub fn freeze(self: *AccountCreateTransaction) !void {
        try self.base.freeze();
    }
    
    // Freeze with client
    pub fn freezeWith(self: *AccountCreateTransaction, client: *Client) !void {
        try self.base.freezeWith(client);
    }
    
    // Sign the transaction
    pub fn sign(self: *AccountCreateTransaction, private_key: anytype) !void {
        try self.base.sign(private_key);
    }
    
    // Sign with operator
    pub fn signWithOperator(self: *AccountCreateTransaction, client: *Client) !void {
        try self.base.signWithOperator(client);
    }
    
    // Set transaction memo matching Go SDK chaining pattern
    pub fn set_transaction_memo(self: *AccountCreateTransaction, memo: []const u8) !*AccountCreateTransaction {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.memo = memo;
        try self.base.setTransactionMemo(memo);
        return self;
    }
    
    // Execute the transaction
    pub fn execute(self: *AccountCreateTransaction, client: *Client) !TransactionResponse {
        if (self.key == null) {
            return error.KeyRequired;
        }
        
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *AccountCreateTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // TransactionBody message
        
        // transactionID = 1
        if (self.base.transaction_id) |tx_id| {
            var tx_id_writer = ProtoWriter.init(self.base.allocator);
            defer tx_id_writer.deinit();
            
            // Write TransactionID fields
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
            
            if (tx_id.scheduled) {
                try tx_id_writer.writeBool(3, true);
            }
            
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
        
        // cryptoCreateAccount = 11 (oneof data)
        var create_writer = ProtoWriter.init(self.base.allocator);
        defer create_writer.deinit();
        
        // key = 1
        if (self.key) |key| {
            const key_bytes = try self.encodeKey(key);
            defer self.base.allocator.free(key_bytes);
            try create_writer.writeMessage(1, key_bytes);
        }
        
        // initialBalance = 2
        try create_writer.writeUint64(2, @intCast(self.initial_balance.toTinybars()));
        
        // receiverSigRequired = 3
        if (self.receiver_signature_required) {
            try create_writer.writeBool(3, true);
        }
        
        // autoRenewPeriod = 4
        var auto_renew_writer = ProtoWriter.init(self.base.allocator);
        defer auto_renew_writer.deinit();
        try auto_renew_writer.writeInt64(1, self.auto_renew_period.seconds);
        const auto_renew_bytes = try auto_renew_writer.toOwnedSlice();
        defer self.base.allocator.free(auto_renew_bytes);
        try create_writer.writeMessage(4, auto_renew_bytes);
        
        // proxyAccountID = 5 (deprecated but included for compatibility)
        if (self.proxy_account_id) |proxy| {
            var proxy_writer = ProtoWriter.init(self.base.allocator);
            defer proxy_writer.deinit();
            try proxy_writer.writeInt64(1, @intCast(proxy.entity.shard));
            try proxy_writer.writeInt64(2, @intCast(proxy.entity.realm));
            try proxy_writer.writeInt64(3, @intCast(proxy.entity.num));
            const proxy_bytes = try proxy_writer.toOwnedSlice();
            defer self.base.allocator.free(proxy_bytes);
            try create_writer.writeMessage(5, proxy_bytes);
        }
        
        // sendRecordThreshold = 6 (deprecated)
        try create_writer.writeUint64(6, @intCast(self.send_record_threshold.toTinybars()));
        
        // receiveRecordThreshold = 7 (deprecated)
        try create_writer.writeUint64(7, @intCast(self.receive_record_threshold.toTinybars()));
        
        // memo = 8
        if (self.memo.len > 0) {
            try create_writer.writeString(8, self.memo);
        }
        
        // maxAutomaticTokenAssociations = 9
        if (self.max_automatic_token_associations > 0) {
            try create_writer.writeInt32(9, self.max_automatic_token_associations);
        }
        
        // stakedAccountId = 10 or stakedNodeId = 11
        if (self.staked_account_id) |staked| {
            var staked_writer = ProtoWriter.init(self.base.allocator);
            defer staked_writer.deinit();
            try staked_writer.writeInt64(1, @intCast(staked.entity.shard));
            try staked_writer.writeInt64(2, @intCast(staked.entity.realm));
            try staked_writer.writeInt64(3, @intCast(staked.entity.num));
            const staked_bytes = try staked_writer.toOwnedSlice();
            defer self.base.allocator.free(staked_bytes);
            try create_writer.writeMessage(10, staked_bytes);
        } else if (self.staked_node_id) |node_id| {
            try create_writer.writeInt64(11, node_id);
        }
        
        // declineStakingReward = 12
        if (self.decline_staking_reward) {
            try create_writer.writeBool(12, true);
        }
        
        // alias = 13
        if (self.alias_key) |alias| {
            const alias_bytes = try self.encodeKey(alias);
            defer self.base.allocator.free(alias_bytes);
            try create_writer.writeMessage(13, alias_bytes);
        } else if (self.alias_evm_address) |evm| {
            try create_writer.writeString(13, evm);
        }
        
        const create_bytes = try create_writer.toOwnedSlice();
        defer self.base.allocator.free(create_bytes);
        try writer.writeMessage(11, create_bytes);
        
        return writer.toOwnedSlice();
    }
    
    fn encodeKey(self: *AccountCreateTransaction, key: Key) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        switch (key) {
            .ed25519 => |k| {
                try writer.writeString(2, &k.bytes);
            },
            .ecdsa_secp256k1 => |k| {
                try writer.writeString(7, &k.bytes);
            },
            .key_list => |list| {
                var list_writer = ProtoWriter.init(self.base.allocator);
                defer list_writer.deinit();
                
                for (list.keys.items) |item_key| {
                    const item_bytes = try self.encodeKey(item_key);
                    defer self.base.allocator.free(item_bytes);
                    try list_writer.writeMessage(1, item_bytes);
                }
                
                const list_bytes = try list_writer.toOwnedSlice();
                defer self.base.allocator.free(list_bytes);
                try writer.writeMessage(6, list_bytes);
            },
            .threshold_key => |tk| {
                var tk_writer = ProtoWriter.init(self.base.allocator);
                defer tk_writer.deinit();
                
                try tk_writer.writeUint32(1, tk.threshold);
                
                var keys_writer = ProtoWriter.init(self.base.allocator);
                defer keys_writer.deinit();
                
                for (tk.keys.keys.items) |item_key| {
                    const item_bytes = try self.encodeKey(item_key);
                    defer self.base.allocator.free(item_bytes);
                    try keys_writer.writeMessage(1, item_bytes);
                }
                
                const keys_bytes = try keys_writer.toOwnedSlice();
                defer self.base.allocator.free(keys_bytes);
                try tk_writer.writeMessage(2, keys_bytes);
                
                const tk_bytes = try tk_writer.toOwnedSlice();
                defer self.base.allocator.free(tk_bytes);
                try writer.writeMessage(5, tk_bytes);
            },
            .contract_id => |cid| {
                var cid_writer = ProtoWriter.init(self.base.allocator);
                defer cid_writer.deinit();
                try cid_writer.writeString(1, cid.contract_id);
                const cid_bytes = try cid_writer.toOwnedSlice();
                defer self.base.allocator.free(cid_bytes);
                try writer.writeMessage(1, cid_bytes);
            },
            .delegatable_contract_id => |cid| {
                var cid_writer = ProtoWriter.init(self.base.allocator);
                defer cid_writer.deinit();
                try cid_writer.writeString(1, cid.contract_id);
                const cid_bytes = try cid_writer.toOwnedSlice();
                defer self.base.allocator.free(cid_bytes);
                try writer.writeMessage(8, cid_bytes);
            },
        }
        
        return writer.toOwnedSlice();
    }
};
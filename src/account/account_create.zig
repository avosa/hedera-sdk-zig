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
        var tx = AccountCreateTransaction{
            .base = Transaction.init(allocator),
            .key = null,
            .initial_balance = Hbar.zero(),
            .receiver_signature_required = false,
            .auto_renew_period = Duration.fromSeconds(7890000), // Match Go SDK default
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
        
        // Set default max transaction fee to 5 HBAR like Go SDK
        tx.base.max_transaction_fee = Hbar.from(5) catch Hbar.zero();
        
        return tx;
    }
    
    pub fn deinit(self: *AccountCreateTransaction) void {
        self.base.deinit();
    }
    
    // Set the key for the new account
    pub fn setKey(self: *AccountCreateTransaction, key: Key) *AccountCreateTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        self.key = key;
        return self;
    }
    
    // Match Go SDK's SetKey chaining pattern
    pub fn set_key(self: *AccountCreateTransaction, key: Key) !*AccountCreateTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        self.key = key;
        return self;
    }
    
    // Match Go SDK's SetKeyWithAlias - sets account key and ECDSA key for alias
    pub fn set_key_with_alias(self: *AccountCreateTransaction, key: Key, ecdsa_key: Key) !*AccountCreateTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        self.key = key;
        
        // Extract EVM address from ECDSA key
        const evm_address = try ecdsa_key.toEvmAddress(self.base.allocator);
        defer self.base.allocator.free(evm_address);
        
        // Convert hex string to bytes (remove 0x prefix if present)
        var start_idx: usize = 0;
        if (std.mem.startsWith(u8, evm_address, "0x")) {
            start_idx = 2;
            return self;
        }
        
        const hex_str = evm_address[start_idx..];
        const alias_bytes = try self.base.allocator.alloc(u8, hex_str.len / 2);
        _ = try std.fmt.hexToBytes(alias_bytes, hex_str);
        
        if (self.alias) |old_alias| {
            self.base.allocator.free(old_alias);
        }
        self.alias = alias_bytes;
        
        return self;
    }
    
    // Match Go SDK's SetECDSAKeyWithAlias - sets ECDSA key and derives EVM address
    pub fn set_ecdsa_key_with_alias(self: *AccountCreateTransaction, ecdsa_key: Key) !*AccountCreateTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        
        // Set the key
        self.key = ecdsa_key;
        
        // Extract EVM address from ECDSA key
        const evm_address = try ecdsa_key.toEvmAddress(self.base.allocator);
        defer self.base.allocator.free(evm_address);
        
        // Convert hex string to bytes (remove 0x prefix if present)
        var start_idx: usize = 0;
        if (std.mem.startsWith(u8, evm_address, "0x")) {
            start_idx = 2;
            return self;
        }
        
        const hex_str = evm_address[start_idx..];
        const alias_bytes = try self.base.allocator.alloc(u8, hex_str.len / 2);
        _ = try std.fmt.hexToBytes(alias_bytes, hex_str);
        
        if (self.alias) |old_alias| {
            self.base.allocator.free(old_alias);
        }
        self.alias = alias_bytes;
        
        return self;
    }
    
    // Match Go SDK's SetKeyWithoutAlias (same as set_key)
    pub fn set_key_without_alias(self: *AccountCreateTransaction, key: Key) !*AccountCreateTransaction {
        return self.set_key(key);
    }
    
    // Set initial balance for the new account
    pub fn setInitialBalance(self: *AccountCreateTransaction, balance: Hbar) *AccountCreateTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        self.initial_balance = balance;
        return self;
    }
    
    // Match Go SDK's SetInitialBalance chaining pattern
    pub fn set_initial_balance(self: *AccountCreateTransaction, balance: Hbar) !*AccountCreateTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        self.initial_balance = balance;
        return self;
    }
    
    // Set whether receiver signature is required
    pub fn setReceiverSignatureRequired(self: *AccountCreateTransaction, required: bool) *AccountCreateTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        self.receiver_signature_required = required;
        return self;
    }
    
    // Match Go SDK's SetReceiverSignatureRequired chaining pattern
    pub fn set_receiver_signature_required(self: *AccountCreateTransaction, required: bool) !*AccountCreateTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        self.receiver_signature_required = required;
        return self;
    }
    
    // Set auto renew period
    pub fn set_auto_renew_period(self: *AccountCreateTransaction, period: Duration) !*AccountCreateTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        self.auto_renew_period = period;
        return self;
    }
    
    // Match Go SDK's SetAlias - accepts EVM address string or raw bytes
    pub fn set_alias(self: *AccountCreateTransaction, input: []const u8) !*AccountCreateTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        
        if (self.alias) |old_alias| {
            self.base.allocator.free(old_alias);
        }
        
        // Check if input is hex string (starts with 0x or is all hex chars)
        if (std.mem.startsWith(u8, input, "0x")) {
            // Hex string with 0x prefix
            const hex_str = input[2..];
            const alias_bytes = try self.base.allocator.alloc(u8, hex_str.len / 2);
            _ = try std.fmt.hexToBytes(alias_bytes, hex_str);
            self.alias = alias_bytes;
        } else if (isHexString(input)) {
            // Hex string without prefix
            const alias_bytes = try self.base.allocator.alloc(u8, input.len / 2);
            _ = try std.fmt.hexToBytes(alias_bytes, input);
            self.alias = alias_bytes;
        } else {
            // Raw bytes - just copy
            self.alias = try self.base.allocator.dupe(u8, input);
        }
        
        return self;
    }
    
    fn isHexString(str: []const u8) bool {
        if (str.len == 0 or str.len % 2 != 0) return false;
        for (str) |c| {
            if (!std.ascii.isHex(c)) return false;
        }
        return true;
    }
    
    pub fn setAlias(self: *AccountCreateTransaction, evm_address: []const u8) !*AccountCreateTransaction {
        return self.set_alias(evm_address);
    }
    
    // Set auto renew period
    pub fn setAutoRenewPeriod(self: *AccountCreateTransaction, period: Duration) *AccountCreateTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        
        const min_period = Duration.fromDays(1);
        const max_period = Duration.fromDays(3653); // ~10 years
        
        if (period.seconds < min_period.seconds or period.seconds > max_period.seconds) {
            @panic("Invalid auto renew period");
        }
        
        self.auto_renew_period = period;
        return self;
    }
    
    // Set account memo
    pub fn setAccountMemo(self: *AccountCreateTransaction, memo: []const u8) *AccountCreateTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        
        if (memo.len > 100) {
            @panic("Memo too long");
        }
        
        self.memo = memo;
        return self;
    }
    
    // Match Go SDK's SetAccountMemo chaining pattern
    pub fn set_account_memo(self: *AccountCreateTransaction, memo: []const u8) !*AccountCreateTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        
        if (memo.len > 100) {
            @panic("Memo too long");
        }
        
        self.memo = memo;
        return self;
    }
    
    // Set max automatic token associations
    pub fn setMaxAutomaticTokenAssociations(self: *AccountCreateTransaction, max: i32) *AccountCreateTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        
        if (max < 0 or max > 5000) {
            @panic("Invalid max automatic token associations");
        }
        
        self.max_automatic_token_associations = max;
        return self;
    }
    
    // SetProxyAccountID sets the ID of the account to which this account is proxy staked
    // Deprecated but kept for compatibility with Go SDK
    pub fn setProxyAccountId(self: *AccountCreateTransaction, id: AccountId) *AccountCreateTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        self.proxy_account_id = id;
        return self;
    }
    
    // Match Go SDK's SetProxyAccountID chaining pattern
    pub fn set_proxy_account_id(self: *AccountCreateTransaction, id: AccountId) !*AccountCreateTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        self.proxy_account_id = id;
        return self;
    }
    
    // Getter methods matching Go SDK
    pub fn get_key(self: *const AccountCreateTransaction) ?Key {
        return self.key;
    }
    
    pub fn get_initial_balance(self: *const AccountCreateTransaction) Hbar {
        return self.initial_balance;
    }
    
    pub fn get_max_automatic_token_associations(self: *const AccountCreateTransaction) i32 {
        return self.max_automatic_token_associations;
    }
    
    pub fn get_auto_renew_period(self: *const AccountCreateTransaction) Duration {
        return self.auto_renew_period;
    }
    
    pub fn get_proxy_account_id(self: *const AccountCreateTransaction) ?AccountId {
        return self.proxy_account_id;
    }
    
    pub fn getProxyAccountID(self: *const AccountCreateTransaction) ?AccountId {
        return self.proxy_account_id;
    }
    
    pub fn get_account_memo(self: *const AccountCreateTransaction) []const u8 {
        return self.memo;
    }
    
    pub fn get_staked_account_id(self: *const AccountCreateTransaction) ?AccountId {
        return self.staked_account_id;
    }
    
    pub fn get_staked_node_id(self: *const AccountCreateTransaction) ?i64 {
        return self.staked_node_id;
    }
    
    pub fn get_decline_staking_reward(self: *const AccountCreateTransaction) bool {
        return self.decline_staking_reward;
    }
    
    pub fn get_alias(self: *const AccountCreateTransaction) ?[]const u8 {
        return self.alias;
    }
    
    pub fn get_receiver_signature_required(self: *const AccountCreateTransaction) bool {
        return self.receiver_signature_required;
    }
    
    // Match Go SDK's SetMaxAutomaticTokenAssociations chaining pattern
    pub fn set_max_automatic_token_associations(self: *AccountCreateTransaction, max: i32) !*AccountCreateTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        
        if (max < 0 or max > 5000) {
            @panic("Invalid max automatic token associations");
        }
        
        self.max_automatic_token_associations = max;
        return self;
    }
    
    // Set staked account ID
    pub fn setStakedAccountId(self: *AccountCreateTransaction, account_id: AccountId) *AccountCreateTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        
        if (self.staked_node_id != null) {
            return error.CannotSetBothStakedAccountAndNode;
        }
        
        self.staked_account_id = account_id;
        return self;
    }
    
    // Match Go SDK's SetStakedAccountID chaining pattern
    pub fn set_staked_account_id(self: *AccountCreateTransaction, account_id: AccountId) !*AccountCreateTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        
        self.staked_account_id = account_id;
        self.staked_node_id = null; // Clear node ID like Go SDK
        return self;
    }
    
    // Set staked node ID
    pub fn setStakedNodeId(self: *AccountCreateTransaction, node_id: i64) *AccountCreateTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        
        if (self.staked_account_id != null) {
            @panic("Cannot set both staked account and node");
        }
        
        self.staked_node_id = node_id;
        return self;
    }
    
    // Match Go SDK's SetStakedNodeID chaining pattern
    pub fn set_staked_node_id(self: *AccountCreateTransaction, node_id: i64) !*AccountCreateTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        
        self.staked_node_id = node_id;
        self.staked_account_id = null; // Clear account ID like Go SDK
        return self;
    }
    
    // Set decline staking reward
    pub fn setDeclineStakingReward(self: *AccountCreateTransaction, decline: bool) *AccountCreateTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        self.decline_staking_reward = decline;
        return self;
    }
    
    // Set decline staking reward (alias with underscore for Go SDK compatibility)
    pub fn set_decline_staking_reward(self: *AccountCreateTransaction, decline: bool) !*AccountCreateTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        self.decline_staking_reward = decline;
        return self;
    }
    
    // Set alias key
    pub fn setAliasKey(self: *AccountCreateTransaction, key: Key) *AccountCreateTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        
        if (self.alias_evm_address != null) {
            return error.CannotSetBothAliasKeyAndEvmAddress;
        }
        
        self.alias_key = key;
        return self;
    }
    
    // Set alias EVM address
    pub fn setAliasEvmAddress(self: *AccountCreateTransaction, address: []const u8) *AccountCreateTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        
        if (address.len != 20) {
            return error.InvalidEvmAddress;
        }
        
        if (self.alias_key != null) {
            return error.CannotSetBothAliasKeyAndEvmAddress;
        }
        
        self.alias_evm_address = address;
        return self;
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
        if (self.base.frozen) @panic("Transaction is frozen");
        self.memo = memo;
        _ = self.base.setTransactionMemo(memo);
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
            try account_writer.writeInt64(1, @intCast(tx_id.account_id.shard));
            try account_writer.writeInt64(2, @intCast(tx_id.account_id.realm));
            try account_writer.writeInt64(3, @intCast(tx_id.account_id.account));
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
            try proxy_writer.writeInt64(1, @intCast(proxy.shard));
            try proxy_writer.writeInt64(2, @intCast(proxy.realm));
            try proxy_writer.writeInt64(3, @intCast(proxy.account));
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
            try staked_writer.writeInt64(1, @intCast(staked.shard));
            try staked_writer.writeInt64(2, @intCast(staked.realm));
            try staked_writer.writeInt64(3, @intCast(staked.account));
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
        
        // alias = 18 (bytes field for EVM address)
        if (self.alias) |alias_bytes| {
            try create_writer.writeBytes(18, alias_bytes);
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
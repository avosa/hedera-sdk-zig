const std = @import("std");
const errors = @import("../core/errors.zig");
const AccountId = @import("../core/id.zig").AccountId;
const FileId = @import("../core/id.zig").FileId;
const Key = @import("../crypto/key.zig").Key;
const PublicKey = @import("../crypto/key.zig").PublicKey;
const Hbar = @import("../core/hbar.zig").Hbar;
const Duration = @import("../core/duration.zig").Duration;
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;

// ContractCreateTransaction creates a new smart contract instance
pub const ContractCreateTransaction = struct {
    base: Transaction,
    bytecode_file_id: ?FileId,
    bytecode: []const u8,
    admin_key: ?Key,
    gas: i64,
    initial_balance: Hbar,
    proxy_account_id: ?AccountId,
    auto_renew_period: Duration,
    constructor_parameters: []const u8,
    memo: []const u8,
    max_automatic_token_associations: i32,
    auto_renew_account_id: ?AccountId,
    staked_account_id: ?AccountId,
    staked_node_id: ?i64,
    decline_staking_reward: bool,
    
    pub fn init(allocator: std.mem.Allocator) ContractCreateTransaction {
        var tx = ContractCreateTransaction{
            .base = Transaction.init(allocator),
            .bytecode_file_id = null,
            .bytecode = "",
            .admin_key = null,
            .gas = 100000,
            .initial_balance = Hbar.zero(),
            .proxy_account_id = null,
            .auto_renew_period = Duration{ .seconds = 7890000, .nanos = 0 }, // 131500 minutes
            .constructor_parameters = "",
            .memo = "",
            .max_automatic_token_associations = 0,
            .auto_renew_account_id = null,
            .staked_account_id = null,
            .staked_node_id = null,
            .decline_staking_reward = false,
        };
        
        // Set default auto-renew period to 131500 minutes (matching Go SDK)
        tx.auto_renew_period = Duration{ .seconds = 131500 * 60, .nanos = 0 };
        // Set default max transaction fee to 20 Hbar (matching Go SDK)
        tx.base.max_transaction_fee = Hbar.from(20) catch Hbar.zero();
        
        return tx;
    }
    
    pub fn deinit(self: *ContractCreateTransaction) void {
        self.base.deinit();
    }
    
    // SetBytecodeFileID sets the file ID containing the contract bytecode
    pub fn setBytecodeFileId(self: *ContractCreateTransaction, file_id: FileId) errors.HederaError!*ContractCreateTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        self.bytecode_file_id = file_id;
        self.bytecode = ""; // Clear bytecode when setting file ID
        return self;
    }
    
    // GetBytecodeFileID returns the file ID containing the contract bytecode
    pub fn getBytecodeFileID(self: *const ContractCreateTransaction) FileId {
        return self.bytecode_file_id orelse FileId{};
    }
    
    // SetBytecode sets the contract bytecode directly
    pub fn setBytecode(self: *ContractCreateTransaction, bytecode: []const u8) errors.HederaError!*ContractCreateTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        self.bytecode = bytecode;
        self.bytecode_file_id = null; // Clear file ID when setting bytecode
        return self;
    }
    
    // GetBytecode returns the contract bytecode
    pub fn getBytecode(self: *const ContractCreateTransaction) []const u8 {
        return self.bytecode;
    }
    
    // SetAdminKey sets the admin key for the contract
    pub fn setAdminKey(self: *ContractCreateTransaction, key: Key) errors.HederaError!*ContractCreateTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        self.admin_key = key;
        return self;
    }
    
    // GetAdminKey returns the admin key for the contract
    pub fn getAdminKey(self: *const ContractCreateTransaction) ?Key {
        return self.admin_key;
    }
    
    // SetGas sets the gas limit for the contract constructor
    pub fn setGas(self: *ContractCreateTransaction, gas: u64) errors.HederaError!*ContractCreateTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        self.gas = @intCast(gas);
        return self;
    }
    
    // GetGas returns the gas limit for the contract constructor
    pub fn getGas(self: *const ContractCreateTransaction) u64 {
        return @intCast(self.gas);
    }
    
    // SetInitialBalance sets the initial balance for the contract
    pub fn setInitialBalance(self: *ContractCreateTransaction, balance: Hbar) errors.HederaError!*ContractCreateTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        self.initial_balance = balance;
        return self;
    }
    
    // GetInitialBalance returns the initial balance for the contract
    pub fn getInitialBalance(self: *const ContractCreateTransaction) Hbar {
        return self.initial_balance;
    }
    
    // SetProxyAccountID sets the proxy account ID (deprecated)
    pub fn setProxyAccountId(self: *ContractCreateTransaction, proxy_id: AccountId) errors.HederaError!*ContractCreateTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        self.proxy_account_id = proxy_id;
        return self;
    }
    
    // GetProxyAccountID returns the proxy account ID (deprecated)
    pub fn getProxyAccountID(self: *const ContractCreateTransaction) AccountId {
        return self.proxy_account_id orelse AccountId{};
    }
    
    // SetAutoRenewPeriod sets the auto renew period for the contract
    pub fn setAutoRenewPeriod(self: *ContractCreateTransaction, period: Duration) errors.HederaError!*ContractCreateTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        self.auto_renew_period = period;
        return self;
    }
    
    // GetAutoRenewPeriod returns the auto renew period for the contract
    pub fn getAutoRenewPeriod(self: *const ContractCreateTransaction) Duration {
        return self.auto_renew_period;
    }
    
    // SetConstructorParameters sets the constructor parameters for the contract
    pub fn setConstructorParameters(self: *ContractCreateTransaction, params: []const u8) errors.HederaError!*ContractCreateTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        self.constructor_parameters = params;
        return self;
    }
    
    // GetConstructorParameters returns the constructor parameters for the contract
    pub fn getConstructorParameters(self: *const ContractCreateTransaction) []const u8 {
        return self.constructor_parameters;
    }
    
    // SetMemo sets the memo for the contract
    pub fn setMemo(self: *ContractCreateTransaction, memo: []const u8) errors.HederaError!*ContractCreateTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        self.memo = memo;
        return self;
    }
    
    // GetContractMemo returns the memo for the contract
    pub fn getContractMemo(self: *const ContractCreateTransaction) []const u8 {
        return self.memo;
    }
    
    // SetMaxAutomaticTokenAssociations sets the maximum number of automatic token associations
    pub fn setMaxAutomaticTokenAssociations(self: *ContractCreateTransaction, max: i32) errors.HederaError!*ContractCreateTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        self.max_automatic_token_associations = max;
        return self;
    }
    
    // GetMaxAutomaticTokenAssociations returns the maximum number of automatic token associations
    pub fn getMaxAutomaticTokenAssociations(self: *const ContractCreateTransaction) i32 {
        return self.max_automatic_token_associations;
    }
    
    // SetAutoRenewAccountID sets the auto renew account ID for the contract
    pub fn setAutoRenewAccountId(self: *ContractCreateTransaction, account_id: AccountId) errors.HederaError!*ContractCreateTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        self.auto_renew_account_id = account_id;
        return self;
    }
    
    // GetAutoRenewAccountID returns the auto renew account ID for the contract
    pub fn getAutoRenewAccountID(self: *const ContractCreateTransaction) AccountId {
        return self.auto_renew_account_id orelse AccountId{};
    }
    
    // SetStakedAccountID sets the staked account ID for the contract
    pub fn setStakedAccountID(self: *ContractCreateTransaction, account_id: AccountId) errors.HederaError!*ContractCreateTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        self.staked_account_id = account_id;
        self.staked_node_id = null; // Clear node ID when setting account ID
        return self;
    }
    
    // GetStakedAccountID returns the staked account ID for the contract
    pub fn getStakedAccountID(self: *const ContractCreateTransaction) AccountId {
        return self.staked_account_id orelse AccountId{};
    }
    
    // SetStakedNodeID sets the staked node ID for the contract
    pub fn setStakedNodeId(self: *ContractCreateTransaction, node_id: i64) errors.HederaError!*ContractCreateTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        self.staked_node_id = node_id;
        self.staked_account_id = null; // Clear account ID when setting node ID
        return self;
    }
    
    // GetStakedNodeID returns the staked node ID for the contract
    pub fn getStakedNodeID(self: *const ContractCreateTransaction) i64 {
        return self.staked_node_id orelse 0;
    }
    
    // SetDeclineStakingReward sets whether to decline staking rewards
    pub fn setDeclineStakingReward(self: *ContractCreateTransaction, decline: bool) errors.HederaError!*ContractCreateTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        self.decline_staking_reward = decline;
        return self;
    }
    
    // GetDeclineStakingReward returns whether to decline staking rewards
    pub fn getDeclineStakingReward(self: *const ContractCreateTransaction) bool {
        return self.decline_staking_reward;
    }
    
    // Execute the transaction
    pub fn execute(self: *ContractCreateTransaction, client: *Client) !TransactionResponse {
        if (self.bytecode_file_id == null and self.bytecode.len == 0) {
            return error.BytecodeRequired;
        }
        
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *ContractCreateTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Common transaction fields
        try self.writeCommonFields(&writer);
        
        // contractCreateInstance = 7 (oneof data)
        var create_writer = ProtoWriter.init(self.base.allocator);
        defer create_writer.deinit();
        
        // fileID = 1
        if (self.bytecode_file_id) |file_id| {
            var file_writer = ProtoWriter.init(self.base.allocator);
            defer file_writer.deinit();
            try file_writer.writeInt64(1, @intCast(file_id.shard));
            try file_writer.writeInt64(2, @intCast(file_id.realm));
            try file_writer.writeInt64(3, @intCast(file_id.num));
            const file_bytes = try file_writer.toOwnedSlice();
            defer self.base.allocator.free(file_bytes);
            try create_writer.writeMessage(1, file_bytes);
        }
        
        // adminKey = 3
        if (self.admin_key) |key| {
            const key_bytes = try key.toProtobuf(self.base.allocator);
            defer self.base.allocator.free(key_bytes);
            try create_writer.writeMessage(3, key_bytes);
        }
        
        // gas = 4
        try create_writer.writeInt64(4, self.gas);
        
        // initialBalance = 5
        try create_writer.writeInt64(5, self.initial_balance.toTinybars());
        
        // proxyAccountID = 6 (deprecated)
        if (self.proxy_account_id) |proxy| {
            var proxy_writer = ProtoWriter.init(self.base.allocator);
            defer proxy_writer.deinit();
            try proxy_writer.writeInt64(1, @intCast(proxy.shard));
            try proxy_writer.writeInt64(2, @intCast(proxy.realm));
            try proxy_writer.writeInt64(3, @intCast(proxy.account));
            const proxy_bytes = try proxy_writer.toOwnedSlice();
            defer self.base.allocator.free(proxy_bytes);
            try create_writer.writeMessage(6, proxy_bytes);
        }
        
        // autoRenewPeriod = 8
        var duration_writer = ProtoWriter.init(self.base.allocator);
        defer duration_writer.deinit();
        try duration_writer.writeInt64(1, self.auto_renew_period.seconds);
        const duration_bytes = try duration_writer.toOwnedSlice();
        defer self.base.allocator.free(duration_bytes);
        try create_writer.writeMessage(8, duration_bytes);
        
        // constructorParameters = 9
        if (self.constructor_parameters.len > 0) {
            try create_writer.writeBytes(9, self.constructor_parameters);
        }
        
        // memo = 13
        if (self.memo.len > 0) {
            try create_writer.writeString(13, self.memo);
        }
        
        // max_automatic_token_associations = 14
        if (self.max_automatic_token_associations > 0) {
            try create_writer.writeInt32(14, self.max_automatic_token_associations);
        }
        
        // auto_renew_account_id = 15
        if (self.auto_renew_account_id) |account| {
            var account_writer = ProtoWriter.init(self.base.allocator);
            defer account_writer.deinit();
            try account_writer.writeInt64(1, @intCast(account.shard));
            try account_writer.writeInt64(2, @intCast(account.realm));
            try account_writer.writeInt64(3, @intCast(account.account));
            const account_bytes = try account_writer.toOwnedSlice();
            defer self.base.allocator.free(account_bytes);
            try create_writer.writeMessage(15, account_bytes);
        }
        
        // initcode = 16 (bytecode)
        if (self.bytecode.len > 0) {
            try create_writer.writeBytes(16, self.bytecode);
        }
        
        // staked_account_id = 17 or staked_node_id = 18
        if (self.staked_account_id) |staked| {
            var staked_writer = ProtoWriter.init(self.base.allocator);
            defer staked_writer.deinit();
            try staked_writer.writeInt64(1, @intCast(staked.shard));
            try staked_writer.writeInt64(2, @intCast(staked.realm));
            try staked_writer.writeInt64(3, @intCast(staked.account));
            const staked_bytes = try staked_writer.toOwnedSlice();
            defer self.base.allocator.free(staked_bytes);
            try create_writer.writeMessage(17, staked_bytes);
        } else if (self.staked_node_id) |node| {
            try create_writer.writeInt64(18, node);
        }
        
        // decline_reward = 19
        if (self.decline_staking_reward) {
            try create_writer.writeBool(19, true);
        }
        
        const create_bytes = try create_writer.toOwnedSlice();
        defer self.base.allocator.free(create_bytes);
        try writer.writeMessage(7, create_bytes);
        
        return writer.toOwnedSlice();
    }
    
    fn writeCommonFields(self: *ContractCreateTransaction, writer: *ProtoWriter) !void {
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

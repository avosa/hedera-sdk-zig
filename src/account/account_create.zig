// Account creation transaction for Hedera network
// Handles new account creation with comprehensive configuration options

const std = @import("std");
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const ProtoWriter = @import("../protobuf/writer.zig").ProtoWriter;
const AccountId = @import("../core/id.zig").AccountId;
const Key = @import("../crypto/key.zig").Key;
const Hbar = @import("../core/hbar.zig").Hbar;
const Duration = @import("../core/duration.zig").Duration;
const HederaError = @import("../core/errors.zig").HederaError;
const requireNotFrozen = @import("../core/errors.zig").requireNotFrozen;
const requirePositive = @import("../core/errors.zig").requirePositive;
const requireMaxLength = @import("../core/errors.zig").requireMaxLength;
const requireNotNull = @import("../core/errors.zig").requireNotNull;

// AccountCreateTransaction structure
pub const AccountCreateTransaction = struct {
    base: Transaction,
    
    // Required fields
    key: ?Key = null,
    
    // Optional fields with defaults
    initial_balance: Hbar = Hbar.zero(),
    auto_renew_period: Duration = Duration.fromDays(90),
    receiver_signature_required: bool = false,
    memo: []const u8 = "",
    max_automatic_token_associations: i32 = 0,
    
    // Staking fields
    staked_account_id: ?AccountId = null,
    staked_node_id: ?i64 = null,
    decline_staking_reward: bool = false,
    
    // Alias field
    alias: ?[]const u8 = null,
    
    // Record threshold fields
    send_record_threshold: Hbar,
    receive_record_threshold: Hbar,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        const max_i64 = 9223372036854775807;
        return Self{
            .base = Transaction.init(allocator),
            .send_record_threshold = Hbar{ .tinybars = max_i64 },
            .receive_record_threshold = Hbar{ .tinybars = max_i64 },
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.base.deinit();
    }
    
    // Set the key for the new account
    pub fn setKey(self: *Self, key: Key) HederaError!*Self {
        try requireNotFrozen(self.base.frozen);
        self.key = key;
        return self;
    }
    
    // Set ECDSA key with derived alias
    pub fn setECDSAKeyWithAlias(self: *Self, key: Key) HederaError!*Self {
        try self.setKeyWithoutAlias(key);
        
        // Derive EVM address from ECDSA public key
        switch (key) {
            .ecdsa_secp256k1 => |ecdsa_key| {
                // Derive alias from ECDSA key
                const derived_alias = try ecdsa_key.toEvmAddress(self.base.allocator);
                self.alias = derived_alias;
            },
            else => return HederaError.InvalidAliasKey,
        }
        return self;
    }
    
    // Set key with separate alias key
    pub fn setKeyWithAlias(self: *Self, key: Key, alias_key: Key) HederaError!*Self {
        try self.setKeyWithoutAlias(key);
        
        // Derive alias from the separate alias key
        switch (alias_key) {
            .ecdsa_secp256k1 => |ecdsa_key| {
                const derived_alias = try ecdsa_key.toEvmAddress(self.base.allocator);
                self.alias = derived_alias;
            },
            else => return HederaError.InvalidAliasKey,
        }
        return self;
    }
    
    // Set key without alias
    pub fn setKeyWithoutAlias(self: *Self, key: Key) HederaError!*Self {
        try requireNotFrozen(self.base.frozen);
        self.key = key;
        return self;
    }
    
    // Set initial balance
    pub fn setInitialBalance(self: *Self, balance: Hbar) HederaError!*Self {
        try requireNotFrozen(self.base.frozen);
        try requirePositive(balance.tinybars);
        self.initial_balance = balance;
        return self;
    }
    
    // Set auto renew period
    pub fn setAutoRenewPeriod(self: *Self, period: Duration) HederaError!*Self {
        try requireNotFrozen(self.base.frozen);
        try requirePositive(period.seconds);
        self.auto_renew_period = period;
        return self;
    }
    
    // Set account memo
    pub fn setAccountMemo(self: *Self, memo: []const u8) HederaError!*Self {
        try requireNotFrozen(self.base.frozen);
        try requireMaxLength(memo, 100);
        self.memo = memo;
        return self;
    }
    
    // Set receiver signature required
    pub fn setReceiverSignatureRequired(self: *Self, required: bool) HederaError!*Self {
        try requireNotFrozen(self.base.frozen);
        self.receiver_signature_required = required;
        return self;
    }
    
    // Set max automatic token associations
    pub fn setMaxAutomaticTokenAssociations(self: *Self, max: i32) HederaError!*Self {
        try requireNotFrozen(self.base.frozen);
        if (max < -1) return HederaError.InvalidParameter;
        self.max_automatic_token_associations = max;
        return self;
    }
    
    // Set staked account ID
    pub fn setStakedAccountId(self: *Self, account_id: AccountId) HederaError!*Self {
        try requireNotFrozen(self.base.frozen);
        self.staked_account_id = account_id;
        self.staked_node_id = null; // Clear node ID when setting account ID
        return self;
    }
    
    // Set staked node ID
    pub fn setStakedNodeId(self: *Self, node_id: i64) HederaError!*Self {
        try requireNotFrozen(self.base.frozen);
        if (node_id < -1) return HederaError.InvalidStakedId;
        self.staked_node_id = node_id;
        self.staked_account_id = null; // Clear account ID when setting node ID
        return self;
    }
    
    // Set decline staking reward
    pub fn setDeclineStakingReward(self: *Self, decline: bool) HederaError!*Self {
        try requireNotFrozen(self.base.frozen);
        self.decline_staking_reward = decline;
        return self;
    }
    
    // Set alias
    pub fn setAlias(self: *Self, alias: []const u8) !*Self {
        if (self.base.frozen) return error.TransactionFrozen;
        // Validate alias length (20 for EVM address, 32 for raw key, 33 for Ed25519, 34 for ECDSA with prefix)
        if (alias.len == 20 or alias.len == 32 or alias.len == 33 or alias.len == 34) {
            self.alias = alias;
            return self;
        }
        return error.InvalidAlias;
    }
    
    // Get key
    pub fn getKey(self: *const Self) ?Key {
        return self.key;
    }
    
    // Get initial balance
    pub fn getInitialBalance(self: *const Self) Hbar {
        return self.initial_balance;
    }
    
    // Get receiver signature required
    pub fn getReceiverSignatureRequired(self: *const Self) bool {
        return self.receiver_signature_required;
    }
    
    // Get auto renew period
    pub fn getAutoRenewPeriod(self: *const Self) Duration {
        return self.auto_renew_period;
    }
    
    // Get account memo
    pub fn getAccountMemo(self: *const Self) []const u8 {
        return self.memo;
    }
    
    // Get max automatic token associations
    pub fn getMaxAutomaticTokenAssociations(self: *const Self) i32 {
        return self.max_automatic_token_associations;
    }
    
    // Get staked account ID
    pub fn getStakedAccountId(self: *const Self) ?AccountId {
        return self.staked_account_id;
    }
    
    // Get staked node ID
    pub fn getStakedNodeId(self: *const Self) ?i64 {
        return self.staked_node_id;
    }
    
    // Get decline staking rewards
    pub fn getDeclineStakingRewards(self: *const Self) bool {
        return self.decline_staking_reward;
    }
    
    // Get alias
    pub fn getAlias(self: *const Self) ?[]const u8 {
        return self.alias;
    }
    
    // Build transaction body for a specific node
    pub fn buildTransactionBodyForNode(self: *Self, node: AccountId) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Build TransactionBody
        
        // transactionID = 1
        if (self.base.transaction_id) |tx_id| {
            var tx_id_writer = ProtoWriter.init(self.base.allocator);
            defer tx_id_writer.deinit();
            
            // validStart
            var timestamp_writer = ProtoWriter.init(self.base.allocator);
            defer timestamp_writer.deinit();
            try timestamp_writer.writeInt64(1, tx_id.valid_start.seconds);
            try timestamp_writer.writeInt32(2, tx_id.valid_start.nanos);
            const timestamp_bytes = try timestamp_writer.toOwnedSlice();
            defer self.base.allocator.free(timestamp_bytes);
            try tx_id_writer.writeMessage(1, timestamp_bytes);
            
            // accountID
            var account_writer = ProtoWriter.init(self.base.allocator);
            defer account_writer.deinit();
            try account_writer.writeInt64(1, @intCast(tx_id.account_id.shard));
            try account_writer.writeInt64(2, @intCast(tx_id.account_id.realm));
            try account_writer.writeInt64(3, @intCast(tx_id.account_id.account));
            const account_bytes = try account_writer.toOwnedSlice();
            defer self.base.allocator.free(account_bytes);
            try tx_id_writer.writeMessage(2, account_bytes);
            
            const tx_id_bytes = try tx_id_writer.toOwnedSlice();
            defer self.base.allocator.free(tx_id_bytes);
            try writer.writeMessage(1, tx_id_bytes);
        }
        
        // nodeAccountID = 2
        var node_writer = ProtoWriter.init(self.base.allocator);
        defer node_writer.deinit();
        try node_writer.writeInt64(1, @intCast(node.shard));
        try node_writer.writeInt64(2, @intCast(node.realm));
        try node_writer.writeInt64(3, @intCast(node.account));
        const node_bytes = try node_writer.toOwnedSlice();
        defer self.base.allocator.free(node_bytes);
        try writer.writeMessage(2, node_bytes);
        
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
            try writer.writeStringField(5, self.base.transaction_memo);
        }
        
        // cryptoCreateAccount = 11
        const create_body = try self.buildCreateAccountBody();
        defer self.base.allocator.free(create_body);
        try writer.writeMessage(11, create_body);
        
        return writer.toOwnedSlice() catch HederaError.SerializationFailed;
    }
    
    // Build CryptoCreateTransactionBody
    fn buildCreateAccountBody(self: *Self) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // key = 1 (REQUIRED)
        if (self.key) |key| {
            const key_bytes = try self.encodeKey(key);
            defer self.base.allocator.free(key_bytes);
            try writer.writeMessage(1, key_bytes);
        } else {
            return HederaError.KeyRequired;
        }
        
        // initialBalance = 2
        try writer.writeUint64(2, @intCast(self.initial_balance.toTinybars()));
        
        // sendRecordThreshold = 6
        try writer.writeUint64(6, @intCast(self.send_record_threshold.toTinybars()));
        
        // receiveRecordThreshold = 7
        try writer.writeUint64(7, @intCast(self.receive_record_threshold.toTinybars()));
        
        // receiverSigRequired = 8
        if (self.receiver_signature_required) {
            try writer.writeBool(8, true);
        }
        
        // autoRenewPeriod = 9
        var auto_renew_writer = ProtoWriter.init(self.base.allocator);
        defer auto_renew_writer.deinit();
        try auto_renew_writer.writeInt64(1, self.auto_renew_period.seconds);
        const auto_renew_bytes = try auto_renew_writer.toOwnedSlice();
        defer self.base.allocator.free(auto_renew_bytes);
        try writer.writeMessage(9, auto_renew_bytes);
        
        // shardID = 10 (field 10 reserved)
        // realmID = 11 (field 11 reserved)
        // newRealmAdminKey = 12 (field 12 reserved)
        
        // memo = 13
        if (self.memo.len > 0) {
            try writer.writeStringField(13, self.memo);
        }
        
        // maxAutomaticTokenAssociations = 14
        try writer.writeInt32(14, self.max_automatic_token_associations);
        
        // stakedAccountId = 15 or stakedNodeId = 16
        if (self.staked_account_id) |staked| {
            var staked_writer = ProtoWriter.init(self.base.allocator);
            defer staked_writer.deinit();
            try staked_writer.writeInt64(1, @intCast(staked.shard));
            try staked_writer.writeInt64(2, @intCast(staked.realm));
            try staked_writer.writeInt64(3, @intCast(staked.account));
            const staked_bytes = try staked_writer.toOwnedSlice();
            defer self.base.allocator.free(staked_bytes);
            try writer.writeMessage(15, staked_bytes);
        } else if (self.staked_node_id) |node_id| {
            try writer.writeInt64(16, node_id);
        }
        
        // declineReward = 17
        if (self.decline_staking_reward) {
            try writer.writeBool(17, true);
        }
        
        // alias = 18
        if (self.alias) |alias_bytes| {
            try writer.writeBytesField(18, alias_bytes);
        }
        
        return writer.toOwnedSlice() catch HederaError.SerializationFailed;
    }
    
    // Encode key to protobuf
    fn encodeKey(self: *Self, key: Key) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        switch (key) {
            .ed25519 => |pub_key| {
                // ed25519 = 2
                try writer.writeBytesField(2, pub_key.bytes[0..32]);
            },
            .ecdsa_secp256k1 => |pub_key| {
                // ecdsaSecp256k1 = 4
                try writer.writeBytesField(4, &pub_key.bytes);
            },
            else => return HederaError.InvalidAliasKey,
        }
        
        return writer.toOwnedSlice() catch HederaError.SerializationFailed;
    }
    
    // Freeze the transaction
    pub fn freeze(self: *Self) HederaError!*Self {
        // Validate required fields
        if (self.key == null) {
            return HederaError.KeyRequired;
        }
        self.base.frozen = true;
        return self;
    }
    
    // Freeze with client
    pub fn freezeWith(self: *Self, client: anytype) HederaError!*Self {
        // Validate required fields
        if (self.key == null) {
            return HederaError.KeyRequired;
        }
        _ = self.base.freezeWith(client) catch return HederaError.TransactionFrozen;
        return self;
    }
    
    // Sign the transaction
    pub fn sign(self: *Self, private_key: anytype) HederaError!*Self {
        _ = self.base.sign(private_key) catch return HederaError.TransactionFrozen;
        return self;
    }
    
    // Execute transaction
    pub fn execute(self: *Self, client: anytype) !TransactionResponse {
        // Validate required fields
        if (self.key == null) {
            return HederaError.KeyRequired;
        }
        
        // Set default fee if not set (2 HBAR)
        if (self.base.max_transaction_fee == null) {
            self.base.max_transaction_fee = try Hbar.fromTinybars(200_000_000);
        }
        
        // Override base buildTransactionBodyForNode
        self.base.buildTransactionBodyForNode = buildTransactionBodyForNodeWrapper;
        
        // Execute through base transaction
        return self.base.execute(client);
    }
    
    // Wrapper function for Transaction base class function pointer
    pub fn buildTransactionBodyForNodeWrapper(transaction: *Transaction, node: AccountId) anyerror![]u8 {
        const self = @as(*AccountCreateTransaction, @fieldParentPtr("base", transaction));
        return self.buildTransactionBodyForNode(node);
    }
};
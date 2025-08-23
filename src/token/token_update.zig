const std = @import("std");
const errors = @import("../core/errors.zig");
const TokenId = @import("../core/id.zig").TokenId;
const AccountId = @import("../core/id.zig").AccountId;
const Key = @import("../crypto/key.zig").Key;
const Duration = @import("../core/duration.zig").Duration;
const Timestamp = @import("../core/timestamp.zig").Timestamp;
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;

// TokenUpdateTransaction updates properties of an existing token
pub const TokenUpdateTransaction = struct {
    base: Transaction,
    token_id: ?TokenId,
    name: ?[]const u8,
    symbol: ?[]const u8,
    treasury: ?AccountId,
    treasury_account_id: ?AccountId,
    admin_key: ?Key,
    kyc_key: ?Key,
    freeze_key: ?Key,
    wipe_key: ?Key,
    supply_key: ?Key,
    auto_renew_account: ?AccountId,
    auto_renew_period: ?Duration,
    expiration_time: ?Timestamp,
    memo: ?[]const u8,
    fee_schedule_key: ?Key,
    pause_key: ?Key,
    metadata: ?[]const u8,
    metadata_key: ?Key,
    key_verification_mode: KeyVerificationMode,
    
    pub const KeyVerificationMode = enum {
        NoVerification,
        FullVerification,
    };
    
    pub fn init(allocator: std.mem.Allocator) TokenUpdateTransaction {
        return TokenUpdateTransaction{
            .base = Transaction.init(allocator),
            .token_id = null,
            .name = null,
            .symbol = null,
            .treasury = null,
            .treasury_account_id = null,
            .admin_key = null,
            .kyc_key = null,
            .freeze_key = null,
            .wipe_key = null,
            .supply_key = null,
            .auto_renew_account = null,
            .auto_renew_period = null,
            .expiration_time = null,
            .memo = null,
            .fee_schedule_key = null,
            .pause_key = null,
            .metadata = null,
            .metadata_key = null,
            .key_verification_mode = .FullVerification,
        };
    }
    
    pub fn deinit(self: *TokenUpdateTransaction) void {
        self.base.deinit();
    }
    
    // Set token to update
    pub fn setTokenId(self: *TokenUpdateTransaction, token_id: TokenId) errors.HederaError!*TokenUpdateTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        self.token_id = token_id;
        return self;
    }
    
    // Set new token name
    pub fn setTokenName(self: *TokenUpdateTransaction, name: []const u8) errors.HederaError!*TokenUpdateTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        try errors.requireMaxLength(name, 100);
        self.name = name;
        return self;
    }
    
    // Set new token symbol
    pub fn setTokenSymbol(self: *TokenUpdateTransaction, symbol: []const u8) errors.HederaError!*TokenUpdateTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        try errors.requireMaxLength(symbol, 100);
        self.symbol = symbol;
        return self;
    }
    
    // Set new treasury account
    pub fn setTreasuryAccountId(self: *TokenUpdateTransaction, account_id: AccountId) errors.HederaError!*TokenUpdateTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        self.treasury_account_id = account_id;
        self.treasury = account_id;  // Keep both fields in sync for uniformity
        return self;
    }
    
    // Set admin key
    pub fn setAdminKey(self: *TokenUpdateTransaction, key: Key) errors.HederaError!*TokenUpdateTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        self.admin_key = key;
        return self;
    }
    
    // Set KYC key
    pub fn setKycKey(self: *TokenUpdateTransaction, key: Key) errors.HederaError!*TokenUpdateTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        self.kyc_key = key;
        return self;
    }
    
    // Set freeze key
    pub fn setFreezeKey(self: *TokenUpdateTransaction, key: Key) errors.HederaError!*TokenUpdateTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        self.freeze_key = key;
        return self;
    }
    
    // Set wipe key
    pub fn setWipeKey(self: *TokenUpdateTransaction, key: Key) errors.HederaError!*TokenUpdateTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        self.wipe_key = key;
        return self;
    }
    
    // Set supply key
    pub fn setSupplyKey(self: *TokenUpdateTransaction, key: Key) errors.HederaError!*TokenUpdateTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        self.supply_key = key;
        return self;
    }
    
    // Set auto renew account
    pub fn setAutoRenewAccount(self: *TokenUpdateTransaction, account_id: AccountId) errors.HederaError!*TokenUpdateTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        self.auto_renew_account = account_id;
        return self;
    }
    
    // Set auto renew period
    pub fn setAutoRenewPeriod(self: *TokenUpdateTransaction, period: Duration) errors.HederaError!*TokenUpdateTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        self.auto_renew_period = period;
        return self;
    }
    
    // Set expiration time
    pub fn setExpirationTime(self: *TokenUpdateTransaction, time: Timestamp) errors.HederaError!*TokenUpdateTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        self.expiration_time = time;
        return self;
    }
    
    // Set token memo
    pub fn setTokenMemo(self: *TokenUpdateTransaction, memo: []const u8) errors.HederaError!*TokenUpdateTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        try errors.requireMaxLength(memo, 100);
        self.memo = memo;
        return self;
    }
    
    // Set fee schedule key
    pub fn setFeeScheduleKey(self: *TokenUpdateTransaction, key: Key) errors.HederaError!*TokenUpdateTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        self.fee_schedule_key = key;
        return self;
    }
    
    // Set pause key
    pub fn setPauseKey(self: *TokenUpdateTransaction, key: Key) errors.HederaError!*TokenUpdateTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        self.pause_key = key;
        return self;
    }
    
    // Set metadata
    pub fn setMetadata(self: *TokenUpdateTransaction, metadata: []const u8) errors.HederaError!*TokenUpdateTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        try errors.requireMaxLength(metadata, 100);
        self.metadata = metadata;
        return self;
    }
    
    // Set metadata key
    pub fn setMetadataKey(self: *TokenUpdateTransaction, key: Key) errors.HederaError!*TokenUpdateTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        self.metadata_key = key;
        return self;
    }
    
    // Set key verification mode
    pub fn setKeyVerificationMode(self: *TokenUpdateTransaction, mode: KeyVerificationMode) errors.HederaError!*TokenUpdateTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        self.key_verification_mode = mode;
        return self;
    }
    
    // Set treasury account
    pub fn setTreasury(self: *TokenUpdateTransaction, treasury: AccountId) errors.HederaError!*TokenUpdateTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        self.treasury_account_id = treasury;
        self.treasury = treasury;  // Keep both fields in sync for uniformity
        return self;
    }
    
    // Getter methods for uniformity with Go SDK
    pub fn getTokenId(self: *const TokenUpdateTransaction) ?TokenId {
        return self.token_id;
    }
    
    pub fn getTokenName(self: *const TokenUpdateTransaction) ?[]const u8 {
        return self.name;
    }
    
    pub fn getTokenSymbol(self: *const TokenUpdateTransaction) ?[]const u8 {
        return self.symbol;
    }
    
    pub fn getTreasuryAccountID(self: *const TokenUpdateTransaction) ?AccountId {
        return self.treasury_account_id;
    }
    
    pub fn getAdminKey(self: *const TokenUpdateTransaction) ?Key {
        return self.admin_key;
    }
    
    pub fn getKycKey(self: *const TokenUpdateTransaction) ?Key {
        return self.kyc_key;
    }
    
    pub fn getFreezeKey(self: *const TokenUpdateTransaction) ?Key {
        return self.freeze_key;
    }
    
    pub fn getWipeKey(self: *const TokenUpdateTransaction) ?Key {
        return self.wipe_key;
    }
    
    pub fn getSupplyKey(self: *const TokenUpdateTransaction) ?Key {
        return self.supply_key;
    }
    
    pub fn getAutoRenewAccount(self: *const TokenUpdateTransaction) ?AccountId {
        return self.auto_renew_account;
    }
    
    pub fn getAutoRenewPeriod(self: *const TokenUpdateTransaction) ?Duration {
        return self.auto_renew_period;
    }
    
    pub fn getExpirationTime(self: *const TokenUpdateTransaction) ?Timestamp {
        return self.expiration_time;
    }
    
    pub fn getTokenMemo(self: *const TokenUpdateTransaction) ?[]const u8 {
        return self.memo;
    }
    
    pub fn getFeeScheduleKey(self: *const TokenUpdateTransaction) ?Key {
        return self.fee_schedule_key;
    }
    
    pub fn getPauseKey(self: *const TokenUpdateTransaction) ?Key {
        return self.pause_key;
    }
    
    pub fn getMetadata(self: *const TokenUpdateTransaction) ?[]const u8 {
        return self.metadata;
    }
    
    pub fn getMetadataKey(self: *const TokenUpdateTransaction) ?Key {
        return self.metadata_key;
    }
    
    pub fn getKeyVerificationMode(self: *const TokenUpdateTransaction) KeyVerificationMode {
        return self.key_verification_mode;
    }
    
    // Execute the transaction
    pub fn execute(self: *TokenUpdateTransaction, client: *Client) !TransactionResponse {
        if (self.token_id == null) {
            return error.TokenIdRequired;
        }
        
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *TokenUpdateTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Common transaction fields
        try self.writeCommonFields(&writer);
        
        // tokenUpdate = 37 (oneof data)
        var update_writer = ProtoWriter.init(self.base.allocator);
        defer update_writer.deinit();
        
        // token = 1
        if (self.token_id) |token| {
            var token_writer = ProtoWriter.init(self.base.allocator);
            defer token_writer.deinit();
            try token_writer.writeInt64(1, @intCast(token.shard));
            try token_writer.writeInt64(2, @intCast(token.realm));
            try token_writer.writeInt64(3, @intCast(token.num));
            const token_bytes = try token_writer.toOwnedSlice();
            defer self.base.allocator.free(token_bytes);
            try update_writer.writeMessage(1, token_bytes);
        }
        
        // symbol = 2
        if (self.symbol) |symbol| {
            try update_writer.writeString(2, symbol);
        }
        
        // name = 3
        if (self.name) |name| {
            try update_writer.writeString(3, name);
        }
        
        // treasury = 4
        if (self.treasury_account_id) |treasury| {
            var treasury_writer = ProtoWriter.init(self.base.allocator);
            defer treasury_writer.deinit();
            try treasury_writer.writeInt64(1, @intCast(treasury.shard));
            try treasury_writer.writeInt64(2, @intCast(treasury.realm));
            try treasury_writer.writeInt64(3, @intCast(treasury.account));
            const treasury_bytes = try treasury_writer.toOwnedSlice();
            defer self.base.allocator.free(treasury_bytes);
            try update_writer.writeMessage(4, treasury_bytes);
        }
        
        // adminKey = 5
        if (self.admin_key) |key| {
            const key_bytes = try key.toProtobuf(self.base.allocator);
            defer self.base.allocator.free(key_bytes);
            try update_writer.writeMessage(5, key_bytes);
        }
        
        // kycKey = 6
        if (self.kyc_key) |key| {
            const key_bytes = try key.toProtobuf(self.base.allocator);
            defer self.base.allocator.free(key_bytes);
            try update_writer.writeMessage(6, key_bytes);
        }
        
        // freezeKey = 7
        if (self.freeze_key) |key| {
            const key_bytes = try key.toProtobuf(self.base.allocator);
            defer self.base.allocator.free(key_bytes);
            try update_writer.writeMessage(7, key_bytes);
        }
        
        // wipeKey = 8
        if (self.wipe_key) |key| {
            const key_bytes = try key.toProtobuf(self.base.allocator);
            defer self.base.allocator.free(key_bytes);
            try update_writer.writeMessage(8, key_bytes);
        }
        
        // supplyKey = 9
        if (self.supply_key) |key| {
            const key_bytes = try key.toProtobuf(self.base.allocator);
            defer self.base.allocator.free(key_bytes);
            try update_writer.writeMessage(9, key_bytes);
        }
        
        // autoRenewAccount = 10
        if (self.auto_renew_account) |account| {
            var account_writer = ProtoWriter.init(self.base.allocator);
            defer account_writer.deinit();
            try account_writer.writeInt64(1, @intCast(account.shard));
            try account_writer.writeInt64(2, @intCast(account.realm));
            try account_writer.writeInt64(3, @intCast(account.account));
            const account_bytes = try account_writer.toOwnedSlice();
            defer self.base.allocator.free(account_bytes);
            try update_writer.writeMessage(10, account_bytes);
        }
        
        // autoRenewPeriod = 11
        if (self.auto_renew_period) |period| {
            var duration_writer = ProtoWriter.init(self.base.allocator);
            defer duration_writer.deinit();
            try duration_writer.writeInt64(1, period.seconds);
            const duration_bytes = try duration_writer.toOwnedSlice();
            defer self.base.allocator.free(duration_bytes);
            try update_writer.writeMessage(11, duration_bytes);
        }
        
        // expiry = 12
        if (self.expiration_time) |time| {
            var timestamp_writer = ProtoWriter.init(self.base.allocator);
            defer timestamp_writer.deinit();
            try timestamp_writer.writeInt64(1, time.seconds);
            try timestamp_writer.writeInt32(2, time.nanos);
            const timestamp_bytes = try timestamp_writer.toOwnedSlice();
            defer self.base.allocator.free(timestamp_bytes);
            try update_writer.writeMessage(12, timestamp_bytes);
        }
        
        // memo = 13
        if (self.memo) |memo| {
            var memo_writer = ProtoWriter.init(self.base.allocator);
            defer memo_writer.deinit();
            try memo_writer.writeString(1, memo);
            const memo_bytes = try memo_writer.toOwnedSlice();
            defer self.base.allocator.free(memo_bytes);
            try update_writer.writeMessage(13, memo_bytes);
        }
        
        // fee_schedule_key = 14
        if (self.fee_schedule_key) |key| {
            const key_bytes = try key.toProtobuf(self.base.allocator);
            defer self.base.allocator.free(key_bytes);
            try update_writer.writeMessage(14, key_bytes);
        }
        
        // pause_key = 15
        if (self.pause_key) |key| {
            const key_bytes = try key.toProtobuf(self.base.allocator);
            defer self.base.allocator.free(key_bytes);
            try update_writer.writeMessage(15, key_bytes);
        }
        
        // metadata = 16
        if (self.metadata) |metadata| {
            try update_writer.writeBytes(16, metadata);
        }
        
        // metadata_key = 17
        if (self.metadata_key) |key| {
            const key_bytes = try key.toProtobuf(self.base.allocator);
            defer self.base.allocator.free(key_bytes);
            try update_writer.writeMessage(17, key_bytes);
        }
        
        // key_verification_mode = 18
        try update_writer.writeInt32(18, @intFromEnum(self.key_verification_mode));
        
        const update_bytes = try update_writer.toOwnedSlice();
        defer self.base.allocator.free(update_bytes);
        try writer.writeMessage(37, update_bytes);
        
        return writer.toOwnedSlice();
    }
    
    fn writeCommonFields(self: *TokenUpdateTransaction, writer: *ProtoWriter) !void {
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

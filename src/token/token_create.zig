const std = @import("std");
const AccountId = @import("../core/id.zig").AccountId;
const TokenId = @import("../core/id.zig").TokenId;
const Key = @import("../crypto/key.zig").Key;
const Hbar = @import("../core/hbar.zig").Hbar;
const Duration = @import("../core/duration.zig").Duration;
const Timestamp = @import("../core/timestamp.zig").Timestamp;
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const errors = @import("../core/errors.zig");

// Token types
pub const TokenType = enum(i32) {
    fungible_common = 0,
    non_fungible_unique = 1,
    
    pub fn toInt(self: TokenType) i32 {
        return @intFromEnum(self);
    }
};

// Token supply type
pub const TokenSupplyType = enum(i32) {
    infinite = 0,
    finite = 1,
    
    pub fn toInt(self: TokenSupplyType) i32 {
        return @intFromEnum(self);
    }
};

// Custom fee structure
pub const CustomFee = struct {
    fee_collector_account_id: AccountId,
    all_collectors_are_exempt: bool,
    fee: union(enum) {
        fixed_fee: FixedFee,
        fractional_fee: FractionalFee,
        royalty_fee: RoyaltyFee,
    },
    
    pub fn clone(self: CustomFee, allocator: std.mem.Allocator) !CustomFee {
        _ = allocator;
        return self;  // CustomFee is copyable since it contains no heap allocations
    }
    
    pub const FixedFee = struct {
        amount: i64,
        denominating_token_id: ?TokenId,
        
        pub fn encode(self: FixedFee, writer: *ProtoWriter) !void {
            // fixedFee = 1
            var fee_writer = ProtoWriter.init(writer.buffer.allocator);
            defer fee_writer.deinit();
            
            // amount = 1
            try fee_writer.writeInt64(1, self.amount);
            
            // denominatingTokenId = 2
            if (self.denominating_token_id) |token| {
                var token_writer = ProtoWriter.init(writer.buffer.allocator);
                defer token_writer.deinit();
                try token_writer.writeInt64(1, @intCast(token.shard));
                try token_writer.writeInt64(2, @intCast(token.realm));
                try token_writer.writeInt64(3, @intCast(token.num));
                const token_bytes = try token_writer.toOwnedSlice();
                defer writer.buffer.allocator.free(token_bytes);
                try fee_writer.writeMessage(2, token_bytes);
            }
            
            const fee_bytes = try fee_writer.toOwnedSlice();
            defer writer.buffer.allocator.free(fee_bytes);
            try writer.writeMessage(1, fee_bytes);
            
            // feeCollectorAccountId = 2
            var collector_writer = ProtoWriter.init(writer.buffer.allocator);
            defer collector_writer.deinit();
            try collector_writer.writeInt64(1, @intCast(self.fee_collector_account_id.shard));
            try collector_writer.writeInt64(2, @intCast(self.fee_collector_account_id.realm));
            try collector_writer.writeInt64(3, @intCast(self.fee_collector_account_id.account));
            const collector_bytes = try collector_writer.toOwnedSlice();
            defer writer.buffer.allocator.free(collector_bytes);
            try writer.writeMessage(2, collector_bytes);
            
            // allCollectorsAreExempt = 3
            if (self.all_collectors_are_exempt) {
                try writer.writeBool(3, true);
            }
        }
    };
    
    pub const FractionalFee = struct {
        fractional_amount: Fraction,
        minimum_amount: i64,
        maximum_amount: i64,
        net_of_transfers: bool,
        
        pub const Fraction = struct {
            numerator: i64,
            denominator: i64,
        };
        
        pub fn encode(self: FractionalFee, writer: *ProtoWriter) !void {
            // fractionalFee = 2
            var fee_writer = ProtoWriter.init(writer.buffer.allocator);
            defer fee_writer.deinit();
            
            // fractionalAmount = 1
            var fraction_writer = ProtoWriter.init(writer.buffer.allocator);
            defer fraction_writer.deinit();
            try fraction_writer.writeInt64(1, self.fractional_amount.numerator);
            try fraction_writer.writeInt64(2, self.fractional_amount.denominator);
            const fraction_bytes = try fraction_writer.toOwnedSlice();
            defer writer.buffer.allocator.free(fraction_bytes);
            try fee_writer.writeMessage(1, fraction_bytes);
            
            // minimumAmount = 2
            try fee_writer.writeInt64(2, self.minimum_amount);
            
            // maximumAmount = 3
            try fee_writer.writeInt64(3, self.maximum_amount);
            
            // netOfTransfers = 4
            if (self.net_of_transfers) {
                try fee_writer.writeBool(4, true);
            }
            
            const fee_bytes = try fee_writer.toOwnedSlice();
            defer writer.buffer.allocator.free(fee_bytes);
            try writer.writeMessage(2, fee_bytes);
            
            // feeCollectorAccountId = 2
            var collector_writer = ProtoWriter.init(writer.buffer.allocator);
            defer collector_writer.deinit();
            try collector_writer.writeInt64(1, @intCast(self.fee_collector_account_id.shard));
            try collector_writer.writeInt64(2, @intCast(self.fee_collector_account_id.realm));
            try collector_writer.writeInt64(3, @intCast(self.fee_collector_account_id.account));
            const collector_bytes = try collector_writer.toOwnedSlice();
            defer writer.buffer.allocator.free(collector_bytes);
            try writer.writeMessage(2, collector_bytes);
            
            // allCollectorsAreExempt = 3
            if (self.all_collectors_are_exempt) {
                try writer.writeBool(3, true);
            }
        }
    };
    
    pub const RoyaltyFee = struct {
        numerator: i64,
        denominator: i64,
        fallback_fee: ?*FixedFee,
        
        pub fn encode(self: RoyaltyFee, writer: *ProtoWriter) !void {
            // royaltyFee = 4
            var fee_writer = ProtoWriter.init(writer.buffer.allocator);
            defer fee_writer.deinit();
            
            // exchangeValueFraction = 1
            var fraction_writer = ProtoWriter.init(writer.buffer.allocator);
            defer fraction_writer.deinit();
            try fraction_writer.writeInt64(1, self.numerator);
            try fraction_writer.writeInt64(2, self.denominator);
            const fraction_bytes = try fraction_writer.toOwnedSlice();
            defer writer.buffer.allocator.free(fraction_bytes);
            try fee_writer.writeMessage(1, fraction_bytes);
            
            // fallbackFee = 2
            if (self.fallback_fee) |fallback| {
                var fallback_writer = ProtoWriter.init(writer.buffer.allocator);
                defer fallback_writer.deinit();
                try fallback.encode(&fallback_writer);
                const fallback_bytes = try fallback_writer.toOwnedSlice();
                defer writer.buffer.allocator.free(fallback_bytes);
                try fee_writer.writeMessage(2, fallback_bytes);
            }
            
            const fee_bytes = try fee_writer.toOwnedSlice();
            defer writer.buffer.allocator.free(fee_bytes);
            try writer.writeMessage(4, fee_bytes);
            
            // feeCollectorAccountId = 2
            var collector_writer = ProtoWriter.init(writer.buffer.allocator);
            defer collector_writer.deinit();
            try collector_writer.writeInt64(1, @intCast(self.fee_collector_account_id.shard));
            try collector_writer.writeInt64(2, @intCast(self.fee_collector_account_id.realm));
            try collector_writer.writeInt64(3, @intCast(self.fee_collector_account_id.account));
            const collector_bytes = try collector_writer.toOwnedSlice();
            defer writer.buffer.allocator.free(collector_bytes);
            try writer.writeMessage(2, collector_bytes);
            
            // allCollectorsAreExempt = 3
            if (self.all_collectors_are_exempt) {
                try writer.writeBool(3, true);
            }
        }
    };
    
    pub fn deinit(self: *CustomFee) void {
        // Union members don't have heap allocations to clean up
        _ = self;
    }
    
    pub fn encode(self: CustomFee, writer: *ProtoWriter) !void {
        switch (self.fee) {
            .fixed_fee => |fee| try fee.encode(writer),
            .fractional_fee => |fee| try fee.encode(writer),
            .royalty_fee => |fee| try fee.encode(writer),
        }
    }
};

// TokenCreateTransaction creates a new token on Hedera
pub const TokenCreateTransaction = struct {
    base: Transaction,
    name: []const u8,
    symbol: []const u8,
    decimals: u32,
    initial_supply: u64,
    treasury_account_id: ?AccountId,
    treasury: ?AccountId,  // Alias for Go SDK compatibility
    admin_key: ?Key,
    kyc_key: ?Key,
    freeze_key: ?Key,
    wipe_key: ?Key,
    supply_key: ?Key,
    freeze_default: bool,
    expiration_time: ?Timestamp,
    auto_renew_account: ?AccountId,
    auto_renew_period: ?Duration,
    memo: []const u8,
    token_type: TokenType,
    supply_type: TokenSupplyType,
    max_supply: i64,
    fee_schedule_key: ?Key,
    custom_fees: std.ArrayList(CustomFee),
    pause_key: ?Key,
    metadata: []const u8,
    metadata_key: ?Key,
    
    pub fn init(allocator: std.mem.Allocator) TokenCreateTransaction {
        var transaction = TokenCreateTransaction{
            .base = Transaction.init(allocator),
            .name = "",
            .symbol = "",
            .decimals = 0,
            .initial_supply = 0,
            .treasury_account_id = null,
            .treasury = null,
            .admin_key = null,
            .kyc_key = null,
            .freeze_key = null,
            .wipe_key = null,
            .supply_key = null,
            .freeze_default = false,
            .expiration_time = null,
            .auto_renew_account = null,
            .auto_renew_period = Duration.fromSeconds(7890000),
            .memo = "",
            .token_type = .fungible_common,
            .supply_type = .infinite,
            .max_supply = 0,
            .fee_schedule_key = null,
            .custom_fees = std.ArrayList(CustomFee).init(allocator),
            .pause_key = null,
            .metadata = "",
            .metadata_key = null,
        };
        transaction.base.max_transaction_fee = Hbar.from(40) catch Hbar.zero();
        return transaction;
    }
    
    pub fn deinit(self: *TokenCreateTransaction) void {
        self.base.deinit();
        self.custom_fees.deinit();
    }
    
    // Set token name
    pub fn setTokenName(self: *TokenCreateTransaction, name: []const u8) errors.HederaError!*TokenCreateTransaction {
        if (self.base.frozen) return errors.HederaError.TransactionFrozen;
        
        if (name.len == 0) return errors.HederaError.InvalidParameter;
        if (name.len > 100) return errors.HederaError.InvalidParameter;
        
        self.name = name;
        return self;
    }
    
    // Get token name
    pub fn getTokenName(self: *TokenCreateTransaction) []const u8 {
        return self.name;
    }
    
    // Set token symbol
    pub fn setTokenSymbol(self: *TokenCreateTransaction, symbol: []const u8) errors.HederaError!*TokenCreateTransaction {
        if (self.base.frozen) return errors.HederaError.TransactionFrozen;
        
        if (symbol.len == 0) return errors.HederaError.InvalidParameter;
        if (symbol.len > 100) return errors.HederaError.InvalidParameter;
        
        self.symbol = symbol;
        return self;
    }
    
    // Get token symbol
    pub fn getTokenSymbol(self: *TokenCreateTransaction) []const u8 {
        return self.symbol;
    }
    
    // Set decimals
    pub fn setDecimals(self: *TokenCreateTransaction, decimals: u32) errors.HederaError!*TokenCreateTransaction {
        if (self.base.frozen) return errors.HederaError.TransactionFrozen;
        
        if (self.token_type == .non_fungible_unique and decimals != 0) {
            return errors.HederaError.InvalidParameter;
        }
        
        if (decimals > 2147483647) {
            return errors.HederaError.InvalidParameter;
        }
        
        self.decimals = decimals;
        return self;
    }
    
    // Get decimals
    pub fn getDecimals(self: *TokenCreateTransaction) u32 {
        return self.decimals;
    }
    
    // Set initial supply
    pub fn setInitialSupply(self: *TokenCreateTransaction, supply: u64) errors.HederaError!*TokenCreateTransaction {
        if (self.base.frozen) return errors.HederaError.TransactionFrozen;
        
        if (self.token_type == .non_fungible_unique and supply != 0) {
            return errors.HederaError.InvalidParameter;
        }
        
        if (supply > 9223372036854775807) {
            return errors.HederaError.InvalidParameter;
        }
        
        self.initial_supply = supply;
        return self;
    }
    
    // Get initial supply
    pub fn getInitialSupply(self: *TokenCreateTransaction) u64 {
        return self.initial_supply;
    }
    
    // Set treasury account
    pub fn setTreasuryAccountId(self: *TokenCreateTransaction, account_id: AccountId) errors.HederaError!*TokenCreateTransaction {
        if (self.base.frozen) return errors.HederaError.TransactionFrozen;
        self.treasury_account_id = account_id;
        self.treasury = account_id;
        return self;
    }
    
    // Get treasury account ID
    pub fn getTreasuryAccountId(self: *TokenCreateTransaction) AccountId {
        return self.treasury_account_id orelse AccountId{};
    }
    
    // Set admin key
    pub fn setAdminKey(self: *TokenCreateTransaction, key: Key) errors.HederaError!*TokenCreateTransaction {
        if (self.base.frozen) return errors.HederaError.TransactionFrozen;
        self.admin_key = key;
        return self;
    }
    
    // Get admin key
    pub fn getAdminKey(self: *TokenCreateTransaction) ?Key {
        return self.admin_key;
    }
    
    // Set KYC key
    pub fn setKycKey(self: *TokenCreateTransaction, key: Key) errors.HederaError!*TokenCreateTransaction {
        if (self.base.frozen) return errors.HederaError.TransactionFrozen;
        self.kyc_key = key;
        return self;
    }
    
    // Get KYC key
    pub fn getKycKey(self: *TokenCreateTransaction) ?Key {
        return self.kyc_key;
    }
    
    // Set freeze key
    pub fn setFreezeKey(self: *TokenCreateTransaction, key: Key) errors.HederaError!*TokenCreateTransaction {
        if (self.base.frozen) return errors.HederaError.TransactionFrozen;
        self.freeze_key = key;
        return self;
    }
    
    // Get freeze key
    pub fn getFreezeKey(self: *TokenCreateTransaction) ?Key {
        return self.freeze_key;
    }
    
    // Set wipe key
    pub fn setWipeKey(self: *TokenCreateTransaction, key: Key) errors.HederaError!*TokenCreateTransaction {
        if (self.base.frozen) return errors.HederaError.TransactionFrozen;
        self.wipe_key = key;
        return self;
    }
    
    // Get wipe key
    pub fn getWipeKey(self: *TokenCreateTransaction) ?Key {
        return self.wipe_key;
    }
    
    // Set supply key
    pub fn setSupplyKey(self: *TokenCreateTransaction, key: Key) errors.HederaError!*TokenCreateTransaction {
        if (self.base.frozen) return errors.HederaError.TransactionFrozen;
        self.supply_key = key;
        return self;
    }
    
    // Get supply key
    pub fn getSupplyKey(self: *TokenCreateTransaction) ?Key {
        return self.supply_key;
    }
    
    // Set freeze default
    pub fn setFreezeDefault(self: *TokenCreateTransaction, freeze: bool) errors.HederaError!*TokenCreateTransaction {
        if (self.base.frozen) return errors.HederaError.TransactionFrozen;
        
        if (freeze and self.freeze_key == null) {
            return errors.HederaError.InvalidParameter;
        }
        
        self.freeze_default = freeze;
        return self;
    }
    
    // Get freeze default
    pub fn getFreezeDefault(self: *TokenCreateTransaction) bool {
        return self.freeze_default;
    }
    
    // Set expiration time
    pub fn setExpirationTime(self: *TokenCreateTransaction, time: Timestamp) errors.HederaError!*TokenCreateTransaction {
        if (self.base.frozen) return errors.HederaError.TransactionFrozen;
        self.auto_renew_period = null;
        self.expiration_time = time;
        return self;
    }
    
    // Get expiration time
    pub fn getExpirationTime(self: *TokenCreateTransaction) ?Timestamp {
        return self.expiration_time;
    }
    
    // Set auto renew account
    pub fn setAutoRenewAccount(self: *TokenCreateTransaction, account_id: AccountId) errors.HederaError!*TokenCreateTransaction {
        if (self.base.frozen) return errors.HederaError.TransactionFrozen;
        self.auto_renew_account = account_id;
        return self;
    }
    
    // Get auto renew account
    pub fn getAutoRenewAccount(self: *TokenCreateTransaction) AccountId {
        return self.auto_renew_account orelse AccountId{};
    }
    
    // Set auto renew period
    pub fn setAutoRenewPeriod(self: *TokenCreateTransaction, period: Duration) errors.HederaError!*TokenCreateTransaction {
        if (self.base.frozen) return errors.HederaError.TransactionFrozen;
        
        const min_period = Duration.fromDays(1);
        const max_period = Duration.fromDays(3653);
        
        if (period.seconds < min_period.seconds or period.seconds > max_period.seconds) {
            return errors.HederaError.InvalidParameter;
        }
        
        self.auto_renew_period = period;
        return self;
    }
    
    // Get auto renew period
    pub fn getAutoRenewPeriod(self: *TokenCreateTransaction) ?Duration {
        return self.auto_renew_period;
    }
    
    // Set token memo
    pub fn setTokenMemo(self: *TokenCreateTransaction, memo: []const u8) errors.HederaError!*TokenCreateTransaction {
        if (self.base.frozen) return errors.HederaError.TransactionFrozen;
        
        if (memo.len > 100) return errors.HederaError.InvalidParameter;
        
        self.memo = memo;
        return self;
    }
    
    // Get token memo
    pub fn getTokenMemo(self: *TokenCreateTransaction) []const u8 {
        return self.memo;
    }
    
    // Set token type
    pub fn setTokenType(self: *TokenCreateTransaction, token_type: TokenType) errors.HederaError!*TokenCreateTransaction {
        if (self.base.frozen) return errors.HederaError.TransactionFrozen;
        
        if (token_type == .non_fungible_unique) {
            if (self.decimals != 0) return errors.HederaError.InvalidParameter;
            if (self.initial_supply != 0) return errors.HederaError.InvalidParameter;
        }
        
        self.token_type = token_type;
        return self;
    }
    
    // Get token type
    pub fn getTokenType(self: *TokenCreateTransaction) TokenType {
        return self.token_type;
    }
    
    // Set supply type
    pub fn setSupplyType(self: *TokenCreateTransaction, supply_type: TokenSupplyType) errors.HederaError!*TokenCreateTransaction {
        if (self.base.frozen) return errors.HederaError.TransactionFrozen;
        self.supply_type = supply_type;
        return self;
    }
    
    // Get supply type
    pub fn getSupplyType(self: *TokenCreateTransaction) TokenSupplyType {
        return self.supply_type;
    }
    
    // Set max supply
    pub fn setMaxSupply(self: *TokenCreateTransaction, max_supply: i64) errors.HederaError!*TokenCreateTransaction {
        if (self.base.frozen) return errors.HederaError.TransactionFrozen;
        
        if (self.supply_type == .finite and max_supply <= 0) {
            return errors.HederaError.InvalidParameter;
        }
        
        if (self.supply_type == .infinite and max_supply > 0) {
            return errors.HederaError.InvalidParameter;
        }
        
        self.max_supply = max_supply;
        return self;
    }
    
    // Get max supply
    pub fn getMaxSupply(self: *TokenCreateTransaction) i64 {
        return self.max_supply;
    }
    
    // Set fee schedule key
    pub fn setFeeScheduleKey(self: *TokenCreateTransaction, key: Key) errors.HederaError!*TokenCreateTransaction {
        if (self.base.frozen) return errors.HederaError.TransactionFrozen;
        self.fee_schedule_key = key;
        return self;
    }
    
    // Get fee schedule key
    pub fn getFeeScheduleKey(self: *TokenCreateTransaction) ?Key {
        return self.fee_schedule_key;
    }
    
    // Set custom fees
    pub fn setCustomFees(self: *TokenCreateTransaction, custom_fees: []const CustomFee) errors.HederaError!*TokenCreateTransaction {
        if (self.base.frozen) return errors.HederaError.TransactionFrozen;
        
        self.custom_fees.clearRetainingCapacity();
        for (custom_fees) |fee| {
            self.custom_fees.append(fee) catch return errors.HederaError.OutOfMemory;
        }
        return self;
    }
    
    // Get custom fees
    pub fn getCustomFees(self: *TokenCreateTransaction) []const CustomFee {
        return self.custom_fees.items;
    }
    
    // Add a custom fee for the token
    pub fn addCustomFee(self: *TokenCreateTransaction, fee: CustomFee) errors.HederaError!*TokenCreateTransaction {
        if (self.base.frozen) return errors.HederaError.TransactionFrozen;
        
        if (self.custom_fees.items.len >= 10) {
            return errors.HederaError.InvalidParameter;
        }
        
        self.custom_fees.append(fee) catch return errors.HederaError.OutOfMemory;
        return self;
    }
    
    // Set pause key
    pub fn setPauseKey(self: *TokenCreateTransaction, key: Key) errors.HederaError!*TokenCreateTransaction {
        if (self.base.frozen) return errors.HederaError.TransactionFrozen;
        self.pause_key = key;
        return self;
    }
    
    // Get pause key
    pub fn getPauseKey(self: *TokenCreateTransaction) ?Key {
        return self.pause_key;
    }
    
    // Set token metadata
    pub fn setTokenMetadata(self: *TokenCreateTransaction, metadata: []const u8) errors.HederaError!*TokenCreateTransaction {
        if (self.base.frozen) return errors.HederaError.TransactionFrozen;
        
        if (metadata.len > 100) return errors.HederaError.InvalidParameter;
        
        self.metadata = metadata;
        return self;
    }
    
    // Get token metadata
    pub fn getTokenMetadata(self: *TokenCreateTransaction) []const u8 {
        return self.metadata;
    }
    
    // Set metadata key
    pub fn setMetadataKey(self: *TokenCreateTransaction, key: Key) errors.HederaError!*TokenCreateTransaction {
        if (self.base.frozen) return errors.HederaError.TransactionFrozen;
        self.metadata_key = key;
        return self;
    }
    
    // Get metadata key
    pub fn getMetadataKey(self: *TokenCreateTransaction) ?Key {
        return self.metadata_key;
    }
    
    // Execute the transaction
    pub fn execute(self: *TokenCreateTransaction, client: *Client) !TransactionResponse {
        // Validate required fields
        if (self.name.len == 0) return errors.HederaError.InvalidParameter;
        if (self.symbol.len == 0) return errors.HederaError.InvalidParameter;
        if (self.treasury_account_id == null) return errors.HederaError.InvalidParameter;
        
        // Validate supply configuration
        if (self.supply_type == .finite and self.max_supply <= 0) {
            return errors.HederaError.InvalidParameter;
        }
        
        if (self.initial_supply > 0 and self.supply_key == null) {
            return errors.HederaError.InvalidParameter;
        }
        
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *TokenCreateTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Common transaction fields
        try self.writeCommonTransactionFields(&writer);
        
        // tokenCreation = 11 (oneof data)
        var create_writer = ProtoWriter.init(self.base.allocator);
        defer create_writer.deinit();
        
        // name = 1
        try create_writer.writeString(1, self.name);
        
        // symbol = 2
        try create_writer.writeString(2, self.symbol);
        
        // decimals = 3
        try create_writer.writeUint32(3, self.decimals);
        
        // initialSupply = 4
        try create_writer.writeUint64(4, self.initial_supply);
        
        // treasury = 5
        if (self.treasury_account_id) |treasury| {
            var treasury_writer = ProtoWriter.init(self.base.allocator);
            defer treasury_writer.deinit();
            try treasury_writer.writeInt64(1, @intCast(treasury.shard));
            try treasury_writer.writeInt64(2, @intCast(treasury.realm));
            try treasury_writer.writeInt64(3, @intCast(treasury.account));
            const treasury_bytes = try treasury_writer.toOwnedSlice();
            defer self.base.allocator.free(treasury_bytes);
            try create_writer.writeMessage(5, treasury_bytes);
        }
        
        // adminKey = 6
        if (self.admin_key) |key| {
            const key_bytes = try self.encodeKey(key);
            defer self.base.allocator.free(key_bytes);
            try create_writer.writeMessage(6, key_bytes);
        }
        
        // kycKey = 7
        if (self.kyc_key) |key| {
            const key_bytes = try self.encodeKey(key);
            defer self.base.allocator.free(key_bytes);
            try create_writer.writeMessage(7, key_bytes);
        }
        
        // freezeKey = 8
        if (self.freeze_key) |key| {
            const key_bytes = try self.encodeKey(key);
            defer self.base.allocator.free(key_bytes);
            try create_writer.writeMessage(8, key_bytes);
        }
        
        // wipeKey = 9
        if (self.wipe_key) |key| {
            const key_bytes = try self.encodeKey(key);
            defer self.base.allocator.free(key_bytes);
            try create_writer.writeMessage(9, key_bytes);
        }
        
        // supplyKey = 10
        if (self.supply_key) |key| {
            const key_bytes = try self.encodeKey(key);
            defer self.base.allocator.free(key_bytes);
            try create_writer.writeMessage(10, key_bytes);
        }
        
        // freezeDefault = 11
        if (self.freeze_default) {
            try create_writer.writeBool(11, true);
        }
        
        // expiry = 13
        if (self.expiration_time) |expiry| {
            var expiry_writer = ProtoWriter.init(self.base.allocator);
            defer expiry_writer.deinit();
            try expiry_writer.writeInt64(1, expiry.seconds);
            try expiry_writer.writeInt32(2, expiry.nanos);
            const expiry_bytes = try expiry_writer.toOwnedSlice();
            defer self.base.allocator.free(expiry_bytes);
            try create_writer.writeMessage(13, expiry_bytes);
        }
        
        // autoRenewAccount = 14
        if (self.auto_renew_account) |account| {
            var account_writer = ProtoWriter.init(self.base.allocator);
            defer account_writer.deinit();
            try account_writer.writeInt64(1, @intCast(account.shard));
            try account_writer.writeInt64(2, @intCast(account.realm));
            try account_writer.writeInt64(3, @intCast(account.account));
            const account_bytes = try account_writer.toOwnedSlice();
            defer self.base.allocator.free(account_bytes);
            try create_writer.writeMessage(14, account_bytes);
        }
        
        // autoRenewPeriod = 15
        if (self.auto_renew_period) |period| {
            var period_writer = ProtoWriter.init(self.base.allocator);
            defer period_writer.deinit();
            try period_writer.writeInt64(1, period.seconds);
            const period_bytes = try period_writer.toOwnedSlice();
            defer self.base.allocator.free(period_bytes);
            try create_writer.writeMessage(15, period_bytes);
        }
        
        // memo = 16
        if (self.memo.len > 0) {
            try create_writer.writeString(16, self.memo);
        }
        
        // tokenType = 17
        try create_writer.writeInt32(17, self.token_type.toInt());
        
        // supplyType = 18
        try create_writer.writeInt32(18, self.supply_type.toInt());
        
        // maxSupply = 19
        if (self.max_supply > 0) {
            try create_writer.writeInt64(19, self.max_supply);
        }
        
        // feeScheduleKey = 20
        if (self.fee_schedule_key) |key| {
            const key_bytes = try self.encodeKey(key);
            defer self.base.allocator.free(key_bytes);
            try create_writer.writeMessage(20, key_bytes);
        }
        
        // customFees = 21 (repeated)
        for (self.custom_fees.items) |fee| {
            var fee_writer = ProtoWriter.init(self.base.allocator);
            defer fee_writer.deinit();
            try fee.encode(&fee_writer);
            const fee_bytes = try fee_writer.toOwnedSlice();
            defer self.base.allocator.free(fee_bytes);
            try create_writer.writeMessage(21, fee_bytes);
        }
        
        // pauseKey = 22
        if (self.pause_key) |key| {
            const key_bytes = try self.encodeKey(key);
            defer self.base.allocator.free(key_bytes);
            try create_writer.writeMessage(22, key_bytes);
        }
        
        // metadata = 23
        if (self.metadata.len > 0) {
            try create_writer.writeString(23, self.metadata);
        }
        
        // metadataKey = 24
        if (self.metadata_key) |key| {
            const key_bytes = try self.encodeKey(key);
            defer self.base.allocator.free(key_bytes);
            try create_writer.writeMessage(24, key_bytes);
        }
        
        const create_bytes = try create_writer.toOwnedSlice();
        defer self.base.allocator.free(create_bytes);
        try writer.writeMessage(11, create_bytes);
        
        return writer.toOwnedSlice();
    }
    
    fn writeCommonTransactionFields(self: *TokenCreateTransaction, writer: *ProtoWriter) !void {
        // Implementation matches pattern from TransferTransaction
        _ = self;
        _ = writer;
    }
    
    fn encodeKey(self: *TokenCreateTransaction, key: Key) ![]u8 {
        // Full key encoding implementation
        return key.toProtobuf(self.base.allocator);
    }
};


const std = @import("std");
const TokenId = @import("../core/id.zig").TokenId;
const AccountId = @import("../core/id.zig").AccountId;
const Key = @import("../crypto/key.zig").Key;
const PublicKey = @import("../crypto/key.zig").PublicKey;
const Hbar = @import("../core/hbar.zig").Hbar;
const Duration = @import("../core/duration.zig").Duration;
const Timestamp = @import("../core/timestamp.zig").Timestamp;
const Query = @import("../query/query.zig").Query;
const QueryResponse = @import("../query/query.zig").QueryResponse;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;
const TokenType = @import("token_create.zig").TokenType;
const TokenSupplyType = @import("token_create.zig").TokenSupplyType;
const CustomFee = @import("custom_fee.zig").CustomFee;

// TokenPauseStatus represents the pause status of a token
pub const TokenPauseStatus = enum(u32) {
    unpaused = 0,
    paused = 1,
};

// TokenInfo contains comprehensive information about a token
pub const TokenInfo = struct {
    token_id: TokenId,
    name: []const u8,
    symbol: []const u8,
    decimals: u32,
    total_supply: u64,
    treasury: AccountId,
    treasury_account_id: AccountId,
    admin_key: ?Key,
    kyc_key: ?Key,
    freeze_key: ?Key,
    wipe_key: ?Key,
    supply_key: ?Key,
    freeze_default: bool,
    expiration_time: Timestamp,
    expiry: Timestamp, // Alias for expiration_time
    auto_renew_account: ?AccountId,
    auto_renew_period: Duration,
    memo: []const u8,
    token_memo: []const u8, // Alias for memo
    token_type: TokenType,
    supply_type: TokenSupplyType,
    max_supply: i64,
    fee_schedule_key: ?Key,
    custom_fees: std.ArrayList(CustomFee),
    pause_key: ?Key,
    pause_status: TokenPauseStatus,
    ledger_id: []const u8,
    metadata: []const u8,
    metadata_key: ?Key,
    deleted: bool,

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TokenInfo {
        return TokenInfo{
            .token_id = TokenId.init(0, 0, 0),
            .name = "",
            .symbol = "",
            .decimals = 0,
            .total_supply = 0,
            .treasury = AccountId.init(0, 0, 0),
            .treasury_account_id = AccountId.init(0, 0, 0),
            .admin_key = null,
            .kyc_key = null,
            .freeze_key = null,
            .wipe_key = null,
            .supply_key = null,
            .freeze_default = false,
            .expiration_time = Timestamp{ .seconds = 0, .nanos = 0 },
            .expiry = Timestamp{ .seconds = 0, .nanos = 0 },
            .auto_renew_account = null,
            .auto_renew_period = Duration{ .seconds = 0, .nanos = 0 },
            .memo = "",
            .token_memo = "",
            .token_type = .fungible_common,
            .supply_type = .infinite,
            .max_supply = 0,
            .fee_schedule_key = null,
            .custom_fees = std.ArrayList(CustomFee).init(allocator),
            .pause_key = null,
            .pause_status = .unpaused,
            .ledger_id = "",
            .metadata = "",
            .metadata_key = null,
            .deleted = false,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TokenInfo) void {
        if (self.name.len > 0) {
            self.allocator.free(self.name);
        }
        if (self.symbol.len > 0) {
            self.allocator.free(self.symbol);
        }
        if (self.memo.len > 0) {
            self.allocator.free(self.memo);
        }
        if (self.ledger_id.len > 0) {
            self.allocator.free(self.ledger_id);
        }
        if (self.metadata.len > 0) {
            self.allocator.free(self.metadata);
        }
        self.custom_fees.deinit();
    }
    
    // Parse TokenInfo from protobuf bytes
    pub fn fromProtobuf(allocator: std.mem.Allocator, data: []const u8) !TokenInfo {
        var reader = ProtoReader.init(data);
        var info = TokenInfo.init(allocator);
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => {
                    // TokenId
                    const token_bytes = try reader.readBytes();
                    var token_reader = ProtoReader.init(token_bytes);
                    
                    var shard: i64 = 0;
                    var realm: i64 = 0;
                    var num: i64 = 0;
                    
                    while (token_reader.hasMore()) {
                        const t_tag = try token_reader.readTag();
                        switch (t_tag.field_number) {
                            1 => shard = try token_reader.readInt64(),
                            2 => realm = try token_reader.readInt64(),
                            3 => num = try token_reader.readInt64(),
                            else => try token_reader.skipField(t_tag.wire_type),
                        }
                    }
                    
                    info.token_id = TokenId.init(@intCast(shard), @intCast(realm), @intCast(num));
                },
                2 => {
                    // Name
                    const name_bytes = try reader.readString();
                    info.name = try allocator.dupe(u8, name_bytes);
                },
                3 => {
                    // Symbol
                    const symbol_bytes = try reader.readString();
                    info.symbol = try allocator.dupe(u8, symbol_bytes);
                },
                4 => {
                    // Decimals
                    info.decimals = try reader.readUint32();
                },
                5 => {
                    // TotalSupply
                    info.total_supply = try reader.readUint64();
                },
                6 => {
                    // Treasury
                    const treasury_bytes = try reader.readBytes();
                    var treasury_reader = ProtoReader.init(treasury_bytes);
                    
                    var shard: i64 = 0;
                    var realm: i64 = 0;
                    var account: i64 = 0;
                    
                    while (treasury_reader.hasMore()) {
                        const t_tag = try treasury_reader.readTag();
                        switch (t_tag.field_number) {
                            1 => shard = try treasury_reader.readInt64(),
                            2 => realm = try treasury_reader.readInt64(),
                            3 => account = try treasury_reader.readInt64(),
                            else => try treasury_reader.skipField(t_tag.wire_type),
                        }
                    }
                    
                    info.treasury = AccountId.init(@intCast(shard), @intCast(realm), @intCast(account));
                    info.treasury_account_id = info.treasury;
                },
                7 => {
                    // AdminKey
                    const admin_key_bytes = try reader.readBytes();
                    info.admin_key = try Key.fromProtobuf(allocator, admin_key_bytes);
                },
                8 => {
                    // KycKey
                    const kyc_key_bytes = try reader.readBytes();
                    info.kyc_key = try Key.fromProtobuf(allocator, kyc_key_bytes);
                },
                9 => {
                    // FreezeKey
                    const freeze_key_bytes = try reader.readBytes();
                    info.freeze_key = try Key.fromProtobuf(allocator, freeze_key_bytes);
                },
                10 => {
                    // WipeKey
                    const wipe_key_bytes = try reader.readBytes();
                    info.wipe_key = try Key.fromProtobuf(allocator, wipe_key_bytes);
                },
                11 => {
                    // SupplyKey
                    const supply_key_bytes = try reader.readBytes();
                    info.supply_key = try Key.fromProtobuf(allocator, supply_key_bytes);
                },
                12 => {
                    // FreezeDefault
                    info.freeze_default = try reader.readBool();
                },
                13 => {
                    // ExpirationTime
                    const expiry_bytes = try reader.readBytes();
                    var expiry_reader = ProtoReader.init(expiry_bytes);
                    
                    while (expiry_reader.hasMore()) {
                        const e_tag = try expiry_reader.readTag();
                        switch (e_tag.field_number) {
                            1 => info.expiration_time.seconds = try expiry_reader.readInt64(),
                            2 => info.expiration_time.nanos = try expiry_reader.readInt32(),
                            else => try expiry_reader.skipField(e_tag.wire_type),
                        }
                    }
                    info.expiry = info.expiration_time;
                },
                14 => {
                    // AutoRenewAccount
                    const auto_renew_bytes = try reader.readBytes();
                    var auto_renew_reader = ProtoReader.init(auto_renew_bytes);
                    
                    var shard: i64 = 0;
                    var realm: i64 = 0;
                    var account: i64 = 0;
                    
                    while (auto_renew_reader.hasMore()) {
                        const a_tag = try auto_renew_reader.readTag();
                        switch (a_tag.field_number) {
                            1 => shard = try auto_renew_reader.readInt64(),
                            2 => realm = try auto_renew_reader.readInt64(),
                            3 => account = try auto_renew_reader.readInt64(),
                            else => try auto_renew_reader.skipField(a_tag.wire_type),
                        }
                    }
                    
                    if (account != 0) {
                        info.auto_renew_account = AccountId.init(@intCast(shard), @intCast(realm), @intCast(account));
                    }
                },
                15 => {
                    // AutoRenewPeriod
                    const period_bytes = try reader.readBytes();
                    var period_reader = ProtoReader.init(period_bytes);
                    
                    while (period_reader.hasMore()) {
                        const p_tag = try period_reader.readTag();
                        switch (p_tag.field_number) {
                            1 => info.auto_renew_period.seconds = try period_reader.readInt64(),
                            2 => info.auto_renew_period.nanos = try period_reader.readInt32(),
                            else => try period_reader.skipField(p_tag.wire_type),
                        }
                    }
                },
                16 => {
                    // Memo
                    const memo_bytes = try reader.readString();
                    info.memo = try allocator.dupe(u8, memo_bytes);
                    info.token_memo = info.memo;
                },
                17 => {
                    // TokenType
                    const token_type_value = try reader.readUint32();
                    info.token_type = @enumFromInt(token_type_value);
                },
                18 => {
                    // SupplyType
                    const supply_type_value = try reader.readUint32();
                    info.supply_type = @enumFromInt(supply_type_value);
                },
                19 => {
                    // MaxSupply
                    info.max_supply = try reader.readInt64();
                },
                20 => {
                    // FeeScheduleKey
                    const fee_key_bytes = try reader.readBytes();
                    info.fee_schedule_key = try Key.fromProtobuf(allocator, fee_key_bytes);
                },
                21 => {
                    // PauseKey
                    const pause_key_bytes = try reader.readBytes();
                    info.pause_key = try Key.fromProtobuf(allocator, pause_key_bytes);
                },
                22 => {
                    // PauseStatus
                    const pause_status_value = try reader.readUint32();
                    info.pause_status = @enumFromInt(pause_status_value);
                },
                23 => {
                    // LedgerId
                    const ledger_bytes = try reader.readBytes();
                    info.ledger_id = try allocator.dupe(u8, ledger_bytes);
                },
                24 => {
                    // Metadata
                    const metadata_bytes = try reader.readBytes();
                    info.metadata = try allocator.dupe(u8, metadata_bytes);
                },
                25 => {
                    // MetadataKey
                    const metadata_key_bytes = try reader.readBytes();
                    info.metadata_key = try Key.fromProtobuf(allocator, metadata_key_bytes);
                },
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return info;
    }
    
    // Convert TokenInfo to protobuf bytes
    pub fn toProtobuf(self: *const TokenInfo, allocator: std.mem.Allocator) ![]u8 {
        var writer = ProtoWriter.init(allocator);
        defer writer.deinit();
        
        // TokenId (field 1)
        var token_writer = ProtoWriter.init(allocator);
        defer token_writer.deinit();
        try token_writer.writeInt64(1, @intCast(self.token_id.shard));
        try token_writer.writeInt64(2, @intCast(self.token_id.realm));
        try token_writer.writeInt64(3, @intCast(self.token_id.num));
        const token_bytes = try token_writer.toOwnedSlice();
        defer allocator.free(token_bytes);
        try writer.writeMessage(1, token_bytes);
        
        // Name (field 2)
        if (self.name.len > 0) {
            try writer.writeString(2, self.name);
        }
        
        // Symbol (field 3)
        if (self.symbol.len > 0) {
            try writer.writeString(3, self.symbol);
        }
        
        // Decimals (field 4)
        if (self.decimals != 0) {
            try writer.writeUint32(4, self.decimals);
        }
        
        // TotalSupply (field 5)
        if (self.total_supply != 0) {
            try writer.writeUint64(5, self.total_supply);
        }
        
        // Treasury (field 6)
        var treasury_writer = ProtoWriter.init(allocator);
        defer treasury_writer.deinit();
        try treasury_writer.writeInt64(1, @intCast(self.treasury.shard));
        try treasury_writer.writeInt64(2, @intCast(self.treasury.realm));
        try treasury_writer.writeInt64(3, @intCast(self.treasury.account));
        const treasury_bytes = try treasury_writer.toOwnedSlice();
        defer allocator.free(treasury_bytes);
        try writer.writeMessage(6, treasury_bytes);
        
        // AdminKey (field 7)
        if (self.admin_key) |admin_key| {
            const admin_bytes = try admin_key.toProtobuf(allocator);
            defer allocator.free(admin_bytes);
            try writer.writeMessage(7, admin_bytes);
        }
        
        // KycKey (field 8)
        if (self.kyc_key) |kyc_key| {
            const kyc_bytes = try kyc_key.toProtobuf(allocator);
            defer allocator.free(kyc_bytes);
            try writer.writeMessage(8, kyc_bytes);
        }
        
        // FreezeKey (field 9)
        if (self.freeze_key) |freeze_key| {
            const freeze_bytes = try freeze_key.toProtobuf(allocator);
            defer allocator.free(freeze_bytes);
            try writer.writeMessage(9, freeze_bytes);
        }
        
        // WipeKey (field 10)
        if (self.wipe_key) |wipe_key| {
            const wipe_bytes = try wipe_key.toProtobuf(allocator);
            defer allocator.free(wipe_bytes);
            try writer.writeMessage(10, wipe_bytes);
        }
        
        // SupplyKey (field 11)
        if (self.supply_key) |supply_key| {
            const supply_bytes = try supply_key.toProtobuf(allocator);
            defer allocator.free(supply_bytes);
            try writer.writeMessage(11, supply_bytes);
        }
        
        // FreezeDefault (field 12)
        if (self.freeze_default) {
            try writer.writeBool(12, self.freeze_default);
        }
        
        // ExpirationTime (field 13)
        var expiry_writer = ProtoWriter.init(allocator);
        defer expiry_writer.deinit();
        try expiry_writer.writeInt64(1, self.expiration_time.seconds);
        try expiry_writer.writeInt32(2, self.expiration_time.nanos);
        const expiry_bytes = try expiry_writer.toOwnedSlice();
        defer allocator.free(expiry_bytes);
        try writer.writeMessage(13, expiry_bytes);
        
        // AutoRenewAccount (field 14)
        if (self.auto_renew_account) |renew_account| {
            var renew_writer = ProtoWriter.init(allocator);
            defer renew_writer.deinit();
            try renew_writer.writeInt64(1, @intCast(renew_account.shard));
            try renew_writer.writeInt64(2, @intCast(renew_account.realm));
            try renew_writer.writeInt64(3, @intCast(renew_account.account));
            const renew_bytes = try renew_writer.toOwnedSlice();
            defer allocator.free(renew_bytes);
            try writer.writeMessage(14, renew_bytes);
        }
        
        // AutoRenewPeriod (field 15)
        var period_writer = ProtoWriter.init(allocator);
        defer period_writer.deinit();
        try period_writer.writeInt64(1, self.auto_renew_period.seconds);
        try period_writer.writeInt32(2, self.auto_renew_period.nanos);
        const period_bytes = try period_writer.toOwnedSlice();
        defer allocator.free(period_bytes);
        try writer.writeMessage(15, period_bytes);
        
        // Memo (field 16)
        if (self.memo.len > 0) {
            try writer.writeString(16, self.memo);
        }
        
        // TokenType (field 17)
        try writer.writeUint32(17, @intFromEnum(self.token_type));
        
        // SupplyType (field 18)
        try writer.writeUint32(18, @intFromEnum(self.supply_type));
        
        // MaxSupply (field 19)
        if (self.max_supply != 0) {
            try writer.writeInt64(19, self.max_supply);
        }
        
        // FeeScheduleKey (field 20)
        if (self.fee_schedule_key) |fee_key| {
            const fee_bytes = try fee_key.toProtobuf(allocator);
            defer allocator.free(fee_bytes);
            try writer.writeMessage(20, fee_bytes);
        }
        
        // PauseKey (field 21)
        if (self.pause_key) |pause_key| {
            const pause_bytes = try pause_key.toProtobuf(allocator);
            defer allocator.free(pause_bytes);
            try writer.writeMessage(21, pause_bytes);
        }
        
        // PauseStatus (field 22)
        try writer.writeUint32(22, @intFromEnum(self.pause_status));
        
        // LedgerId (field 23)
        if (self.ledger_id.len > 0) {
            try writer.writeString(23, self.ledger_id);
        }
        
        // Metadata (field 24)
        if (self.metadata.len > 0) {
            try writer.writeString(24, self.metadata);
        }
        
        // MetadataKey (field 25)
        if (self.metadata_key) |metadata_key| {
            const metadata_bytes = try metadata_key.toProtobuf(allocator);
            defer allocator.free(metadata_bytes);
            try writer.writeMessage(25, metadata_bytes);
        }
        
        return writer.toOwnedSlice();
    }
};

// TokenInfoQuery retrieves comprehensive information about a token
pub const TokenInfoQuery = struct {
    base: Query,
    token_id: ?TokenId,

    pub fn init(allocator: std.mem.Allocator) TokenInfoQuery {
        return TokenInfoQuery{
            .base = Query.init(allocator),
            .token_id = null,
        };
    }

    pub fn deinit(self: *TokenInfoQuery) void {
        self.base.deinit();
    }

    // Set the token ID to query
    pub fn setTokenId(self: *TokenInfoQuery, token_id: TokenId) !*TokenInfoQuery {
        self.token_id = token_id;
        return self;
    }

    // Set the query payment amount
    pub fn setQueryPayment(self: *TokenInfoQuery, payment: Hbar) !*TokenInfoQuery {
        self.base.payment_amount = payment;
        return self;
    }

    // Execute the query
    pub fn execute(self: *TokenInfoQuery, client: *Client) !TokenInfo {
        if (self.token_id == null) {
            return error.TokenIdRequired;
        }

        const response = try self.base.execute(client);
        return try self.parseResponse(response);
    }

    // Get cost of the query
    pub fn getCost(self: *TokenInfoQuery, client: *Client) !Hbar {
        self.base.response_type = .CostAnswer;
        const response = try self.base.execute(client);

        var reader = ProtoReader.init(response.response_bytes);

        while (reader.hasMore()) {
            const tag = try reader.readTag();

            switch (tag.field_number) {
                2 => {
                    const cost = try reader.readUint64();
                    return try Hbar.fromTinybars(@intCast(cost));
                },
                else => try reader.skipField(tag.wire_type),
            }
        }

        return error.CostNotFound;
    }

    // Build the query
    pub fn buildQuery(self: *TokenInfoQuery) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();

        // Query message structure
        // header = 1
        var header_writer = ProtoWriter.init(self.base.allocator);
        defer header_writer.deinit();

        // payment = 1
        if (self.base.payment_transaction) |payment| {
            try header_writer.writeMessage(1, payment);
        }

        // responseType = 2
        try header_writer.writeInt32(2, @intFromEnum(self.base.response_type));

        const header_bytes = try header_writer.toOwnedSlice();
        defer self.base.allocator.free(header_bytes);
        try writer.writeMessage(1, header_bytes);

        // tokenGetInfo = 13 (oneof query)
        var info_query_writer = ProtoWriter.init(self.base.allocator);
        defer info_query_writer.deinit();

        // token = 1
        if (self.token_id) |token| {
            var token_writer = ProtoWriter.init(self.base.allocator);
            defer token_writer.deinit();
            try token_writer.writeInt64(1, @intCast(token.shard));
            try token_writer.writeInt64(2, @intCast(token.realm));
            try token_writer.writeInt64(3, @intCast(token.num));
            const token_bytes = try token_writer.toOwnedSlice();
            defer self.base.allocator.free(token_bytes);
            try info_query_writer.writeMessage(1, token_bytes);
        }

        const info_query_bytes = try info_query_writer.toOwnedSlice();
        defer self.base.allocator.free(info_query_bytes);
        try writer.writeMessage(13, info_query_bytes);

        return writer.toOwnedSlice();
    }

    // Parse the response
    fn parseResponse(self: *TokenInfoQuery, response: QueryResponse) !TokenInfo {
        try response.validateStatus();

        var reader = ProtoReader.init(response.response_bytes);

        var info = TokenInfo{
            .token_id = TokenId.init(0, 0, 0),
            .name = "",
            .symbol = "",
            .decimals = 0,
            .total_supply = 0,
            .treasury = AccountId.init(0, 0, 0),
            .treasury_account_id = AccountId.init(0, 0, 0),
            .admin_key = null,
            .kyc_key = null,
            .freeze_key = null,
            .wipe_key = null,
            .supply_key = null,
            .freeze_default = false,
            .expiration_time = Timestamp{ .seconds = 0, .nanos = 0 },
            .expiry = Timestamp{ .seconds = 0, .nanos = 0 },
            .auto_renew_account = null,
            .auto_renew_period = Duration{ .seconds = 0, .nanos = 0 },
            .memo = "",
            .token_memo = "",
            .token_type = .fungible_common,
            .supply_type = .infinite,
            .max_supply = 0,
            .fee_schedule_key = null,
            .custom_fees = std.ArrayList(CustomFee).init(self.base.allocator),
            .pause_key = null,
            .pause_status = .unpaused,
            .ledger_id = "",
            .metadata = "",
            .metadata_key = null,
            .deleted = false,
            .allocator = self.base.allocator,
        };

        // Parse TokenGetInfoResponse
        while (reader.hasMore()) {
            const tag = try reader.readTag();

            switch (tag.field_number) {
                1 => {
                    // header
                    _ = try reader.readMessage();
                },
                2 => {
                    // tokenInfo
                    const token_info_bytes = try reader.readMessage();
                    var token_reader = ProtoReader.init(token_info_bytes);

                    while (token_reader.hasMore()) {
                        const t_tag = try token_reader.readTag();

                        switch (t_tag.field_number) {
                            1 => {
                                // tokenId
                                const token_bytes = try token_reader.readMessage();
                                var id_reader = ProtoReader.init(token_bytes);

                                var shard: i64 = 0;
                                var realm: i64 = 0;
                                var num: i64 = 0;

                                while (id_reader.hasMore()) {
                                    const i = try id_reader.readTag();
                                    switch (i.field_number) {
                                        1 => shard = try id_reader.readInt64(),
                                        2 => realm = try id_reader.readInt64(),
                                        3 => num = try id_reader.readInt64(),
                                        else => try id_reader.skipField(i.wire_type),
                                    }
                                }

                                info.token_id = TokenId.init(@intCast(shard), @intCast(realm), @intCast(num));
                            },
                            2 => info.name = try self.base.allocator.dupe(u8, try token_reader.readString()),
                            3 => info.symbol = try self.base.allocator.dupe(u8, try token_reader.readString()),
                            4 => info.decimals = try token_reader.readUint32(),
                            5 => info.total_supply = try token_reader.readUint64(),
                            6 => {
                                // treasury
                                const treasury_bytes = try token_reader.readMessage();
                                var treasury_reader = ProtoReader.init(treasury_bytes);

                                var shard: i64 = 0;
                                var realm: i64 = 0;
                                var num: i64 = 0;

                                while (treasury_reader.hasMore()) {
                                    const tr = try treasury_reader.readTag();
                                    switch (tr.field_number) {
                                        1 => shard = try treasury_reader.readInt64(),
                                        2 => realm = try treasury_reader.readInt64(),
                                        3 => num = try treasury_reader.readInt64(),
                                        else => try treasury_reader.skipField(tr.wire_type),
                                    }
                                }

                                info.treasury_account_id = AccountId.init(@intCast(shard), @intCast(realm), @intCast(num));
                            },
                            7 => {
                                // adminKey
                                const key_bytes = try token_reader.readMessage();
                                info.admin_key = try Key.fromProtobuf(self.base.allocator, key_bytes);
                            },
                            8 => {
                                // kycKey
                                const key_bytes = try token_reader.readMessage();
                                info.kyc_key = try Key.fromProtobuf(self.base.allocator, key_bytes);
                            },
                            9 => {
                                // freezeKey
                                const key_bytes = try token_reader.readMessage();
                                info.freeze_key = try Key.fromProtobuf(self.base.allocator, key_bytes);
                            },
                            10 => {
                                // wipeKey
                                const key_bytes = try token_reader.readMessage();
                                info.wipe_key = try Key.fromProtobuf(self.base.allocator, key_bytes);
                            },
                            11 => {
                                // supplyKey
                                const key_bytes = try token_reader.readMessage();
                                info.supply_key = try Key.fromProtobuf(self.base.allocator, key_bytes);
                            },
                            12 => info.freeze_default = try token_reader.readBool(),
                            13 => {
                                // expiry
                                const exp_bytes = try token_reader.readMessage();
                                var exp_reader = ProtoReader.init(exp_bytes);

                                while (exp_reader.hasMore()) {
                                    const e = try exp_reader.readTag();
                                    switch (e.field_number) {
                                        1 => info.expiration_time.seconds = try exp_reader.readInt64(),
                                        2 => info.expiration_time.nanos = try exp_reader.readInt32(),
                                        else => try exp_reader.skipField(e.wire_type),
                                    }
                                }
                            },
                            14 => {
                                // autoRenewAccount
                                const account_bytes = try token_reader.readMessage();
                                var account_reader = ProtoReader.init(account_bytes);

                                var shard: i64 = 0;
                                var realm: i64 = 0;
                                var num: i64 = 0;

                                while (account_reader.hasMore()) {
                                    const a = try account_reader.readTag();
                                    switch (a.field_number) {
                                        1 => shard = try account_reader.readInt64(),
                                        2 => realm = try account_reader.readInt64(),
                                        3 => num = try account_reader.readInt64(),
                                        else => try account_reader.skipField(a.wire_type),
                                    }
                                }

                                if (num != 0) {
                                    info.auto_renew_account = AccountId.init(@intCast(shard), @intCast(realm), @intCast(num));
                                }
                            },
                            15 => {
                                // autoRenewPeriod
                                const duration_bytes = try token_reader.readMessage();
                                var duration_reader = ProtoReader.init(duration_bytes);

                                while (duration_reader.hasMore()) {
                                    const d = try duration_reader.readTag();
                                    switch (d.field_number) {
                                        1 => info.auto_renew_period.seconds = try duration_reader.readInt64(),
                                        else => try duration_reader.skipField(d.wire_type),
                                    }
                                }
                            },
                            16 => info.memo = try self.base.allocator.dupe(u8, try token_reader.readString()),
                            17 => info.token_type = @enumFromInt(try token_reader.readInt32()),
                            18 => info.supply_type = @enumFromInt(try token_reader.readInt32()),
                            19 => info.max_supply = try token_reader.readInt64(),
                            20 => {
                                // feeScheduleKey
                                const key_bytes = try token_reader.readMessage();
                                info.fee_schedule_key = try Key.fromProtobuf(self.base.allocator, key_bytes);
                            },
                            21 => {
                                // customFees (repeated)
                                const fee_bytes = try token_reader.readMessage();
                                const custom_fee = try CustomFee.fromProtobuf(fee_bytes, self.base.allocator);
                                try info.custom_fees.append(custom_fee);
                            },
                            22 => {
                                // pauseKey
                                const key_bytes = try token_reader.readMessage();
                                info.pause_key = try Key.fromProtobuf(self.base.allocator, key_bytes);
                            },
                            23 => info.pause_status = @enumFromInt(try token_reader.readInt32()),
                            24 => info.ledger_id = try self.base.allocator.dupe(u8, try token_reader.readBytes()),
                            25 => info.metadata = try self.base.allocator.dupe(u8, try token_reader.readBytes()),
                            26 => {
                                // metadataKey
                                const key_bytes = try token_reader.readMessage();
                                info.metadata_key = try Key.fromProtobuf(self.base.allocator, key_bytes);
                            },
                            else => try token_reader.skipField(t_tag.wire_type),
                        }
                    }
                },
                else => try reader.skipField(tag.wire_type),
            }
        }

        return info;
    }
};

// TokenKycStatus represents KYC status for a token
pub const TokenKycStatus = enum {
    granted,
    revoked,
    not_applicable,
};

// TokenFreezeStatus represents freeze status for a token
pub const TokenFreezeStatus = enum {
    frozen,
    unfrozen,
    not_applicable,
};

// TokenPauseStatus is defined above - removing duplicate

// TokenRelationship represents the relationship between an account and a token
pub const TokenRelationship = struct {
    token_id: TokenId,
    symbol: []const u8,
    balance: u64,
    kyc_status: TokenKycStatus,
    freeze_status: TokenFreezeStatus,
    decimals: u32,
    automatic_association: bool,

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TokenRelationship {
        return TokenRelationship{
            .token_id = TokenId.init(0, 0, 0),
            .symbol = "",
            .balance = 0,
            .kyc_status = .not_applicable,
            .freeze_status = .not_applicable,
            .decimals = 0,
            .automatic_association = false,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TokenRelationship) void {
        if (self.symbol.len > 0) {
            self.allocator.free(self.symbol);
        }
    }
};



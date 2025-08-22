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
const CustomFee = @import("token_create.zig").CustomFee;

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
    expiry: Timestamp,  // Alias for expiration_time
    auto_renew_account: ?AccountId,
    auto_renew_period: Duration,
    memo: []const u8,
    token_memo: []const u8,  // Alias for memo (Go SDK compatibility)
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
    pub fn setTokenId(self: *TokenInfoQuery, token_id: TokenId) *TokenInfoQuery {
        self.token_id = token_id;
        return self;
    }
    
    // Set the query payment amount
    pub fn setQueryPayment(self: *TokenInfoQuery, payment: Hbar) *TokenInfoQuery {
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
            .token_type = .FungibleCommon,
            .supply_type = .infinite,
            .max_supply = 0,
            .fee_schedule_key = null,
            .custom_fees = std.ArrayList(CustomFee).init(self.base.allocator),
            .pause_key = null,
            .pause_status = .unpaused,
            .ledger_id = "",
            .metadata = "",
            .metadata_key = null,
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
                                info.admin_key = try Key.fromProtobuf(key_bytes, self.base.allocator);
                            },
                            8 => {
                                // kycKey
                                const key_bytes = try token_reader.readMessage();
                                info.kyc_key = try Key.fromProtobuf(key_bytes, self.base.allocator);
                            },
                            9 => {
                                // freezeKey
                                const key_bytes = try token_reader.readMessage();
                                info.freeze_key = try Key.fromProtobuf(key_bytes, self.base.allocator);
                            },
                            10 => {
                                // wipeKey
                                const key_bytes = try token_reader.readMessage();
                                info.wipe_key = try Key.fromProtobuf(key_bytes, self.base.allocator);
                            },
                            11 => {
                                // supplyKey
                                const key_bytes = try token_reader.readMessage();
                                info.supply_key = try Key.fromProtobuf(key_bytes, self.base.allocator);
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
                                info.fee_schedule_key = try Key.fromProtobuf(key_bytes, self.base.allocator);
                            },
                            21 => {
                                // customFees (repeated)
                                const fee_bytes = try token_reader.readMessage();
                                const custom_fee = try CustomFee.decode(fee_bytes, self.base.allocator);
                                try info.custom_fees.append(custom_fee);
                            },
                            22 => {
                                // pauseKey
                                const key_bytes = try token_reader.readMessage();
                                info.pause_key = try Key.fromProtobuf(key_bytes, self.base.allocator);
                            },
                            23 => info.pause_status = @enumFromInt(try token_reader.readInt32()),
                            24 => info.ledger_id = try self.base.allocator.dupe(u8, try token_reader.readBytes()),
                            25 => info.metadata = try self.base.allocator.dupe(u8, try token_reader.readBytes()),
                            26 => {
                                // metadataKey
                                const key_bytes = try token_reader.readMessage();
                                info.metadata_key = try Key.fromProtobuf(key_bytes, self.base.allocator);
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

// TokenPauseStatus represents pause status for a token  
pub const TokenPauseStatus = enum {
    paused,
    unpaused,
    not_applicable,
};

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

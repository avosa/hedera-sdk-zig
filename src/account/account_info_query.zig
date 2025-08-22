const std = @import("std");
const AccountId = @import("../core/id.zig").AccountId;
const PublicKey = @import("../crypto/key.zig").PublicKey;
const Ed25519PublicKey = @import("../crypto/key.zig").Ed25519PublicKey;
const Hbar = @import("../core/hbar.zig").Hbar;
const Duration = @import("../core/duration.zig").Duration;
const Timestamp = @import("../core/timestamp.zig").Timestamp;
const Query = @import("../query/query.zig").Query;
const QueryResponse = @import("../query/query.zig").QueryResponse;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;
const TokenRelationship = @import("../token/token_info_query.zig").TokenRelationship;

// StakingInfo consolidated inside AccountInfoQuery to eliminate redundancy
pub const StakingInfo = struct {
    decline_reward: bool,
    stake_period_start: ?Timestamp,
    pending_reward: i64,
    staked_to_me: i64,
    staked_account_id: ?AccountId,
    staked_node_id: ?i64,
    
    pub fn decode(reader: *ProtoReader, allocator: std.mem.Allocator) !StakingInfo {
        var info = StakingInfo{
            .decline_reward = false,
            .stake_period_start = null,
            .pending_reward = 0,
            .staked_to_me = 0,
            .staked_account_id = null,
            .staked_node_id = null,
        };
        
        _ = allocator;
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => info.decline_reward = try reader.readBool(),
                2 => {
                    const timestamp_bytes = try reader.readMessage();
                    var timestamp_reader = ProtoReader.init(timestamp_bytes);
                    var seconds: i64 = 0;
                    var nanos: i32 = 0;
                    
                    while (timestamp_reader.hasMore()) {
                        const t = try timestamp_reader.readTag();
                        switch (t.field_number) {
                            1 => seconds = try timestamp_reader.readInt64(),
                            2 => nanos = try timestamp_reader.readInt32(),
                            else => try timestamp_reader.skipField(t.wire_type),
                        }
                    }
                    
                    info.stake_period_start = Timestamp{ .seconds = seconds, .nanos = nanos };
                },
                3 => info.pending_reward = try reader.readInt64(),
                4 => info.staked_to_me = try reader.readInt64(),
                5 => {
                    const account_bytes = try reader.readMessage();
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
                    
                    info.staked_account_id = AccountId.init(@intCast(shard), @intCast(realm), @intCast(num));
                },
                6 => info.staked_node_id = try reader.readInt64(),
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return info;
    }
};

// AccountInfo contains comprehensive information about an account
pub const AccountInfo = struct {
    account_id: AccountId,
    contract_account_id: []const u8,
    deleted: bool,
    proxy_account_id: ?AccountId,
    proxy_received: i64,
    key: PublicKey,
    balance: Hbar,
    receiver_signature_required: bool,
    expiration_time: Timestamp,
    auto_renew_period: Duration,
    memo: []const u8,
    owned_nfts: i64,
    max_automatic_token_associations: i32,
    alias: []const u8,
    ledger_id: []const u8,
    ethereum_nonce: i64,
    staking_info: ?StakingInfo,
    token_relationships: std.ArrayList(TokenRelationship),
    
    // Track which string fields were allocated by this struct
    _contract_account_id_allocated: bool,
    _memo_allocated: bool,
    _alias_allocated: bool,
    _ledger_id_allocated: bool,
    
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) AccountInfo {
        return AccountInfo{
            .account_id = AccountId.init(0, 0, 0),
            .contract_account_id = "",
            .deleted = false,
            .proxy_account_id = null,
            .proxy_received = 0,
            .key = PublicKey{ .ed25519 = Ed25519PublicKey{ .bytes = [_]u8{0} ** 32 } },
            .balance = Hbar.zero(),
            .receiver_signature_required = false,
            .expiration_time = Timestamp{ .seconds = 0, .nanos = 0 },
            .auto_renew_period = Duration{ .seconds = 0, .nanos = 0 },
            .memo = "",
            .owned_nfts = 0,
            .max_automatic_token_associations = 0,
            .alias = "",
            .ledger_id = "",
            .ethereum_nonce = 0,
            .staking_info = null,
            .token_relationships = std.ArrayList(TokenRelationship).init(allocator),
            ._contract_account_id_allocated = false,
            ._memo_allocated = false,
            ._alias_allocated = false,
            ._ledger_id_allocated = false,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *AccountInfo) void {
        if (self._contract_account_id_allocated) {
            self.allocator.free(self.contract_account_id);
        }
        if (self._memo_allocated) {
            self.allocator.free(self.memo);
        }
        if (self._alias_allocated) {
            self.allocator.free(self.alias);
        }
        if (self._ledger_id_allocated) {
            self.allocator.free(self.ledger_id);
        }
        self.token_relationships.deinit();
    }
};

// AccountInfoQuery retrieves comprehensive information about an account  
pub const AccountInfoQuery = struct {
    // Use the module-level StakingInfo definition to eliminate redundancy
    
    base: Query,
    account_id: ?AccountId,
    max_retry: u32,
    max_backoff: Duration,
    min_backoff: Duration,
    node_account_ids: std.ArrayList(AccountId),
    
    pub fn init(allocator: std.mem.Allocator) AccountInfoQuery {
        return AccountInfoQuery{
            .base = Query.init(allocator),
            .account_id = null,
            .max_retry = 3,
            .max_backoff = Duration.fromSeconds(8),
            .min_backoff = Duration.fromMillis(250),
            .node_account_ids = std.ArrayList(AccountId).init(allocator),
        };
    }
    
    pub fn deinit(self: *AccountInfoQuery) void {
        self.base.deinit();
        self.node_account_ids.deinit();
    }
    
    // Set the account ID to query
    pub fn setAccountId(self: *AccountInfoQuery, account_id: AccountId) !*AccountInfoQuery {
        self.account_id = account_id;
        return self;
    }
    
    // Set the query payment amount
    pub fn setQueryPayment(self: *AccountInfoQuery, payment: Hbar) !void {
        self.base.payment_amount = payment;
    }
    
    // Set max retry attempts
    pub fn setMaxRetry(self: *AccountInfoQuery, max_retry: u32) void {
        self.max_retry = max_retry;
        self.base.setMaxRetry(max_retry);
    }
    
    // Set max backoff
    pub fn setMaxBackoff(self: *AccountInfoQuery, max_backoff: Duration) void {
        self.max_backoff = max_backoff;
        self.base.setMaxBackoff(max_backoff.toMilliseconds());
    }
    
    pub fn setMinBackoff(self: *AccountInfoQuery, min_backoff: Duration) void {
        self.min_backoff = min_backoff;
        self.base.setMinBackoff(min_backoff.toMilliseconds());
    }
    
    // Set node account IDs
    pub fn setNodeAccountIds(self: *AccountInfoQuery, node_ids: []const AccountId) !void {
        try self.base.setNodeAccountIds(node_ids);
        self.node_account_ids.clearRetainingCapacity();
        for (node_ids) |node_id| {
            try self.node_account_ids.append(node_id);
        }
    }
    
    // Execute the query
    pub fn execute(self: *AccountInfoQuery, client: *Client) !AccountInfo {
        if (self.account_id == null) {
            return error.AccountIdRequired;
        }
        
        const response = try self.base.execute(client);
        return try self.parseResponse(response);
    }
    
    // Get cost of the query
    pub fn getCost(self: *AccountInfoQuery, client: *Client) !Hbar {
        self.base.response_type = .CostAnswer;
        const response = try self.base.execute(client);
        
        var reader = ProtoReader.init(response.response_bytes);
        
        // Parse response to get cost
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                2 => {
                    // cost field
                    const cost = try reader.readUint64();
                    return try Hbar.fromTinybars(@intCast(cost));
                },
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return error.CostNotFound;
    }
    
    // Build the query
    pub fn buildQuery(self: *AccountInfoQuery) ![]u8 {
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
        
        // cryptoGetInfo = 9 (oneof query)
        var info_query_writer = ProtoWriter.init(self.base.allocator);
        defer info_query_writer.deinit();
        
        // accountID = 1
        if (self.account_id) |account| {
            var account_writer = ProtoWriter.init(self.base.allocator);
            defer account_writer.deinit();
            try account_writer.writeInt64(1, @intCast(account.entity.shard));
            try account_writer.writeInt64(2, @intCast(account.entity.realm));
            try account_writer.writeInt64(3, @intCast(account.entity.num));
            
            if (account.alias_key) |alias| {
                try account_writer.writeString(4, alias);
            } else if (account.evm_address) |evm| {
                try account_writer.writeString(4, evm);
            }
            
            const account_bytes = try account_writer.toOwnedSlice();
            defer self.base.allocator.free(account_bytes);
            try info_query_writer.writeMessage(1, account_bytes);
        }
        
        const info_query_bytes = try info_query_writer.toOwnedSlice();
        defer self.base.allocator.free(info_query_bytes);
        try writer.writeMessage(9, info_query_bytes);
        
        return writer.toOwnedSlice();
    }
    
    // Parse the response
    fn parseResponse(self: *AccountInfoQuery, response: QueryResponse) !AccountInfo {
        try response.validateStatus();
        
        var reader = ProtoReader.init(response.response_bytes);
        
        var info = AccountInfo{
            .account_id = AccountId.init(0, 0, 0),
            .contract_account_id = "",
            .deleted = false,
            .proxy_account_id = null,
            .proxy_received = 0,
            .key = undefined,
            .balance = Hbar.zero(),
            .receiver_signature_required = false,
            .expiration_time = Timestamp{ .seconds = 0, .nanos = 0 },
            .auto_renew_period = Duration{ .seconds = 0, .nanos = 0 },
            .memo = "",
            .owned_nfts = 0,
            .max_automatic_token_associations = 0,
            .alias = "",
            .ledger_id = "",
            .ethereum_nonce = 0,
            .staking_info = null,
            .token_relationships = std.ArrayList(TokenRelationship).init(self.base.allocator),
            ._contract_account_id_allocated = false,
            ._memo_allocated = false,
            ._alias_allocated = false,
            ._ledger_id_allocated = false,
            .allocator = self.base.allocator,
        };
        
        // Parse CryptoGetInfoResponse
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => {
                    // header
                    _ = try reader.readMessage();
                },
                2 => {
                    // accountInfo
                    const account_info_bytes = try reader.readMessage();
                    var account_reader = ProtoReader.init(account_info_bytes);
                    
                    while (account_reader.hasMore()) {
                        const a_tag = try account_reader.readTag();
                        
                        switch (a_tag.field_number) {
                            1 => {
                                // accountID
                                const account_bytes = try account_reader.readMessage();
                                var id_reader = ProtoReader.init(account_bytes);
                                
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
                                
                                info.account_id = AccountId.init(@intCast(shard), @intCast(realm), @intCast(num));
                            },
                            2 => {
                                // contractAccountID
                                info.contract_account_id = try self.base.allocator.dupe(u8, try account_reader.readString());
                                info._contract_account_id_allocated = true;
                            },
                            3 => info.deleted = try account_reader.readBool(),
                            4 => {
                                // proxyAccountID
                                const proxy_bytes = try account_reader.readMessage();
                                var proxy_reader = ProtoReader.init(proxy_bytes);
                                
                                var shard: i64 = 0;
                                var realm: i64 = 0;
                                var num: i64 = 0;
                                
                                while (proxy_reader.hasMore()) {
                                    const p = try proxy_reader.readTag();
                                    switch (p.field_number) {
                                        1 => shard = try proxy_reader.readInt64(),
                                        2 => realm = try proxy_reader.readInt64(),
                                        3 => num = try proxy_reader.readInt64(),
                                        else => try proxy_reader.skipField(p.wire_type),
                                    }
                                }
                                
                                if (num != 0) {
                                    info.proxy_account_id = AccountId.init(@intCast(shard), @intCast(realm), @intCast(num));
                                }
                            },
                            5 => info.proxy_received = try account_reader.readInt64(),
                            6 => {
                                // key
                                const key_bytes = try account_reader.readMessage();
                                info.key = try PublicKey.fromProtobuf(key_bytes, self.base.allocator);
                            },
                            7 => {
                                // balance in tinybars
                                const tinybars = try account_reader.readUint64();
                                info.balance = try Hbar.fromTinybars(@intCast(tinybars));
                            },
                            10 => info.receiver_signature_required = try account_reader.readBool(),
                            11 => {
                                // expirationTime
                                const exp_bytes = try account_reader.readMessage();
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
                            12 => {
                                // autoRenewPeriod
                                const duration_bytes = try account_reader.readMessage();
                                var duration_reader = ProtoReader.init(duration_bytes);
                                
                                while (duration_reader.hasMore()) {
                                    const d = try duration_reader.readTag();
                                    switch (d.field_number) {
                                        1 => info.auto_renew_period.seconds = try duration_reader.readInt64(),
                                        else => try duration_reader.skipField(d.wire_type),
                                    }
                                }
                            },
                            16 => {
                                // memo
                                info.memo = try self.base.allocator.dupe(u8, try account_reader.readString());
                                info._memo_allocated = true;
                            },
                            17 => info.owned_nfts = try account_reader.readInt64(),
                            18 => info.max_automatic_token_associations = try account_reader.readInt32(),
                            19 => {
                                // alias
                                info.alias = try self.base.allocator.dupe(u8, try account_reader.readBytes());
                                info._alias_allocated = true;
                            },
                            20 => {
                                // ledger_id
                                info.ledger_id = try self.base.allocator.dupe(u8, try account_reader.readBytes());
                                info._ledger_id_allocated = true;
                            },
                            21 => info.ethereum_nonce = try account_reader.readInt64(),
                            22 => {
                                // staking_info
                                const staking_bytes = try account_reader.readMessage();
                                var staking_reader = ProtoReader.init(staking_bytes);
                                info.staking_info = try StakingInfo.decode(&staking_reader, self.base.allocator);
                            },
                            else => try account_reader.skipField(a_tag.wire_type),
                        }
                    }
                },
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return info;
    }
};
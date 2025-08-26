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
    
    // Parse StakingInfo from protobuf bytes  
    pub fn fromProtobuf(allocator: std.mem.Allocator, data: []const u8) !StakingInfo {
        var reader = ProtoReader.init(data);
        return decode(&reader, allocator);
    }
    
    // Convert StakingInfo to protobuf bytes
    pub fn toProtobuf(self: *const StakingInfo, allocator: std.mem.Allocator) ![]u8 {
        var writer = ProtoWriter.init(allocator);
        defer writer.deinit();
        
        // DeclineReward (field 1)
        if (self.decline_reward) {
            try writer.writeBool(1, self.decline_reward);
        }
        
        // StakePeriodStart (field 2)
        if (self.stake_period_start) |timestamp| {
            var timestamp_writer = ProtoWriter.init(allocator);
            defer timestamp_writer.deinit();
            try timestamp_writer.writeInt64(1, timestamp.seconds);
            try timestamp_writer.writeInt32(2, timestamp.nanos);
            const timestamp_bytes = try timestamp_writer.toOwnedSlice();
            defer allocator.free(timestamp_bytes);
            try writer.writeMessage(2, timestamp_bytes);
        }
        
        // PendingReward (field 3)
        if (self.pending_reward != 0) {
            try writer.writeInt64(3, self.pending_reward);
        }
        
        // StakedToMe (field 4)
        if (self.staked_to_me != 0) {
            try writer.writeInt64(4, self.staked_to_me);
        }
        
        // StakedAccountId (field 5)
        if (self.staked_account_id) |account_id| {
            var account_writer = ProtoWriter.init(allocator);
            defer account_writer.deinit();
            try account_writer.writeInt64(1, @intCast(account_id.shard));
            try account_writer.writeInt64(2, @intCast(account_id.realm));
            try account_writer.writeInt64(3, @intCast(account_id.account));
            const account_bytes = try account_writer.toOwnedSlice();
            defer allocator.free(account_bytes);
            try writer.writeMessage(5, account_bytes);
        }
        
        // StakedNodeId (field 6)
        if (self.staked_node_id) |node_id| {
            try writer.writeInt64(6, node_id);
        }
        
        return writer.toOwnedSlice();
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
    
    // Parse AccountInfo from protobuf bytes
    pub fn fromProtobuf(allocator: std.mem.Allocator, data: []const u8) !AccountInfo {
        var reader = ProtoReader.init(data);
        var info = AccountInfo.init(allocator);
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => {
                    // AccountID
                    const account_bytes = try reader.readBytes();
                    var account_reader = ProtoReader.init(account_bytes);
                    
                    var shard: i64 = 0;
                    var realm: i64 = 0;
                    var account: i64 = 0;
                    
                    while (account_reader.hasMore()) {
                        const a_tag = try account_reader.readTag();
                        switch (a_tag.field_number) {
                            1 => shard = try account_reader.readInt64(),
                            2 => realm = try account_reader.readInt64(),
                            3 => account = try account_reader.readInt64(),
                            else => try account_reader.skipField(a_tag.wire_type),
                        }
                    }
                    
                    info.account_id = AccountId.init(@intCast(shard), @intCast(realm), @intCast(account));
                },
                2 => {
                    // ContractAccountID
                    const contract_id_bytes = try reader.readString();
                    info.contract_account_id = try allocator.dupe(u8, contract_id_bytes);
                    info._contract_account_id_allocated = true;
                },
                3 => {
                    // Deleted
                    info.deleted = try reader.readBool();
                },
                4 => {
                    // ProxyAccountID
                    const proxy_bytes = try reader.readBytes();
                    var proxy_reader = ProtoReader.init(proxy_bytes);
                    
                    var shard: i64 = 0;
                    var realm: i64 = 0;
                    var proxy: i64 = 0;
                    
                    while (proxy_reader.hasMore()) {
                        const p_tag = try proxy_reader.readTag();
                        switch (p_tag.field_number) {
                            1 => shard = try proxy_reader.readInt64(),
                            2 => realm = try proxy_reader.readInt64(),
                            3 => proxy = try proxy_reader.readInt64(),
                            else => try proxy_reader.skipField(p_tag.wire_type),
                        }
                    }
                    
                    if (proxy != 0) {
                        info.proxy_account_id = AccountId.init(@intCast(shard), @intCast(realm), @intCast(proxy));
                    }
                },
                5 => {
                    // ProxyReceived
                    info.proxy_received = try reader.readInt64();
                },
                6 => {
                    // Key
                    const key_bytes = try reader.readBytes();
                    info.key = try PublicKey.fromProtobuf(allocator, key_bytes);
                },
                7 => {
                    // Balance (in tinybars)
                    const balance_tinybars = try reader.readUint64();
                    info.balance = try Hbar.fromTinybars(@intCast(balance_tinybars));
                },
                10 => {
                    // ReceiverSignatureRequired
                    info.receiver_signature_required = try reader.readBool();
                },
                11 => {
                    // ExpirationTime
                    const expiration_bytes = try reader.readBytes();
                    var exp_reader = ProtoReader.init(expiration_bytes);
                    
                    while (exp_reader.hasMore()) {
                        const e_tag = try exp_reader.readTag();
                        switch (e_tag.field_number) {
                            1 => info.expiration_time.seconds = try exp_reader.readInt64(),
                            2 => info.expiration_time.nanos = try exp_reader.readInt32(),
                            else => try exp_reader.skipField(e_tag.wire_type),
                        }
                    }
                },
                12 => {
                    // AutoRenewPeriod
                    const duration_bytes = try reader.readBytes();
                    var dur_reader = ProtoReader.init(duration_bytes);
                    
                    while (dur_reader.hasMore()) {
                        const d_tag = try dur_reader.readTag();
                        switch (d_tag.field_number) {
                            1 => info.auto_renew_period.seconds = try dur_reader.readInt64(),
                            2 => info.auto_renew_period.nanos = try dur_reader.readInt32(),
                            else => try dur_reader.skipField(d_tag.wire_type),
                        }
                    }
                },
                16 => {
                    // Memo
                    const memo_bytes = try reader.readString();
                    info.memo = try allocator.dupe(u8, memo_bytes);
                    info._memo_allocated = true;
                },
                17 => {
                    // OwnedNfts
                    info.owned_nfts = try reader.readInt64();
                },
                18 => {
                    // MaxAutomaticTokenAssociations
                    info.max_automatic_token_associations = try reader.readInt32();
                },
                19 => {
                    // Alias
                    const alias_bytes = try reader.readBytes();
                    info.alias = try allocator.dupe(u8, alias_bytes);
                    info._alias_allocated = true;
                },
                20 => {
                    // LedgerID
                    const ledger_bytes = try reader.readBytes();
                    info.ledger_id = try allocator.dupe(u8, ledger_bytes);
                    info._ledger_id_allocated = true;
                },
                21 => {
                    // EthereumNonce
                    info.ethereum_nonce = try reader.readInt64();
                },
                22 => {
                    // StakingInfo
                    const staking_bytes = try reader.readBytes();
                    var staking_reader = ProtoReader.init(staking_bytes);
                    info.staking_info = try StakingInfo.decode(&staking_reader, allocator);
                },
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return info;
    }
    
    // Convert AccountInfo to protobuf bytes
    pub fn toProtobuf(self: *const AccountInfo, allocator: std.mem.Allocator) ![]u8 {
        var writer = ProtoWriter.init(allocator);
        defer writer.deinit();
        
        // AccountID (field 1)
        var account_writer = ProtoWriter.init(allocator);
        defer account_writer.deinit();
        try account_writer.writeInt64(1, @intCast(self.account_id.shard));
        try account_writer.writeInt64(2, @intCast(self.account_id.realm));
        try account_writer.writeInt64(3, @intCast(self.account_id.account));
        const account_bytes = try account_writer.toOwnedSlice();
        defer allocator.free(account_bytes);
        try writer.writeMessage(1, account_bytes);
        
        // ContractAccountID (field 2)
        if (self.contract_account_id.len > 0) {
            try writer.writeString(2, self.contract_account_id);
        }
        
        // Deleted (field 3)
        if (self.deleted) {
            try writer.writeBool(3, self.deleted);
        }
        
        // ProxyAccountID (field 4)
        if (self.proxy_account_id) |proxy_id| {
            var proxy_writer = ProtoWriter.init(allocator);
            defer proxy_writer.deinit();
            try proxy_writer.writeInt64(1, @intCast(proxy_id.shard));
            try proxy_writer.writeInt64(2, @intCast(proxy_id.realm));
            try proxy_writer.writeInt64(3, @intCast(proxy_id.account));
            const proxy_bytes = try proxy_writer.toOwnedSlice();
            defer allocator.free(proxy_bytes);
            try writer.writeMessage(4, proxy_bytes);
        }
        
        // ProxyReceived (field 5)
        if (self.proxy_received != 0) {
            try writer.writeInt64(5, self.proxy_received);
        }
        
        // Key (field 6)
        const key_bytes = try self.key.toBytes(allocator);
        defer allocator.free(key_bytes);
        try writer.writeMessage(6, key_bytes);
        
        // Balance (field 7) - in tinybars
        try writer.writeUint64(7, @intCast(self.balance.toTinybars()));
        
        // ReceiverSignatureRequired (field 10)
        if (self.receiver_signature_required) {
            try writer.writeBool(10, self.receiver_signature_required);
        }
        
        // ExpirationTime (field 11)
        var expiration_writer = ProtoWriter.init(allocator);
        defer expiration_writer.deinit();
        try expiration_writer.writeInt64(1, self.expiration_time.seconds);
        try expiration_writer.writeInt32(2, self.expiration_time.nanos);
        const expiration_bytes = try expiration_writer.toOwnedSlice();
        defer allocator.free(expiration_bytes);
        try writer.writeMessage(11, expiration_bytes);
        
        // AutoRenewPeriod (field 12)
        var duration_writer = ProtoWriter.init(allocator);
        defer duration_writer.deinit();
        try duration_writer.writeInt64(1, self.auto_renew_period.seconds);
        try duration_writer.writeInt32(2, self.auto_renew_period.nanos);
        const duration_bytes = try duration_writer.toOwnedSlice();
        defer allocator.free(duration_bytes);
        try writer.writeMessage(12, duration_bytes);
        
        // Memo (field 16)
        if (self.memo.len > 0) {
            try writer.writeString(16, self.memo);
        }
        
        // OwnedNfts (field 17)
        if (self.owned_nfts != 0) {
            try writer.writeInt64(17, self.owned_nfts);
        }
        
        // MaxAutomaticTokenAssociations (field 18)
        if (self.max_automatic_token_associations != 0) {
            try writer.writeInt32(18, self.max_automatic_token_associations);
        }
        
        // Alias (field 19)
        if (self.alias.len > 0) {
            try writer.writeString(19, self.alias);
        }
        
        // LedgerID (field 20)
        if (self.ledger_id.len > 0) {
            try writer.writeString(20, self.ledger_id);
        }
        
        // EthereumNonce (field 21)
        if (self.ethereum_nonce != 0) {
            try writer.writeInt64(21, self.ethereum_nonce);
        }
        
        // StakingInfo (field 22)
        if (self.staking_info) |staking_info| {
            const staking_bytes = try staking_info.toProtobuf(allocator);
            defer allocator.free(staking_bytes);
            try writer.writeMessage(22, staking_bytes);
        }
        
        return writer.toOwnedSlice();
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
    pub fn setQueryPayment(self: *AccountInfoQuery, payment: Hbar) !*AccountInfoQuery {
        self.base.payment_amount = payment;
        return self;
    }
    
    // Set max retry attempts
    pub fn setMaxRetry(self: *AccountInfoQuery, max_retry: u32) !*AccountInfoQuery {
        self.max_retry = max_retry;
        _ = try self.base.setMaxRetry(max_retry);
        return self;
    }
    
    // Set max backoff
    pub fn setMaxBackoff(self: *AccountInfoQuery, max_backoff: Duration) !*AccountInfoQuery {
        self.max_backoff = max_backoff;
        _ = try self.base.setMaxBackoff(max_backoff.toMilliseconds());
        return self;
    }
    
    pub fn setMinBackoff(self: *AccountInfoQuery, min_backoff: Duration) !*AccountInfoQuery {
        self.min_backoff = min_backoff;
        _ = try self.base.setMinBackoff(min_backoff.toMilliseconds());
        return self;
    }
    
    // Set node account IDs
    pub fn setNodeAccountIds(self: *AccountInfoQuery, node_ids: []const AccountId) !*AccountInfoQuery {
        _ = try self.base.setNodeAccountIds(node_ids);
        self.node_account_ids.clearRetainingCapacity();
        for (node_ids) |node_id| {
            try self.node_account_ids.append(node_id);
        }
        return self;
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
            try account_writer.writeInt64(1, @intCast(account.shard));
            try account_writer.writeInt64(2, @intCast(account.realm));
            try account_writer.writeInt64(3, @intCast(account.account));
            
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
                                info.key = try PublicKey.fromProtobuf(self.base.allocator, key_bytes);
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
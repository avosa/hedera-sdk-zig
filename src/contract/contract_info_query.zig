const std = @import("std");
const ContractId = @import("../core/id.zig").ContractId;
const AccountId = @import("../core/id.zig").AccountId;
const Key = @import("../crypto/key.zig").Key;
const Timestamp = @import("../core/timestamp.zig").Timestamp;
const Duration = @import("../core/duration.zig").Duration;
const Query = @import("../query/query.zig").Query;
const QueryResponse = @import("../query/query.zig").QueryResponse;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;
const Hbar = @import("../core/hbar.zig").Hbar;

// ContractInfo contains information about a smart contract
pub const ContractInfo = struct {
    contract_id: ContractId,
    account_id: AccountId,
    contract_account_id: []const u8,
    admin_key: ?Key,
    expiration_time: Timestamp,
    auto_renew_period: Duration,
    storage: i64,
    memo: []const u8,
    balance: u64,
    deleted: bool,
    evm_address: []const u8,
    auto_renew_account_id: ?AccountId,
    max_automatic_token_associations: i32,
    ledger_id: []const u8,
    staking_info: ?StakingInfo,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ContractInfo {
        return ContractInfo{
            .contract_id = ContractId.init(0, 0, 0),
            .account_id = AccountId.init(0, 0, 0),
            .contract_account_id = "",
            .admin_key = null,
            .expiration_time = Timestamp{ .seconds = 0, .nanos = 0 },
            .auto_renew_period = Duration{ .seconds = 0, .nanos = 0 },
            .storage = 0,
            .memo = "",
            .balance = 0,
            .deleted = false,
            .evm_address = "",
            .auto_renew_account_id = null,
            .max_automatic_token_associations = 0,
            .ledger_id = "",
            .staking_info = null,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ContractInfo) void {
        if (self.contract_account_id.len > 0) {
            self.allocator.free(self.contract_account_id);
        }
        if (self.memo.len > 0) {
            self.allocator.free(self.memo);
        }
        if (self.evm_address.len > 0) {
            self.allocator.free(self.evm_address);
        }
        if (self.ledger_id.len > 0) {
            self.allocator.free(self.ledger_id);
        }
        // Key is a union, no deinit needed
    }
    
    // Parse ContractInfo from protobuf bytes
    pub fn fromProtobuf(allocator: std.mem.Allocator, data: []const u8) !ContractInfo {
        var reader = ProtoReader.init(data);
        var info = ContractInfo.init(allocator);
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => {
                    // ContractId
                    const contract_bytes = try reader.readBytes();
                    var contract_reader = ProtoReader.init(contract_bytes);
                    
                    var shard: i64 = 0;
                    var realm: i64 = 0;
                    var num: i64 = 0;
                    
                    while (contract_reader.hasMore()) {
                        const c_tag = try contract_reader.readTag();
                        switch (c_tag.field_number) {
                            1 => shard = try contract_reader.readInt64(),
                            2 => realm = try contract_reader.readInt64(),
                            3 => num = try contract_reader.readInt64(),
                            else => try contract_reader.skipField(c_tag.wire_type),
                        }
                    }
                    
                    info.contract_id = ContractId.init(@intCast(shard), @intCast(realm), @intCast(num));
                },
                2 => {
                    // AccountId
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
                3 => {
                    // ContractAccountId
                    const contract_account_bytes = try reader.readString();
                    info.contract_account_id = try allocator.dupe(u8, contract_account_bytes);
                },
                4 => {
                    // AdminKey
                    const admin_key_bytes = try reader.readBytes();
                    info.admin_key = try Key.fromProtobuf(allocator, admin_key_bytes);
                },
                5 => {
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
                },
                6 => {
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
                7 => {
                    // Storage
                    info.storage = try reader.readInt64();
                },
                8 => {
                    // Memo
                    const memo_bytes = try reader.readString();
                    info.memo = try allocator.dupe(u8, memo_bytes);
                },
                9 => {
                    // Balance
                    info.balance = try reader.readUint64();
                },
                10 => {
                    // Deleted
                    info.deleted = try reader.readBool();
                },
                11 => {
                    // EvmAddress
                    const evm_bytes = try reader.readBytes();
                    info.evm_address = try allocator.dupe(u8, evm_bytes);
                },
                12 => {
                    // AutoRenewAccountId
                    const auto_renew_bytes = try reader.readBytes();
                    var auto_renew_reader = ProtoReader.init(auto_renew_bytes);
                    
                    var shard: i64 = 0;
                    var realm: i64 = 0;
                    var account: i64 = 0;
                    
                    while (auto_renew_reader.hasMore()) {
                        const ar_tag = try auto_renew_reader.readTag();
                        switch (ar_tag.field_number) {
                            1 => shard = try auto_renew_reader.readInt64(),
                            2 => realm = try auto_renew_reader.readInt64(),
                            3 => account = try auto_renew_reader.readInt64(),
                            else => try auto_renew_reader.skipField(ar_tag.wire_type),
                        }
                    }
                    
                    if (account != 0) {
                        info.auto_renew_account_id = AccountId.init(@intCast(shard), @intCast(realm), @intCast(account));
                    }
                },
                13 => {
                    // MaxAutomaticTokenAssociations
                    info.max_automatic_token_associations = try reader.readInt32();
                },
                14 => {
                    // LedgerId
                    const ledger_bytes = try reader.readBytes();
                    info.ledger_id = try allocator.dupe(u8, ledger_bytes);
                },
                15 => {
                    // StakingInfo
                    const staking_bytes = try reader.readBytes();
                    var staking_reader = ProtoReader.init(staking_bytes);
                    
                    var staking_info = StakingInfo{
                        .decline_reward = false,
                        .stake_period_start = null,
                        .pending_reward = 0,
                        .staked_to_me = 0,
                        .staked_account_id = null,
                        .staked_node_id = null,
                    };
                    
                    while (staking_reader.hasMore()) {
                        const s_tag = try staking_reader.readTag();
                        switch (s_tag.field_number) {
                            1 => staking_info.decline_reward = try staking_reader.readBool(),
                            2 => {
                                const timestamp_bytes = try staking_reader.readBytes();
                                var timestamp_reader = ProtoReader.init(timestamp_bytes);
                                var timestamp = Timestamp{ .seconds = 0, .nanos = 0 };
                                
                                while (timestamp_reader.hasMore()) {
                                    const t_tag = try timestamp_reader.readTag();
                                    switch (t_tag.field_number) {
                                        1 => timestamp.seconds = try timestamp_reader.readInt64(),
                                        2 => timestamp.nanos = try timestamp_reader.readInt32(),
                                        else => try timestamp_reader.skipField(t_tag.wire_type),
                                    }
                                }
                                staking_info.stake_period_start = timestamp;
                            },
                            3 => staking_info.pending_reward = try staking_reader.readInt64(),
                            4 => staking_info.staked_to_me = try staking_reader.readInt64(),
                            5 => {
                                const staked_account_bytes = try staking_reader.readBytes();
                                var staked_account_reader = ProtoReader.init(staked_account_bytes);
                                
                                var shard: i64 = 0;
                                var realm: i64 = 0;
                                var account: i64 = 0;
                                
                                while (staked_account_reader.hasMore()) {
                                    const sa_tag = try staked_account_reader.readTag();
                                    switch (sa_tag.field_number) {
                                        1 => shard = try staked_account_reader.readInt64(),
                                        2 => realm = try staked_account_reader.readInt64(),
                                        3 => account = try staked_account_reader.readInt64(),
                                        else => try staked_account_reader.skipField(sa_tag.wire_type),
                                    }
                                }
                                staking_info.staked_account_id = AccountId.init(@intCast(shard), @intCast(realm), @intCast(account));
                            },
                            6 => staking_info.staked_node_id = try staking_reader.readInt64(),
                            else => try staking_reader.skipField(s_tag.wire_type),
                        }
                    }
                    
                    info.staking_info = staking_info;
                },
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return info;
    }
    
    // Convert ContractInfo to protobuf bytes
    pub fn toProtobuf(self: *const ContractInfo, allocator: std.mem.Allocator) ![]u8 {
        var writer = ProtoWriter.init(allocator);
        defer writer.deinit();
        
        // ContractId (field 1)
        var contract_writer = ProtoWriter.init(allocator);
        defer contract_writer.deinit();
        try contract_writer.writeInt64(1, @intCast(self.contract_id.shard));
        try contract_writer.writeInt64(2, @intCast(self.contract_id.realm));
        try contract_writer.writeInt64(3, @intCast(self.contract_id.num));
        const contract_bytes = try contract_writer.toOwnedSlice();
        defer allocator.free(contract_bytes);
        try writer.writeMessage(1, contract_bytes);
        
        // AccountId (field 2)
        var account_writer = ProtoWriter.init(allocator);
        defer account_writer.deinit();
        try account_writer.writeInt64(1, @intCast(self.account_id.shard));
        try account_writer.writeInt64(2, @intCast(self.account_id.realm));
        try account_writer.writeInt64(3, @intCast(self.account_id.account));
        const account_bytes = try account_writer.toOwnedSlice();
        defer allocator.free(account_bytes);
        try writer.writeMessage(2, account_bytes);
        
        // ContractAccountId (field 3)
        if (self.contract_account_id.len > 0) {
            try writer.writeString(3, self.contract_account_id);
        }
        
        // AdminKey (field 4)
        if (self.admin_key) |admin_key| {
            const admin_bytes = try admin_key.toProtobuf(allocator);
            defer allocator.free(admin_bytes);
            try writer.writeMessage(4, admin_bytes);
        }
        
        // ExpirationTime (field 5)
        var expiry_writer = ProtoWriter.init(allocator);
        defer expiry_writer.deinit();
        try expiry_writer.writeInt64(1, self.expiration_time.seconds);
        try expiry_writer.writeInt32(2, self.expiration_time.nanos);
        const expiry_bytes = try expiry_writer.toOwnedSlice();
        defer allocator.free(expiry_bytes);
        try writer.writeMessage(5, expiry_bytes);
        
        // AutoRenewPeriod (field 6)
        var period_writer = ProtoWriter.init(allocator);
        defer period_writer.deinit();
        try period_writer.writeInt64(1, self.auto_renew_period.seconds);
        try period_writer.writeInt32(2, self.auto_renew_period.nanos);
        const period_bytes = try period_writer.toOwnedSlice();
        defer allocator.free(period_bytes);
        try writer.writeMessage(6, period_bytes);
        
        // Storage (field 7)
        if (self.storage != 0) {
            try writer.writeInt64(7, self.storage);
        }
        
        // Memo (field 8)
        if (self.memo.len > 0) {
            try writer.writeString(8, self.memo);
        }
        
        // Balance (field 9)
        if (self.balance != 0) {
            try writer.writeUint64(9, self.balance);
        }
        
        // Deleted (field 10)
        if (self.deleted) {
            try writer.writeBool(10, self.deleted);
        }
        
        // EvmAddress (field 11)
        if (self.evm_address.len > 0) {
            try writer.writeString(11, self.evm_address);
        }
        
        // AutoRenewAccountId (field 12)
        if (self.auto_renew_account_id) |renew_account| {
            var renew_writer = ProtoWriter.init(allocator);
            defer renew_writer.deinit();
            try renew_writer.writeInt64(1, @intCast(renew_account.shard));
            try renew_writer.writeInt64(2, @intCast(renew_account.realm));
            try renew_writer.writeInt64(3, @intCast(renew_account.account));
            const renew_bytes = try renew_writer.toOwnedSlice();
            defer allocator.free(renew_bytes);
            try writer.writeMessage(12, renew_bytes);
        }
        
        // MaxAutomaticTokenAssociations (field 13)
        if (self.max_automatic_token_associations != 0) {
            try writer.writeInt32(13, self.max_automatic_token_associations);
        }
        
        // LedgerId (field 14)
        if (self.ledger_id.len > 0) {
            try writer.writeString(14, self.ledger_id);
        }
        
        // StakingInfo (field 15)
        if (self.staking_info) |staking_info| {
            var staking_writer = ProtoWriter.init(allocator);
            defer staking_writer.deinit();
            
            // DeclineReward (field 1)
            if (staking_info.decline_reward) {
                try staking_writer.writeBool(1, staking_info.decline_reward);
            }
            
            // StakePeriodStart (field 2)
            if (staking_info.stake_period_start) |timestamp| {
                var timestamp_writer = ProtoWriter.init(allocator);
                defer timestamp_writer.deinit();
                try timestamp_writer.writeInt64(1, timestamp.seconds);
                try timestamp_writer.writeInt32(2, timestamp.nanos);
                const timestamp_bytes = try timestamp_writer.toOwnedSlice();
                defer allocator.free(timestamp_bytes);
                try staking_writer.writeMessage(2, timestamp_bytes);
            }
            
            // PendingReward (field 3)
            if (staking_info.pending_reward != 0) {
                try staking_writer.writeInt64(3, staking_info.pending_reward);
            }
            
            // StakedToMe (field 4)
            if (staking_info.staked_to_me != 0) {
                try staking_writer.writeInt64(4, staking_info.staked_to_me);
            }
            
            // StakedAccountId (field 5)
            if (staking_info.staked_account_id) |staked_account| {
                var staked_writer = ProtoWriter.init(allocator);
                defer staked_writer.deinit();
                try staked_writer.writeInt64(1, @intCast(staked_account.shard));
                try staked_writer.writeInt64(2, @intCast(staked_account.realm));
                try staked_writer.writeInt64(3, @intCast(staked_account.account));
                const staked_bytes = try staked_writer.toOwnedSlice();
                defer allocator.free(staked_bytes);
                try staking_writer.writeMessage(5, staked_bytes);
            }
            
            // StakedNodeId (field 6)
            if (staking_info.staked_node_id) |node_id| {
                try staking_writer.writeInt64(6, node_id);
            }
            
            const staking_bytes = try staking_writer.toOwnedSlice();
            defer allocator.free(staking_bytes);
            try writer.writeMessage(15, staking_bytes);
        }
        
        return writer.toOwnedSlice();
    }
};

pub const StakingInfo = struct {
    decline_reward: bool,
    stake_period_start: ?Timestamp,
    pending_reward: i64,
    staked_to_me: i64,
    staked_account_id: ?AccountId,
    staked_node_id: ?i64,

    pub fn deinit(self: *StakingInfo) void {
        _ = self;
    }
};

// ContractInfoQuery retrieves information about a smart contract
pub const ContractInfoQuery = struct {
    base: Query,
    contract_id: ?ContractId,

    pub fn init(allocator: std.mem.Allocator) ContractInfoQuery {
        return ContractInfoQuery{
            .base = Query.init(allocator),
            .contract_id = null,
        };
    }

    pub fn deinit(self: *ContractInfoQuery) void {
        self.base.deinit();
    }

    // Set the contract ID to query
    pub fn setContractId(self: *ContractInfoQuery, contract_id: ContractId) !*ContractInfoQuery {
        self.contract_id = contract_id;
        return self;
    }

    // Set the query payment amount
    pub fn setQueryPayment(self: *ContractInfoQuery, payment: Hbar) !*ContractInfoQuery {
        self.base.payment_amount = payment;
        return self;
    }

    // Execute the query
    pub fn execute(self: *ContractInfoQuery, client: *Client) !ContractInfo {
        if (self.contract_id == null) {
            return error.ContractIdRequired;
        }

        const response = try self.base.execute(client);
        return try self.parseResponse(response);
    }

    // Get cost of the query
    pub fn getCost(self: *ContractInfoQuery, client: *Client) !Hbar {
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
    pub fn buildQuery(self: *ContractInfoQuery) ![]u8 {
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

        // contractGetInfo = 9 (oneof query)
        var info_query_writer = ProtoWriter.init(self.base.allocator);
        defer info_query_writer.deinit();

        // contractID = 1
        if (self.contract_id) |contract| {
            var contract_writer = ProtoWriter.init(self.base.allocator);
            defer contract_writer.deinit();
            try contract_writer.writeInt64(1, @intCast(contract.shard));
            try contract_writer.writeInt64(2, @intCast(contract.realm));
            try contract_writer.writeInt64(3, @intCast(contract.num));
            const contract_bytes = try contract_writer.toOwnedSlice();
            defer self.base.allocator.free(contract_bytes);
            try info_query_writer.writeMessage(1, contract_bytes);
        }

        const info_query_bytes = try info_query_writer.toOwnedSlice();
        defer self.base.allocator.free(info_query_bytes);
        try writer.writeMessage(9, info_query_bytes);

        return writer.toOwnedSlice();
    }

    // Parse the response
    fn parseResponse(self: *ContractInfoQuery, response: QueryResponse) !ContractInfo {
        try response.validateStatus();

        var reader = ProtoReader.init(response.response_bytes);

        var info = ContractInfo.init(self.base.allocator);

        // Parse ContractGetInfoResponse
        while (reader.hasMore()) {
            const tag = try reader.readTag();

            switch (tag.field_number) {
                1 => {
                    // header
                    _ = try reader.readMessage();
                },
                2 => {
                    // contractInfo
                    const contract_info_bytes = try reader.readMessage();
                    var contract_reader = ProtoReader.init(contract_info_bytes);

                    while (contract_reader.hasMore()) {
                        const c_tag = try contract_reader.readTag();

                        switch (c_tag.field_number) {
                            1 => {
                                // contractID
                                const contract_bytes = try contract_reader.readMessage();
                                var id_reader = ProtoReader.init(contract_bytes);

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

                                info.contract_id = ContractId.init(@intCast(shard), @intCast(realm), @intCast(num));
                            },
                            2 => {
                                // accountID
                                const account_bytes = try contract_reader.readMessage();
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

                                info.account_id = AccountId.init(@intCast(shard), @intCast(realm), @intCast(num));
                            },
                            3 => info.contract_account_id = try self.base.allocator.dupe(u8, try contract_reader.readString()),
                            4 => {
                                // adminKey
                                const key_bytes = try contract_reader.readMessage();
                                info.admin_key = try Key.fromProtobuf(key_bytes, self.base.allocator);
                            },
                            5 => {
                                // expirationTime
                                const exp_bytes = try contract_reader.readMessage();
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
                            6 => {
                                // autoRenewPeriod
                                const period_bytes = try contract_reader.readMessage();
                                var period_reader = ProtoReader.init(period_bytes);

                                while (period_reader.hasMore()) {
                                    const p = try period_reader.readTag();
                                    switch (p.field_number) {
                                        1 => info.auto_renew_period.seconds = try period_reader.readInt64(),
                                        2 => info.auto_renew_period.nanos = try period_reader.readInt32(),
                                        else => try period_reader.skipField(p.wire_type),
                                    }
                                }
                            },
                            7 => info.storage = try contract_reader.readInt64(),
                            8 => info.memo = try self.base.allocator.dupe(u8, try contract_reader.readString()),
                            9 => info.balance = try contract_reader.readUint64(),
                            10 => info.deleted = try contract_reader.readBool(),
                            11 => {
                                // evmAddress
                                const evm_bytes = try contract_reader.readBytes();
                                info.evm_address = try self.base.allocator.dupe(u8, evm_bytes);
                            },
                            12 => {
                                // autoRenewAccountId
                                const account_bytes = try contract_reader.readMessage();
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
                                    info.auto_renew_account_id = AccountId.init(@intCast(shard), @intCast(realm), @intCast(num));
                                }
                            },
                            13 => info.max_automatic_token_associations = try contract_reader.readInt32(),
                            14 => {
                                // ledgerId
                                const ledger_bytes = try contract_reader.readBytes();
                                info.ledger_id = try self.base.allocator.dupe(u8, ledger_bytes);
                            },
                            15 => {
                                // stakingInfo
                                const staking_bytes = try contract_reader.readMessage();
                                var staking_reader = ProtoReader.init(staking_bytes);

                                var staking_info = StakingInfo{
                                    .decline_reward = false,
                                    .stake_period_start = null,
                                    .pending_reward = 0,
                                    .staked_to_me = 0,
                                    .staked_account_id = null,
                                    .staked_node_id = null,
                                };

                                while (staking_reader.hasMore()) {
                                    const s = try staking_reader.readTag();
                                    switch (s.field_number) {
                                        1 => staking_info.decline_reward = try staking_reader.readBool(),
                                        2 => {
                                            // stakePeriodStart
                                            const start_bytes = try staking_reader.readMessage();
                                            var start_reader = ProtoReader.init(start_bytes);

                                            var start_time = Timestamp{ .seconds = 0, .nanos = 0 };
                                            while (start_reader.hasMore()) {
                                                const st = try start_reader.readTag();
                                                switch (st.field_number) {
                                                    1 => start_time.seconds = try start_reader.readInt64(),
                                                    2 => start_time.nanos = try start_reader.readInt32(),
                                                    else => try start_reader.skipField(st.wire_type),
                                                }
                                            }
                                            staking_info.stake_period_start = start_time;
                                        },
                                        3 => staking_info.pending_reward = try staking_reader.readInt64(),
                                        4 => staking_info.staked_to_me = try staking_reader.readInt64(),
                                        5 => {
                                            // stakedAccountId
                                            const account_bytes = try staking_reader.readMessage();
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
                                                staking_info.staked_account_id = AccountId.init(@intCast(shard), @intCast(realm), @intCast(num));
                                            }
                                        },
                                        6 => staking_info.staked_node_id = try staking_reader.readInt64(),
                                        else => try staking_reader.skipField(s.wire_type),
                                    }
                                }

                                info.staking_info = staking_info;
                            },
                            else => try contract_reader.skipField(c_tag.wire_type),
                        }
                    }
                },
                else => try reader.skipField(tag.wire_type),
            }
        }

        return info;
    }
};

// Factory function for creating a new ContractInfoQuery

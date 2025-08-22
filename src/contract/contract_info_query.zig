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
    contract_id: ?ContractId = null,
    account_id: ?AccountId = null,
    contract_account_id: ?[]const u8 = null,
    admin_key: ?Key = null,
    expiration_time: ?Timestamp = null,
    auto_renew_period: ?Duration = null,
    storage: i64 = 0,
    memo: ?[]const u8 = null,
    balance: Hbar = Hbar.zero(),
    deleted: bool = false,
    evm_address: ?[]const u8 = null,
    auto_renew_account_id: ?AccountId = null,
    max_automatic_token_associations: i32 = 0,
    ledger_id: ?[]const u8 = null,
    staking_info: ?StakingInfo = null,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) ContractInfo {
        return ContractInfo{
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *ContractInfo) void {
        if (self.contract_account_id) |caid| {
            self.allocator.free(caid);
        }
        if (self.memo) |m| {
            self.allocator.free(m);
        }
        if (self.evm_address) |ea| {
            self.allocator.free(ea);
        }
        if (self.ledger_id) |lid| {
            self.allocator.free(lid);
        }
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
    pub fn setContractId(self: *ContractInfoQuery, contract_id: ContractId) *ContractInfoQuery {
        self.contract_id = contract_id;
        return self;
    }
    
    // Set the query payment amount
    pub fn setQueryPayment(self: *ContractInfoQuery, payment: Hbar) *ContractInfoQuery {
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
        
        var info = ContractInfo{
            .contract_id = ContractId.init(0, 0, 0),
            .account_id = AccountId.init(0, 0, 0),
            .contract_account_id = "",
            .admin_key = null,
            .expiration_time = Timestamp{ .seconds = 0, .nanos = 0 },
            .auto_renew_period = Duration{ .seconds = 0 },
            .storage = 0,
            .memo = "",
            .balance = 0,
            .deleted = false,
            .evm_address = "",
            .auto_renew_account_id = null,
            .max_automatic_token_associations = 0,
            .ledger_id = "",
            .staking_info = null,
            .allocator = self.base.allocator,
        };
        
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
                                
                                var staking_info = ContractInfo.StakingInfo{
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
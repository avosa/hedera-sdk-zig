const std = @import("std");
const AccountId = @import("../core/id.zig").AccountId;
const Hbar = @import("../core/hbar.zig").Hbar;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;

// Proxy staker information for delegation
pub const ProxyStaker = struct {
    staker_id: AccountId,
    account_id: AccountId,  // Alias for staker_id
    proxy_account_id: AccountId,
    staked_amount: Hbar,
    amount: Hbar,  // Alias for staked_amount
    stake_period_start: i64,
    decline_reward: bool,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, staker_id: AccountId, proxy_account_id: AccountId) ProxyStaker {
        return ProxyStaker{
            .staker_id = staker_id,
            .account_id = staker_id,  // Alias
            .proxy_account_id = proxy_account_id,
            .staked_amount = Hbar.ZERO,
            .amount = Hbar.ZERO,  // Alias
            .stake_period_start = 0,
            .decline_reward = false,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ProxyStaker) void {
        _ = self;
    }

    pub fn setStakedAmount(self: *ProxyStaker, amount: Hbar) *ProxyStaker {
        self.staked_amount = amount;
        return self;
    }

    pub fn setStakePeriodStart(self: *ProxyStaker, start: i64) *ProxyStaker {
        self.stake_period_start = start;
        return self;
    }

    pub fn setDeclineReward(self: *ProxyStaker, decline: bool) *ProxyStaker {
        self.decline_reward = decline;
        return self;
    }

    pub fn getStakerId(self: *const ProxyStaker) AccountId {
        return self.staker_id;
    }

    pub fn getProxyAccountId(self: *const ProxyStaker) AccountId {
        return self.proxy_account_id;
    }

    pub fn getStakedAmount(self: *const ProxyStaker) Hbar {
        return self.staked_amount;
    }

    pub fn getStakePeriodStart(self: *const ProxyStaker) i64 {
        return self.stake_period_start;
    }

    pub fn getDeclineReward(self: *const ProxyStaker) bool {
        return self.decline_reward;
    }

    pub fn isStaking(self: *const ProxyStaker) bool {
        return self.staked_amount.toTinybars() > 0;
    }

    pub fn getStakingDuration(self: *const ProxyStaker, current_time: i64) i64 {
        if (self.stake_period_start == 0) return 0;
        return @max(0, current_time - self.stake_period_start);
    }

    pub fn calculatePendingReward(self: *const ProxyStaker, reward_rate: f64, current_time: i64) Hbar {
        if (self.decline_reward or !self.isStaking()) {
            return Hbar.ZERO;
        }

        const duration_days = @as(f64, @floatFromInt(self.getStakingDuration(current_time))) / (24.0 * 60.0 * 60.0);
        const staked_hbars = @as(f64, @floatFromInt(self.staked_amount.toTinybars())) / 100000000.0;
        const reward_hbars = staked_hbars * reward_rate * duration_days / 365.0;
        
        return Hbar.fromTinybars(@intFromFloat(reward_hbars * 100000000.0));
    }

    pub fn toProtobuf(self: *const ProxyStaker, allocator: std.mem.Allocator) ![]u8 {
        var writer = ProtoWriter.init(allocator);
        defer writer.deinit();

        // staker_id = 1
        var staker_writer = ProtoWriter.init(allocator);
        defer staker_writer.deinit();
        try staker_writer.writeInt64(1, @intCast(self.staker_id.entity.shard));
        try staker_writer.writeInt64(2, @intCast(self.staker_id.entity.realm));
        try staker_writer.writeInt64(3, @intCast(self.staker_id.entity.num));
        const staker_bytes = try staker_writer.toOwnedSlice();
        defer allocator.free(staker_bytes);
        try writer.writeMessage(1, staker_bytes);

        // proxy_account_id = 2
        var proxy_writer = ProtoWriter.init(allocator);
        defer proxy_writer.deinit();
        try proxy_writer.writeInt64(1, @intCast(self.proxy_account_id.entity.shard));
        try proxy_writer.writeInt64(2, @intCast(self.proxy_account_id.entity.realm));
        try proxy_writer.writeInt64(3, @intCast(self.proxy_account_id.entity.num));
        const proxy_bytes = try proxy_writer.toOwnedSlice();
        defer allocator.free(proxy_bytes);
        try writer.writeMessage(2, proxy_bytes);

        // staked_amount = 3
        try writer.writeInt64(3, self.staked_amount.toTinybars());

        // stake_period_start = 4
        try writer.writeInt64(4, self.stake_period_start);

        // decline_reward = 5
        try writer.writeBool(5, self.decline_reward);

        return writer.toOwnedSlice();
    }

    pub fn fromProtobuf(data: []const u8, allocator: std.mem.Allocator) !ProxyStaker {
        var reader = ProtoReader.init(data);
        const staker_id = AccountId.init(0, 0, 0);
        const proxy_account_id = AccountId.init(0, 0, 0);
        var proxy_staker = ProxyStaker.init(allocator, staker_id, proxy_account_id);

        while (try reader.next()) |field| {
            switch (field.number) {
                1 => {
                    var staker_reader = ProtoReader.init(field.data);
                    var shard: i64 = 0;
                    var realm: i64 = 0;
                    var num: i64 = 0;

                    while (try staker_reader.next()) |staker_field| {
                        switch (staker_field.number) {
                            1 => shard = try staker_reader.readInt64(staker_field.data),
                            2 => realm = try staker_reader.readInt64(staker_field.data),
                            3 => num = try staker_reader.readInt64(staker_field.data),
                            else => {},
                        }
                    }

                    proxy_staker.staker_id = AccountId{
                        .entity = .{
                            .shard = shard,
                            .realm = realm,
                            .num = num,
                        },
                    };
                },
                2 => {
                    var proxy_reader = ProtoReader.init(field.data);
                    var shard: i64 = 0;
                    var realm: i64 = 0;
                    var num: i64 = 0;

                    while (try proxy_reader.next()) |proxy_field| {
                        switch (proxy_field.number) {
                            1 => shard = try proxy_reader.readInt64(proxy_field.data),
                            2 => realm = try proxy_reader.readInt64(proxy_field.data),
                            3 => num = try proxy_reader.readInt64(proxy_field.data),
                            else => {},
                        }
                    }

                    proxy_staker.proxy_account_id = AccountId{
                        .entity = .{
                            .shard = shard,
                            .realm = realm,
                            .num = num,
                        },
                    };
                },
                3 => proxy_staker.staked_amount = Hbar.fromTinybars(try reader.readInt64(field.data)),
                4 => proxy_staker.stake_period_start = try reader.readInt64(field.data),
                5 => proxy_staker.decline_reward = try reader.readBool(field.data),
                else => {},
            }
        }

        return proxy_staker;
    }

    pub fn clone(self: *const ProxyStaker, allocator: std.mem.Allocator) ProxyStaker {
        return ProxyStaker{
            .staker_id = self.staker_id,
            .account_id = self.staker_id,  // Alias
            .proxy_account_id = self.proxy_account_id,
            .staked_amount = self.staked_amount,
            .stake_period_start = self.stake_period_start,
            .decline_reward = self.decline_reward,
            .allocator = allocator,
        };
    }

    pub fn equals(self: *const ProxyStaker, other: *const ProxyStaker) bool {
        if (self.staker_id.entity.shard != other.staker_id.entity.shard or
            self.staker_id.entity.realm != other.staker_id.entity.realm or
            self.staker_id.entity.num != other.staker_id.entity.num) {
            return false;
        }

        if (self.proxy_account_id.entity.shard != other.proxy_account_id.entity.shard or
            self.proxy_account_id.entity.realm != other.proxy_account_id.entity.realm or
            self.proxy_account_id.entity.num != other.proxy_account_id.entity.num) {
            return false;
        }

        return self.staked_amount.toTinybars() == other.staked_amount.toTinybars() and
               self.stake_period_start == other.stake_period_start and
               self.decline_reward == other.decline_reward;
    }

    pub fn toString(self: *const ProxyStaker, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "ProxyStaker{{staker={}, proxy={}, amount={}, decline_reward={}}}", .{
            self.staker_id,
            self.proxy_account_id,
            self.staked_amount.toString(),
            self.decline_reward,
        });
    }
};

// Staking information for accounts
pub const StakingInfo = struct {
    staked_to_me: Hbar,
    staked_node_id: ?i64,
    staked_account_id: ?AccountId,
    decline_reward: bool,
    stake_period_start: i64,
    pending_reward: Hbar,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) StakingInfo {
        return StakingInfo{
            .staked_to_me = Hbar.ZERO,
            .staked_node_id = null,
            .staked_account_id = null,
            .decline_reward = false,
            .stake_period_start = 0,
            .pending_reward = Hbar.ZERO,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *StakingInfo) void {
        _ = self;
    }

    pub fn setStakedToMe(self: *StakingInfo, amount: Hbar) *StakingInfo {
        self.staked_to_me = amount;
        return self;
    }

    pub fn setStakedNodeId(self: *StakingInfo, node_id: i64) *StakingInfo {
        self.staked_node_id = node_id;
        self.staked_account_id = null;
        return self;
    }

    pub fn setStakedAccountId(self: *StakingInfo, account_id: AccountId) *StakingInfo {
        self.staked_account_id = account_id;
        self.staked_node_id = null;
        return self;
    }

    pub fn setDeclineReward(self: *StakingInfo, decline: bool) *StakingInfo {
        self.decline_reward = decline;
        return self;
    }

    pub fn setStakePeriodStart(self: *StakingInfo, start: i64) *StakingInfo {
        self.stake_period_start = start;
        return self;
    }

    pub fn setPendingReward(self: *StakingInfo, reward: Hbar) *StakingInfo {
        self.pending_reward = reward;
        return self;
    }

    pub fn getStakedToMe(self: *const StakingInfo) Hbar {
        return self.staked_to_me;
    }

    pub fn getStakedNodeId(self: *const StakingInfo) ?i64 {
        return self.staked_node_id;
    }

    pub fn getStakedAccountId(self: *const StakingInfo) ?AccountId {
        return self.staked_account_id;
    }

    pub fn getDeclineReward(self: *const StakingInfo) bool {
        return self.decline_reward;
    }

    pub fn getStakePeriodStart(self: *const StakingInfo) i64 {
        return self.stake_period_start;
    }

    pub fn getPendingReward(self: *const StakingInfo) Hbar {
        return self.pending_reward;
    }

    pub fn isStakingToNode(self: *const StakingInfo) bool {
        return self.staked_node_id != null;
    }

    pub fn isStakingToAccount(self: *const StakingInfo) bool {
        return self.staked_account_id != null;
    }

    pub fn isStaking(self: *const StakingInfo) bool {
        return self.isStakingToNode() or self.isStakingToAccount();
    }

    pub fn hasStakeDelegatedToMe(self: *const StakingInfo) bool {
        return self.staked_to_me.toTinybars() > 0;
    }

    pub fn getStakingTarget(self: *const StakingInfo) union(enum) {
        node: i64,
        account: AccountId,
        none: void,
    } {
        if (self.staked_node_id) |node_id| {
            return .{ .node = node_id };
        } else if (self.staked_account_id) |account_id| {
            return .{ .account = account_id };
        } else {
            return .none;
        }
    }

    pub fn toProtobuf(self: *const StakingInfo, allocator: std.mem.Allocator) ![]u8 {
        var writer = ProtoWriter.init(allocator);
        defer writer.deinit();

        // staked_to_me = 1
        try writer.writeInt64(1, self.staked_to_me.toTinybars());

        // staked_node_id = 2 (optional)
        if (self.staked_node_id) |node_id| {
            try writer.writeInt64(2, node_id);
        }

        // staked_account_id = 3 (optional)
        if (self.staked_account_id) |account_id| {
            var account_writer = ProtoWriter.init(allocator);
            defer account_writer.deinit();
            try account_writer.writeInt64(1, @intCast(account_id.entity.shard));
            try account_writer.writeInt64(2, @intCast(account_id.entity.realm));
            try account_writer.writeInt64(3, @intCast(account_id.entity.num));
            const account_bytes = try account_writer.toOwnedSlice();
            defer allocator.free(account_bytes);
            try writer.writeMessage(3, account_bytes);
        }

        // decline_reward = 4
        try writer.writeBool(4, self.decline_reward);

        // stake_period_start = 5
        try writer.writeInt64(5, self.stake_period_start);

        // pending_reward = 6
        try writer.writeInt64(6, self.pending_reward.toTinybars());

        return writer.toOwnedSlice();
    }

    pub fn fromProtobuf(data: []const u8, allocator: std.mem.Allocator) !StakingInfo {
        var reader = ProtoReader.init(data);
        var staking_info = StakingInfo.init(allocator);

        while (try reader.next()) |field| {
            switch (field.number) {
                1 => staking_info.staked_to_me = Hbar.fromTinybars(try reader.readInt64(field.data)),
                2 => staking_info.staked_node_id = try reader.readInt64(field.data),
                3 => {
                    var account_reader = ProtoReader.init(field.data);
                    var shard: i64 = 0;
                    var realm: i64 = 0;
                    var num: i64 = 0;

                    while (try account_reader.next()) |account_field| {
                        switch (account_field.number) {
                            1 => shard = try account_reader.readInt64(account_field.data),
                            2 => realm = try account_reader.readInt64(account_field.data),
                            3 => num = try account_reader.readInt64(account_field.data),
                            else => {},
                        }
                    }

                    staking_info.staked_account_id = AccountId{
                        .entity = .{
                            .shard = shard,
                            .realm = realm,
                            .num = num,
                        },
                    };
                },
                4 => staking_info.decline_reward = try reader.readBool(field.data),
                5 => staking_info.stake_period_start = try reader.readInt64(field.data),
                6 => staking_info.pending_reward = Hbar.fromTinybars(try reader.readInt64(field.data)),
                else => {},
            }
        }

        return staking_info;
    }

    pub fn clone(self: *const StakingInfo, allocator: std.mem.Allocator) StakingInfo {
        return StakingInfo{
            .staked_to_me = self.staked_to_me,
            .staked_node_id = self.staked_node_id,
            .staked_account_id = self.staked_account_id,
            .decline_reward = self.decline_reward,
            .stake_period_start = self.stake_period_start,
            .pending_reward = self.pending_reward,
            .allocator = allocator,
        };
    }
};
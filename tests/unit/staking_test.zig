const std = @import("std");
const testing = std.testing;
const AccountId = @import("../account/delete_account_id.zig").AccountId;
const Timestamp = @import("../core/timestamp.zig").Timestamp;
const Hbar = @import("../core/hbar.zig").Hbar;

test "StakingInfo initialization and fields" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var info = @import("staking_info.zig").StakingInfo.init(allocator);
    defer info.deinit();
    
    // Test staking to node
    info.staked_node_id = 3;
    info.stake_period_start = Timestamp.fromSeconds(1234567890);
    info.pending_reward = 100000000; // 1 hbar
    info.staked_to_me = 1000000000000; // 10000 hbar
    info.decline_reward = false;
    
    try testing.expectEqual(@as(?i64, 3), info.staked_node_id);
    try testing.expect(info.staked_account_id == null);
    try testing.expectEqual(@as(i64, 100000000), info.pending_reward);
    try testing.expect(!info.decline_reward);
    
    // Switch to staking to account
    info.staked_node_id = null;
    info.staked_account_id = AccountId.init(0, 0, 800);
    
    try testing.expect(info.staked_node_id == null);
    try testing.expectEqual(@as(u64, 800), info.staked_account_id.?.account);
}

test "ProxyStaker" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const staker = @import("proxy_staker.zig").ProxyStaker{
        .account_id = AccountId.init(0, 0, 100),
        .amount = 50000000000, // 500 hbar
    };
    
    try testing.expectEqual(@as(u64, 100), staker.account_id.account);
    try testing.expectEqual(@as(i64, 50000000000), staker.amount);
    
    // Test serialization
    var writer = @import("../protobuf/writer.zig").ProtobufWriter.init(allocator);
    defer writer.deinit();
    
    try staker.serialize(&writer);
    const bytes = writer.toBytes();
    try testing.expect(bytes.len > 0);
}

test "NodeStake" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var node_stake = @import("node_stake.zig").NodeStake.init(allocator);
    defer node_stake.deinit();
    
    node_stake.max_stake = 10000000000000; // 100000 hbar
    node_stake.min_stake = 100000000000; // 1000 hbar
    node_stake.node_id = 3;
    node_stake.reward_rate = 10000; // 0.1 = 10%
    node_stake.stake = 5000000000000; // 50000 hbar
    node_stake.stake_not_rewarded = 100000000000; // 1000 hbar
    node_stake.stake_rewarded = 4900000000000; // 49000 hbar
    
    try testing.expectEqual(@as(i64, 3), node_stake.node_id);
    try testing.expectEqual(@as(i64, 10000), node_stake.reward_rate);
    try testing.expectEqual(@as(i64, 5000000000000), node_stake.stake);
}

test "StakeTransferTransaction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = @import("stake_transfer.zig").StakeTransferTransaction.init(allocator);
    defer tx.deinit();
    
    // Transfer stake from one account to another
    const from_account = AccountId.init(0, 0, 100);
    const to_account = AccountId.init(0, 0, 200);
    
    _ = try tx.setFromAccountId(from_account);
    _ = try tx.setToAccountId(to_account);
    tx.setAmount(try Hbar.from(1000));
    
    try testing.expectEqual(from_account.num(), tx.from_delete_account_id.?.account);
    try testing.expectEqual(to_account.num(), tx.to_delete_account_id.?.account);
    try testing.expectEqual(@as(i64, 100000000000), tx.amount.?.tinybar);
}

test "NodeStakeUpdateTransaction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = @import("node_stake_update.zig").NodeStakeUpdateTransaction.init(allocator);
    defer tx.deinit();
    
    // Update node stake settings
    _ = try tx.setNodeId(3);
    tx.setMaxStake(try Hbar.from(100000));
    tx.setMinStake(try Hbar.from(1000));
    tx.setRewardRate(10000); // 10%
    
    try testing.expectEqual(@as(i64, 3), tx.node_id.?);
    try testing.expectEqual(@as(i64, 10000000000000), tx.max_stake.?.tinybar);
    try testing.expectEqual(@as(i64, 100000000000), tx.min_stake.?.tinybar);
    try testing.expectEqual(@as(i64, 10000), tx.reward_rate.?);
}

test "StakingRewardsInfo" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var rewards = @import("staking_rewards.zig").StakingRewardsInfo.init(allocator);
    defer rewards.deinit();
    
    rewards.node_id = 3;
    rewards.stake_period_start = Timestamp.fromSeconds(1234567890);
    rewards.stake_period_end = Timestamp.fromSeconds(1234654290);
    rewards.total_stake_start = 1000000000000; // 10000 hbar
    rewards.total_stake_rewarded = 950000000000; // 9500 hbar
    rewards.total_stake_unrewarded = 50000000000; // 500 hbar
    rewards.total_rewards_earned = 10000000000; // 100 hbar
    rewards.rewards_rate = 10000; // 10%
    
    try testing.expectEqual(@as(i64, 3), rewards.node_id);
    try testing.expectEqual(@as(i64, 10000000000), rewards.total_rewards_earned);
    try testing.expectEqual(@as(i64, 10000), rewards.rewards_rate);
    
    // Calculate APR
    const apr = rewards.calculateAPR();
    try testing.expect(apr > 0);
}


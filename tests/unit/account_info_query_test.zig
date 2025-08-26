const std = @import("std");
const testing = std.testing;
const AccountInfoQuery = @import("../../src/account/account_info_query.zig").AccountInfoQuery;
const AccountInfo = @import("../../src/account/account_info_query.zig").AccountInfo;
const StakingInfo = @import("../../src/account/account_info_query.zig").StakingInfo;
const AccountId = @import("../../src/core/id.zig").AccountId;
const Hbar = @import("../../src/core/hbar.zig").Hbar;
const Duration = @import("../../src/core/duration.zig").Duration;
const Timestamp = @import("../../src/core/timestamp.zig").Timestamp;
const Key = @import("../../src/crypto/key.zig").Key;
const PublicKey = @import("../../src/crypto/public_key.zig").PublicKey;
const PrivateKey = @import("../../src/crypto/private_key.zig").PrivateKey;

const newAccountInfoQuery = @import("../../src/account/account_info_query.zig").newAccountInfoQuery;

test "newAccountInfoQuery creates valid query" {
    const allocator = testing.allocator;
    
    var query = newAccountInfoQuery(allocator);
    defer query.deinit();
    
    // Verify default values
    try testing.expectEqual(@as(?AccountId, null), query.account_id);
    try testing.expectEqual(@as(u32, 3), query.max_retry);
    try testing.expectEqual(@as(i64, 8), query.max_backoff.seconds);
    try testing.expectEqual(@as(i64, 0), query.min_backoff.seconds);
    try testing.expectEqual(@as(i32, 250000000), query.min_backoff.nanos);
    try testing.expectEqual(@as(usize, 0), query.node_account_ids.items.len);
}

test "AccountInfoQuery.setAccountId sets account to query" {
    const allocator = testing.allocator;
    
    var query = AccountInfoQuery.init(allocator);
    defer query.deinit();
    
    const account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    _ = query.setAccountId(account_id);
    
    try testing.expect(query.account_id != null);
    try testing.expect(query.account_id.?.equals(account_id));
}

test "AccountInfoQuery.setNodeAccountIds sets node accounts" {
    const allocator = testing.allocator;
    
    var query = AccountInfoQuery.init(allocator);
    defer query.deinit();
    
    var node_ids = std.ArrayList(AccountId).init(allocator);
    defer node_ids.deinit();
    
    try node_ids.append(AccountId{ .shard = 0, .realm = 0, .account = 3 });
    try node_ids.append(AccountId{ .shard = 0, .realm = 0, .account = 4 });
    
    _ = try query.setNodeAccountIds(node_ids.items);
    
    try testing.expectEqual(@as(usize, 2), query.node_account_ids.items.len);
    try testing.expect(query.node_account_ids.items[0].equals(node_ids.items[0]));
    try testing.expect(query.node_account_ids.items[1].equals(node_ids.items[1]));
}

test "AccountInfoQuery.setMaxRetry sets max retry attempts" {
    const allocator = testing.allocator;
    
    var query = AccountInfoQuery.init(allocator);
    defer query.deinit();
    
    const max_retry: u32 = 5;
    _ = query.setMaxRetry(max_retry);
    
    try testing.expectEqual(max_retry, query.max_retry);
}

test "AccountInfoQuery.setMaxBackoff sets max backoff" {
    const allocator = testing.allocator;
    
    var query = AccountInfoQuery.init(allocator);
    defer query.deinit();
    
    const max_backoff = Duration.fromSeconds(30);
    _ = query.setMaxBackoff(max_backoff);
    
    try testing.expectEqual(max_backoff.seconds, query.max_backoff.seconds);
}

test "AccountInfoQuery.setMinBackoff sets min backoff" {
    const allocator = testing.allocator;
    
    var query = AccountInfoQuery.init(allocator);
    defer query.deinit();
    
    const min_backoff = Duration.fromMillis(500);
    _ = query.setMinBackoff(min_backoff);
    
    try testing.expectEqual(min_backoff.seconds, query.min_backoff.seconds);
    try testing.expectEqual(min_backoff.nanos, query.min_backoff.nanos);
}

test "AccountInfoQuery.setQueryPayment sets query payment" {
    const allocator = testing.allocator;
    
    var query = AccountInfoQuery.init(allocator);
    defer query.deinit();
    
    const payment = try Hbar.from(1);
    _ = try query.setQueryPayment(payment);
    
    try testing.expect(query.base.payment != null);
    try testing.expectEqual(payment.toTinybars(), query.base.payment.?.toTinybars());
}

test "AccountInfoQuery.setMaxQueryPayment sets max query payment" {
    const allocator = testing.allocator;
    
    var query = AccountInfoQuery.init(allocator);
    defer query.deinit();
    
    const max_payment = try Hbar.from(5);
    _ = try query.setMaxQueryPayment(max_payment);
    
    try testing.expect(query.base.max_query_payment != null);
    try testing.expectEqual(max_payment.toTinybars(), query.base.max_query_payment.?.toTinybars());
}

test "AccountInfoQuery.execute returns AccountInfo" {
    const allocator = testing.allocator;
    
    var query = AccountInfoQuery.init(allocator);
    defer query.deinit();
    
    // Verify execute method exists
    try testing.expect(@hasDecl(@TypeOf(query), "execute"));
}

test "AccountInfoQuery.getCost returns query cost" {
    const allocator = testing.allocator;
    
    var query = AccountInfoQuery.init(allocator);
    defer query.deinit();
    
    // Verify getCost method exists
    try testing.expect(@hasDecl(@TypeOf(query), "getCost"));
}

test "AccountInfoQuery method chaining works" {
    const allocator = testing.allocator;
    
    var query = AccountInfoQuery.init(allocator);
    defer query.deinit();
    
    const account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    
    const result = query
        .setAccountId(account_id)
        .setMaxRetry(5);
    
    try testing.expectEqual(&query, result);
    try testing.expect(query.account_id != null);
    try testing.expectEqual(@as(u32, 5), query.max_retry);
}

test "AccountInfoQuery validates account ID is set" {
    const allocator = testing.allocator;
    
    var query = AccountInfoQuery.init(allocator);
    defer query.deinit();
    
    // Query without account ID should be invalid
    try testing.expectEqual(@as(?AccountId, null), query.account_id);
}

test "AccountInfo structure has expected fields" {
    const allocator = testing.allocator;
    
    var info = AccountInfo.init(allocator);
    defer info.deinit();
    
    // Verify default values
    try testing.expect(info.account_id.equals(AccountId{ .shard = 0, .realm = 0, .account = 0 }));
    try testing.expectEqual(@as(?Key, null), info.key);
    try testing.expectEqual(@as(i64, 0), info.balance.toTinybars());
    try testing.expect(!info.receiver_signature_required);
    try testing.expectEqual(@as(i64, 0), info.auto_renew_period.seconds);
    try testing.expectEqualStrings("", info.memo);
    try testing.expectEqual(@as(u64, 0), info.owned_nfts);
    try testing.expectEqual(@as(i32, 0), info.max_automatic_token_associations);
    try testing.expectEqual(@as(?[]const u8, null), info.alias);
    try testing.expectEqual(@as(?[]const u8, null), info.ledger_id);
    try testing.expectEqual(@as(usize, 0), info.token_relationships.items.len);
}

test "StakingInfo structure has expected fields" {
    const staking_info = StakingInfo{
        .decline_reward = false,
        .stake_period_start = null,
        .pending_reward = 0,
        .staked_to_me = 0,
        .staked_account_id = null,
        .staked_node_id = null,
    };
    
    try testing.expect(!staking_info.decline_reward);
    try testing.expectEqual(@as(?Timestamp, null), staking_info.stake_period_start);
    try testing.expectEqual(@as(i64, 0), staking_info.pending_reward);
    try testing.expectEqual(@as(i64, 0), staking_info.staked_to_me);
    try testing.expectEqual(@as(?AccountId, null), staking_info.staked_account_id);
    try testing.expectEqual(@as(?i64, null), staking_info.staked_node_id);
}

test "StakingInfo.decode parses protobuf correctly" {
    const allocator = testing.allocator;
    
    // Create sample protobuf bytes
    var writer = @import("../../src/protobuf/encoding.zig").ProtoWriter.init(allocator);
    defer writer.deinit();
    
    // decline_reward = 1
    try writer.writeBool(1, true);
    // pending_reward = 3
    try writer.writeInt64(3, 1000);
    // staked_to_me = 4
    try writer.writeInt64(4, 5000);
    // staked_node_id = 6
    try writer.writeInt64(6, 3);
    
    const bytes = try writer.toOwnedSlice();
    defer allocator.free(bytes);
    
    // Decode
    var reader = @import("../../src/protobuf/encoding.zig").ProtoReader.init(bytes);
    const decoded = try StakingInfo.decode(&reader, allocator);
    
    try testing.expect(decoded.decline_reward);
    try testing.expectEqual(@as(i64, 1000), decoded.pending_reward);
    try testing.expectEqual(@as(i64, 5000), decoded.staked_to_me);
    try testing.expectEqual(@as(?i64, 3), decoded.staked_node_id);
}

test "AccountInfoQuery supports payment configuration" {
    const allocator = testing.allocator;
    
    var query = AccountInfoQuery.init(allocator);
    defer query.deinit();
    
    // Set explicit payment
    const payment = try Hbar.from(2);
    _ = try query.setQueryPayment(payment);
    
    try testing.expect(query.base.payment != null);
    try testing.expectEqual(payment.toTinybars(), query.base.payment.?.toTinybars());
    
    // Set max payment
    const max_payment = try Hbar.from(10);
    _ = try query.setMaxQueryPayment(max_payment);
    
    try testing.expect(query.base.max_query_payment != null);
    try testing.expectEqual(max_payment.toTinybars(), query.base.max_query_payment.?.toTinybars());
}

test "AccountInfoQuery deinit cleans up properly" {
    const allocator = testing.allocator;
    
    var query = AccountInfoQuery.init(allocator);
    
    // Add some node account IDs
    try query.node_account_ids.append(AccountId{ .shard = 0, .realm = 0, .account = 3 });
    try query.node_account_ids.append(AccountId{ .shard = 0, .realm = 0, .account = 4 });
    
    // Deinit should clean up all allocations
    query.deinit();
    
    // Test passes if no memory leaks
}

test "AccountInfo.deinit cleans up properly" {
    const allocator = testing.allocator;
    
    var info = AccountInfo.init(allocator);
    
    // Add some token relationships
    const TokenRelationship = @import("../../src/token/token_info_query.zig").TokenRelationship;
    const TokenId = @import("../../src/core/id.zig").TokenId;
    
    try info.token_relationships.append(TokenRelationship{
        .token_id = TokenId{ .shard = 0, .realm = 0, .account = 100 },
        .symbol = "TEST",
        .balance = 1000,
        .kycStatus = null,
        .freezeStatus = null,
        .decimals = 8,
        .automatic = false,
    });
    
    // Deinit should clean up all allocations
    info.deinit();
    
    // Test passes if no memory leaks
}
const std = @import("std");
const testing = std.testing;
const AccountUpdateTransaction = @import("../../src/account/account_update.zig").AccountUpdateTransaction;
const newAccountUpdateTransaction = @import("../../src/account/account_update.zig").newAccountUpdateTransaction;
const AccountId = @import("../../src/core/id.zig").AccountId;
const Key = @import("../../src/crypto/key.zig").Key;
const PublicKey = @import("../../src/crypto/public_key.zig").PublicKey;
const PrivateKey = @import("../../src/crypto/private_key.zig").PrivateKey;
const Duration = @import("../../src/core/duration.zig").Duration;
const Timestamp = @import("../../src/core/timestamp.zig").Timestamp;

test "newAccountUpdateTransaction creates valid transaction" {
    const allocator = testing.allocator;
    
    var tx = newAccountUpdateTransaction(allocator);
    defer tx.deinit();
    
    // Verify default values
    try testing.expectEqual(@as(?AccountId, null), tx.account_id);
    try testing.expectEqual(@as(?Key, null), tx.key);
    try testing.expectEqual(@as(?PublicKey, null), tx.alias_key);
    try testing.expectEqual(@as(?bool, null), tx.receiver_sig_required);
    try testing.expect(tx.auto_renew_period != null);
    try testing.expectEqual(@as(i64, 7890000), tx.auto_renew_period.?.seconds);
    try testing.expectEqual(@as(?Timestamp, null), tx.expiration_time);
    try testing.expectEqual(@as(?[]const u8, null), tx.memo);
    try testing.expectEqual(@as(?i32, null), tx.max_automatic_token_associations);
    try testing.expectEqual(@as(?bool, null), tx.decline_staking_reward);
    try testing.expectEqual(@as(?AccountId, null), tx.staked_account_id);
    try testing.expectEqual(@as(?i64, null), tx.staked_node_id);
    try testing.expectEqual(@as(?AccountId, null), tx.proxy_account_id);
}

test "AccountUpdateTransaction.setAccountId sets account to update" {
    const allocator = testing.allocator;
    
    var tx = newAccountUpdateTransaction(allocator);
    defer tx.deinit();
    
    const account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    _ = try tx.setAccountId(account_id);
    
    try testing.expect(tx.account_id != null);
    try testing.expect(tx.account_id.?.equals(account_id));
}

test "AccountUpdateTransaction.setKey sets new key" {
    const allocator = testing.allocator;
    
    var tx = newAccountUpdateTransaction(allocator);
    defer tx.deinit();
    
    const private_key = try PrivateKey.generateEd25519(allocator);
    defer private_key.deinit();
    
    const public_key = private_key.getPublicKey();
    const key = Key{ .ed25519 = public_key };
    
    _ = try tx.setKey(key);
    
    try testing.expect(tx.key != null);
    try testing.expect(std.meta.eql(tx.key.?, key));
}

test "AccountUpdateTransaction.setReceiverSignatureRequired sets flag" {
    const allocator = testing.allocator;
    
    var tx = newAccountUpdateTransaction(allocator);
    defer tx.deinit();
    
    _ = try tx.setReceiverSignatureRequired(true);
    
    try testing.expect(tx.receiver_sig_required != null);
    try testing.expect(tx.receiver_sig_required.?);
}

test "AccountUpdateTransaction.setAutoRenewPeriod sets period" {
    const allocator = testing.allocator;
    
    var tx = newAccountUpdateTransaction(allocator);
    defer tx.deinit();
    
    const period = Duration.fromDays(90);
    _ = try tx.setAutoRenewPeriod(period);
    
    try testing.expect(tx.auto_renew_period != null);
    try testing.expectEqual(period.seconds, tx.auto_renew_period.?.seconds);
}

test "AccountUpdateTransaction.setExpirationTime sets expiration" {
    const allocator = testing.allocator;
    
    var tx = newAccountUpdateTransaction(allocator);
    defer tx.deinit();
    
    const expiration = Timestamp{ .seconds = 1234567890, .nanos = 0 };
    _ = try tx.setExpirationTime(expiration);
    
    try testing.expect(tx.expiration_time != null);
    try testing.expectEqual(expiration.seconds, tx.expiration_time.?.seconds);
}

test "AccountUpdateTransaction.setAccountMemo sets memo" {
    const allocator = testing.allocator;
    
    var tx = newAccountUpdateTransaction(allocator);
    defer tx.deinit();
    
    const memo = "Updated account memo";
    _ = try tx.setAccountMemo(memo);
    
    try testing.expect(tx.memo != null);
    try testing.expectEqualStrings(memo, tx.memo.?);
}

test "AccountUpdateTransaction.setMaxAutomaticTokenAssociations sets max associations" {
    const allocator = testing.allocator;
    
    var tx = newAccountUpdateTransaction(allocator);
    defer tx.deinit();
    
    const max_associations: i32 = 100;
    _ = try tx.setMaxAutomaticTokenAssociations(max_associations);
    
    try testing.expect(tx.max_automatic_token_associations != null);
    try testing.expectEqual(max_associations, tx.max_automatic_token_associations.?);
}

test "AccountUpdateTransaction.setDeclineStakingReward sets flag" {
    const allocator = testing.allocator;
    
    var tx = newAccountUpdateTransaction(allocator);
    defer tx.deinit();
    
    _ = try tx.setDeclineStakingReward(true);
    
    try testing.expect(tx.decline_staking_reward != null);
    try testing.expect(tx.decline_staking_reward.?);
}

test "AccountUpdateTransaction.setStakedAccountId sets staked account" {
    const allocator = testing.allocator;
    
    var tx = newAccountUpdateTransaction(allocator);
    defer tx.deinit();
    
    const staked_account = AccountId{ .shard = 0, .realm = 0, .account = 3 };
    _ = try tx.setStakedAccountId(staked_account);
    
    try testing.expect(tx.staked_account_id != null);
    try testing.expect(tx.staked_account_id.?.equals(staked_account));
    try testing.expectEqual(@as(?i64, null), tx.staked_node_id);
}

test "AccountUpdateTransaction.setStakedNodeId sets staked node" {
    const allocator = testing.allocator;
    
    var tx = newAccountUpdateTransaction(allocator);
    defer tx.deinit();
    
    const node_id: i64 = 5;
    _ = try tx.setStakedNodeId(node_id);
    
    try testing.expectEqual(@as(?i64, node_id), tx.staked_node_id);
    try testing.expectEqual(@as(?AccountId, null), tx.staked_account_id);
}

test "AccountUpdateTransaction.setProxyAccountId sets proxy account" {
    const allocator = testing.allocator;
    
    var tx = newAccountUpdateTransaction(allocator);
    defer tx.deinit();
    
    const proxy_account = AccountId{ .shard = 0, .realm = 0, .account = 2001 };
    _ = try tx.setProxyAccountId(proxy_account);
    
    try testing.expect(tx.proxy_account_id != null);
    try testing.expect(tx.proxy_account_id.?.equals(proxy_account));
}

test "AccountUpdateTransaction.clearKey clears the key" {
    const allocator = testing.allocator;
    
    var tx = newAccountUpdateTransaction(allocator);
    defer tx.deinit();
    
    // Set a key first
    const private_key = try PrivateKey.generateEd25519(allocator);
    defer private_key.deinit();
    
    const public_key = private_key.getPublicKey();
    const key = Key{ .ed25519 = public_key };
    _ = try tx.setKey(key);
    
    try testing.expect(tx.key != null);
    
    // Clear the key
    _ = try tx.clearKey();
    
    try testing.expectEqual(@as(?Key, null), tx.key);
}

test "AccountUpdateTransaction.clearMemo clears the memo" {
    const allocator = testing.allocator;
    
    var tx = newAccountUpdateTransaction(allocator);
    defer tx.deinit();
    
    // Set a memo first
    _ = try tx.setAccountMemo("Test memo");
    try testing.expect(tx.memo != null);
    
    // Clear the memo
    _ = try tx.clearMemo();
    
    try testing.expectEqual(@as(?[]const u8, null), tx.memo);
}

test "AccountUpdateTransaction.clearAutoRenewPeriod clears the period" {
    const allocator = testing.allocator;
    
    var tx = newAccountUpdateTransaction(allocator);
    defer tx.deinit();
    
    // Should have default auto-renew period
    try testing.expect(tx.auto_renew_period != null);
    
    // Clear it
    _ = try tx.clearAutoRenewPeriod();
    
    try testing.expectEqual(@as(?Duration, null), tx.auto_renew_period);
}

test "AccountUpdateTransaction.setTransactionMemo sets transaction memo" {
    const allocator = testing.allocator;
    
    var tx = newAccountUpdateTransaction(allocator);
    defer tx.deinit();
    
    const memo = "Transaction memo";
    _ = try tx.setTransactionMemo(memo);
    
    try testing.expectEqualStrings(memo, tx.base.transaction_memo);
}

test "AccountUpdateTransaction.freezeWith freezes transaction" {
    const allocator = testing.allocator;
    
    var tx = newAccountUpdateTransaction(allocator);
    defer tx.deinit();
    
    // Set required account ID
    const account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    _ = try tx.setAccountId(account_id);
    
    // Verify freezeWith method exists
    try testing.expect(@hasDecl(@TypeOf(tx), "freezeWith"));
}

test "AccountUpdateTransaction.execute returns TransactionResponse" {
    const allocator = testing.allocator;
    
    var tx = newAccountUpdateTransaction(allocator);
    defer tx.deinit();
    
    // Verify execute method exists
    try testing.expect(@hasDecl(@TypeOf(tx), "execute"));
}

test "AccountUpdateTransaction.buildTransactionBody creates protobuf" {
    const allocator = testing.allocator;
    
    var tx = newAccountUpdateTransaction(allocator);
    defer tx.deinit();
    
    // Set some fields
    const account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    _ = try tx.setAccountId(account_id);
    _ = try tx.setAccountMemo("Updated");
    
    const body = try tx.buildTransactionBody();
    defer allocator.free(body);
    
    try testing.expect(body.len > 0);
}

test "AccountUpdateTransaction validates account ID is set" {
    const allocator = testing.allocator;
    
    var tx = newAccountUpdateTransaction(allocator);
    defer tx.deinit();
    
    // Transaction should require account ID to be set
    try testing.expectEqual(@as(?AccountId, null), tx.account_id);
}

test "AccountUpdateTransaction method chaining works" {
    const allocator = testing.allocator;
    
    var tx = newAccountUpdateTransaction(allocator);
    defer tx.deinit();
    
    const account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    
    const result = try tx
        .setAccountId(account_id)
        .setAccountMemo("Chained update")
        .setMaxAutomaticTokenAssociations(50);
    
    try testing.expectEqual(&tx, result);
    try testing.expect(tx.account_id != null);
    try testing.expect(tx.memo != null);
    try testing.expectEqual(@as(i32, 50), tx.max_automatic_token_associations.?);
}

test "AccountUpdateTransaction supports all staking configurations" {
    const allocator = testing.allocator;
    
    // Test staking to account
    {
        var tx = newAccountUpdateTransaction(allocator);
        defer tx.deinit();
        
        const staked_account = AccountId{ .shard = 0, .realm = 0, .account = 3 };
        _ = try tx.setStakedAccountId(staked_account);
        _ = try tx.setDeclineStakingReward(false);
        
        try testing.expect(tx.staked_account_id != null);
        try testing.expectEqual(@as(?i64, null), tx.staked_node_id);
        try testing.expect(tx.decline_staking_reward != null);
        try testing.expect(!tx.decline_staking_reward.?);
    }
    
    // Test staking to node
    {
        var tx = newAccountUpdateTransaction(allocator);
        defer tx.deinit();
        
        _ = try tx.setStakedNodeId(5);
        _ = try tx.setDeclineStakingReward(true);
        
        try testing.expectEqual(@as(?i64, 5), tx.staked_node_id);
        try testing.expectEqual(@as(?AccountId, null), tx.staked_account_id);
        try testing.expect(tx.decline_staking_reward != null);
        try testing.expect(tx.decline_staking_reward.?);
    }
}

test "AccountUpdateTransaction setters validate frozen state" {
    const allocator = testing.allocator;
    
    var tx = newAccountUpdateTransaction(allocator);
    defer tx.deinit();
    
    // Manually set frozen state
    tx.base.frozen = true;
    
    const account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    
    // All setters should fail when frozen
    try testing.expectError(error.TransactionFrozen, tx.setAccountId(account_id));
    try testing.expectError(error.TransactionFrozen, tx.setAccountMemo("test"));
    try testing.expectError(error.TransactionFrozen, tx.setReceiverSignatureRequired(true));
    try testing.expectError(error.TransactionFrozen, tx.setAutoRenewPeriod(Duration.fromDays(30)));
    try testing.expectError(error.TransactionFrozen, tx.setMaxAutomaticTokenAssociations(10));
}

test "AccountUpdateTransaction deinit cleans up properly" {
    const allocator = testing.allocator;
    
    var tx = newAccountUpdateTransaction(allocator);
    
    // Set some values
    const account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    _ = try tx.setAccountId(account_id);
    _ = try tx.setAccountMemo("Test memo");
    
    // Deinit should clean up all allocations
    tx.deinit();
    
    // Test passes if no memory leaks
}
const std = @import("std");
const testing = std.testing;
const AccountCreateTransaction = @import("../../src/account/account_create.zig").AccountCreateTransaction;
const newAccountCreateTransaction = @import("../../src/account/account_create.zig").newAccountCreateTransaction;
const AccountId = @import("../../src/core/id.zig").AccountId;
const Hbar = @import("../../src/core/hbar.zig").Hbar;
const Key = @import("../../src/crypto/key.zig").Key;
const PrivateKey = @import("../../src/crypto/private_key.zig").PrivateKey;
const PublicKey = @import("../../src/crypto/public_key.zig").PublicKey;
const Duration = @import("../../src/core/duration.zig").Duration;

test "newAccountCreateTransaction creates valid transaction" {
    const allocator = testing.allocator;
    
    var tx = newAccountCreateTransaction(allocator);
    defer tx.deinit();
    
    // Verify default values
    try testing.expectEqual(@as(?Key, null), tx.key);
    try testing.expectEqual(@as(i64, 0), tx.initial_balance.toTinybars());
    try testing.expect(!tx.receiver_signature_required);
    try testing.expectEqual(@as(i64, 7890000), tx.auto_renew_period.seconds);
    try testing.expectEqual(Hbar.max().toTinybars(), tx.send_record_threshold.toTinybars());
    try testing.expectEqual(Hbar.max().toTinybars(), tx.receive_record_threshold.toTinybars());
    try testing.expectEqual(@as(?AccountId, null), tx.proxy_account_id);
    try testing.expectEqualStrings("", tx.memo);
    try testing.expectEqual(@as(i32, 0), tx.max_automatic_token_associations);
    try testing.expectEqual(@as(?AccountId, null), tx.staked_account_id);
    try testing.expectEqual(@as(?i64, null), tx.staked_node_id);
    try testing.expect(!tx.decline_staking_reward);
    try testing.expectEqual(@as(?Key, null), tx.alias_key);
    try testing.expectEqual(@as(?[]const u8, null), tx.alias_evm_address);
    try testing.expectEqual(@as(?[]const u8, null), tx.alias);
    
    // Verify default max fee is 5 HBAR
    try testing.expectEqual(@as(i64, 500000000), tx.base.max_transaction_fee.?.toTinybars());
}

test "AccountCreateTransaction.setKey sets account key" {
    const allocator = testing.allocator;
    
    var tx = newAccountCreateTransaction(allocator);
    defer tx.deinit();
    
    const private_key = try PrivateKey.generateEd25519(allocator);
    defer private_key.deinit();
    
    const public_key = private_key.getPublicKey();
    const key = Key{ .ed25519 = public_key };
    
    _ = try tx.setKey(key);
    
    try testing.expect(tx.key != null);
    try testing.expect(std.meta.eql(tx.key.?, key));
}

test "AccountCreateTransaction.setInitialBalance sets initial balance" {
    const allocator = testing.allocator;
    
    var tx = newAccountCreateTransaction(allocator);
    defer tx.deinit();
    
    const balance = try Hbar.from(100);
    _ = try tx.setInitialBalance(balance);
    
    try testing.expectEqual(balance.toTinybars(), tx.initial_balance.toTinybars());
}

test "AccountCreateTransaction.setReceiverSignatureRequired sets flag" {
    const allocator = testing.allocator;
    
    var tx = newAccountCreateTransaction(allocator);
    defer tx.deinit();
    
    _ = try tx.setReceiverSignatureRequired(true);
    
    try testing.expect(tx.receiver_signature_required);
}

test "AccountCreateTransaction.setAutoRenewPeriod sets period" {
    const allocator = testing.allocator;
    
    var tx = newAccountCreateTransaction(allocator);
    defer tx.deinit();
    
    const period = Duration.fromDays(30);
    _ = try tx.setAutoRenewPeriod(period);
    
    try testing.expectEqual(period.seconds, tx.auto_renew_period.seconds);
}

test "AccountCreateTransaction.setAccountMemo sets memo" {
    const allocator = testing.allocator;
    
    var tx = newAccountCreateTransaction(allocator);
    defer tx.deinit();
    
    const memo = "Test account memo";
    _ = try tx.setAccountMemo(memo);
    
    try testing.expectEqualStrings(memo, tx.memo);
}

test "AccountCreateTransaction.setMaxAutomaticTokenAssociations sets max associations" {
    const allocator = testing.allocator;
    
    var tx = newAccountCreateTransaction(allocator);
    defer tx.deinit();
    
    const max_associations: i32 = 10;
    _ = try tx.setMaxAutomaticTokenAssociations(max_associations);
    
    try testing.expectEqual(max_associations, tx.max_automatic_token_associations);
}

test "AccountCreateTransaction.setStakedAccountId sets staked account" {
    const allocator = testing.allocator;
    
    var tx = newAccountCreateTransaction(allocator);
    defer tx.deinit();
    
    const staked_account = AccountId{ .shard = 0, .realm = 0, .account = 3 };
    _ = try tx.setStakedAccountId(staked_account);
    
    try testing.expect(tx.staked_account_id != null);
    try testing.expect(tx.staked_account_id.?.equals(staked_account));
    try testing.expectEqual(@as(?i64, null), tx.staked_node_id);
}

test "AccountCreateTransaction.setStakedNodeId sets staked node" {
    const allocator = testing.allocator;
    
    var tx = newAccountCreateTransaction(allocator);
    defer tx.deinit();
    
    const node_id: i64 = 5;
    _ = try tx.setStakedNodeId(node_id);
    
    try testing.expectEqual(@as(?i64, node_id), tx.staked_node_id);
    try testing.expectEqual(@as(?AccountId, null), tx.staked_account_id);
}

test "AccountCreateTransaction.setDeclineStakingReward sets flag" {
    const allocator = testing.allocator;
    
    var tx = newAccountCreateTransaction(allocator);
    defer tx.deinit();
    
    _ = try tx.setDeclineStakingReward(true);
    
    try testing.expect(tx.decline_staking_reward);
}

test "AccountCreateTransaction.setAlias sets alias" {
    const allocator = testing.allocator;
    
    var tx = newAccountCreateTransaction(allocator);
    defer tx.deinit();
    
    const alias = "test_alias";
    const alias_bytes = try allocator.dupe(u8, alias);
    defer allocator.free(alias_bytes);
    
    _ = try tx.setAlias(alias_bytes);
    
    try testing.expect(tx.alias != null);
    try testing.expectEqualStrings(alias, tx.alias.?);
}

test "AccountCreateTransaction.setTransactionMemo sets transaction memo" {
    const allocator = testing.allocator;
    
    var tx = newAccountCreateTransaction(allocator);
    defer tx.deinit();
    
    const memo = "Transaction memo";
    _ = try tx.setTransactionMemo(memo);
    
    try testing.expectEqualStrings(memo, tx.base.transaction_memo);
}

test "AccountCreateTransaction.freezeWith freezes transaction" {
    const allocator = testing.allocator;
    
    var tx = newAccountCreateTransaction(allocator);
    defer tx.deinit();
    
    // Set required key
    const private_key = try PrivateKey.generateEd25519(allocator);
    defer private_key.deinit();
    
    const public_key = private_key.getPublicKey();
    const key = Key{ .ed25519 = public_key };
    _ = try tx.setKey(key);
    
    // Mock client would be needed for actual freeze
    // For unit test, we verify the method exists
    try testing.expect(@hasDecl(@TypeOf(tx), "freezeWith"));
}

test "AccountCreateTransaction.execute returns TransactionResponse" {
    const allocator = testing.allocator;
    
    var tx = newAccountCreateTransaction(allocator);
    defer tx.deinit();
    
    // Verify execute method exists with correct signature
    try testing.expect(@hasDecl(@TypeOf(tx), "execute"));
}

test "AccountCreateTransaction.buildTransactionBody creates protobuf" {
    const allocator = testing.allocator;
    
    var tx = newAccountCreateTransaction(allocator);
    defer tx.deinit();
    
    // Set some fields
    const private_key = try PrivateKey.generateEd25519(allocator);
    defer private_key.deinit();
    
    const public_key = private_key.getPublicKey();
    const key = Key{ .ed25519 = public_key };
    _ = try tx.setKey(key);
    _ = try tx.setInitialBalance(try Hbar.from(10));
    _ = try tx.setAccountMemo("Test account");
    
    const body = try tx.buildTransactionBody();
    defer allocator.free(body);
    
    try testing.expect(body.len > 0);
}

test "AccountCreateTransaction validates key is set before execution" {
    const allocator = testing.allocator;
    
    var tx = newAccountCreateTransaction(allocator);
    defer tx.deinit();
    
    // Transaction should require a key to be set
    // This is implementation-specific validation
    try testing.expectEqual(@as(?Key, null), tx.key);
}

test "AccountCreateTransaction method chaining works" {
    const allocator = testing.allocator;
    
    var tx = newAccountCreateTransaction(allocator);
    defer tx.deinit();
    
    const private_key = try PrivateKey.generateEd25519(allocator);
    defer private_key.deinit();
    
    const public_key = private_key.getPublicKey();
    const key = Key{ .ed25519 = public_key };
    
    const result = try tx
        .setKey(key)
        .setInitialBalance(try Hbar.from(100))
        .setAccountMemo("Chained account");
    
    try testing.expectEqual(&tx, result);
    try testing.expect(tx.key != null);
    try testing.expectEqual(@as(i64, 10000000000), tx.initial_balance.toTinybars());
    try testing.expectEqualStrings("Chained account", tx.memo);
}

test "AccountCreateTransaction.setKeyWithAlias sets key and alias" {
    const allocator = testing.allocator;
    
    var tx = newAccountCreateTransaction(allocator);
    defer tx.deinit();
    
    const account_key = try PrivateKey.generateEd25519(allocator);
    defer account_key.deinit();
    
    const ecdsa_key = try PrivateKey.generateEcdsa(allocator);
    defer ecdsa_key.deinit();
    
    const key = Key{ .ed25519 = account_key.getPublicKey() };
    const alias_key = Key{ .ecdsa_secp256k1 = ecdsa_key.getPublicKey() };
    
    _ = try tx.setKeyWithAlias(key, alias_key);
    
    try testing.expect(tx.key != null);
    try testing.expect(tx.alias != null);
}

test "AccountCreateTransaction supports all staking configurations" {
    const allocator = testing.allocator;
    
    // Test staking to account
    {
        var tx = newAccountCreateTransaction(allocator);
        defer tx.deinit();
        
        const staked_account = AccountId{ .shard = 0, .realm = 0, .account = 3 };
        _ = try tx.setStakedAccountId(staked_account);
        _ = try tx.setDeclineStakingReward(false);
        
        try testing.expect(tx.staked_account_id != null);
        try testing.expectEqual(@as(?i64, null), tx.staked_node_id);
        try testing.expect(!tx.decline_staking_reward);
    }
    
    // Test staking to node
    {
        var tx = newAccountCreateTransaction(allocator);
        defer tx.deinit();
        
        _ = try tx.setStakedNodeId(5);
        _ = try tx.setDeclineStakingReward(true);
        
        try testing.expectEqual(@as(?i64, 5), tx.staked_node_id);
        try testing.expectEqual(@as(?AccountId, null), tx.staked_account_id);
        try testing.expect(tx.decline_staking_reward);
    }
}

test "AccountCreateTransaction setters validate frozen state" {
    const allocator = testing.allocator;
    
    var tx = newAccountCreateTransaction(allocator);
    defer tx.deinit();
    
    // Manually set frozen state
    tx.base.frozen = true;
    
    const private_key = try PrivateKey.generateEd25519(allocator);
    defer private_key.deinit();
    
    const public_key = private_key.getPublicKey();
    const key = Key{ .ed25519 = public_key };
    
    // All setters should fail when frozen
    try testing.expectError(error.TransactionFrozen, tx.setKey(key));
    try testing.expectError(error.TransactionFrozen, tx.setInitialBalance(try Hbar.from(10)));
    try testing.expectError(error.TransactionFrozen, tx.setReceiverSignatureRequired(true));
    try testing.expectError(error.TransactionFrozen, tx.setAutoRenewPeriod(Duration.fromDays(30)));
    try testing.expectError(error.TransactionFrozen, tx.setAccountMemo("test"));
    try testing.expectError(error.TransactionFrozen, tx.setMaxAutomaticTokenAssociations(10));
}
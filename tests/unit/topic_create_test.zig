const std = @import("std");
const testing = std.testing;
const hedera = @import("hedera");

test "TopicCreateTransaction factory creates valid instance" {
    const allocator = testing.allocator;
    
    // Create transaction using factory
    const tx = try hedera.newTopicCreateTransaction(allocator);
    defer tx.deinit();
    
    // Verify it's properly initialized
    try testing.expect(tx.admin_key == null);
    try testing.expect(tx.submit_key == null);
    try testing.expect(tx.fee_schedule_key == null);
    try testing.expectEqual(tx.fee_exempt_keys.items.len, 0);
    try testing.expectEqual(tx.custom_fees.items.len, 0);
    try testing.expectEqualStrings(tx.memo, "");
    try testing.expect(tx.auto_renew_account_id == null);
    try testing.expect(tx.auto_renew_period.seconds > 0); // Has default value
}

test "TopicCreateTransaction basic topic creation" {
    const allocator = testing.allocator;
    
    const tx = try hedera.newTopicCreateTransaction(allocator);
    defer tx.deinit();
    
    // Set topic memo
    _ = try tx.setTopicMemo("Test topic memo");
    try testing.expectEqualStrings(tx.getTopicMemo(), "Test topic memo");
    
    // Set auto renew period
    const period = hedera.Duration.fromDays(30);
    _ = try tx.setAutoRenewPeriod(period);
    try testing.expectEqual(tx.getAutoRenewPeriod().seconds, period.seconds);
    
    // Set auto renew account
    const auto_renew_account = hedera.AccountId.init(0, 0, 100);
    _ = try tx.setAutoRenewAccountId(auto_renew_account);
    try testing.expect(tx.getAutoRenewAccountID().equals(auto_renew_account));
}

test "TopicCreateTransaction with admin key" {
    const allocator = testing.allocator;
    
    const tx = try hedera.newTopicCreateTransaction(allocator);
    defer tx.deinit();
    
    // Create test key
    const private_key = try hedera.Ed25519PrivateKey.generate();
    defer private_key.deinit();
    const public_key = private_key.getPublicKey();
    const key = hedera.Key.fromPublicKey(public_key);
    
    // Set admin key
    _ = try tx.setAdminKey(key);
    const retrieved_key = try tx.getAdminKey();
    try testing.expect(retrieved_key.equals(key));
}

test "TopicCreateTransaction with submit key" {
    const allocator = testing.allocator;
    
    const tx = try hedera.newTopicCreateTransaction(allocator);
    defer tx.deinit();
    
    // Create test key
    const private_key = try hedera.Ed25519PrivateKey.generate();
    defer private_key.deinit();
    const public_key = private_key.getPublicKey();
    const key = hedera.Key.fromPublicKey(public_key);
    
    // Set submit key
    _ = try tx.setSubmitKey(key);
    const retrieved_key = try tx.getSubmitKey();
    try testing.expect(retrieved_key.equals(key));
}

test "TopicCreateTransaction with fee schedule key" {
    const allocator = testing.allocator;
    
    const tx = try hedera.newTopicCreateTransaction(allocator);
    defer tx.deinit();
    
    // Create test key
    const private_key = try hedera.Ed25519PrivateKey.generate();
    defer private_key.deinit();
    const public_key = private_key.getPublicKey();
    const key = hedera.Key.fromPublicKey(public_key);
    
    // Set fee schedule key
    _ = try tx.setFeeScheduleKey(key);
    const retrieved_key = tx.getFeeScheduleKey();
    try testing.expect(retrieved_key.equals(key));
}

test "TopicCreateTransaction fee exempt keys" {
    const allocator = testing.allocator;
    
    const tx = try hedera.newTopicCreateTransaction(allocator);
    defer tx.deinit();
    
    // Create test keys
    const private_key1 = try hedera.Ed25519PrivateKey.generate();
    defer private_key1.deinit();
    const private_key2 = try hedera.Ed25519PrivateKey.generate();
    defer private_key2.deinit();
    const private_key3 = try hedera.Ed25519PrivateKey.generate();
    defer private_key3.deinit();
    
    const key1 = hedera.Key.fromPublicKey(private_key1.getPublicKey());
    const key2 = hedera.Key.fromPublicKey(private_key2.getPublicKey());
    const key3 = hedera.Key.fromPublicKey(private_key3.getPublicKey());
    
    // Add fee exempt keys individually
    _ = try tx.addFeeExemptKey(key1);
    _ = try tx.addFeeExemptKey(key2);
    try testing.expectEqual(tx.getFeeExemptKeys().len, 2);
    
    // Set fee exempt keys as array
    const keys = [_]hedera.Key{ key2, key3 };
    _ = try tx.setFeeExemptKeys(&keys);
    try testing.expectEqual(tx.getFeeExemptKeys().len, 2);
    
    // Clear fee exempt keys
    _ = try tx.clearFeeExemptKeys();
    try testing.expectEqual(tx.getFeeExemptKeys().len, 0);
}

test "TopicCreateTransaction custom fees" {
    const allocator = testing.allocator;
    
    const tx = try hedera.newTopicCreateTransaction(allocator);
    defer tx.deinit();
    
    // Create custom fixed fees
    const fee_collector = hedera.AccountId.init(0, 0, 200);
    const fee1 = try allocator.create(hedera.CustomFixedFee);
    fee1.* = hedera.CustomFixedFee.init(100, fee_collector);
    
    const fee2 = try allocator.create(hedera.CustomFixedFee);
    fee2.* = hedera.CustomFixedFee.init(200, fee_collector);
    
    // Add custom fees individually
    _ = try tx.addCustomFee(fee1);
    try testing.expectEqual(tx.getCustomFees().len, 1);
    try testing.expectEqual(tx.getCustomFees()[0].amount, 100);
    
    // Set custom fees as array
    const fees = [_]*hedera.CustomFixedFee{ fee2 };
    _ = try tx.setCustomFees(&fees);
    try testing.expectEqual(tx.getCustomFees().len, 1);
    try testing.expectEqual(tx.getCustomFees()[0].amount, 200);
    
    // Clear custom fees
    _ = try tx.clearCustomFees();
    try testing.expectEqual(tx.getCustomFees().len, 0);
    
    // Note: fees are cleaned up by tx.deinit()
}

test "TopicCreateTransaction key getters without keys set" {
    const allocator = testing.allocator;
    
    const tx = try hedera.newTopicCreateTransaction(allocator);
    defer tx.deinit();
    
    // Test getters when keys are not set
    const admin_result = tx.getAdminKey();
    try testing.expectError(error.AdminKeyNotSet, admin_result);
    
    const submit_result = tx.getSubmitKey();
    try testing.expectError(error.SubmitKeyNotSet, submit_result);
    
    // Fee schedule key returns empty key when not set
    const fee_schedule_key = tx.getFeeScheduleKey();
    try testing.expect(fee_schedule_key.isEmpty());
}

test "TopicCreateTransaction transaction methods" {
    const allocator = testing.allocator;
    
    const tx = try hedera.newTopicCreateTransaction(allocator);
    defer tx.deinit();
    
    // Test max transaction fee
    const fee = try hedera.Hbar.fromHbars(10);
    _ = tx.setMaxTransactionFee(fee);
    try testing.expect(tx.getMaxTransactionFee().?.equals(fee));
    
    // Test transaction memo
    _ = tx.setTransactionMemo("Transaction memo");
    try testing.expectEqualStrings(tx.getTransactionMemo(), "Transaction memo");
    
    // Test node account IDs
    const node_ids = [_]hedera.AccountId{
        hedera.AccountId.init(0, 0, 3),
        hedera.AccountId.init(0, 0, 4),
    };
    _ = tx.setNodeAccountIDs(&node_ids);
    const retrieved_nodes = tx.getNodeAccountIDs();
    try testing.expectEqual(retrieved_nodes.len, 2);
    try testing.expect(retrieved_nodes[0].equals(node_ids[0]));
    try testing.expect(retrieved_nodes[1].equals(node_ids[1]));
}

test "TopicCreateTransaction freezeWith" {
    const allocator = testing.allocator;
    
    const tx = try hedera.newTopicCreateTransaction(allocator);
    defer tx.deinit();
    
    // Set some fields
    _ = try tx.setTopicMemo("Freeze test");
    
    // Freeze without client
    _ = try tx.freezeWith(null);
    
    // Verify transaction is frozen
    try testing.expect(tx.transaction.frozen);
    try testing.expect(tx.transaction.transaction_id != null);
}

test "TopicCreateTransaction freeze alias" {
    const allocator = testing.allocator;
    
    const tx = try hedera.newTopicCreateTransaction(allocator);
    defer tx.deinit();
    
    // Set some fields
    _ = try tx.setTopicMemo("Freeze alias test");
    
    // Test freeze method (alias for freezeWith(null))
    _ = try tx.freeze();
    
    // Verify transaction is frozen
    try testing.expect(tx.transaction.frozen);
}

test "TopicCreateTransaction execute" {
    const allocator = testing.allocator;
    
    const tx = try hedera.newTopicCreateTransaction(allocator);
    defer tx.deinit();
    
    // Set required fields
    _ = try tx.setTopicMemo("Execute test");
    
    // Execute should call underlying transaction execute
    // Note: This will fail with network error, but we test the call path
    const result = tx.execute(null);
    try testing.expectError(error.ClientNotProvided, result);
}

test "TopicCreateTransaction sign methods" {
    const allocator = testing.allocator;
    
    const tx = try hedera.newTopicCreateTransaction(allocator);
    defer tx.deinit();
    
    // Create test keys
    const private_key = try hedera.Ed25519PrivateKey.generate();
    defer private_key.deinit();
    const public_key = private_key.getPublicKey();
    
    // Test sign method
    _ = try tx.sign(private_key);
    
    // Test signWith method
    _ = tx.signWith(public_key, private_key);
    
    // Both should succeed without errors
    try testing.expect(true);
}

test "TopicCreateTransaction frozen state protection" {
    const allocator = testing.allocator;
    
    const tx = try hedera.newTopicCreateTransaction(allocator);
    defer tx.deinit();
    
    // Manually freeze the transaction
    tx.transaction.frozen = true;
    
    // Verify all setters fail when frozen
    const private_key = try hedera.Ed25519PrivateKey.generate();
    defer private_key.deinit();
    const key = hedera.Key.fromPublicKey(private_key.getPublicKey());
    
    const admin_result = tx.setAdminKey(key);
    try testing.expectError(hedera.errors.HederaError.TransactionIsFrozen, admin_result);
    
    const submit_result = tx.setSubmitKey(key);
    try testing.expectError(hedera.errors.HederaError.TransactionIsFrozen, submit_result);
    
    const fee_schedule_result = tx.setFeeScheduleKey(key);
    try testing.expectError(hedera.errors.HederaError.TransactionIsFrozen, fee_schedule_result);
    
    const memo_result = tx.setTopicMemo("frozen test");
    try testing.expectError(hedera.errors.HederaError.TransactionIsFrozen, memo_result);
    
    const period_result = tx.setAutoRenewPeriod(hedera.Duration.fromDays(30));
    try testing.expectError(hedera.errors.HederaError.TransactionIsFrozen, period_result);
    
    const account_result = tx.setAutoRenewAccountId(hedera.AccountId.init(0, 0, 100));
    try testing.expectError(hedera.errors.HederaError.TransactionIsFrozen, account_result);
    
    const exempt_key_result = tx.addFeeExemptKey(key);
    try testing.expectError(hedera.errors.HederaError.TransactionIsFrozen, exempt_key_result);
    
    const fee_collector = hedera.AccountId.init(0, 0, 200);
    const fee = try allocator.create(hedera.CustomFixedFee);
    defer allocator.destroy(fee);
    fee.* = hedera.CustomFixedFee.init(100, fee_collector);
    const custom_fee_result = tx.addCustomFee(fee);
    try testing.expectError(hedera.errors.HederaError.TransactionIsFrozen, custom_fee_result);
}

test "TopicCreateTransaction default values" {
    const allocator = testing.allocator;
    
    const tx = try hedera.newTopicCreateTransaction(allocator);
    defer tx.deinit();
    
    // Verify default auto renew period is set (7890000 seconds = ~3 months)
    try testing.expectEqual(tx.getAutoRenewPeriod().seconds, 7890000);
    
    // Verify default max transaction fee is set (25 Hbar = 2500000000 tinybars)
    const default_fee = tx.getMaxTransactionFee();
    try testing.expect(default_fee != null);
    try testing.expectEqual(default_fee.?.toTinybars(), 2500000000);
}

test "TopicCreateTransaction complex scenario" {
    const allocator = testing.allocator;
    
    const tx = try hedera.newTopicCreateTransaction(allocator);
    defer tx.deinit();
    
    // Create multiple keys
    const admin_private = try hedera.Ed25519PrivateKey.generate();
    defer admin_private.deinit();
    const submit_private = try hedera.Ed25519PrivateKey.generate();
    defer submit_private.deinit();
    const fee_schedule_private = try hedera.Ed25519PrivateKey.generate();
    defer fee_schedule_private.deinit();
    const exempt_private = try hedera.Ed25519PrivateKey.generate();
    defer exempt_private.deinit();
    
    const admin_key = hedera.Key.fromPublicKey(admin_private.getPublicKey());
    const submit_key = hedera.Key.fromPublicKey(submit_private.getPublicKey());
    const fee_schedule_key = hedera.Key.fromPublicKey(fee_schedule_private.getPublicKey());
    const exempt_key = hedera.Key.fromPublicKey(exempt_private.getPublicKey());
    
    // Configure complex topic
    _ = try tx.setAdminKey(admin_key);
    _ = try tx.setSubmitKey(submit_key);
    _ = try tx.setFeeScheduleKey(fee_schedule_key);
    _ = try tx.addFeeExemptKey(exempt_key);
    _ = try tx.setTopicMemo("Complex topic with all features");
    _ = try tx.setAutoRenewPeriod(hedera.Duration.fromDays(90));
    _ = try tx.setAutoRenewAccountId(hedera.AccountId.init(0, 0, 500));
    
    // Add custom fee
    const fee_collector = hedera.AccountId.init(0, 0, 600);
    const fee = try allocator.create(hedera.CustomFixedFee);
    fee.* = hedera.CustomFixedFee.init(1000, fee_collector);
    _ = try tx.addCustomFee(fee);
    
    // Set transaction properties
    _ = tx.setMaxTransactionFee(try hedera.Hbar.fromHbars(50));
    _ = tx.setTransactionMemo("Complex topic creation transaction");
    
    // Verify all values are set correctly
    try testing.expect((try tx.getAdminKey()).equals(admin_key));
    try testing.expect((try tx.getSubmitKey()).equals(submit_key));
    try testing.expect(tx.getFeeScheduleKey().equals(fee_schedule_key));
    try testing.expectEqual(tx.getFeeExemptKeys().len, 1);
    try testing.expectEqualStrings(tx.getTopicMemo(), "Complex topic with all features");
    try testing.expectEqual(tx.getAutoRenewPeriod().seconds, hedera.Duration.fromDays(90).seconds);
    try testing.expect(tx.getAutoRenewAccountID().equals(hedera.AccountId.init(0, 0, 500)));
    try testing.expectEqual(tx.getCustomFees().len, 1);
    try testing.expectEqual(tx.getCustomFees()[0].amount, 1000);
    try testing.expectEqualStrings(tx.getTransactionMemo(), "Complex topic creation transaction");
}

test "TopicCreateTransaction custom fee management" {
    const allocator = testing.allocator;
    
    const tx = try hedera.newTopicCreateTransaction(allocator);
    defer tx.deinit();
    
    const fee_collector = hedera.AccountId.init(0, 0, 300);
    
    // Create multiple fees
    const fee1 = try allocator.create(hedera.CustomFixedFee);
    fee1.* = hedera.CustomFixedFee.init(100, fee_collector);
    const fee2 = try allocator.create(hedera.CustomFixedFee);
    fee2.* = hedera.CustomFixedFee.init(200, fee_collector);
    const fee3 = try allocator.create(hedera.CustomFixedFee);
    fee3.* = hedera.CustomFixedFee.init(300, fee_collector);
    
    // Add fees individually
    _ = try tx.addCustomFee(fee1);
    _ = try tx.addCustomFee(fee2);
    try testing.expectEqual(tx.getCustomFees().len, 2);
    
    // Replace all fees with new array
    const new_fees = [_]*hedera.CustomFixedFee{fee3};
    _ = try tx.setCustomFees(&new_fees);
    try testing.expectEqual(tx.getCustomFees().len, 1);
    try testing.expectEqual(tx.getCustomFees()[0].amount, 300);
    
    // Clear all fees
    _ = try tx.clearCustomFees();
    try testing.expectEqual(tx.getCustomFees().len, 0);
}

test "TopicCreateTransaction edge cases" {
    const allocator = testing.allocator;
    
    const tx = try hedera.newTopicCreateTransaction(allocator);
    defer tx.deinit();
    
    // Test empty memo
    _ = try tx.setTopicMemo("");
    try testing.expectEqualStrings(tx.getTopicMemo(), "");
    
    // Test zero auto renew period (edge case)
    const zero_period = hedera.Duration{ .seconds = 0, .nanos = 0 };
    _ = try tx.setAutoRenewPeriod(zero_period);
    try testing.expectEqual(tx.getAutoRenewPeriod().seconds, 0);
    
    // Test auto renew account ID with zero values
    const zero_account = hedera.AccountId.init(0, 0, 0);
    _ = try tx.setAutoRenewAccountId(zero_account);
    try testing.expect(tx.getAutoRenewAccountID().equals(zero_account));
    
    // Test getAutoRenewAccountID when not set
    const tx2 = try hedera.newTopicCreateTransaction(allocator);
    defer tx2.deinit();
    const empty_account = tx2.getAutoRenewAccountID();
    try testing.expectEqual(empty_account.shard, 0);
    try testing.expectEqual(empty_account.realm, 0);
    try testing.expectEqual(empty_account.account, 0);
}

test "TopicCreateTransaction CustomFixedFee structure" {
    _ = testing.allocator; // Not used in this test
    
    const fee_collector = hedera.AccountId.init(0, 0, 400);
    
    // Test CustomFixedFee initialization
    const fee = hedera.CustomFixedFee.init(500, fee_collector);
    try testing.expectEqual(fee.amount, 500);
    try testing.expect(fee.fee_collector_account_id.equals(fee_collector));
    try testing.expect(fee.denomination_token_id == null);
    
    // Test with denomination token ID
    var fee_with_token = hedera.CustomFixedFee.init(1000, fee_collector);
    fee_with_token.denomination_token_id = "0.0.1001";
    try testing.expectEqual(fee_with_token.amount, 1000);
    try testing.expectEqualStrings(fee_with_token.denomination_token_id.?, "0.0.1001");
}

test "TopicCreateTransaction memory management" {
    const allocator = testing.allocator;
    
    // Test proper cleanup of dynamically allocated fees
    const tx = try hedera.newTopicCreateTransaction(allocator);
    
    const fee_collector = hedera.AccountId.init(0, 0, 500);
    
    // Add multiple fees
    for (0..5) |i| {
        const fee = try allocator.create(hedera.CustomFixedFee);
        fee.* = hedera.CustomFixedFee.init(@intCast(i * 100), fee_collector);
        _ = try tx.addCustomFee(fee);
    }
    
    try testing.expectEqual(tx.getCustomFees().len, 5);
    
    // deinit should properly clean up all allocated fees
    tx.deinit();
    
    // Test passed if no memory leaks occur
    try testing.expect(true);
}
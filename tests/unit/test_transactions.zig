const std = @import("std");
const testing = std.testing;
const hedera = @import("hedera");

test "Transaction base functionality" {
    const allocator = testing.allocator;
    
    var transaction = hedera.Transaction.init(allocator);
    defer transaction.deinit();
    
    // Test initial state
    try testing.expect(!transaction.frozen);
    try testing.expect(transaction.transaction_id == null);
    try testing.expect(transaction.node_delete_account_ids.items.len == 0);
    try testing.expect(transaction.max_transaction_fee == null);
    
    // Test setting transaction memo
    _ = try transaction.setTransactionMemo("Test transaction memo");
    try testing.expectEqualStrings("Test transaction memo", transaction.transaction_memo);
    
    // Test setting node account IDs
    _ = try transaction.addNodeAccountId(hedera.AccountId.init(0, 0, 3));
    _ = try transaction.addNodeAccountId(hedera.AccountId.init(0, 0, 4));
    
    try testing.expectEqual(@as(usize, 2), transaction.node_delete_account_ids.items.len);
    try testing.expect(transaction.node_delete_account_ids.items[0].equals(hedera.AccountId.init(0, 0, 3)));
    try testing.expect(transaction.node_delete_account_ids.items[1].equals(hedera.AccountId.init(0, 0, 4)));
    
    // Test setting max transaction fee
    _ = try transaction.setMaxTransactionFee(hedera.Hbar.from(1));
    try testing.expect(transaction.max_transaction_fee != null);
    try testing.expectEqual(@as(f64, 1.0), transaction.max_transaction_fee.?.toHbars());
    
    // Test setting transaction valid duration
    transaction.setTransactionValidDuration(hedera.Duration.fromMinutes(3));
    try testing.expectEqual(@as(i64, 180), transaction.transaction_valid_duration.seconds);
}

test "Transaction ID generation and setting" {
    const allocator = testing.allocator;
    
    var transaction = hedera.Transaction.init(allocator);
    defer transaction.deinit();
    
    const account_id = hedera.AccountId.init(0, 0, 123);
    
    // Test setting transaction ID
    const tx_id = hedera.TransactionId.generate(account_id);
    _ = try transaction.setTransactionId(tx_id);
    
    try testing.expect(transaction.transaction_id != null);
    try testing.expect(transaction.transaction_id.?.account_id.equals(account_id));
    try testing.expect(transaction.transaction_id.?.isValid());
    
    // Test that frozen transactions cannot be modified
    var client = try hedera.Client.forTestnet(allocator);
    defer client.deinit();
    
    transaction.freezeWith(&client);
    try testing.expect(transaction.frozen);
    
    // Should fail to modify frozen transaction
    try testing.expectError(error.TransactionIsFrozen, transaction.setTransactionMemo("Should fail"));
    try testing.expectError(error.TransactionIsFrozen, transaction.setMaxTransactionFee(hedera.Hbar.from(2)));
}

test "Transaction signing" {
    const allocator = testing.allocator;
    
    var transaction = hedera.Transaction.init(allocator);
    defer transaction.deinit();
    
    // Set up transaction
    const account_id = hedera.AccountId.init(0, 0, 123);
    const tx_id = hedera.TransactionId.generate(account_id);
    _ = try transaction.setTransactionId(tx_id);
    _ = try transaction.addNodeAccountId(hedera.AccountId.init(0, 0, 3));
    
    var client = try hedera.Client.forTestnet(allocator);
    defer client.deinit();
    
    transaction.freezeWith(&client);
    
    // Test signing with private key
    var private_key = try hedera.PrivateKey.generateEd25519(allocator);
    defer private_key.deinit();
    
    try transaction.sign(private_key);
    
    // Verify signature was added
    try testing.expect(transaction.signature_map.signatures.items.len > 0);
    
    // Test signing with multiple keys
    var second_key = try hedera.PrivateKey.generateEcdsa(allocator);
    defer second_key.deinit();
    
    try transaction.sign(second_key);
    
    try testing.expect(transaction.signature_map.signatures.items.len >= 2);
    
    // Test that unsigned transactions fail validation
    var unsigned_tx = hedera.Transaction.init(allocator);
    defer unsigned_tx.deinit();
    
    _ = try unsigned_tx.setTransactionId(tx_id);
    _ = try unsigned_tx.addNodeAccountId(hedera.AccountId.init(0, 0, 3));
    unsigned_tx.freezeWith(&client);
    
    // Should have no signatures
    try testing.expectEqual(@as(usize, 0), unsigned_tx.signature_map.signatures.items.len);
}

test "AccountCreateTransaction" {
    const allocator = testing.allocator;
    
    var account_create = hedera.AccountCreateTransaction.init(allocator);
    defer account_create.deinit();
    
    // Test setting properties
    var key = try hedera.PrivateKey.generateEd25519(allocator);
    defer key.deinit();
    
    _ = try account_create.setKey(key.getPublicKey());
    _ = try account_create.setInitialBalance(hedera.Hbar.from(10));
    _ = try account_create.setAccountMemo("Test account memo");
    _ = try account_create.setMaxAutomaticTokenAssociations(100);
    _ = try account_create.setReceiverSignatureRequired(true);
    _ = try account_create.setAutoRenewPeriod(hedera.Duration.fromDays(90));
    
    // Verify properties were set
    try testing.expect(account_create.key != null);
    try testing.expect(account_create.initial_balance != null);
    try testing.expectEqual(@as(f64, 10.0), account_create.initial_balance.?.toHbars());
    try testing.expectEqualStrings("Test account memo", account_create.account_memo);
    try testing.expectEqual(@as(u32, 100), account_create.max_automatic_token_associations.?);
    try testing.expectEqual(true, account_create.is_receiver_signature_required.?);
    try testing.expectEqual(@as(i64, 7776000), account_create.auto_renew_period.?.seconds); // 90 days
    
    // Test that transaction can be built
    const tx_body = try account_create.buildTransactionBody();
    defer allocator.free(tx_body);
    
    try testing.expect(tx_body.len > 0);
}

test "TransferTransaction" {
    const allocator = testing.allocator;
    
    var transfer = hedera.TransferTransaction.init(allocator);
    defer transfer.deinit();
    
    // Test HBAR transfers
    const account1 = hedera.AccountId.init(0, 0, 123);
    const account2 = hedera.AccountId.init(0, 0, 456);
    
    _ = try transfer.addHbarTransfer(account1, hedera.Hbar.from(-10));
    _ = try transfer.addHbarTransfer(account2, hedera.Hbar.from(10));
    
    // Verify transfers were added
    try testing.expectEqual(@as(usize, 2), transfer.hbar_transfers.items.len);
    
    // Check that transfers balance to zero
    var total = hedera.Hbar.ZERO;
    for (transfer.hbar_transfers.items) |hbar_transfer| {
        total = total.add(hbar_transfer.amount);
    }
    try testing.expectEqual(@as(i64, 0), total.toTinybars());
    
    // Test token transfers
    const token_id = hedera.TokenId.init(0, 0, 1000);
    
    try transfer.addTokenTransfer(token_id, account1, -500);
    try transfer.addTokenTransfer(token_id, account2, 500);
    
    // Verify token transfers were added
    try testing.expect(transfer.token_transfers.contains(token_id));
    const token_transfer_list = transfer.token_transfers.get(token_id).?;
    try testing.expectEqual(@as(usize, 2), token_transfer_list.items.len);
    
    // Check that token transfers balance to zero
    var token_total: i64 = 0;
    for (token_transfer_list.items) |token_transfer| {
        token_total += token_transfer.amount;
    }
    try testing.expectEqual(@as(i64, 0), token_total);
    
    // Test NFT transfers
    const nft_id = hedera.NftId.init(token_id, 123);
    
    try transfer.addNftTransfer(nft_id, account1, account2);
    
    // Verify NFT transfer was added
    try testing.expectEqual(@as(usize, 1), transfer.nft_transfers.items.len);
    try testing.expect(transfer.nft_transfers.items[0].nft_id.equals(nft_id));
    try testing.expect(transfer.nft_transfers.items[0].sender_delete_account_id.equals(account1));
    try testing.expect(transfer.nft_transfers.items[0].receiver_delete_account_id.equals(account2));
    
    // Test transaction body building
    const tx_body = try transfer.buildTransactionBody();
    defer allocator.free(tx_body);
    
    try testing.expect(tx_body.len > 0);
}

test "TokenCreateTransaction" {
    const allocator = testing.allocator;
    
    var token_create = hedera.TokenCreateTransaction.init(allocator);
    defer token_create.deinit();
    
    // Test setting token properties
    _ = try token_create.setTokenName("Test Token");
    _ = try token_create.setTokenSymbol("TEST");
    _ = try token_create.setDecimals(8);
    _ = try token_create.setInitialSupply(1000000);
    _ = try token_create.setTreasuryAccountId(hedera.AccountId.init(0, 0, 123));
    _ = try token_create.setTokenType(hedera.TokenType.FungibleCommon);
    _ = try token_create.setSupplyType(hedera.TokenSupplyType.Finite);
    _ = try token_create.setMaxSupply(10000000);
    _ = try token_create.setFreezeDefault(false);
    _ = try token_create.setTokenMemo("Test token memo");
    
    var admin_key = try hedera.PrivateKey.generateEd25519(allocator);
    defer admin_key.deinit();
    
    _ = try token_create.setAdminKey(admin_key.getPublicKey());
    _ = try token_create.setSupplyKey(admin_key.getPublicKey());
    _ = try token_create.setFreezeKey(admin_key.getPublicKey());
    _ = try token_create.setWipeKey(admin_key.getPublicKey());
    _ = try token_create.setKycKey(admin_key.getPublicKey());
    _ = try token_create.setPauseKey(admin_key.getPublicKey());
    
    _ = try token_create.setAutoRenewAccountId(hedera.AccountId.init(0, 0, 123));
    _ = try token_create.setAutoRenewPeriod(hedera.Duration.fromDays(90));
    _ = try token_create.setExpirationTime(hedera.Timestamp.fromUnixSeconds(std.time.timestamp() + 7776000));
    
    // Verify properties were set
    try testing.expectEqualStrings("Test Token", token_create.token_name);
    try testing.expectEqualStrings("TEST", token_create.token_symbol);
    try testing.expectEqual(@as(u32, 8), token_create.decimals.?);
    try testing.expectEqual(@as(u64, 1000000), token_create.initial_supply.?);
    try testing.expect(token_create.treasury_delete_account_id != null);
    try testing.expectEqual(hedera.TokenType.FungibleCommon, token_create.token_type.?);
    try testing.expectEqual(hedera.TokenSupplyType.Finite, token_create.supply_type.?);
    try testing.expectEqual(@as(u64, 10000000), token_create.max_supply.?);
    try testing.expectEqual(false, token_create.freeze_default.?);
    try testing.expectEqualStrings("Test token memo", token_create.token_memo);
    
    // Test transaction body building
    const tx_body = try token_create.buildTransactionBody();
    defer allocator.free(tx_body);
    
    try testing.expect(tx_body.len > 0);
}

test "ContractCreateTransaction" {
    const allocator = testing.allocator;
    
    var contract_create = hedera.ContractCreateTransaction.init(allocator);
    defer contract_create.deinit();
    
    // Test setting contract properties
    const bytecode = [_]u8{ 0x60, 0x80, 0x60, 0x40, 0x52, 0x34, 0x80, 0x15, 0x61, 0x00, 0x10 };
    
    _ = try contract_create.setBytecode(&bytecode);
    _ = try contract_create.setGas(100000);
    _ = try contract_create.setInitialBalance(hedera.Hbar.from(5));
    _ = try contract_create.setConstructorParameters(&[_]u8{ 0x00, 0x01, 0x02 });
    _ = try contract_create.setContractMemo("Test contract memo");
    _ = try contract_create.setMaxAutomaticTokenAssociations(50);
    _ = try contract_create.setAutoRenewPeriod(hedera.Duration.fromDays(90));
    
    var admin_key = try hedera.PrivateKey.generateEd25519(allocator);
    defer admin_key.deinit();
    
    _ = try contract_create.setAdminKey(admin_key.getPublicKey());
    
    // Verify properties were set
    try testing.expectEqualSlices(u8, &bytecode, contract_create.bytecode);
    try testing.expectEqual(@as(u64, 100000), contract_create.gas.?);
    try testing.expect(contract_create.initial_balance != null);
    try testing.expectEqual(@as(f64, 5.0), contract_create.initial_balance.?.toHbars());
    try testing.expectEqual(@as(usize, 3), contract_create.constructor_parameters.len);
    try testing.expectEqualStrings("Test contract memo", contract_create.contract_memo);
    try testing.expectEqual(@as(u32, 50), contract_create.max_automatic_token_associations.?);
    try testing.expect(contract_create.admin_key != null);
    
    // Test transaction body building
    const tx_body = try contract_create.buildTransactionBody();
    defer allocator.free(tx_body);
    
    try testing.expect(tx_body.len > 0);
}

test "TopicCreateTransaction" {
    const allocator = testing.allocator;
    
    var topic_create = hedera.TopicCreateTransaction.init(allocator);
    defer topic_create.deinit();
    
    // Test setting topic properties
    _ = try topic_create.setTopicMemo("Test topic memo");
    
    var admin_key = try hedera.PrivateKey.generateEd25519(allocator);
    defer admin_key.deinit();
    
    var submit_key = try hedera.PrivateKey.generateEcdsa(allocator);
    defer submit_key.deinit();
    
    _ = try topic_create.setAdminKey(admin_key.getPublicKey());
    _ = try topic_create.setSubmitKey(submit_key.getPublicKey());
    _ = try topic_create.setAutoRenewAccountId(hedera.AccountId.init(0, 0, 123));
    _ = try topic_create.setAutoRenewPeriod(hedera.Duration.fromDays(90));
    
    // Verify properties were set
    try testing.expectEqualStrings("Test topic memo", topic_create.topic_memo);
    try testing.expect(topic_create.admin_key != null);
    try testing.expect(topic_create.submit_key != null);
    try testing.expect(topic_create.auto_renew_account_id != null);
    try testing.expect(topic_create.auto_renew_period != null);
    try testing.expectEqual(@as(i64, 7776000), topic_create.auto_renew_period.?.seconds);
    
    // Test transaction body building
    const tx_body = try topic_create.buildTransactionBody();
    defer allocator.free(tx_body);
    
    try testing.expect(tx_body.len > 0);
}

test "TopicMessageSubmitTransaction" {
    const allocator = testing.allocator;
    
    var message_submit = hedera.TopicMessageSubmitTransaction.init(allocator);
    defer message_submit.deinit();
    
    // Test setting message properties
    const topic_id = hedera.TopicId.init(0, 0, 1000);
    const message = "Hello, Hedera Consensus Service! This is a test message.";
    
    _ = try message_submit.setTopicId(topic_id);
    _ = try message_submit.setMessage(message);
    
    // Verify properties were set
    try testing.expect(message_submit.topic_id != null);
    try testing.expect(message_submit.topic_id.?.equals(topic_id));
    try testing.expectEqualStrings(message, message_submit.message);
    
    // Test large message chunking
    var large_message = try allocator.alloc(u8, 2048); // Larger than 1024 byte limit
    defer allocator.free(large_message);
    
    for (large_message, 0..) |_, i| {
        large_message[i] = @intCast((i % 26) + 'a');
    }
    
    var large_message_submit = hedera.TopicMessageSubmitTransaction.init(allocator);
    defer large_message_submit.deinit();
    
    _ = try large_message_submit.setTopicId(topic_id);
    _ = try large_message_submit.setMessage(large_message);
    
    // Should automatically handle chunking
    try testing.expectEqual(@as(usize, 2048), large_message_submit.message.len);
    
    // Test transaction body building
    const tx_body = try message_submit.buildTransactionBody();
    defer allocator.free(tx_body);
    
    try testing.expect(tx_body.len > 0);
}

test "Transaction validation and error handling" {
    const allocator = testing.allocator;
    
    // Test AccountCreateTransaction validation
    var account_create = hedera.AccountCreateTransaction.init(allocator);
    defer account_create.deinit();
    
    var client = try hedera.Client.forTestnet(allocator);
    defer client.deinit();
    
    // Should fail validation without required fields
    try testing.expectError(error.KeyRequired, account_create.execute(&client));
    
    // Set key and try again
    var key = try hedera.PrivateKey.generateEd25519(allocator);
    defer key.deinit();
    
    _ = try account_create.setKey(key.getPublicKey());
    
    // Should still fail without operator set on client
    try testing.expectError(error.OperatorRequired, account_create.execute(&client));
    
    // Test TransferTransaction validation
    var transfer = hedera.TransferTransaction.init(allocator);
    defer transfer.deinit();
    
    // Should fail without any transfers
    try testing.expectError(error.EmptyTransferList, transfer.execute(&client));
    
    // Configure unbalanced transfers
    const account1 = hedera.AccountId.init(0, 0, 123);
    const account2 = hedera.AccountId.init(0, 0, 456);
    
    _ = try transfer.addHbarTransfer(account1, hedera.Hbar.from(-10));
    _ = try transfer.addHbarTransfer(account2, hedera.Hbar.from(5)); // Doesn't balance
    
    try testing.expectError(error.UnbalancedTransfers, transfer.execute(&client));
    
    // Test invalid transaction fees
    var transaction = hedera.Transaction.init(allocator);
    defer transaction.deinit();
    
    try testing.expectError(error.InvalidTransactionFee, transaction.setMaxTransactionFee(hedera.Hbar.ZERO));
    try testing.expectError(error.InvalidTransactionFee, transaction.setMaxTransactionFee(try hedera.Hbar.fromTinybars(-1000)));
    
    // Test invalid node account IDs
    try testing.expectError(error.InvalidNodeAccountId, transaction.addNodeAccountId(hedera.AccountId.init(0, 0, 0)));
}

test "Transaction fee calculation and estimation" {
    const allocator = testing.allocator;
    
    var transfer = hedera.TransferTransaction.init(allocator);
    defer transfer.deinit();
    
    // Set up a simple transfer
    const account1 = hedera.AccountId.init(0, 0, 123);
    const account2 = hedera.AccountId.init(0, 0, 456);
    
    _ = try transfer.addHbarTransfer(account1, hedera.Hbar.from(-1));
    _ = try transfer.addHbarTransfer(account2, hedera.Hbar.from(1));
    
    // Test fee estimation (basic implementation)
    const estimated_fee = transfer.estimateFee();
    try testing.expect(estimated_fee.greaterThan(hedera.Hbar.ZERO));
    
    // More complex transaction should have higher fee
    var complex_transfer = hedera.TransferTransaction.init(allocator);
    defer complex_transfer.deinit();
    
    // Configure multiple transfers
    for (0..10) |i| {
        const sender = hedera.AccountId.init(0, 0, @intCast(100 + i));
        const receiver = hedera.AccountId.init(0, 0, @intCast(200 + i));
        
        try complex_transfer.addHbarTransfer(sender, hedera.Hbar.from(-1));
        try complex_transfer.addHbarTransfer(receiver, hedera.Hbar.from(1));
    }
    
    const complex_estimated_fee = complex_transfer.estimateFee();
    try testing.expect(complex_estimated_fee.greaterThan(estimated_fee));
    
    // Test setting explicit fee
    _ = try transfer.setMaxTransactionFee(hedera.Hbar.from(0.1));
    try testing.expect(transfer.base.max_transaction_fee != null);
    try testing.expectEqual(@as(f64, 0.1), transfer.base.max_transaction_fee.?.toHbars());
}

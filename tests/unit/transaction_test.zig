const std = @import("std");
const testing = std.testing;
const hedera = @import("hedera");

test "Transaction ID generation and uniqueness" {
    const account_id = hedera.AccountId.init(0, 0, 1234);
    
    const tx_id1 = hedera.TransactionId.generate(account_id);
    // Small delay to ensure different timestamp
    std.time.sleep(1000000); // 1ms
    const tx_id2 = hedera.TransactionId.generate(account_id);
    
    // Transaction IDs should be different
    try testing.expect(tx_id1.valid_start.seconds != tx_id2.valid_start.seconds or
                       tx_id1.valid_start.nanos != tx_id2.valid_start.nanos);
    
    // Account IDs should be the same
    try testing.expectEqual(tx_id1.account_id.account, tx_id2.account_id.account);
}

test "Transaction ID with nonce" {
    const account_id = hedera.AccountId.init(0, 0, 5678);
    
    var tx_id = hedera.TransactionId.generate(account_id);
    tx_id.nonce = 42;
    
    try testing.expectEqual(@as(u32, 42), tx_id.nonce.?);
    try testing.expect(!tx_id.scheduled);
}

test "Scheduled transaction ID" {
    const account_id = hedera.AccountId.init(0, 0, 9999);
    
    var tx_id = hedera.TransactionId.generate(account_id);
    tx_id.scheduled = true;
    
    try testing.expect(tx_id.scheduled);
    try testing.expect(tx_id.nonce == null);
}

test "Transaction memo validation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.TransferTransaction.init(allocator);
    defer tx.deinit();
    
    // Valid memo (under 100 bytes)
    const valid_memo = "This is a valid transaction memo";
    _ = tx.base.setTransactionMemo(valid_memo);
    try testing.expectEqualStrings(valid_memo, tx.base.transaction_memo);
    
    // Long memo (exactly 100 bytes)
    const long_memo = "a" ** 100;
    _ = tx.base.setTransactionMemo(long_memo);
    try testing.expectEqualStrings(long_memo, tx.base.memo);
    
    // Too long memo would panic (removed test as setters use @panic not errors)
}

test "Transaction valid duration" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.TransferTransaction.init(allocator);
    defer tx.deinit();
    
    // Default valid duration should be 120 seconds
    try testing.expectEqual(@as(i64, 120), tx.base.transaction_valid_duration.seconds);
    
    // Set custom valid duration
    const custom_duration = hedera.Duration.fromMinutes(3);
    _ = tx.base.setTransactionValidDuration(custom_duration);
    try testing.expectEqual(@as(i64, 180), tx.base.transaction_valid_duration.seconds);
}

test "Transaction max transaction fee" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.TransferTransaction.init(allocator);
    defer tx.deinit();
    
    // Set max transaction fee
    const max_fee = try hedera.Hbar.from(5);
    _ = tx.base.setMaxTransactionFee(max_fee);
    try testing.expectEqual(max_fee.toTinybars(), tx.base.max_transaction_fee.?.toTinybars());
}

test "Transaction node account IDs" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.TransferTransaction.init(allocator);
    defer tx.deinit();
    
    // Set node account IDs
    const node1 = hedera.AccountId.init(0, 0, 3);
    const node2 = hedera.AccountId.init(0, 0, 4);
    const node3 = hedera.AccountId.init(0, 0, 5);
    
    var node_ids = std.ArrayList(hedera.AccountId).init(allocator);
    defer node_ids.deinit();
    
    try node_ids.append(node1);
    try node_ids.append(node2);
    try node_ids.append(node3);
    
    _ = try tx.base.setNodeAccountIds(node_ids.items);
    try testing.expectEqual(@as(usize, 3), tx.base.node_account_ids.items.len);
}

test "Transaction freeze and sign" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var client = try hedera.Client.forTestnet();
    defer client.deinit();
    
    // Set operator
    const operator_id = hedera.AccountId.init(0, 0, 1001);
    var operator_key = try hedera.generatePrivateKey(allocator);
    defer operator_key.deinit();
    
    const op_key = try operator_key.toOperatorKey();
    _ = client.setOperator(operator_id, op_key);
    
    // Create transaction
    var tx = hedera.TransferTransaction.init(allocator);
    defer tx.deinit();
    
    const account1 = hedera.AccountId.init(0, 0, 100);
    const account2 = hedera.AccountId.init(0, 0, 200);
    
    _ = try tx.addHbarTransfer(account1, try hedera.Hbar.from(-10));
    _ = try tx.addHbarTransfer(account2, try hedera.Hbar.from(10));
    
    // Freeze transaction
    try tx.base.freezeWith(&client);
    try testing.expect(tx.base.frozen);
    
    // Sign transaction
    try tx.base.sign(operator_key);
    try testing.expectEqual(@as(usize, 1), tx.base.signatures.items.len);
    
    // Cannot modify frozen transaction (would panic - removed test as frozen transactions use @panic)
}

test "Transaction signature map" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.TransferTransaction.init(allocator);
    defer tx.deinit();
    
    // Add transfers
    const account1 = hedera.AccountId.init(0, 0, 100);
    const account2 = hedera.AccountId.init(0, 0, 200);
    
    _ = try tx.addHbarTransfer(account1, try hedera.Hbar.from(-10));
    _ = try tx.addHbarTransfer(account2, try hedera.Hbar.from(10));
    
    // Generate multiple signers
    var key1 = try hedera.generatePrivateKey(allocator);
    defer key1.deinit();
    
    var key2 = try hedera.generatePrivateKey(allocator);
    defer key2.deinit();
    
    var key3 = try hedera.generatePrivateKey(allocator);
    defer key3.deinit();
    
    // Freeze transaction before signing
    try tx.base.freezeWith(null);
    
    // Add signatures
    try tx.base.sign(key1);
    try tx.base.sign(key2);
    try tx.base.sign(key3);
    
    // Verify all signatures were added
    try testing.expectEqual(@as(usize, 3), tx.base.signatures.items.len);
    
    // Add public key signature
    const public_key = key1.getPublicKey();
    const signature = try key1.sign("test message");
    defer allocator.free(signature);
    
    const public_key_bytes = try public_key.toBytes(allocator);
    defer allocator.free(public_key_bytes);
    try tx.base.addSignature(public_key_bytes, signature);
    try testing.expectEqual(@as(usize, 4), tx.base.signatures.items.len);
}

test "Transfer transaction HBAR transfers" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var transfer = hedera.TransferTransaction.init(allocator);
    defer transfer.deinit();
    
    const account1 = hedera.AccountId.init(0, 0, 100);
    const account2 = hedera.AccountId.init(0, 0, 200);
    const account3 = hedera.AccountId.init(0, 0, 300);
    
    // Add transfers
    _ = try transfer.addHbarTransfer(account1, try hedera.Hbar.from(-100));
    _ = try transfer.addHbarTransfer(account2, try hedera.Hbar.from(60));
    _ = try transfer.addHbarTransfer(account3, try hedera.Hbar.from(40));
    
    // Verify transfers
    try testing.expectEqual(@as(usize, 3), transfer.hbar_transfers.items.len);
    
    // Verify sum is zero
    var sum: i64 = 0;
    for (transfer.hbar_transfers.items) |hbar_transfer| {
        sum += hbar_transfer.amount.toTinybars();
    }
    try testing.expectEqual(@as(i64, 0), sum);
    
    // Add approved transfer
    _ = try transfer.addApprovedHbarTransfer(account1, try hedera.Hbar.from(-50));
    _ = try transfer.addApprovedHbarTransfer(account2, try hedera.Hbar.from(50));
    
    try testing.expectEqual(@as(usize, 3), transfer.hbar_transfers.items.len);
}

test "Transfer transaction token transfers" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var transfer = hedera.TransferTransaction.init(allocator);
    defer transfer.deinit();
    
    const token_id = hedera.TokenId.init(0, 0, 1000);
    const account1 = hedera.AccountId.init(0, 0, 100);
    const account2 = hedera.AccountId.init(0, 0, 200);
    
    // Add token transfers
    try transfer.addTokenTransfer(token_id, account1, -500);
    try transfer.addTokenTransfer(token_id, account2, 500);
    
    // Verify token transfers
    // Should have 2 token transfers (one for each account)
    try testing.expectEqual(@as(usize, 2), transfer.token_transfers.items.len);
    
    // Add approved token transfer
    try transfer.addApprovedTokenTransfer(token_id, account1, -100);
    try transfer.addApprovedTokenTransfer(token_id, account2, 100);
    
    try testing.expectEqual(@as(usize, 2), transfer.token_transfers.items.len);
    
    // Add NFT transfer
    const nft_id = hedera.NftId{
        .token_id = token_id,
        .serial_number = 1,
    };
    
    try transfer.addNftTransfer(nft_id, account1, account2);
    try testing.expectEqual(@as(usize, 1), transfer.nft_transfers.items.len);
    
    // Add approved NFT transfer
    try transfer.addApprovedNftTransfer(nft_id, account2, account1);
    try testing.expectEqual(@as(usize, 2), transfer.nft_transfers.items.len);
}

test "Transfer transaction with decimals" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var transfer = hedera.TransferTransaction.init(allocator);
    defer transfer.deinit();
    
    const token_id = hedera.TokenId.init(0, 0, 2000);
    const account1 = hedera.AccountId.init(0, 0, 100);
    const account2 = hedera.AccountId.init(0, 0, 200);
    
    // Add token transfer with decimals
    const decimals: u32 = 8;
    try transfer.addTokenTransferWithDecimals(token_id, account1, -1000, decimals);
    try transfer.addTokenTransferWithDecimals(token_id, account2, 1000, decimals);
    
    // Verify expected decimals are set
    try testing.expectEqual(@as(usize, 2), transfer.token_transfers.items.len);
    try testing.expectEqual(@as(?u32, decimals), transfer.token_transfers.items[0].expected_decimals);
}

test "System delete transaction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var delete_tx = hedera.SystemDeleteTransaction.init(allocator);
    defer delete_tx.deinit();
    
    // Set file to delete
    const file_id = hedera.FileId.init(0, 0, 111);
    _ = delete_tx.setFileId(file_id);
    
    // Set expiration time
    const expiration = hedera.Timestamp.fromSeconds(1234567890);
    _ = delete_tx.setExpirationTime(expiration);
    
    try testing.expect(delete_tx.file_id != null);
    try testing.expectEqual(@as(u64, 111), delete_tx.file_id.?.num());
    try testing.expectEqual(@as(i64, 1234567890), delete_tx.expiration_time.?.seconds);
    
    // Set contract to delete
    const contract_id = hedera.ContractId.init(0, 0, 222);
    _ = delete_tx.setContractId(contract_id);
    
    try testing.expect(delete_tx.contract_id != null);
    try testing.expectEqual(@as(u64, 222), delete_tx.contract_id.?.num());
}

test "System undelete transaction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var undelete_tx = hedera.SystemUndeleteTransaction.init(allocator);
    defer undelete_tx.deinit();
    
    // Set file to undelete
    const file_id = hedera.FileId.init(0, 0, 333);
    _ = undelete_tx.setFileId(file_id);
    
    try testing.expect(undelete_tx.file_id != null);
    try testing.expectEqual(@as(u64, 333), undelete_tx.file_id.?.num());
    
    // Set contract to undelete
    const contract_id = hedera.ContractId.init(0, 0, 444);
    _ = undelete_tx.setContractId(contract_id);
    
    try testing.expect(undelete_tx.contract_id != null);
    try testing.expectEqual(@as(u64, 444), undelete_tx.contract_id.?.num());
}

test "Freeze transaction types" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var freeze_tx = hedera.FreezeTransaction.init(allocator);
    defer freeze_tx.deinit();
    
    // Test different freeze types
    _ = freeze_tx.setFreezeType(.freeze_only);
    try testing.expectEqual(hedera.FreezeType.freeze_only, freeze_tx.freeze_type);
    
    _ = freeze_tx.setFreezeType(.prepare_upgrade);
    try testing.expectEqual(hedera.FreezeType.prepare_upgrade, freeze_tx.freeze_type);
    
    _ = freeze_tx.setFreezeType(.freeze_upgrade);
    try testing.expectEqual(hedera.FreezeType.freeze_upgrade, freeze_tx.freeze_type);
    
    _ = freeze_tx.setFreezeType(.freeze_abort);
    try testing.expectEqual(hedera.FreezeType.freeze_abort, freeze_tx.freeze_type);
    
    _ = freeze_tx.setFreezeType(.telemetry_upgrade);
    try testing.expectEqual(hedera.FreezeType.telemetry_upgrade, freeze_tx.freeze_type);
    
    // Set start and end times (hour, minute format)
    _ = freeze_tx.setStartTime(12, 30);  // 12:30
    _ = freeze_tx.setEndTime(14, 45);    // 14:45
    
    try testing.expectEqual(@as(u8, 12), freeze_tx.start_hour);
    try testing.expectEqual(@as(u8, 30), freeze_tx.start_min);
    try testing.expectEqual(@as(u8, 14), freeze_tx.end_hour);
    try testing.expectEqual(@as(u8, 45), freeze_tx.end_min);
    
    // Set file hash
    const file_hash = [_]u8{0xFF} ** 48;
    _ = freeze_tx.setFileHash(&file_hash);
    
    try testing.expectEqualSlices(u8, &file_hash, freeze_tx.file_hash);
}

test "Prng transaction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var prng_tx = hedera.PrngTransaction.init(allocator);
    defer prng_tx.deinit();
    
    // Set range for random number
    const range: u32 = 100;
    _ = prng_tx.setRange(range);
    
    try testing.expectEqual(@as(?i32, @intCast(range)), prng_tx.range);
}

test "Transaction response and receipt" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create mock transaction response
    const tx_id = hedera.TransactionId.generate(hedera.AccountId.init(0, 0, 100));
    const hash_bytes = try allocator.alloc(u8, 48);
    @memset(hash_bytes, 0xAB);
    
    var response = hedera.TransactionResponse{
        .transaction_id = tx_id,
        .scheduled_transaction_id = null,
        .node_id = hedera.AccountId.init(0, 0, 3),
        .hash = hash_bytes,
        .transaction_hash = hash_bytes,
        .validate_status = false,
        .include_child_receipts = false,
        .transaction = null,
        .allocator = allocator,
    };
    defer response.deinit();
    
    // Verify response fields
    try testing.expectEqual(tx_id.account_id.account, response.transaction_id.account_id.account);
    try testing.expectEqual(@as(u64, 3), response.node_id.account);
    try testing.expectEqual(@as(usize, 48), response.transaction_hash.len);
}

test "Transaction chunking for large data" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create file append transaction with large data
    var file_append = hedera.FileAppendTransaction.init(allocator);
    defer file_append.deinit();
    
    const file_id = hedera.FileId.init(0, 0, 123);
    _ = file_append.setFileId(file_id);
    
    // Create large content (over 4KB)
    const large_content = try allocator.alloc(u8, 5000);
    defer allocator.free(large_content);
    @memset(large_content, 'A');
    
    _ = file_append.setContents(large_content);
    
    // Set chunk size
    const chunk_size: u32 = 1024;
    _ = file_append.setChunkSize(chunk_size);
    
    try testing.expectEqual(@as(u32, chunk_size), file_append.chunk_size);
    try testing.expectEqual(@as(usize, 5000), file_append.contents.len);
}

test "Transaction builder pattern" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Test method chaining with account create transaction
    var tx = hedera.newAccountCreateTransaction(allocator);
    defer tx.deinit();
    
    var key = try hedera.generatePrivateKey(allocator);
    defer key.deinit();
    
    // Chain methods
    _ = tx.setKey(hedera.Key.fromPublicKey(key.getPublicKey()));
    _ = tx.setInitialBalance(try hedera.Hbar.from(100));
    _ = tx.setAutoRenewPeriod(hedera.Duration.fromDays(90));
    _ = tx.setAccountMemo("Test account");
    _ = tx.setMaxAutomaticTokenAssociations(10);
    _ = tx.setReceiverSignatureRequired(true);
    _ = tx.setStakedNodeId(3);
    _ = tx.setDeclineStakingReward(false);
    
    // Verify all settings
    try testing.expect(tx.key != null);
    try testing.expectEqual(@as(i64, 10_000_000_000), tx.initial_balance.toTinybars());
    try testing.expectEqual(@as(i64, 7776000), tx.auto_renew_period.seconds);
    try testing.expectEqualStrings("Test account", tx.memo);
    try testing.expectEqual(@as(i32, 10), tx.max_automatic_token_associations);
    try testing.expect(tx.receiver_signature_required);
    try testing.expectEqual(@as(?i64, 3), tx.staked_node_id);
    try testing.expect(!tx.decline_staking_reward);
}


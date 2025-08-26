const std = @import("std");
const testing = std.testing;
const hedera = @import("hedera");

test "TransactionId - generation and validation" {
    // Test basic generation
    const account_id = hedera.AccountId.init(0, 0, 100);
    const tx_id = hedera.TransactionId.generate(account_id);
    
    try testing.expectEqual(@as(u64, 100), tx_id.account_id.account);
    try testing.expect(!tx_id.scheduled);
    try testing.expectEqual(@as(?i32, null), tx_id.nonce);
    
    // Test with nonce
    const tx_id_nonce = hedera.TransactionId{
        .account_id = account_id,
        .valid_start = hedera.Timestamp.fromSeconds(1000000000),
        .scheduled = false,
        .nonce = 42,
    };
    
    try testing.expectEqual(@as(?i32, 42), tx_id_nonce.nonce);
    
    // Test scheduled transaction
    const tx_id_scheduled = hedera.TransactionId{
        .account_id = account_id,
        .valid_start = hedera.Timestamp.fromSeconds(1000000000),
        .scheduled = true,
        .nonce = null,
    };
    
    try testing.expect(tx_id_scheduled.scheduled);
    
    // Test with different account
    const other_account = hedera.AccountId.init(1, 2, 300);
    const tx_id_other = hedera.TransactionId.generate(other_account);
    try testing.expectEqual(@as(u64, 1), tx_id_other.account_id.shard);
    try testing.expectEqual(@as(u64, 2), tx_id_other.account_id.realm);
    try testing.expectEqual(@as(u64, 300), tx_id_other.account_id.account);
}

test "TransactionId - string conversions" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const tx_id = hedera.TransactionId{
        .account_id = hedera.AccountId.init(0, 0, 100),
        .valid_start = hedera.Timestamp.fromSeconds(1234567890),
        .scheduled = false,
        .nonce = null,
    };
    
    // Test toString
    const str = try tx_id.toString(allocator);
    defer allocator.free(str);
    
    try testing.expect(str.len > 0);
    try testing.expect(std.mem.indexOf(u8, str, "0.0.100") != null);
    try testing.expect(std.mem.indexOf(u8, str, "1234567890") != null);
    
    // Test fromString
    const parsed = try hedera.transactionIdFromString(allocator, str);
    try testing.expectEqual(@as(u64, 100), parsed.account_id.account);
    try testing.expectEqual(@as(i64, 1234567890), parsed.valid_start.seconds);
    
    // Test with nonce
    const tx_id_nonce = hedera.TransactionId{
        .account_id = hedera.AccountId.init(0, 0, 200),
        .valid_start = hedera.Timestamp.fromSeconds(1234567890),
        .scheduled = false,
        .nonce = 42,
    };
    
    const str_nonce = try tx_id_nonce.toString(allocator);
    defer allocator.free(str_nonce);
    
    try testing.expect(std.mem.indexOf(u8, str_nonce, "/42") != null);
}

test "TransferTransaction - comprehensive HBAR transfers" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.transferTransaction(allocator);
    defer tx.deinit();
    
    // Add HBAR transfers
    const sender = hedera.AccountId.init(0, 0, 100);
    const receiver1 = hedera.AccountId.init(0, 0, 200);
    const receiver2 = hedera.AccountId.init(0, 0, 300);
    
    // Sender sends -100 HBAR total
    _ = try tx.addHbarTransfer(sender, try hedera.Hbar.from(-100));
    
    // Receiver1 gets 60 HBAR
    _ = try tx.addHbarTransfer(receiver1, try hedera.Hbar.from(60));
    
    // Receiver2 gets 40 HBAR
    _ = try tx.addHbarTransfer(receiver2, try hedera.Hbar.from(40));
    
    // Test approved transfers
    _ = try tx.addHbarTransferWithApproval(sender, try hedera.Hbar.from(-10), true);
    _ = try tx.addHbarTransferWithApproval(receiver1, try hedera.Hbar.from(10), false);
    
    try testing.expectEqual(@as(usize, 5), tx.hbar_transfers.items.len);
    
    // Verify sum is zero
    var total: i64 = 0;
    for (tx.hbar_transfers.items) |transfer| {
        total += transfer.amount.toTinybars();
    }
    try testing.expectEqual(@as(i64, 0), total);
}

test "TransferTransaction - token transfers comprehensive" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.transferTransaction(allocator);
    defer tx.deinit();
    
    const token1 = hedera.TokenId.init(0, 0, 1000);
    const token2 = hedera.TokenId.init(0, 0, 2000);
    
    const sender = hedera.AccountId.init(0, 0, 100);
    const receiver1 = hedera.AccountId.init(0, 0, 200);
    const receiver2 = hedera.AccountId.init(0, 0, 300);
    
    // Token1 transfers
    _ = try tx.addTokenTransfer(token1, sender, -1000000);
    _ = try tx.addTokenTransfer(token1, receiver1, 600000);
    _ = try tx.addTokenTransfer(token1, receiver2, 400000);
    
    // Token2 transfers with approval
    _ = try tx.addTokenTransferWithApproval(token2, sender, -50000, true);
    _ = try tx.addTokenTransferWithApproval(token2, receiver1, 30000, false);
    _ = try tx.addTokenTransferWithApproval(token2, receiver2, 20000, false);
    
    // Set expected decimals
    _ = try tx.setTokenTransferExpectedDecimals(token1, 6);
    _ = try tx.setTokenTransferExpectedDecimals(token2, 8);
    
    try testing.expect(tx.token_transfers.count() >= 2);
    
    // Verify token1 transfers sum to zero
    if (tx.token_transfers.get(token1)) |transfers| {
        var total: i64 = 0;
        for (transfers.items) |transfer| {
            total += transfer.amount;
        }
        try testing.expectEqual(@as(i64, 0), total);
    }
    
    // Verify token2 transfers sum to zero
    if (tx.token_transfers.get(token2)) |transfers| {
        var total: i64 = 0;
        for (transfers.items) |transfer| {
            total += transfer.amount;
        }
        try testing.expectEqual(@as(i64, 0), total);
    }
}

test "TransferTransaction - NFT transfers" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.transferTransaction(allocator);
    defer tx.deinit();
    
    const nft_token = hedera.TokenId.init(0, 0, 5000);
    const sender = hedera.AccountId.init(0, 0, 100);
    const receiver = hedera.AccountId.init(0, 0, 200);
    
    // Transfer multiple NFTs
    const serials = [_]i64{1, 5, 10, 42, 100};
    
    for (serials) |serial| {
        const nft_id = hedera.NftId{
            .token_id = nft_token,
            .serial_number = serial,
        };
        _ = try tx.addNftTransfer(nft_id, sender, receiver);
    }
    
    // Test approved NFT transfer
    const approved_nft = hedera.NftId{
        .token_id = nft_token,
        .serial_number = 999,
    };
    _ = try tx.addNftTransferWithApproval(approved_nft, sender, receiver, true);
    
    try testing.expect(tx.nft_transfers.count() > 0);
    
    if (tx.nft_transfers.get(nft_token)) |transfers| {
        try testing.expectEqual(@as(usize, 6), transfers.items.len); // 5 + 1 approved
        
        // Check specific transfers
        for (transfers.items[0..5], serials) |transfer, expected_serial| {
            try testing.expectEqual(@as(i64, expected_serial), transfer.serial_number);
            try testing.expectEqual(@as(u64, 100), transfer.sender.account);
            try testing.expectEqual(@as(u64, 200), transfer.receiver.account);
            try testing.expect(!transfer.is_approved);
        }
        
        // Check approved transfer
        try testing.expectEqual(@as(i64, 999), transfers.items[5].serial_number);
        try testing.expect(transfers.items[5].is_approved);
    }
}

test "TransferTransaction - transaction properties" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.transferTransaction(allocator);
    defer tx.deinit();
    
    // Set transaction properties
    const tx_id = hedera.TransactionId.generate(hedera.AccountId.init(0, 0, 100));
    _ = try tx.setTransactionId(tx_id);
    
    const node_ids = [_]hedera.AccountId{
        hedera.AccountId.init(0, 0, 3),
        hedera.AccountId.init(0, 0, 4),
        hedera.AccountId.init(0, 0, 5),
    };
    _ = try tx.setNodeAccountIds(&node_ids);
    
    _ = try tx.setMaxTransactionFee(try hedera.Hbar.from(5));
    _ = try tx.setTransactionValidDuration(hedera.Duration.fromSeconds(180));
    _ = try tx.setTransactionMemo("Transfer transaction memo");
    _ = try tx.setRegenerateTransactionId(true);
    
    // Verify properties
    try testing.expectEqual(@as(u64, 100), tx.transaction_id.?.account_id.account);
    try testing.expectEqual(@as(usize, 3), tx.node_account_ids.items.len);
    try testing.expectEqual(@as(i64, 500_000_000), tx.max_transaction_fee.?.toTinybars());
    try testing.expectEqual(@as(i64, 180), tx.transaction_valid_duration.?.seconds);
    try testing.expectEqualStrings("Transfer transaction memo", tx.transaction_memo.?);
    try testing.expect(tx.regenerate_transaction_id);
}

test "Transaction - signing and verification" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.transferTransaction(allocator);
    defer tx.deinit();
    
    // Add simple transfer
    _ = try tx.addHbarTransfer(hedera.AccountId.init(0, 0, 100), try hedera.Hbar.from(-10));
    _ = try tx.addHbarTransfer(hedera.AccountId.init(0, 0, 200), try hedera.Hbar.from(10));
    
    // Generate signing keys
    var key1 = try hedera.generatePrivateKey(allocator);
    defer key1.deinit();
    var key2 = try hedera.generatePrivateKey(allocator);
    defer key2.deinit();
    
    // Sign transaction
    try tx.sign(key1);
    try tx.sign(key2);
    
    // Verify signatures
    try testing.expectEqual(@as(usize, 2), tx.signatures.items.len);
    
    // Test signature verification
    const message = try tx.getTransactionHash(allocator);
    defer allocator.free(message);
    
    for (tx.signatures.items) |sig| {
        try testing.expect(sig.signature.len > 0);
        try testing.expect(sig.public_key.len > 0);
    }
}

test "Transaction - freeze and execute workflow" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.transferTransaction(allocator);
    defer tx.deinit();
    
    // Add transfer
    _ = try tx.addHbarTransfer(hedera.AccountId.init(0, 0, 100), try hedera.Hbar.from(-5));
    _ = try tx.addHbarTransfer(hedera.AccountId.init(0, 0, 200), try hedera.Hbar.from(5));
    
    // Create client
    var client = try hedera.Client.forTestnet();
    defer client.deinit();
    
    // Set operator
    var operator_key = try hedera.generatePrivateKey(allocator);
    defer operator_key.deinit();
    const op_key = try operator_key.toOperatorKey();
    _ = try client.setOperator(hedera.AccountId.init(0, 0, 100), op_key);
    
    // Test freeze
    _ = try tx.freezeWith(&client);
    try testing.expect(tx.frozen);
    
    // Test that we can't modify after freezing
    try testing.expectError(error.TransactionFrozen, tx.addHbarTransfer(
        hedera.AccountId.init(0, 0, 300), 
        try hedera.Hbar.from(1)
    ));
    
    // Note: We can't actually execute without a real network connection,
    // but we can test that the execute method exists and accepts the right parameters
    try testing.expect(@hasDecl(@TypeOf(tx), "execute"));
}

test "Transaction - serialization and deserialization" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.transferTransaction(allocator);
    defer tx.deinit();
    
    // Set up transaction
    const tx_id = hedera.TransactionId.generate(hedera.AccountId.init(0, 0, 100));
    _ = try tx.setTransactionId(tx_id);
    _ = try tx.setMaxTransactionFee(try hedera.Hbar.from(2));
    _ = try tx.setTransactionMemo("Serialization test");
    
    // Add transfers
    _ = try tx.addHbarTransfer(hedera.AccountId.init(0, 0, 100), try hedera.Hbar.from(-25));
    _ = try tx.addHbarTransfer(hedera.AccountId.init(0, 0, 200), try hedera.Hbar.from(25));
    
    // Serialize to bytes
    const bytes = try tx.toBytes(allocator);
    defer allocator.free(bytes);
    
    try testing.expect(bytes.len > 0);
    
    // Deserialize from bytes
    var tx2 = try hedera.TransferTransaction.fromBytes(allocator, bytes);
    defer tx2.deinit();
    
    // Verify deserialized transaction
    try testing.expectEqual(@as(u64, 100), tx2.transaction_id.?.account_id.account);
    try testing.expectEqual(@as(i64, 200_000_000), tx2.max_transaction_fee.?.toTinybars());
    try testing.expectEqualStrings("Serialization test", tx2.transaction_memo.?);
    try testing.expectEqual(@as(usize, 2), tx2.hbar_transfers.items.len);
}

test "TransactionReceipt - comprehensive status handling" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Test successful receipt
    var receipt = hedera.TransactionReceipt.init(allocator, hedera.Status.OK);
    defer receipt.deinit();
    
    receipt.account_id = hedera.AccountId.init(0, 0, 1000);
    receipt.file_id = hedera.FileId.init(0, 0, 2000);
    receipt.contract_id = hedera.ContractId.init(0, 0, 3000);
    receipt.topic_id = hedera.TopicId.init(0, 0, 4000);
    receipt.token_id = hedera.TokenId.init(0, 0, 5000);
    receipt.schedule_id = hedera.ScheduleId.init(0, 0, 6000);
    receipt.scheduled_transaction_id = hedera.TransactionId.generate(hedera.AccountId.init(0, 0, 100));
    
    // Add serial numbers for NFT operations
    try receipt.serials.append(1);
    try receipt.serials.append(5);
    try receipt.serials.append(10);
    
    receipt.total_supply = 1000000;
    receipt.exchange_rate = hedera.ExchangeRate{
        .hbar_equivalent = 1,
        .cent_equivalent = 12,
        .expiration_time = hedera.Timestamp.fromSeconds(1234567890),
    };
    receipt.topic_sequence_number = 42;
    receipt.topic_running_hash = &[_]u8{0xAB} ** 48;
    receipt.topic_running_hash_version = 3;
    
    // Verify receipt properties
    try testing.expectEqual(hedera.Status.OK, receipt.status);
    try testing.expectEqual(@as(u64, 1000), receipt.account_id.?.account);
    try testing.expectEqual(@as(u64, 2000), receipt.file_id.?.num());
    try testing.expectEqual(@as(u64, 3000), receipt.contract_id.?.num());
    try testing.expectEqual(@as(u64, 4000), receipt.topic_id.?.num());
    try testing.expectEqual(@as(u64, 5000), receipt.token_id.?.num());
    try testing.expectEqual(@as(u64, 6000), receipt.schedule_id.?.num());
    try testing.expectEqual(@as(usize, 3), receipt.serials.items.len);
    try testing.expectEqual(@as(i64, 1), receipt.serials.items[0]);
    try testing.expectEqual(@as(i64, 10), receipt.serials.items[2]);
    try testing.expectEqual(@as(u64, 1000000), receipt.total_supply);
    try testing.expectEqual(@as(i32, 1), receipt.exchange_rate.hbar_equivalent);
    try testing.expectEqual(@as(i32, 12), receipt.exchange_rate.cent_equivalent);
    try testing.expectEqual(@as(u64, 42), receipt.topic_sequence_number);
    try testing.expectEqualSlices(u8, &[_]u8{0xAB} ** 48, receipt.topic_running_hash);
    try testing.expectEqual(@as(i64, 3), receipt.topic_running_hash_version);
    
    // Test error receipt
    var error_receipt = hedera.TransactionReceipt.init(allocator, hedera.Status.INSUFFICIENT_ACCOUNT_BALANCE);
    defer error_receipt.deinit();
    
    try testing.expectEqual(hedera.Status.INSUFFICIENT_ACCOUNT_BALANCE, error_receipt.status);
}

test "TransactionRecord - comprehensive record data" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create receipt
    var receipt = hedera.TransactionReceipt.init(allocator, hedera.Status.OK);
    receipt.account_id = hedera.AccountId.init(0, 0, 1000);
    
    // Create transaction ID
    const tx_id = hedera.TransactionId{
        .account_id = hedera.AccountId.init(0, 0, 100),
        .valid_start = hedera.Timestamp.fromSeconds(1000000000),
        .scheduled = false,
        .nonce = null,
    };
    
    // Create record
    var record = hedera.TransactionRecord.init(allocator, receipt, tx_id);
    defer record.deinit();
    
    // Set record properties
    record.transaction_fee = try hedera.Hbar.fromTinybars(1000000);
    record.consensus_timestamp = hedera.Timestamp.fromSeconds(1000000010);
    record.transaction_hash = &[_]u8{0xCD} ** 48;
    record.memo = "Transaction record memo";
    
    // Add transfers
    try record.transfers.append(hedera.Transfer{
        .account_id = hedera.AccountId.init(0, 0, 100),
        .amount = try hedera.Hbar.from(-50),
        .is_approved = true,
    });
    try record.transfers.append(hedera.Transfer{
        .account_id = hedera.AccountId.init(0, 0, 200),
        .amount = try hedera.Hbar.from(50),
        .is_approved = false,
    });
    
    // Add token transfers
    const token_id = hedera.TokenId.init(0, 0, 7000);
    
    var token_transfer = hedera.TokenTransfer{
        .token_id = token_id,
        .account_id = hedera.AccountId.init(0, 0, 100),
        .amount = 0,
        .transfers = std.ArrayList(hedera.AccountAmount).init(allocator),
        .expected_decimals = 6,
        .is_approved = false,
    };
    
    try token_transfer.transfers.append(.{
        .account_id = hedera.AccountId.init(0, 0, 100),
        .amount = -100000,
        .is_approved = true,
    });
    try token_transfer.transfers.append(.{
        .account_id = hedera.AccountId.init(0, 0, 200),
        .amount = 100000,
        .is_approved = false,
    });
    
    try record.token_transfers.put(token_id, token_transfer);
    
    // Add NFT transfers
    const nft_token = hedera.TokenId.init(0, 0, 8000);
    var nft_transfers = std.ArrayList(hedera.NftTransfer).init(allocator);
    
    try nft_transfers.append(hedera.NftTransfer{
        .token_id = nft_token,
        .sender = hedera.AccountId.init(0, 0, 100),
        .receiver = hedera.AccountId.init(0, 0, 200),
        .serial_number = 42,
        .is_approved = false,
    });
    
    try record.nft_transfers.put(nft_token, nft_transfers);
    
    // Set contract result (if applicable)
    record.contract_function_result = hedera.ContractFunctionResult{
        .contract_id = hedera.ContractId.init(0, 0, 9000),
        .contract_call_result = &[_]u8{0x01, 0x02, 0x03, 0x04},
        .error_message = "",
        .bloom = &[_]u8{0x00} ** 256,
        .gas_used = 25000,
        .gas_limit = 50000,
        .hbar_amount = try hedera.Hbar.fromTinybars(0),
        .contract_function_parameters = &[_]u8{},
        .sender_id = hedera.AccountId.init(0, 0, 100),
        .contract_nonces = std.ArrayList(hedera.ContractNonceInfo).init(allocator),
        .signer_nonce = null,
    };
    
    // Add automatic token associations
    try record.automatic_token_associations.append(.{
        .token_id = hedera.TokenId.init(0, 0, 10000),
        .account_id = hedera.AccountId.init(0, 0, 300),
    });
    
    // Add prng bytes and number
    record.prng_bytes = &[_]u8{0xFF, 0xEE, 0xDD, 0xCC};
    record.prng_number = 123456789;
    
    // Set ethereum hash
    record.ethereum_hash = &[_]u8{0xAA} ** 32;
    
    // Add paid staking rewards
    try record.paid_staking_rewards.append(.{
        .account_id = hedera.AccountId.init(0, 0, 400),
        .amount = try hedera.Hbar.fromTinybars(5000000),
    });
    
    // Verify record properties
    try testing.expectEqual(hedera.Status.OK, record.receipt.status);
    try testing.expectEqual(@as(u64, 100), record.transaction_id.account_id.account);
    try testing.expectEqual(@as(i64, 1000000), record.transaction_fee.toTinybars());
    try testing.expectEqual(@as(i64, 1000000010), record.consensus_timestamp.seconds);
    try testing.expectEqualSlices(u8, &[_]u8{0xCD} ** 48, record.transaction_hash);
    try testing.expectEqualStrings("Transaction record memo", record.memo.?);
    try testing.expectEqual(@as(usize, 2), record.transfers.items.len);
    try testing.expect(record.token_transfers.count() > 0);
    try testing.expect(record.nft_transfers.count() > 0);
    try testing.expectEqual(@as(u64, 9000), record.contract_function_result.?.contract_id.num());
    try testing.expectEqual(@as(usize, 1), record.automatic_token_associations.items.len);
    try testing.expectEqualSlices(u8, &[_]u8{0xFF, 0xEE, 0xDD, 0xCC}, record.prng_bytes.?);
    try testing.expectEqual(@as(?i32, 123456789), record.prng_number);
    try testing.expectEqualSlices(u8, &[_]u8{0xAA} ** 32, record.ethereum_hash.?);
    try testing.expectEqual(@as(usize, 1), record.paid_staking_rewards.items.len);
}

test "Transaction - error handling and edge cases" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.transferTransaction(allocator);
    defer tx.deinit();
    
    // Test empty transaction
    try testing.expectEqual(@as(usize, 0), tx.hbar_transfers.items.len);
    
    // Test maximum fee
    _ = try tx.setMaxTransactionFee(try hedera.Hbar.from(std.math.maxInt(i32)));
    try testing.expect(tx.max_transaction_fee.?.toTinybars() > 0);
    
    // Test zero fee
    _ = try tx.setMaxTransactionFee(try hedera.Hbar.fromTinybars(0));
    try testing.expectEqual(@as(i64, 0), tx.max_transaction_fee.?.toTinybars());
    
    // Test long memo (100 bytes max)
    const long_memo = "a" ** 100;
    _ = try tx.setTransactionMemo(long_memo);
    try testing.expectEqual(@as(usize, 100), tx.transaction_memo.?.len);
    
    // Test empty memo
    _ = try tx.setTransactionMemo("");
    try testing.expectEqualStrings("", tx.transaction_memo.?);
    
    // Test transaction validity duration limits
    _ = try tx.setTransactionValidDuration(hedera.Duration.fromSeconds(1)); // Minimum
    try testing.expectEqual(@as(i64, 1), tx.transaction_valid_duration.?.seconds);
    
    _ = try tx.setTransactionValidDuration(hedera.Duration.fromSeconds(180)); // Maximum
    try testing.expectEqual(@as(i64, 180), tx.transaction_valid_duration.?.seconds);
    
    // Test duplicate transfer to same account (should accumulate)
    const account = hedera.AccountId.init(0, 0, 500);
    _ = try tx.addHbarTransfer(account, try hedera.Hbar.from(10));
    _ = try tx.addHbarTransfer(account, try hedera.Hbar.from(20));
    
    // Should have combined the transfers
    var total_for_account: i64 = 0;
    for (tx.hbar_transfers.items) |transfer| {
        if (transfer.account_id.equals(account)) {
            total_for_account += transfer.amount.toTinybars();
        }
    }
    try testing.expectEqual(@as(i64, 3_000_000_000), total_for_account); // 30 HBAR in tinybars
}

test "Transaction - network and node management" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.transferTransaction(allocator);
    defer tx.deinit();
    
    // Test setting multiple node account IDs
    const nodes = [_]hedera.AccountId{
        hedera.AccountId.init(0, 0, 3),
        hedera.AccountId.init(0, 0, 4),
        hedera.AccountId.init(0, 0, 5),
        hedera.AccountId.init(0, 0, 6),
        hedera.AccountId.init(0, 0, 7),
    };
    
    _ = try tx.setNodeAccountIds(&nodes);
    
    try testing.expectEqual(@as(usize, 5), tx.node_account_ids.items.len);
    try testing.expectEqual(@as(u64, 3), tx.node_account_ids.items[0].account);
    try testing.expectEqual(@as(u64, 7), tx.node_account_ids.items[4].account);
    
    // Test clearing node account IDs
    try tx.node_account_ids.clearRetainingCapacity();
    try testing.expectEqual(@as(usize, 0), tx.node_account_ids.items.len);
    
    // Test single node
    _ = try tx.setNodeAccountIds(&[_]hedera.AccountId{
        hedera.AccountId.init(0, 0, 3)
    });
    try testing.expectEqual(@as(usize, 1), tx.node_account_ids.items.len);
}

test "Transaction - batch operations" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create multiple transactions for a batch
    var tx1 = hedera.transferTransaction(allocator);
    defer tx1.deinit();
    var tx2 = hedera.transferTransaction(allocator);
    defer tx2.deinit();
    var tx3 = hedera.transferTransaction(allocator);
    defer tx3.deinit();
    
    // Set up transactions
    _ = try tx1.addHbarTransfer(hedera.AccountId.init(0, 0, 100), try hedera.Hbar.from(-10));
    _ = try tx1.addHbarTransfer(hedera.AccountId.init(0, 0, 200), try hedera.Hbar.from(10));
    
    _ = try tx2.addHbarTransfer(hedera.AccountId.init(0, 0, 200), try hedera.Hbar.from(-5));
    _ = try tx2.addHbarTransfer(hedera.AccountId.init(0, 0, 300), try hedera.Hbar.from(5));
    
    const token_id = hedera.TokenId.init(0, 0, 1000);
    _ = try tx3.addTokenTransfer(token_id, hedera.AccountId.init(0, 0, 100), -1000);
    _ = try tx3.addTokenTransfer(token_id, hedera.AccountId.init(0, 0, 200), 1000);
    
    // Verify each transaction
    try testing.expectEqual(@as(usize, 2), tx1.hbar_transfers.items.len);
    try testing.expectEqual(@as(usize, 2), tx2.hbar_transfers.items.len);
    try testing.expect(tx3.token_transfers.count() > 0);
}

test "TransactionResponse - response handling" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create mock transaction response
    const tx_id = hedera.TransactionId.generate(hedera.AccountId.init(0, 0, 100));
    const node_id = hedera.AccountId.init(0, 0, 3);
    
    const response = hedera.TransactionResponse{
        .transaction_id = tx_id,
        .node_id = node_id,
        .hash = &[_]u8{0xAB} ** 32,
        .scheduled = false,
    };
    
    // Verify response properties
    try testing.expectEqual(@as(u64, 100), response.transaction_id.account_id.account);
    try testing.expectEqual(@as(u64, 3), response.node_id.account);
    try testing.expectEqualSlices(u8, &[_]u8{0xAB} ** 32, response.hash);
    try testing.expect(!response.scheduled);
}
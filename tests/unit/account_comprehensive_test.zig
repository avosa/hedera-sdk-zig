const std = @import("std");
const testing = std.testing;
const hedera = @import("hedera");

test "AccountId - complete initialization tests" {
    // Test standard initialization
    const acc1 = hedera.AccountId.init(0, 0, 100);
    try testing.expectEqual(@as(u64, 0), acc1.shard);
    try testing.expectEqual(@as(u64, 0), acc1.realm);
    try testing.expectEqual(@as(u64, 100), acc1.account);
    
    // Test with different shard and realm
    const acc2 = hedera.AccountId.init(5, 10, 999999);
    try testing.expectEqual(@as(u64, 5), acc2.shard);
    try testing.expectEqual(@as(u64, 10), acc2.realm);
    try testing.expectEqual(@as(u64, 999999), acc2.account);
    
    // Test maximum values
    const acc3 = hedera.AccountId.init(std.math.maxInt(u64), std.math.maxInt(u64), std.math.maxInt(u64));
    try testing.expectEqual(std.math.maxInt(u64), acc3.shard);
    try testing.expectEqual(std.math.maxInt(u64), acc3.realm);
    try testing.expectEqual(std.math.maxInt(u64), acc3.account);
}

test "AccountId - string parsing comprehensive" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Test standard format
    const acc1 = try hedera.accountIdFromString(allocator, "0.0.100");
    try testing.expectEqual(@as(u64, 0), acc1.shard);
    try testing.expectEqual(@as(u64, 0), acc1.realm);
    try testing.expectEqual(@as(u64, 100), acc1.account);
    
    // Test with non-zero shard and realm
    const acc2 = try hedera.accountIdFromString(allocator, "5.10.999");
    try testing.expectEqual(@as(u64, 5), acc2.shard);
    try testing.expectEqual(@as(u64, 10), acc2.realm);
    try testing.expectEqual(@as(u64, 999), acc2.account);
    
    // Test invalid formats
    try testing.expectError(error.InvalidAccountId, hedera.accountIdFromString(allocator, "invalid"));
    try testing.expectError(error.InvalidAccountId, hedera.accountIdFromString(allocator, "0.0"));
    try testing.expectError(error.InvalidAccountId, hedera.accountIdFromString(allocator, "0.0.0.0"));
    try testing.expectError(error.InvalidAccountId, hedera.accountIdFromString(allocator, "abc.def.ghi"));
    try testing.expectError(error.InvalidAccountId, hedera.accountIdFromString(allocator, ""));
    try testing.expectError(error.InvalidAccountId, hedera.accountIdFromString(allocator, "0..100"));
    try testing.expectError(error.InvalidAccountId, hedera.accountIdFromString(allocator, ".0.100"));
    try testing.expectError(error.InvalidAccountId, hedera.accountIdFromString(allocator, "0.0."));
}

test "AccountId - toString conversions" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Test standard account
    const acc1 = hedera.AccountId.init(0, 0, 100);
    const str1 = try acc1.toString(allocator);
    defer allocator.free(str1);
    try testing.expectEqualStrings("0.0.100", str1);
    
    // Test with non-zero shard and realm
    const acc2 = hedera.AccountId.init(5, 10, 999);
    const str2 = try acc2.toString(allocator);
    defer allocator.free(str2);
    try testing.expectEqualStrings("5.10.999", str2);
    
    // Test large numbers
    const acc3 = hedera.AccountId.init(999, 888, 777666555);
    const str3 = try acc3.toString(allocator);
    defer allocator.free(str3);
    try testing.expectEqualStrings("999.888.777666555", str3);
}

test "AccountId - comparison operations" {
    const acc1 = hedera.AccountId.init(0, 0, 100);
    const acc2 = hedera.AccountId.init(0, 0, 100);
    const acc3 = hedera.AccountId.init(0, 0, 200);
    const acc4 = hedera.AccountId.init(1, 0, 100);
    const acc5 = hedera.AccountId.init(0, 1, 100);
    
    // Test equals
    try testing.expect(acc1.equals(acc2));
    try testing.expect(!acc1.equals(acc3));
    try testing.expect(!acc1.equals(acc4));
    try testing.expect(!acc1.equals(acc5));
    
    // Test num() helper
    try testing.expectEqual(@as(u64, 100), acc1.num());
    try testing.expectEqual(@as(u64, 200), acc3.num());
}

test "AccountId - aliased account support" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create account from alias (public key bytes)
    var key = try hedera.PrivateKey.generateEcdsa(allocator);
    defer key.deinit();
    
    const public_key = key.getPublicKey();
    const alias_bytes = try public_key.toBytes(allocator);
    defer allocator.free(alias_bytes);
    
    // Test creating AccountId from alias
    const aliased = hedera.AccountId.fromAlias(alias_bytes);
    try testing.expect(aliased.alias != null);
    try testing.expectEqualSlices(u8, alias_bytes, aliased.alias.?);
    try testing.expectEqual(@as(u64, 0), aliased.account);
}

test "AccountCreateTransaction - all fields and methods" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.accountCreateTransaction(allocator);
    defer tx.deinit();
    
    // Test all setters
    var key = try hedera.generatePrivateKey(allocator);
    defer key.deinit();
    
    _ = try tx.setKey(hedera.Key.fromPublicKey(key.getPublicKey()));
    _ = try tx.setInitialBalance(try hedera.Hbar.from(100));
    _ = try tx.setReceiverSignatureRequired(true);
    _ = try tx.setMaxAutomaticTokenAssociations(10);
    _ = try tx.setAccountMemo("Test memo with special chars: SUCCESS! & symbols!");
    _ = try tx.setAutoRenewPeriod(hedera.Duration.fromDays(90));
    _ = try tx.setStakedNodeId(3);
    _ = try tx.setStakedAccountId(hedera.AccountId.init(0, 0, 800));
    _ = try tx.setDeclineStakingReward(false);
    
    // Test ECDSA alias
    var ecdsa_key = try hedera.PrivateKey.generateEcdsa(allocator);
    defer ecdsa_key.deinit();
    const alias = try ecdsa_key.getPublicKey().toBytes(allocator);
    defer allocator.free(alias);
    _ = try tx.setAlias(alias);
    
    // Test transaction properties
    _ = try tx.setTransactionId(hedera.TransactionId.generate(hedera.AccountId.init(0, 0, 100)));
    _ = try tx.setNodeAccountIds(&[_]hedera.AccountId{
        hedera.AccountId.init(0, 0, 3),
        hedera.AccountId.init(0, 0, 4),
    });
    _ = try tx.setMaxTransactionFee(try hedera.Hbar.from(2));
    _ = try tx.setTransactionValidDuration(hedera.Duration.fromSeconds(120));
    _ = try tx.setTransactionMemo("Transaction memo");
    _ = try tx.setRegenerateTransactionId(true);
    
    // Verify all fields
    try testing.expect(tx.key != null);
    try testing.expectEqual(@as(i64, 10_000_000_000), tx.initial_balance.toTinybars());
    try testing.expect(tx.receiver_signature_required);
    try testing.expectEqual(@as(i32, 10), tx.max_automatic_token_associations);
    try testing.expectEqualStrings("Test memo with special chars: SUCCESS! & symbols!", tx.memo);
    try testing.expectEqual(@as(i64, 7776000), tx.auto_renew_period.seconds);
    try testing.expectEqual(@as(?i64, 3), tx.staked_node_id);
    try testing.expectEqual(@as(?u64, 800), tx.staked_account_id.?.account);
    try testing.expect(!tx.decline_staking_reward);
    try testing.expectEqualSlices(u8, alias, tx.alias.?);
    try testing.expectEqual(@as(i64, 200_000_000), tx.max_transaction_fee.?.toTinybars());
    try testing.expectEqual(@as(i64, 120), tx.transaction_valid_duration.?.seconds);
    try testing.expectEqualStrings("Transaction memo", tx.transaction_memo.?);
}

test "AccountCreateTransaction - staking conflicts" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.accountCreateTransaction(allocator);
    defer tx.deinit();
    
    // Set staked node ID first
    _ = try tx.setStakedNodeId(3);
    try testing.expectEqual(@as(?i64, 3), tx.staked_node_id);
    try testing.expectEqual(@as(?hedera.AccountId, null), tx.staked_account_id);
    
    // Setting staked account ID should clear node ID
    _ = try tx.setStakedAccountId(hedera.AccountId.init(0, 0, 800));
    try testing.expectEqual(@as(?i64, null), tx.staked_node_id);
    try testing.expectEqual(@as(?u64, 800), tx.staked_account_id.?.account);
    
    // Setting node ID again should clear account ID
    _ = try tx.setStakedNodeId(5);
    try testing.expectEqual(@as(?i64, 5), tx.staked_node_id);
    try testing.expectEqual(@as(?hedera.AccountId, null), tx.staked_account_id);
}

test "AccountUpdateTransaction - comprehensive field updates" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.AccountUpdateTransaction.init(allocator);
    defer tx.deinit();
    
    // Set account to update
    const account_id = hedera.AccountId.init(0, 0, 1234);
    _ = try tx.setAccountId(account_id);
    
    // Generate keys
    var new_key = try hedera.generatePrivateKey(allocator);
    defer new_key.deinit();
    
    // Update all possible fields
    _ = try tx.setKey(hedera.Key.fromPublicKey(new_key.getPublicKey()));
    _ = try tx.setReceiverSignatureRequired(false);
    _ = try tx.setMaxAutomaticTokenAssociations(20);
    _ = try tx.setMemo("Updated memo NOTE:");
    _ = try tx.setExpirationTime(hedera.Timestamp.fromSeconds(1234567890));
    _ = try tx.setAutoRenewPeriod(hedera.Duration.fromDays(120));
    _ = try tx.setStakedNodeId(4);
    _ = try tx.setDeclineStakingReward(true);
    
    // Clear memo
    _ = try tx.clearMemo();
    
    // Verify updates
    try testing.expectEqual(@as(u64, 1234), tx.account_id.?.account);
    try testing.expect(tx.key != null);
    try testing.expect(tx.receiver_sig_required != null);
    try testing.expect(!tx.receiver_sig_required.?);
    try testing.expectEqual(@as(i32, 20), tx.max_automatic_token_associations);
    try testing.expectEqual(@as(?[]const u8, null), tx.memo);
    try testing.expectEqual(@as(i64, 1234567890), tx.expiration_time.?.seconds);
    try testing.expectEqual(@as(i64, 10368000), tx.auto_renew_period.?.seconds);
    try testing.expectEqual(@as(?i64, 4), tx.staked_node_id);
    try testing.expect(tx.decline_staking_reward.?);
}

test "AccountDeleteTransaction - transfer scenarios" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.AccountDeleteTransaction.init(allocator);
    defer tx.deinit();
    
    // Set account to delete
    const account_id = hedera.AccountId.init(0, 0, 1000);
    _ = try tx.setAccountId(account_id);
    
    // Set transfer account (where remaining funds go)
    const transfer_account = hedera.AccountId.init(0, 0, 2000);
    _ = try tx.setTransferAccountId(transfer_account);
    
    // Test contract transfer
    const contract_id = hedera.ContractId.init(0, 0, 3000);
    _ = try tx.setTransferContractId(contract_id);
    
    // Verify - setting contract should clear account
    try testing.expectEqual(@as(u64, 1000), tx.delete_account_id.?.account);
    try testing.expectEqual(@as(?hedera.AccountId, null), tx.transfer_account_id);
    try testing.expectEqual(@as(?u64, 3000), tx.transfer_contract_id.?.num());
}

test "AccountAllowanceApproveTransaction - comprehensive allowances" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.AccountAllowanceApproveTransaction.init(allocator);
    defer tx.deinit();
    
    const owner = hedera.AccountId.init(0, 0, 100);
    const spender1 = hedera.AccountId.init(0, 0, 200);
    const spender2 = hedera.AccountId.init(0, 0, 300);
    const delegating_spender = hedera.AccountId.init(0, 0, 400);
    
    // HBAR allowances
    try tx.addHbarAllowance(owner, spender1, try hedera.Hbar.from(50));
    try tx.addHbarAllowance(owner, spender2, try hedera.Hbar.from(100));
    
    // Token allowances
    const token1 = hedera.TokenId.init(0, 0, 1000);
    const token2 = hedera.TokenId.init(0, 0, 2000);
    
    try tx.addTokenAllowance(token1, owner, spender1, 10000);
    try tx.addTokenAllowance(token2, owner, spender2, 50000);
    
    // NFT allowances
    const nft1 = hedera.NftId{
        .token_id = token1,
        .serial_number = 1,
    };
    const nft2 = hedera.NftId{
        .token_id = token1,
        .serial_number = 2,
    };
    
    try tx.addNftAllowance(nft1, owner, spender1);
    try tx.addNftAllowance(nft2, owner, spender2);
    
    // Approve all NFTs for a token
    try tx.addAllNftAllowance(token2, owner, spender1);
    
    // Delegated allowances
    try tx.addTokenAllowanceWithDelegatingSpender(
        token1,
        owner,
        spender1,
        delegating_spender,
        5000
    );
    
    // Verify counts
    try testing.expectEqual(@as(usize, 2), tx.hbar_allowances.items.len);
    try testing.expectEqual(@as(usize, 3), tx.token_allowances.items.len); // 2 regular + 1 delegated
    try testing.expectEqual(@as(usize, 2), tx.nft_allowances.items.len);
    try testing.expectEqual(@as(usize, 1), tx.token_nft_allowances.items.len);
    
    // Verify specific allowances
    try testing.expectEqual(@as(i64, 5_000_000_000), tx.hbar_allowances.items[0].amount.toTinybars());
    try testing.expectEqual(@as(i64, 10_000_000_000), tx.hbar_allowances.items[1].amount.toTinybars());
    try testing.expectEqual(@as(i64, 10000), tx.token_allowances.items[0].amount);
    try testing.expectEqual(@as(i64, 50000), tx.token_allowances.items[1].amount);
}

test "AccountAllowanceDeleteTransaction - delete operations" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.AccountAllowanceDeleteTransaction.init(allocator);
    defer tx.deinit();
    
    const owner = hedera.AccountId.init(0, 0, 300);
    const token1 = hedera.TokenId.init(0, 0, 2000);
    const token2 = hedera.TokenId.init(0, 0, 3000);
    
    // Delete all NFT allowances for multiple tokens
    try tx.deleteAllTokenNftAllowances(token1, owner);
    try tx.deleteAllTokenNftAllowances(token2, owner);
    
    // Add specific NFT serial deletions
    const serials = [_]i64{1, 2, 3, 4, 5};
    try tx.deleteTokenNftAllowances(token1, owner, &serials);
    
    // Verify deletions
    try testing.expectEqual(@as(usize, 3), tx.nft_allowance_deletions.items.len);
    try testing.expectEqual(@as(u64, 2000), tx.nft_allowance_deletions.items[0].token_id.num());
    try testing.expectEqual(@as(u64, 3000), tx.nft_allowance_deletions.items[1].token_id.num());
    try testing.expectEqual(@as(usize, 5), tx.nft_allowance_deletions.items[2].serials.items.len);
}

test "AccountInfo - comprehensive structure test" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var info = hedera.AccountInfo.init(allocator);
    defer info.deinit();
    
    // Set all fields
    info.account_id = hedera.AccountId.init(0, 0, 1234);
    info.contract_account_id = "0x1234567890123456789012345678901234567890";
    info.deleted = false;
    info.proxy_received = (try hedera.Hbar.from(10)).toTinybars();
    
    var key = try hedera.generatePrivateKey(allocator);
    defer key.deinit();
    info.key = key.getPublicKey();
    
    info.balance = try hedera.Hbar.from(1000);
    info.receiver_signature_required = true;
    info.expiration_time = hedera.Timestamp.fromSeconds(1234567890);
    info.auto_renew_period = hedera.Duration.fromDays(90);
    info.memo = "Test account with emoji LAUNCH:";
    info.owned_nfts = 5;
    info.max_automatic_token_associations = 10;
    info.alias = "alias123";
    info.ledger_id = "mainnet";
    info.ethereum_nonce = 42;
    
    // Staking info
    info.staking_info = hedera.AccountStakingInfo{
        .staked_node_id = 3,
        .staked_account_id = null,
        .stake_period_start = hedera.Timestamp.fromSeconds(1234567800),
        .pending_reward = 50000000,
        .staked_to_me = 100000000000,
        .decline_reward = false,
    };
    
    // Add multiple token relationships
    const tokens = [_]hedera.TokenId{
        hedera.TokenId.init(0, 0, 1000),
        hedera.TokenId.init(0, 0, 2000),
        hedera.TokenId.init(0, 0, 3000),
    };
    
    for (tokens, 0..) |token_id, i| {
        const rel = hedera.TokenRelationship{
            .token_id = token_id,
            .symbol = try std.fmt.allocPrint(allocator, "TKN{}", .{i}),
            .balance = (i + 1) * 1000,
            .kyc_status = if (i % 2 == 0) .granted else .revoked,
            .freeze_status = if (i % 2 == 0) .unfrozen else .frozen,
            .decimals = @intCast(i + 2),
            .automatic_association = i % 2 == 0,
            .allocator = allocator,
        };
        try info.token_relationships.append(rel);
    }
    
    // Verify all fields
    try testing.expectEqual(@as(u64, 1234), info.account_id.account);
    try testing.expectEqualStrings("0x1234567890123456789012345678901234567890", info.contract_account_id);
    try testing.expect(!info.deleted);
    try testing.expectEqual(@as(i64, 1_000_000_000), info.proxy_received);
    try testing.expectEqual(@as(i64, 100_000_000_000), info.balance.toTinybars());
    try testing.expect(info.receiver_signature_required);
    try testing.expectEqualStrings("Test account with emoji LAUNCH:", info.memo);
    try testing.expectEqual(@as(usize, 3), info.token_relationships.items.len);
    
    // Verify token relationships
    try testing.expectEqual(@as(u64, 1000), info.token_relationships.items[0].balance);
    try testing.expectEqual(hedera.KycStatus.granted, info.token_relationships.items[0].kyc_status);
    try testing.expectEqual(hedera.FreezeStatus.unfrozen, info.token_relationships.items[0].freeze_status);
    try testing.expect(info.token_relationships.items[0].automatic_association);
    
    try testing.expectEqual(@as(u64, 2000), info.token_relationships.items[1].balance);
    try testing.expectEqual(hedera.KycStatus.revoked, info.token_relationships.items[1].kyc_status);
    try testing.expectEqual(hedera.FreezeStatus.frozen, info.token_relationships.items[1].freeze_status);
    try testing.expect(!info.token_relationships.items[1].automatic_association);
}

test "AccountBalance - token balance management" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var balance = hedera.AccountBalance.init(allocator);
    defer balance.deinit();
    
    // Set HBAR balance
    balance.hbars = try hedera.Hbar.from(500);
    
    // Add multiple token balances
    const tokens = [_]struct { id: hedera.TokenId, balance: u64, decimals: u32 }{
        .{ .id = hedera.TokenId.init(0, 0, 1000), .balance = 10000, .decimals = 2 },
        .{ .id = hedera.TokenId.init(0, 0, 2000), .balance = 50000, .decimals = 6 },
        .{ .id = hedera.TokenId.init(0, 0, 3000), .balance = 100000, .decimals = 8 },
        .{ .id = hedera.TokenId.init(0, 0, 4000), .balance = 999999999, .decimals = 18 },
    };
    
    for (tokens) |token| {
        try balance.tokens.put(token.id, token.balance);
        try balance.token_decimals.put(token.id, token.decimals);
    }
    
    // Verify balances
    try testing.expectEqual(@as(i64, 50_000_000_000), balance.hbars.toTinybars());
    
    for (tokens) |token| {
        try testing.expectEqual(token.balance, balance.tokens.get(token.id).?);
        try testing.expectEqual(token.decimals, balance.token_decimals.get(token.id).?);
    }
    
    // Test missing token
    const missing_token = hedera.TokenId.init(0, 0, 9999);
    try testing.expectEqual(@as(?u64, null), balance.tokens.get(missing_token));
    try testing.expectEqual(@as(?u32, null), balance.token_decimals.get(missing_token));
}

test "AccountRecords - transaction record management" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const account_id = hedera.AccountId.init(0, 0, 100);
    var records = hedera.AccountRecords.init(allocator, account_id);
    defer records.deinit();
    
    // Add multiple transaction records with different statuses
    const statuses = [_]hedera.Status{
        .OK,
        .INSUFFICIENT_ACCOUNT_BALANCE,
        .INVALID_SIGNATURE,
        .DUPLICATE_TRANSACTION,
        .BUSY,
    };
    
    for (statuses, 0..) |status, i| {
        const receipt = hedera.TransactionReceipt.init(allocator, status);
        const tx_id = hedera.TransactionId{
            .account_id = account_id,
            .valid_start = hedera.Timestamp.fromSeconds(@intCast(1000000 + i * 100)),
            .scheduled = i % 2 == 0,
            .nonce = if (i % 3 == 0) i else null,
        };
        
        var record = hedera.TransactionRecord.init(allocator, receipt, tx_id);
        record.transaction_fee = try hedera.Hbar.fromTinybars(@intCast((i + 1) * 1000000));
        record.consensus_timestamp = hedera.Timestamp.fromSeconds(@intCast(1000000 + i * 100 + 10));
        record.memo = try std.fmt.allocPrint(allocator, "Record {}", .{i});
        
        // Add transfers
        try record.transfers.append(hedera.Transfer{
            .account_id = hedera.AccountId.init(0, 0, @intCast(100 + i)),
            .amount = try hedera.Hbar.from(@intCast(i * 10)),
            .is_approved = i % 2 == 0,
        });
        
        try records.records.append(record);
    }
    
    // Verify records
    try testing.expectEqual(@as(usize, statuses.len), records.records.items.len);
    try testing.expectEqual(account_id.account, records.account_id.account);
    
    // Check each record
    for (records.records.items, 0..) |record, i| {
        try testing.expectEqual(statuses[i], record.receipt.status);
        try testing.expectEqual(@as(i64, @intCast((i + 1) * 1000000)), record.transaction_fee.toTinybars());
        try testing.expectEqual(@as(bool, i % 2 == 0), record.transaction_id.scheduled);
        
        const expected_memo = try std.fmt.allocPrint(allocator, "Record {}", .{i});
        defer allocator.free(expected_memo);
        try testing.expectEqualStrings(expected_memo, record.memo.?);
    }
}

test "LiveHash operations - add and delete" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // LiveHashAddTransaction
    var add_tx = hedera.LiveHashAddTransaction.init(allocator);
    defer add_tx.deinit();
    
    const account_id = hedera.AccountId.init(0, 0, 500);
    _ = try add_tx.setAccountId(account_id);
    
    // Create SHA-384 hash (48 bytes)
    var hash: [48]u8 = undefined;
    for (&hash, 0..) |*byte, i| {
        byte.* = @intCast(i % 256);
    }
    _ = try add_tx.setHash(&hash);
    
    const duration = hedera.Duration.fromDays(30);
    _ = try add_tx.setDuration(duration);
    
    // Add multiple keys
    var keys = std.ArrayList(hedera.PrivateKey).init(allocator);
    defer {
        for (keys.items) |*key| {
            key.deinit();
        }
        keys.deinit();
    }
    
    for (0..5) |_| {
        var key = try hedera.generatePrivateKey(allocator);
        try keys.append(key);
        _ = try add_tx.addKey(hedera.Key.fromPublicKey(key.getPublicKey()));
    }
    
    // Verify add transaction
    try testing.expectEqual(@as(u64, 500), add_tx.account_id.?.account);
    try testing.expectEqualSlices(u8, &hash, add_tx.hash);
    try testing.expectEqual(@as(i64, 2592000), add_tx.duration.?.seconds);
    try testing.expectEqual(@as(usize, 5), add_tx.keys.items.len);
    
    // LiveHashDeleteTransaction
    var delete_tx = hedera.LiveHashDeleteTransaction.init(allocator);
    defer delete_tx.deinit();
    
    _ = try delete_tx.setAccountId(account_id);
    _ = try delete_tx.setHash(&hash);
    
    // Verify delete transaction
    try testing.expectEqual(@as(u64, 500), delete_tx.account_id.?.account);
    try testing.expectEqualSlices(u8, &hash, delete_tx.hash);
}

test "Transfer and TokenTransfer structures - comprehensive" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Test HBAR transfers
    const transfers = [_]hedera.Transfer{
        .{
            .account_id = hedera.AccountId.init(0, 0, 100),
            .amount = try hedera.Hbar.from(-100),
            .is_approved = true,
        },
        .{
            .account_id = hedera.AccountId.init(0, 0, 200),
            .amount = try hedera.Hbar.from(50),
            .is_approved = false,
        },
        .{
            .account_id = hedera.AccountId.init(0, 0, 300),
            .amount = try hedera.Hbar.from(50),
            .is_approved = true,
        },
    };
    
    // Verify sum is zero (balanced transfer)
    var sum: i64 = 0;
    for (transfers) |transfer| {
        sum += transfer.amount.toTinybars();
    }
    try testing.expectEqual(@as(i64, 0), sum);
    
    // Test token transfers
    var token_transfer = hedera.TokenTransfer{
        .token_id = hedera.TokenId.init(0, 0, 5000),
        .account_id = hedera.AccountId.init(0, 0, 1001),
        .amount = 1000000,
        .transfers = std.ArrayList(hedera.AccountAmount).init(allocator),
        .expected_decimals = 6,
        .is_approved = false,
    };
    defer token_transfer.transfers.deinit();
    
    // Add multiple account amounts
    const accounts = [_]hedera.AccountAmount{
        .{
            .account_id = hedera.AccountId.init(0, 0, 100),
            .amount = -1000000,
            .is_approved = true,
        },
        .{
            .account_id = hedera.AccountId.init(0, 0, 200),
            .amount = 600000,
            .is_approved = false,
        },
        .{
            .account_id = hedera.AccountId.init(0, 0, 300),
            .amount = 400000,
            .is_approved = false,
        },
    };
    
    for (accounts) |account| {
        try token_transfer.transfers.append(account);
    }
    
    // Verify token transfer sum is zero
    var token_sum: i64 = 0;
    for (token_transfer.transfers.items) |transfer| {
        token_sum += transfer.amount;
    }
    try testing.expectEqual(@as(i64, 0), token_sum);
    
    // Test NFT transfers
    var nft_transfer = hedera.NftTransfer{
        .token_id = hedera.TokenId.init(0, 0, 6000),
        .sender = hedera.AccountId.init(0, 0, 100),
        .receiver = hedera.AccountId.init(0, 0, 200),
        .serial_number = 42,
        .is_approved = true,
    };
    
    try testing.expectEqual(@as(u64, 6000), nft_transfer.token_id.num());
    try testing.expectEqual(@as(i64, 42), nft_transfer.serial_number);
    try testing.expect(nft_transfer.is_approved);
}

test "ProxyStaker structure" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    
    const proxy_staker = hedera.ProxyStaker{
        .staker_id = hedera.AccountId.init(0, 0, 777),
        .account_id = hedera.AccountId.init(0, 0, 777),
        .proxy_account_id = hedera.AccountId.init(0, 0, 888),
        .staked_amount = try hedera.Hbar.from(1000),
        .amount = try hedera.Hbar.from(1000),
        .stake_period_start = 1000000,
        .decline_reward = false,
        .allocator = arena.allocator(),
    };
    
    try testing.expectEqual(@as(u64, 777), proxy_staker.account_id.account);
    try testing.expectEqual(@as(u64, 888), proxy_staker.proxy_account_id.account);
    try testing.expectEqual(@as(i64, 100_000_000_000), proxy_staker.amount.toTinybars());
    try testing.expectEqual(@as(i64, 1000000), proxy_staker.stake_period_start);
    try testing.expect(!proxy_staker.decline_reward);
}

test "Account edge cases and error conditions" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Test empty memo handling
    var tx = hedera.accountCreateTransaction(allocator);
    defer tx.deinit();
    
    _ = try tx.setAccountMemo("");
    try testing.expectEqualStrings("", tx.memo);
    
    // Test maximum memo length (100 bytes)
    const long_memo = "a" ** 100;
    _ = try tx.setAccountMemo(long_memo);
    try testing.expectEqual(@as(usize, 100), tx.memo.len);
    
    // Test clearing optional fields
    var update_tx = hedera.AccountUpdateTransaction.init(allocator);
    defer update_tx.deinit();
    
    _ = try update_tx.setMemo("test");
    try testing.expectEqualStrings("test", update_tx.memo.?);
    _ = try update_tx.clearMemo();
    try testing.expectEqual(@as(?[]const u8, null), update_tx.memo);
    
    // Test zero balances
    var balance = hedera.AccountBalance.init(allocator);
    defer balance.deinit();
    
    balance.hbars = try hedera.Hbar.fromTinybars(0);
    try testing.expectEqual(@as(i64, 0), balance.hbars.toTinybars());
    
    // Test negative balances (for transfers)
    const negative_transfer = hedera.Transfer{
        .account_id = hedera.AccountId.init(0, 0, 100),
        .amount = try hedera.Hbar.from(-999999),
        .is_approved = false,
    };
    try testing.expectEqual(@as(i64, -99999900000000), negative_transfer.amount.toTinybars());
}
const std = @import("std");
const testing = std.testing;
const hedera = @import("hedera");

test "Account create transaction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.new_account_create_transaction(allocator);
    defer tx.deinit();
    
    // Generate key for new account
    var key = try hedera.generate_private_key(allocator);
    defer key.deinit();
    
    // Set all parameters
    _ = try tx.set_key_without_alias(hedera.Key.fromPublicKey(key.getPublicKey()));
    _ = tx.setInitialBalance(try hedera.Hbar.from(100));
    _ = tx.setReceiverSignatureRequired(true);
    _ = tx.setMaxAutomaticTokenAssociations(10);
    _ = tx.setAccountMemo("Test account creation");
    _ = tx.setAutoRenewPeriod(hedera.Duration.fromDays(90));
    _ = tx.setStakedNodeId(3);
    _ = tx.setDeclineStakingReward(false);
    
    // Verify all settings
    try testing.expect(tx.key != null);
    try testing.expectEqual(@as(i64, 10_000_000_000), tx.initial_balance.toTinybars());
    try testing.expect(tx.receiver_signature_required);
    try testing.expectEqual(@as(i32, 10), tx.max_automatic_token_associations);
    try testing.expectEqualStrings("Test account creation", tx.memo);
    try testing.expectEqual(@as(i64, 7776000), tx.auto_renew_period.seconds);
    try testing.expectEqual(@as(?i64, 3), tx.staked_node_id);
    try testing.expect(!tx.decline_staking_reward);
}

test "Account create with alias" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.new_account_create_transaction(allocator);
    defer tx.deinit();
    
    // Generate ECDSA key for alias
    var key = try hedera.PrivateKey.generateEcdsa(allocator);
    defer key.deinit();
    
    // Set alias
    const public_key = key.getPublicKey();
    const alias = try public_key.toBytes(allocator);
    defer allocator.free(alias);
    
    _ = try tx.setAlias(alias);
    
    try testing.expect(tx.alias != null);
    try testing.expectEqualSlices(u8, alias, tx.alias.?);
}

test "Account update transaction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.AccountUpdateTransaction.init(allocator);
    defer tx.deinit();
    
    // Set account to update
    const account_id = hedera.AccountId.init(0, 0, 1234);
    _ = tx.setAccountId(account_id);
    
    // Generate new key
    var new_key = try hedera.generate_private_key(allocator);
    defer new_key.deinit();
    
    // Update various properties
    _ = tx.setKey(hedera.Key.fromPublicKey(new_key.getPublicKey()));
    _ = tx.setReceiverSignatureRequired(false);
    _ = tx.setMaxAutomaticTokenAssociations(20);
    _ = tx.setMemo("Updated account");
    _ = tx.setExpirationTime(hedera.Timestamp.fromSeconds(1234567890));
    _ = tx.setAutoRenewPeriod(hedera.Duration.fromDays(120));
    _ = tx.setStakedNodeId(4);
    _ = tx.setDeclineStakingReward(true);
    
    // Verify settings
    try testing.expectEqual(@as(u64, 1234), tx.account_id.?.account);
    try testing.expect(tx.key != null);
    try testing.expect(tx.receiver_sig_required != null);
    try testing.expect(!tx.receiver_sig_required.?);
    try testing.expectEqual(@as(i32, 20), tx.max_automatic_token_associations);
    try testing.expectEqualStrings("Updated account", tx.memo.?);
    try testing.expectEqual(@as(i64, 1234567890), tx.expiration_time.?.seconds);
    try testing.expectEqual(@as(i64, 10368000), tx.auto_renew_period.?.seconds);
    try testing.expectEqual(@as(?i64, 4), tx.staked_node_id);
    try testing.expect(tx.decline_staking_reward.?);
}

test "Account delete transaction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.AccountDeleteTransaction.init(allocator);
    defer tx.deinit();
    
    // Set account to delete
    const account_id = hedera.AccountId.init(0, 0, 1000);
    _ = tx.setAccountId(account_id);
    
    // Set transfer account (where remaining funds go)
    const transfer_account = hedera.AccountId.init(0, 0, 2000);
    _ = tx.setTransferAccountId(transfer_account);
    
    try testing.expectEqual(@as(u64, 1000), tx.delete_account_id.?.account);
    try testing.expectEqual(@as(u64, 2000), tx.transfer_account_id.?.account);
}

test "Account allowance approve transaction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.AccountAllowanceApproveTransaction.init(allocator);
    defer tx.deinit();
    
    // Approve HBAR allowance
    const owner = hedera.AccountId.init(0, 0, 100);
    const spender = hedera.AccountId.init(0, 0, 200);
    const amount = try hedera.Hbar.from(50);
    
    try tx.addHbarAllowance(owner, spender, amount);
    
    // Approve token allowance
    const token_id = hedera.TokenId.init(0, 0, 1000);
    const token_amount: i64 = 10000;
    
    try tx.addTokenAllowance(token_id, owner, spender, token_amount);
    
    // Approve NFT allowance
    const nft_id = hedera.NftId{
        .token_id = token_id,
        .serial_number = 1,
    };
    
    try tx.addNftAllowance(nft_id, owner, spender);
    
    // Approve all NFTs
    try tx.addAllNftAllowance(token_id, owner, spender);
    
    // Verify allowances
    try testing.expectEqual(@as(usize, 1), tx.hbar_allowances.items.len);
    try testing.expectEqual(@as(usize, 1), tx.token_allowances.items.len);
    try testing.expectEqual(@as(usize, 1), tx.nft_allowances.items.len);
    try testing.expectEqual(@as(usize, 1), tx.token_nft_allowances.items.len);
}

test "Account allowance delete transaction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.AccountAllowanceDeleteTransaction.init(allocator);
    defer tx.deinit();
    
    // Delete all NFT allowances
    const token_id = hedera.TokenId.init(0, 0, 2000);
    const owner = hedera.AccountId.init(0, 0, 300);
    
    try tx.deleteAllTokenNftAllowances(token_id, owner);
    
    try testing.expectEqual(@as(usize, 1), tx.nft_allowance_deletions.items.len);
    try testing.expectEqual(@as(u64, 2000), tx.nft_allowance_deletions.items[0].token_id.num());
    try testing.expectEqual(@as(u64, 300), tx.nft_allowance_deletions.items[0].owner.num());
}

test "Live hash add transaction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.LiveHashAddTransaction.init(allocator);
    defer tx.deinit();
    
    // Set account
    const account_id = hedera.AccountId.init(0, 0, 500);
    _ = tx.setAccountId(account_id);
    
    // Set hash
    const hash = [_]u8{0xAB} ** 48;
    _ = try tx.setHash(&hash);
    
    // Set duration
    const duration = hedera.Duration.fromDays(30);
    _ = tx.setDuration(duration);
    
    // Add keys
    var key1 = try hedera.generate_private_key(allocator);
    defer key1.deinit();
    
    var key2 = try hedera.generate_private_key(allocator);
    defer key2.deinit();
    
    _ = try tx.addKey(hedera.Key.fromPublicKey(key1.getPublicKey()));
    _ = try tx.addKey(hedera.Key.fromPublicKey(key2.getPublicKey()));
    
    try testing.expectEqual(@as(u64, 500), tx.account_id.?.account);
    try testing.expectEqualSlices(u8, &hash, tx.hash);
    try testing.expectEqual(@as(i64, 2592000), tx.duration.?.seconds);
    try testing.expectEqual(@as(usize, 2), tx.keys.items.len);
}

test "Live hash delete transaction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.LiveHashDeleteTransaction.init(allocator);
    defer tx.deinit();
    
    // Set account
    const account_id = hedera.AccountId.init(0, 0, 600);
    _ = tx.setAccountId(account_id);
    
    // Set hash to delete
    const hash = [_]u8{0xCD} ** 48;
    _ = try tx.setHash(&hash);
    
    try testing.expectEqual(@as(u64, 600), tx.account_id.?.account);
    try testing.expectEqualSlices(u8, &hash, tx.hash);
}

test "Account info structure" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var info = hedera.AccountInfo.init(allocator);
    defer info.deinit();
    
    // Set account info fields
    info.account_id = hedera.AccountId.init(0, 0, 1234);
    info.contract_account_id = "0x1234567890123456789012345678901234567890";
    info.deleted = false;
    info.proxy_received = (try hedera.Hbar.from(10)).toTinybars();
    
    var key = try hedera.generate_private_key(allocator);
    defer key.deinit();
    info.key = key.getPublicKey();
    
    info.balance = try hedera.Hbar.from(1000);
    info.receiver_signature_required = true;
    info.expiration_time = hedera.Timestamp.fromSeconds(1234567890);
    info.auto_renew_period = hedera.Duration.fromDays(90);
    info.memo = "Test account";
    info.owned_nfts = 5;
    info.max_automatic_token_associations = 10;
    info.alias = "";
    info.ledger_id = "mainnet";
    info.ethereum_nonce = 42;
    
    // Staking info (using AccountInfo StakingInfo type)
    info.staking_info = hedera.AccountStakingInfo{
        .staked_node_id = 3,
        .staked_account_id = null,
        .stake_period_start = hedera.Timestamp.fromSeconds(1234567800),
        .pending_reward = 50000000, // in tinybars
        .staked_to_me = 100000000000, // in tinybars
        .decline_reward = false,
    };
    
    // Add token relationships
    const token_rel = hedera.TokenRelationship{
        .token_id = hedera.TokenId.init(0, 0, 1000),
        .symbol = "TST",
        .balance = 10000,
        .kyc_status = .granted,
        .freeze_status = .unfrozen,
        .decimals = 2,
        .automatic_association = false,
        .allocator = allocator,
    };
    
    try info.token_relationships.append(token_rel);
    
    // Verify fields
    try testing.expectEqual(@as(u64, 1234), info.account_id.account);
    try testing.expect(!info.deleted);
    try testing.expectEqual(@as(i64, 1_000_000_000), info.proxy_received);
    try testing.expectEqual(@as(i64, 100_000_000_000), info.balance.toTinybars());
    try testing.expect(info.receiver_signature_required);
    try testing.expectEqual(@as(i64, 1234567890), info.expiration_time.seconds);
    try testing.expectEqual(@as(i64, 7776000), info.auto_renew_period.seconds);
    try testing.expectEqualStrings("Test account", info.memo);
    try testing.expectEqual(@as(i64, 5), info.owned_nfts);
    try testing.expectEqual(@as(i32, 10), info.max_automatic_token_associations);
    try testing.expectEqualStrings("mainnet", info.ledger_id);
    try testing.expectEqual(@as(i64, 42), info.ethereum_nonce);
    try testing.expectEqual(@as(i64, 3), info.staking_info.?.staked_node_id.?);
    try testing.expectEqual(@as(usize, 1), info.token_relationships.items.len);
}

test "Account balance structure" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var balance = hedera.AccountBalance.init(allocator);
    defer balance.deinit();
    
    // Set HBAR balance
    balance.hbars = try hedera.Hbar.from(500);
    
    // Add token balances
    const token1 = hedera.TokenId.init(0, 0, 1000);
    const token2 = hedera.TokenId.init(0, 0, 2000);
    
    try balance.tokens.put(token1, 10000);
    try balance.tokens.put(token2, 50000);
    
    // Add token decimals
    try balance.token_decimals.put(token1, 2);
    try balance.token_decimals.put(token2, 8);
    
    // Verify balances
    try testing.expectEqual(@as(i64, 50_000_000_000), balance.hbars.toTinybars());
    try testing.expectEqual(@as(u64, 10000), balance.tokens.get(token1).?);
    try testing.expectEqual(@as(u64, 50000), balance.tokens.get(token2).?);
    try testing.expectEqual(@as(u32, 2), balance.token_decimals.get(token1).?);
    try testing.expectEqual(@as(u32, 8), balance.token_decimals.get(token2).?);
}

test "Account records structure" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var records = hedera.AccountRecords.init(allocator, hedera.AccountId.init(0, 0, 100));
    defer records.deinit();
    
    // Add transaction records - use the exported TransactionRecord
    const receipt1 = hedera.TransactionReceipt.init(allocator, hedera.Status.OK);
    const tx_id1 = hedera.TransactionId.generate(hedera.AccountId.init(0, 0, 100));
    var record1 = hedera.TransactionRecord.init(allocator, receipt1, tx_id1);
    record1.transaction_fee = try hedera.Hbar.fromTinybars(1000000);
    
    const receipt2 = hedera.TransactionReceipt.init(allocator, hedera.Status.OK);
    const tx_id2 = hedera.TransactionId.generate(hedera.AccountId.init(0, 0, 100));
    var record2 = hedera.TransactionRecord.init(allocator, receipt2, tx_id2);
    record2.transaction_fee = try hedera.Hbar.fromTinybars(2000000);
    
    try records.records.append(record1);
    try records.records.append(record2);
    
    // Verify records
    try testing.expectEqual(@as(usize, 2), records.records.items.len);
    try testing.expectEqual(@as(i64, 1000000), records.records.items[0].transaction_fee.toTinybars());
    try testing.expectEqual(@as(i64, 2000000), records.records.items[1].transaction_fee.toTinybars());
}

test "Proxy staker structure" {
    const proxy_staker = hedera.ProxyStaker{
        .staker_id = hedera.AccountId.init(0, 0, 777),
        .account_id = hedera.AccountId.init(0, 0, 777),
        .proxy_account_id = hedera.AccountId.init(0, 0, 888),
        .staked_amount = try hedera.Hbar.from(1000),
        .amount = try hedera.Hbar.from(1000),
        .stake_period_start = 1000000,
        .decline_reward = false,
        .allocator = testing.allocator,
    };
    
    try testing.expectEqual(@as(u64, 777), proxy_staker.account_id.account);
    try testing.expectEqual(@as(i64, 100_000_000_000), proxy_staker.amount.toTinybars());
}

test "Transfer structure" {
    const transfer = hedera.Transfer{
        .account_id = hedera.AccountId.init(0, 0, 888),
        .amount = try hedera.Hbar.from(-50),
        .is_approved = true,
    };
    
    try testing.expectEqual(@as(u64, 888), transfer.account_id.account);
    try testing.expectEqual(@as(i64, -5_000_000_000), transfer.amount.toTinybars());
    try testing.expect(transfer.is_approved);
}

test "Token transfer structure" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var token_transfer = hedera.TokenTransfer{
        .token_id = hedera.TokenId.init(0, 0, 3000),
        .account_id = hedera.AccountId.init(0, 0, 1001),
        .amount = 1000000,
        .transfers = std.ArrayList(hedera.AccountAmount).init(allocator),
        .nft_transfers = std.ArrayList(hedera.NftTransfer).init(allocator),
        .expected_decimals = 6,
    };
    defer token_transfer.transfers.deinit();
    defer token_transfer.nft_transfers.deinit();
    
    // Add account amounts
    try token_transfer.transfers.append(.{
        .account_id = hedera.AccountId.init(0, 0, 100),
        .amount = -1000000,
        .is_approved = false,
    });
    
    try token_transfer.transfers.append(.{
        .account_id = hedera.AccountId.init(0, 0, 200),
        .amount = 1000000,
        .is_approved = true,
    });
    
    // Add NFT transfer
    try token_transfer.nft_transfers.append(.{
        .nft_id = hedera.NftId.init(hedera.TokenId.init(0, 0, 3000), 42),
        .sender_account_id = hedera.AccountId.init(0, 0, 100),
        .receiver_account_id = hedera.AccountId.init(0, 0, 200),
        .is_approved = true,
    });
    
    try testing.expectEqual(@as(u64, 3000), token_transfer.token_id.num());
    try testing.expectEqual(@as(usize, 2), token_transfer.transfers.items.len);
    try testing.expectEqual(@as(usize, 1), token_transfer.nft_transfers.items.len);
    try testing.expectEqual(@as(?u32, 6), token_transfer.expected_decimals);
}


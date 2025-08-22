const std = @import("std");
const testing = std.testing;
const hedera = @import("hedera");

test "Schedule create transaction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create transaction to schedule
    var transfer = hedera.TransferTransaction.init(allocator);
    defer transfer.deinit();
    
    const account1 = hedera.AccountId.init(0, 0, 100);
    const account2 = hedera.AccountId.init(0, 0, 200);
    
    _ = try transfer.addHbarTransfer(account1, try hedera.Hbar.from(-100));
    _ = try transfer.addHbarTransfer(account2, try hedera.Hbar.from(100));
    
    // Create schedule
    var schedule = hedera.ScheduleCreateTransaction.init(allocator);
    defer schedule.deinit();
    
    _ = schedule.setScheduledTransaction(&transfer.base);
    _ = try schedule.setScheduleMemo("Scheduled transfer");
    _ = schedule.setPayerAccountId(account1);
    
    // Set admin key
    var admin_key = try hedera.generatePrivateKey(allocator);
    defer admin_key.deinit();
    _ = schedule.setAdminKey(hedera.Key.fromPublicKey(admin_key.getPublicKey()));
    
    // Set expiration time
    const expiration = hedera.Timestamp.fromSeconds(1234567890);
    _ = schedule.setExpirationTime(expiration);
    
    // Wait for expiry
    _ = schedule.setWaitForExpiry(true);
    
    // Verify settings
    try testing.expect(schedule.scheduled_transaction != null);
    try testing.expectEqualStrings("Scheduled transfer", schedule.memo.?);
    try testing.expectEqual(@as(u64, 100), schedule.payer_account_id.?.account);
    try testing.expect(schedule.admin_key != null);
    try testing.expectEqual(@as(i64, 1234567890), schedule.expiration_time.?.seconds);
    try testing.expect(schedule.wait_for_expiry);
}

test "Schedule sign transaction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.ScheduleSignTransaction.init(allocator);
    defer tx.deinit();
    
    // Set schedule ID
    const schedule_id = hedera.ScheduleId.init(0, 0, 555);
    _ = tx.setScheduleId(schedule_id);
    
    try testing.expectEqual(@as(u64, 555), tx.schedule_id.?.num());
}

test "Schedule delete transaction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.ScheduleDeleteTransaction.init(allocator);
    defer tx.deinit();
    
    // Set schedule ID
    const schedule_id = hedera.ScheduleId.init(0, 0, 666);
    _ = tx.setScheduleId(schedule_id);
    
    try testing.expectEqual(@as(u64, 666), tx.schedule_id.?.num());
}

test "Schedule info structure" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var info = hedera.ScheduleInfo.init(allocator);
    defer info.deinit();
    
    // Set schedule info fields
    info.schedule_id = hedera.ScheduleId.init(0, 0, 777);
    info.creator_account_id = hedera.AccountId.init(0, 0, 300);
    info.payer_account_id = hedera.AccountId.init(0, 0, 400);
    
    // Set transaction body
    var transfer = hedera.TransferTransaction.init(allocator);
    defer transfer.deinit();
    
    const account1 = hedera.AccountId.init(0, 0, 100);
    const account2 = hedera.AccountId.init(0, 0, 200);
    
    _ = try transfer.addHbarTransfer(account1, try hedera.Hbar.from(-50));
    _ = try transfer.addHbarTransfer(account2, try hedera.Hbar.from(50));
    
    info.scheduled_transaction = &transfer.base;
    
    // Set signatories
    var key1 = try hedera.generatePrivateKey(allocator);
    defer key1.deinit();
    
    var key2 = try hedera.generatePrivateKey(allocator);
    defer key2.deinit();
    
    try info.signatories.append(hedera.Key.fromPublicKey(key1.getPublicKey()));
    try info.signatories.append(hedera.Key.fromPublicKey(key2.getPublicKey()));
    
    // Set admin key
    var admin_key = try hedera.generatePrivateKey(allocator);
    defer admin_key.deinit();
    info.admin_key = hedera.Key.fromPublicKey(admin_key.getPublicKey());
    
    // Set memo
    info.memo = "Schedule info";
    
    // Set executed timestamp
    info.executed_at = hedera.Timestamp.fromSeconds(1234567890);
    
    // Set deleted timestamp
    info.deleted_at = null;
    
    // Set expiration time
    info.expiration_time = hedera.Timestamp.fromSeconds(2345678901);
    
    // Set ledger ID
    info.ledger_id = "mainnet";
    
    // Set wait for expiry
    info.wait_for_expiry = true;
    
    // Verify fields
    try testing.expectEqual(@as(u64, 777), info.schedule_id.num());
    try testing.expectEqual(@as(u64, 300), info.creator_account_id.account);
    try testing.expectEqual(@as(u64, 400), info.payer_account_id.account);
    try testing.expect(info.scheduled_transaction != null);
    try testing.expectEqual(@as(usize, 2), info.signatories.items.len);
    try testing.expect(info.admin_key != null);
    try testing.expectEqualStrings("Schedule info", info.memo);
    try testing.expectEqual(@as(i64, 1234567890), info.executed_at.?.seconds);
    try testing.expect(info.deleted_at == null);
    try testing.expectEqual(@as(i64, 2345678901), info.expiration_time.seconds);
    try testing.expectEqualStrings("mainnet", info.ledger_id);
    try testing.expect(info.wait_for_expiry);
}

test "Schedule with token operations" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create token transfer to schedule
    var token_transfer = hedera.TransferTransaction.init(allocator);
    defer token_transfer.deinit();
    
    const token_id = hedera.TokenId.init(0, 0, 1000);
    const account1 = hedera.AccountId.init(0, 0, 500);
    const account2 = hedera.AccountId.init(0, 0, 600);
    
    try token_transfer.addTokenTransfer(token_id, account1, -1000);
    try token_transfer.addTokenTransfer(token_id, account2, 1000);
    
    // Create schedule
    var schedule = hedera.ScheduleCreateTransaction.init(allocator);
    defer schedule.deinit();
    
    _ = schedule.setScheduledTransaction(&token_transfer.base);
    _ = try schedule.setScheduleMemo("Scheduled token transfer");
    
    try testing.expect(schedule.scheduled_transaction != null);
    try testing.expectEqualStrings("Scheduled token transfer", schedule.memo.?);
}

test "Schedule with smart contract operations" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create contract execute to schedule
    var contract_execute = hedera.ContractExecuteTransaction.init(allocator);
    defer contract_execute.deinit();
    
    const contract_id = hedera.ContractId.init(0, 0, 2000);
    _ = contract_execute.setContractId(contract_id);
    _ = contract_execute.setGas(100000);
    _ = contract_execute.setPayableAmount(try hedera.Hbar.from(1));
    
    // Set function parameters
    var params = hedera.ContractFunctionParameters.init(allocator);
    defer params.deinit();
    
    try params.addUint256(42);
    try params.addAddress("0x1234567890123456789012345678901234567890");
    
    const function_params = try params.toBytes();
    defer allocator.free(function_params);
    _ = contract_execute.setFunctionParameters(function_params);
    
    // Create schedule
    var schedule = hedera.ScheduleCreateTransaction.init(allocator);
    defer schedule.deinit();
    
    _ = schedule.setScheduledTransaction(&contract_execute.base);
    _ = try schedule.setScheduleMemo("Scheduled contract execution");
    
    try testing.expect(schedule.scheduled_transaction != null);
    try testing.expectEqualStrings("Scheduled contract execution", schedule.memo.?);
}

test "Schedule with account operations" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create account update to schedule
    var account_update = hedera.AccountUpdateTransaction.init(allocator);
    defer account_update.deinit();
    
    const account_id = hedera.AccountId.init(0, 0, 700);
    _ = account_update.setAccountId(account_id);
    
    // Generate new key
    var new_key = try hedera.generatePrivateKey(allocator);
    defer new_key.deinit();
    _ = account_update.setKey(hedera.Key.fromPublicKey(new_key.getPublicKey()));
    
    _ = account_update.setMemo("Updated via schedule");
    
    // Create schedule
    var schedule = hedera.ScheduleCreateTransaction.init(allocator);
    defer schedule.deinit();
    
    _ = schedule.setScheduledTransaction(&account_update.base);
    _ = try schedule.setScheduleMemo("Scheduled account update");
    
    try testing.expect(schedule.scheduled_transaction != null);
    try testing.expectEqualStrings("Scheduled account update", schedule.memo.?);
}

test "Schedule expiration handling" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create transaction to schedule
    var transfer = hedera.TransferTransaction.init(allocator);
    defer transfer.deinit();
    
    const account1 = hedera.AccountId.init(0, 0, 800);
    const account2 = hedera.AccountId.init(0, 0, 900);
    
    _ = try transfer.addHbarTransfer(account1, try hedera.Hbar.from(-10));
    _ = try transfer.addHbarTransfer(account2, try hedera.Hbar.from(10));
    
    // Create schedule with short expiration
    var schedule = hedera.ScheduleCreateTransaction.init(allocator);
    defer schedule.deinit();
    
    _ = schedule.setScheduledTransaction(&transfer.base);
    
    // Set expiration time (1 hour from now)
    const now = hedera.Timestamp.now();
    const expiration = hedera.Timestamp{
        .seconds = now.seconds + 3600,
        .nanos = now.nanos,
    };
    _ = schedule.setExpirationTime(expiration);
    
    // Don't wait for expiry
    _ = schedule.setWaitForExpiry(false);
    
    try testing.expect(schedule.expiration_time != null);
    try testing.expect(!schedule.wait_for_expiry);
}

test "Schedule signature requirements" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create multi-sig transfer
    var transfer = hedera.TransferTransaction.init(allocator);
    defer transfer.deinit();
    
    const treasury = hedera.AccountId.init(0, 0, 98);
    const recipient = hedera.AccountId.init(0, 0, 1100);
    
    _ = try transfer.addHbarTransfer(treasury, try hedera.Hbar.from(-1000));
    _ = try transfer.addHbarTransfer(recipient, try hedera.Hbar.from(1000));
    
    // Create schedule
    var schedule = hedera.ScheduleCreateTransaction.init(allocator);
    defer schedule.deinit();
    
    _ = schedule.setScheduledTransaction(&transfer.base);
    _ = try schedule.setScheduleMemo("Multi-sig required");
    
    // Create threshold key for admin
    var key1 = try hedera.generatePrivateKey(allocator);
    defer key1.deinit();
    
    var key2 = try hedera.generatePrivateKey(allocator);
    defer key2.deinit();
    
    var key3 = try hedera.generatePrivateKey(allocator);
    defer key3.deinit();
    
    var threshold_key = hedera.KeyList.init(allocator);
    defer threshold_key.deinit();
    threshold_key.threshold = 2;
    
    try threshold_key.add(hedera.Key.fromPublicKey(key1.getPublicKey()));
    try threshold_key.add(hedera.Key.fromPublicKey(key2.getPublicKey()));
    try threshold_key.add(hedera.Key.fromPublicKey(key3.getPublicKey()));
    
    _ = schedule.setAdminKey(hedera.Key.fromKeyList(threshold_key));
    
    try testing.expect(schedule.admin_key != null);
    if (schedule.admin_key.? == .key_list) {
        try testing.expectEqual(@as(usize, 3), schedule.admin_key.?.key_list.keys.items.len);
        try testing.expectEqual(@as(?u32, 2), schedule.admin_key.?.key_list.threshold);
    }
}

test "Schedule memo limits" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var transfer = hedera.TransferTransaction.init(allocator);
    defer transfer.deinit();
    
    _ = try transfer.addHbarTransfer(hedera.AccountId.init(0, 0, 1), try hedera.Hbar.from(-1));
    _ = try transfer.addHbarTransfer(hedera.AccountId.init(0, 0, 2), try hedera.Hbar.from(1));
    
    var schedule = hedera.ScheduleCreateTransaction.init(allocator);
    defer schedule.deinit();
    
    _ = schedule.setScheduledTransaction(&transfer.base);
    
    // Valid memo (under 100 bytes)
    const valid_memo = "This is a valid schedule memo";
    _ = try schedule.setScheduleMemo(valid_memo);
    try testing.expectEqualStrings(valid_memo, schedule.memo.?);
    
    // Long memo (exactly 100 bytes)
    const long_memo = "a" ** 100;
    _ = try schedule.setScheduleMemo(long_memo);
    try testing.expectEqualStrings(long_memo, schedule.memo.?);
    
    // Too long memo would panic (removed test as setters use @panic not errors)
}

test "Schedule creation response" {
    // Mock schedule creation response
    const response = hedera.ScheduleCreateResponse{
        .schedule_id = hedera.ScheduleId.init(0, 0, 888),
        .transaction_id = hedera.TransactionId.generate(hedera.AccountId.init(0, 0, 1200)),
        .scheduled_transaction_id = hedera.TransactionId.generate(hedera.AccountId.init(0, 0, 1300)),
    };
    
    // Verify fields
    try testing.expectEqual(@as(u64, 888), response.schedule_id.num());
    try testing.expectEqual(@as(u64, 1200), response.transaction_id.account_id.account);
    try testing.expectEqual(@as(u64, 1300), response.scheduled_transaction_id.account_id.account);
}

test "Schedule ID parsing" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Test fromString
    const schedule_id = try hedera.ScheduleId.fromString(allocator, "0.0.999");
    try testing.expectEqual(@as(u64, 0), schedule_id.entity.shard);
    try testing.expectEqual(@as(u64, 0), schedule_id.entity.realm);
    try testing.expectEqual(@as(u64, 999), schedule_id.num());
    
    // Test toString
    const str = try schedule_id.toString(allocator);
    defer allocator.free(str);
    try testing.expectEqualStrings("0.0.999", str);
}


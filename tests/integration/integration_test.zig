const std = @import("std");
const testing = std.testing;
const hedera = @import("hedera");

// Integration tests that verify components work together
// These tests require a test network or mock network to be available

test "Client initialization and configuration" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Test forTestnet
    var client = try hedera.Client.forTestnet();
    defer client.deinit();
    
    try testing.expect(client.network == .Testnet);
    try testing.expectEqualStrings("testnet", client.ledger_id);
    
    // Test client_for_name (Go SDK compatible)
    var client2 = try hedera.clientForName("mainnet");
    defer client2.deinit();
    
    try testing.expect(client2.network == .Mainnet);
    
    // Test operator setting
    const operator_id = try hedera.accountIdFromString(allocator, "0.0.1001");
    var operator_key = try hedera.generatePrivateKey(allocator);
    defer operator_key.deinit();
    
    const op_key = try operator_key.toOperatorKey();
    _ = client.setOperator(operator_id, op_key);
    
    const retrieved_id = client.getOperatorAccountId();
    try testing.expect(retrieved_id != null);
    try testing.expectEqual(@as(u64, 1001), retrieved_id.?.num());
}

test "Transaction building and signing flow" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var client = try hedera.Client.forTestnet();
    defer client.deinit();
    
    // Set up operator
    const operator_id = try hedera.accountIdFromString(allocator, "0.0.1001");
    var operator_key = try hedera.generatePrivateKey(allocator);
    defer operator_key.deinit();
    
    const op_key = try operator_key.toOperatorKey();
    _ = client.setOperator(operator_id, op_key);
    
    // Create a transaction
    var tx = hedera.newAccountCreateTransaction(allocator);
    defer tx.deinit();
    
    // Test method chaining
    _ = tx.setKey(hedera.Key.fromPublicKey(operator_key.getPublicKey()));
    _ = tx.setInitialBalance(try hedera.Hbar.from(10));
    _ = tx.setReceiverSignatureRequired(false);
    _ = tx.setMaxAutomaticTokenAssociations(5);
    _ = tx.setAccountMemo("Integration test account");
    
    // Verify transaction can be frozen
    try tx.freezeWith(&client);
    try testing.expect(tx.base.frozen);
    
    // Verify transaction ID was generated
    const tx_id = try tx.base.getTransactionId();
    try testing.expectEqual(operator_id.num(), tx_id.account_id.num());
}

test "Query building and configuration" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create account balance query
    var balance_query = hedera.AccountBalanceQuery.init(allocator);
    defer balance_query.deinit();
    
    const account_id = try hedera.accountIdFromString(allocator, "0.0.98");
    _ = balance_query.setAccountId(account_id);
    
    // Verify query configuration
    try testing.expect(balance_query.account_id != null);
    try testing.expectEqual(@as(u64, 98), balance_query.account_id.?.num());
    
    // Test cost retrieval
    var client = try hedera.Client.forTestnet();
    defer client.deinit();
    
    const cost = try balance_query.getCost(&client);
    try testing.expect(cost.toTinybars() >= 0);
}

test "Transfer transaction with multiple transfers" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var transfer = hedera.TransferTransaction.init(allocator);
    defer transfer.deinit();
    
    const account1 = try hedera.accountIdFromString(allocator, "0.0.100");
    const account2 = try hedera.accountIdFromString(allocator, "0.0.200");
    const account3 = try hedera.accountIdFromString(allocator, "0.0.300");
    
    // Add HBAR transfers
    try transfer.addHbarTransfer(account1, try hedera.Hbar.from(-100));
    try transfer.addHbarTransfer(account2, try hedera.Hbar.from(60));
    try transfer.addHbarTransfer(account3, try hedera.Hbar.from(40));
    
    // Verify transfers were added
    try testing.expectEqual(@as(usize, 3), transfer.hbar_transfers.items.len);
    
    // Verify sum is zero (balanced)
    var sum: i64 = 0;
    for (transfer.hbar_transfers.items) |hbar_transfer| {
        sum += hbar_transfer.amount.toTinybars();
    }
    try testing.expectEqual(@as(i64, 0), sum);
    
    // Add token transfers
    const token_id = hedera.TokenId.init(0, 0, 500);
    try transfer.addTokenTransfer(token_id, account1, -1000);
    try transfer.addTokenTransfer(token_id, account2, 1000);
    
    // We expect 2 separate token transfer entries (one per account)
    try testing.expectEqual(@as(usize, 2), transfer.token_transfers.items.len);
    // Each transfer should be for the same token
    try testing.expect(transfer.token_transfers.items[0].token_id.equals(token_id));
    try testing.expect(transfer.token_transfers.items[1].token_id.equals(token_id));
}

test "Token operations flow" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create token
    var token_create = hedera.TokenCreateTransaction.init(allocator);
    defer token_create.deinit();
    
    _ = token_create.setTokenName("Test Token");
    _ = token_create.setTokenSymbol("TST");
    _ = token_create.setDecimals(2);
    _ = token_create.setInitialSupply(1000000);
    
    var admin_key = try hedera.generatePrivateKey(allocator);
    defer admin_key.deinit();
    
    _ = token_create.setAdminKey(hedera.Key.fromPublicKey(admin_key.getPublicKey()));
    _ = token_create.setSupplyKey(hedera.Key.fromPublicKey(admin_key.getPublicKey()));
    
    // Verify configuration
    try testing.expectEqualStrings("Test Token", token_create.name);
    try testing.expectEqualStrings("TST", token_create.symbol);
    try testing.expectEqual(@as(u32, 2), token_create.decimals);
    try testing.expectEqual(@as(u64, 1000000), token_create.initial_supply);
    
    // Token associate transaction
    var token_associate = hedera.TokenAssociateTransaction.init(allocator);
    defer token_associate.deinit();
    
    const account_id = try hedera.accountIdFromString(allocator, "0.0.1234");
    const token_id = hedera.TokenId.init(0, 0, 999);
    
    _ = token_associate.setAccountId(account_id);
    _ = token_associate.addTokenId(token_id);
    
    try testing.expectEqual(@as(usize, 1), token_associate.token_ids.items.len);
}

test "Smart contract operations" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Contract create
    var contract_create = hedera.ContractCreateTransaction.init(allocator);
    defer contract_create.deinit();
    
    const file_id = hedera.FileId.init(0, 0, 12345);
    _ = contract_create.setBytecodeFileId(file_id);
    _ = contract_create.setGas(100000);
    _ = contract_create.setInitialBalance(try hedera.Hbar.from(1));
    
    // Constructor parameters
    var params = hedera.ContractFunctionParameters.init(allocator);
    defer params.deinit();
    
    try params.addUint256(42);
    try params.addString("Hello");
    // Use 20-byte address (40 hex chars without 0x prefix)
    const address_bytes = [_]u8{0x12, 0x34, 0x56, 0x78, 0x90, 0x12, 0x34, 0x56, 0x78, 0x90, 0x12, 0x34, 0x56, 0x78, 0x90, 0x12, 0x34, 0x56, 0x78, 0x90};
    try params.addAddress(&address_bytes);
    
    const constructor_params = try params.toBytes();
    defer allocator.free(constructor_params);
    _ = contract_create.setConstructorParameters(constructor_params);
    
    // Verify configuration
    try testing.expect(contract_create.bytecode_file_id != null);
    try testing.expectEqual(@as(i64, 100000), contract_create.gas);
    
    // Contract execute
    var contract_execute = hedera.ContractExecuteTransaction.init(allocator);
    defer contract_execute.deinit();
    
    const contract_id = hedera.ContractId.init(0, 0, 5000);
    _ = contract_execute.setContractId(contract_id);
    _ = contract_execute.setGas(50000);
    _ = contract_execute.setPayableAmount(try hedera.Hbar.fromTinybars(50000000));
    
    // Contract query
    var contract_query = hedera.ContractCallQuery.init(allocator);
    defer contract_query.deinit();
    
    _ = contract_query.setContractId(contract_id);
    _ = contract_query.setGas(30000);
    _ = contract_query.setFunction("get", null);
}

test "Topic operations" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Topic create
    var topic_create = try hedera.TopicCreateTransaction.init(allocator);
    defer topic_create.deinit();
    
    _ = topic_create.setTopicMemo("Test Topic");
    
    var admin_key = try hedera.generatePrivateKey(allocator);
    defer admin_key.deinit();
    
    _ = topic_create.setAdminKey(hedera.Key.fromPublicKey(admin_key.getPublicKey()));
    _ = topic_create.setSubmitKey(hedera.Key.fromPublicKey(admin_key.getPublicKey()));
    
    // Topic message submit
    var message_submit = try hedera.TopicMessageSubmitTransaction.init(allocator);
    defer message_submit.deinit();
    
    const topic_id = hedera.TopicId.init(0, 0, 888);
    _ = message_submit.setTopicId(topic_id);
    _ = message_submit.setMessage("Hello from integration test!");
    
    try testing.expectEqualStrings("Hello from integration test!", message_submit.message);
}

test "Schedule operations" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create a transaction to schedule
    var transfer = hedera.TransferTransaction.init(allocator);
    defer transfer.deinit();
    
    const account1 = try hedera.accountIdFromString(allocator, "0.0.100");
    const account2 = try hedera.accountIdFromString(allocator, "0.0.200");
    
    try transfer.addHbarTransfer(account1, try hedera.Hbar.from(-10));
    try transfer.addHbarTransfer(account2, try hedera.Hbar.from(10));
    
    // Schedule the transaction
    var schedule_create = hedera.ScheduleCreateTransaction.init(allocator);
    defer schedule_create.deinit();
    
    _ = schedule_create.setScheduledTransaction(&transfer.base);
    _ = try schedule_create.setScheduleMemo("Scheduled transfer");
    _ = schedule_create.setPayerAccountId(account1);
    
    // Schedule sign
    var schedule_sign = hedera.ScheduleSignTransaction.init(allocator);
    defer schedule_sign.deinit();
    
    const schedule_id = hedera.ScheduleId.init(0, 0, 555);
    _ = schedule_sign.setScheduleId(schedule_id);
}
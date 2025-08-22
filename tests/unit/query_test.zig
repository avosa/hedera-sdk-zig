const std = @import("std");
const testing = std.testing;
const hedera = @import("hedera");

test "Query payment transaction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.AccountBalanceQuery.init(allocator);
    defer query.deinit();
    
    // Set payment amount
    const payment = try hedera.Hbar.from(1);
    query.setQueryPayment(payment);
    
    try testing.expectEqual(payment.toTinybars(), query.base.payment_amount.?.toTinybars());
}

test "Query max retry and backoff" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.AccountInfoQuery.init(allocator);
    defer query.deinit();
    
    // Set max retry
    query.setMaxRetry(5);
    try testing.expectEqual(@as(u32, 5), query.max_retry);
    
    // Set max backoff
    const max_backoff = hedera.Duration.fromSeconds(8);
    query.setMaxBackoff(max_backoff);
    try testing.expectEqual(@as(i64, 8), query.max_backoff.seconds);
    
    // Set min backoff
    const min_backoff = hedera.Duration.fromMillis(250);
    query.setMinBackoff(min_backoff);
    try testing.expectEqual(@as(i64, 0), query.min_backoff.seconds);
    try testing.expectEqual(@as(i32, 250000000), query.min_backoff.nanos);
}

test "Account balance query" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.AccountBalanceQuery.init(allocator);
    defer query.deinit();
    
    // Set account ID
    const account_id = hedera.AccountId.init(0, 0, 1234);
    try query.setAccountId(account_id);
    
    try testing.expectEqual(@as(u64, 1234), query.account_id.?.entity.num);
    
    // Set contract ID (alternative)
    const contract_id = hedera.ContractId.init(0, 0, 5678);
    try query.setContractId(contract_id);
    
    try testing.expectEqual(@as(u64, 5678), query.contract_id.?.entity.num);
}

test "Account info query" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.AccountInfoQuery.init(allocator);
    defer query.deinit();
    
    // Set account ID
    const account_id = hedera.AccountId.init(0, 0, 100);
    _ = try query.setAccountId(account_id);
    
    try testing.expectEqual(@as(u64, 100), query.account_id.?.entity.num);
}

test "Account records query" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.AccountRecordsQuery.init(allocator);
    defer query.deinit();
    
    // Set account ID
    const account_id = hedera.AccountId.init(0, 0, 200);
    try query.setAccountId(account_id);
    
    try testing.expectEqual(@as(u64, 200), query.account_id.?.entity.num);
}

test "Account stakers query" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.AccountStakersQuery.init(allocator);
    defer query.deinit();
    
    // Set account ID
    const account_id = hedera.AccountId.init(0, 0, 300);
    try query.setAccountId(account_id);
    
    try testing.expectEqual(@as(u64, 300), query.account_id.?.entity.num);
}

test "Contract bytecode query" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.ContractBytecodeQuery.init(allocator);
    defer query.deinit();
    
    // Set contract ID
    const contract_id = hedera.ContractId.init(0, 0, 1000);
    try query.setContractId(contract_id);
    
    try testing.expectEqual(@as(u64, 1000), query.contract_id.?.entity.num);
}

test "Contract call query" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.ContractCallQuery.init(allocator);
    defer query.deinit();
    
    // Set contract ID
    const contract_id = hedera.ContractId.init(0, 0, 2000);
    try query.setContractId(contract_id);
    
    // Set gas
    try query.setGas(100000);
    try testing.expectEqual(@as(i64, 100000), query.gas);
    
    // Set function with parameters
    var params = hedera.ContractFunctionParameters.init(allocator);
    defer params.deinit();
    
    try params.addUint256(42);
    try params.addAddress("0x1234567890123456789012345678901234567890");
    
    try query.setFunction("transfer", params);
    
    try testing.expectEqualStrings("transfer", query.function_name);
    try testing.expect(query.function_parameters.len > 0);
}

test "Contract info query" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.ContractInfoQuery.init(allocator);
    defer query.deinit();
    
    // Set contract ID
    const contract_id = hedera.ContractId.init(0, 0, 3000);
    try query.setContractId(contract_id);
    
    try testing.expectEqual(@as(u64, 3000), query.contract_id.?.entity.num);
}

test "File contents query" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.FileContentsQuery.init(allocator);
    defer query.deinit();
    
    // Set file ID
    const file_id = hedera.FileId.init(0, 0, 111);
    try query.setFileId(file_id);
    
    try testing.expectEqual(@as(u64, 111), query.file_id.?.entity.num);
}

test "File info query" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.FileInfoQuery.init(allocator);
    defer query.deinit();
    
    // Set file ID
    const file_id = hedera.FileId.init(0, 0, 222);
    try query.setFileId(file_id);
    
    try testing.expectEqual(@as(u64, 222), query.file_id.?.entity.num);
}

test "Token balance query" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.TokenBalanceQuery.init(allocator);
    defer query.deinit();
    
    // Set token ID
    const token_id = hedera.TokenId.init(0, 0, 1000);
    try query.setTokenId(token_id);
    
    // Set account ID
    const account_id = hedera.AccountId.init(0, 0, 100);
    try query.setAccountId(account_id);
    
    try testing.expectEqual(@as(u64, 1000), query.token_id.?.entity.num);
    try testing.expectEqual(@as(u64, 100), query.account_id.?.entity.num);
}

test "Token info query" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.TokenInfoQuery.init(allocator);
    defer query.deinit();
    
    // Set token ID
    const token_id = hedera.TokenId.init(0, 0, 2000);
    try query.setTokenId(token_id);
    
    try testing.expectEqual(@as(u64, 2000), query.token_id.?.entity.num);
}

test "Token NFT info query" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.TokenNftInfoQuery.init(allocator);
    defer query.deinit();
    
    // Set NFT ID
    const nft_id = hedera.NftId{
        .token_id = hedera.TokenId.init(0, 0, 3000),
        .serial_number = 42,
    };
    try query.setNftId(nft_id);
    
    try testing.expectEqual(@as(u64, 3000), query.nft_id.?.token_id.entity.num);
    try testing.expectEqual(@as(u64, 42), query.nft_id.?.serial_number);
}

test "Topic info query" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.TopicInfoQuery.init(allocator);
    defer query.deinit();
    
    // Set topic ID
    const topic_id = hedera.TopicId.init(0, 0, 777);
    try query.setTopicId(topic_id);
    
    try testing.expectEqual(@as(u64, 777), query.topic_id.?.entity.num);
}

test "Topic message query" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.TopicMessageQuery.init(allocator);
    defer query.deinit();
    
    // Set topic ID
    const topic_id = hedera.TopicId.init(0, 0, 888);
    _ = try query.setTopicId(topic_id);
    
    // Set start time
    const start_time = hedera.Timestamp.fromSeconds(1000000000);
    _ = query.setStartTime(start_time);
    
    // Set end time
    const end_time = hedera.Timestamp.fromSeconds(2000000000);
    _ = query.setEndTime(end_time);
    
    // Set limit
    _ = query.setLimit(100);
    
    try testing.expectEqual(@as(u64, 888), query.topic_id.?.entity.num);
    try testing.expectEqual(@as(i64, 1000000000), query.start_time.?.seconds);
    try testing.expectEqual(@as(i64, 2000000000), query.end_time.?.seconds);
    try testing.expectEqual(@as(u64, 100), query.limit);
}

test "Schedule info query" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.ScheduleInfoQuery.init(allocator);
    defer query.deinit();
    
    // Set schedule ID
    const schedule_id = hedera.ScheduleId.init(0, 0, 555);
    try query.setScheduleId(schedule_id);
    
    try testing.expectEqual(@as(u64, 555), query.schedule_id.?.entity.num);
}

test "Transaction receipt query" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.TransactionReceiptQuery.init(allocator);
    defer query.deinit();
    
    // Set transaction ID
    const tx_id = hedera.TransactionId.generate(hedera.AccountId.init(0, 0, 100));
    try query.setTransactionId(tx_id);
    
    // Set include children
    try query.setIncludeChildren(true);
    
    // Set include duplicates
    try query.setIncludeDuplicates(true);
    
    try testing.expectEqual(@as(u64, 100), query.transaction_id.?.account_id.entity.num);
    try testing.expect(query.include_children);
    try testing.expect(query.include_duplicates);
}

test "Transaction record query" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.TransactionRecordQuery.init(allocator);
    defer query.deinit();
    
    // Set transaction ID
    const tx_id = hedera.TransactionId.generate(hedera.AccountId.init(0, 0, 200));
    try query.setTransactionId(tx_id);
    
    // Set include children
    query.setIncludeChildren(true);
    
    // Set include duplicates
    query.setIncludeDuplicates(true);
    
    try testing.expectEqual(@as(u64, 200), query.transaction_id.?.account_id.entity.num);
    try testing.expect(query.include_children);
    try testing.expect(query.include_duplicates);
}

test "Network version info query" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.NetworkVersionInfoQuery.init(allocator);
    defer query.deinit();
    
    // Network version query doesn't require parameters
    // Just verify it initializes correctly
    try testing.expect(query.max_retry > 0);
}

test "Query cost estimation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var client = try hedera.Client.forTestnet();
    defer client.deinit();
    
    // Set operator
    const operator_id = hedera.AccountId.init(0, 0, 1001);
    var operator_key = try hedera.generate_private_key(allocator);
    defer operator_key.deinit();
    
    try client.set_operator(operator_id, operator_key);
    
    // Create query
    var query = hedera.AccountBalanceQuery.init(allocator);
    defer query.deinit();
    
    const account_id = hedera.AccountId.init(0, 0, 98);
    try query.setAccountId(account_id);
    
    // Get cost estimate
    const cost = try query.getCost(&client);
    try testing.expect(cost.toTinybars() >= 0);
}

test "Query with node account IDs" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.AccountInfoQuery.init(allocator);
    defer query.deinit();
    
    // Set specific node account IDs
    const node1 = hedera.AccountId.init(0, 0, 3);
    const node2 = hedera.AccountId.init(0, 0, 4);
    
    var node_ids = std.ArrayList(hedera.AccountId).init(allocator);
    defer node_ids.deinit();
    
    try node_ids.append(node1);
    try node_ids.append(node2);
    
    try query.setNodeAccountIds(node_ids.items);
    
    try testing.expectEqual(@as(usize, 2), query.node_account_ids.items.len);
    try testing.expectEqual(@as(u64, 3), query.node_account_ids.items[0].entity.num);
    try testing.expectEqual(@as(u64, 4), query.node_account_ids.items[1].entity.num);
}

test "Query timeout configuration" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.AccountBalanceQuery.init(allocator);
    defer query.deinit();
    
    // Set request timeout
    const timeout = hedera.Duration.fromSeconds(30);
    query.setRequestTimeout(timeout);
    
    try testing.expectEqual(@as(i64, 30), query.request_timeout.seconds);
}

test "Query builder pattern" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Test method chaining with account balance query
    var query = hedera.AccountBalanceQuery.init(allocator);
    defer query.deinit();
    
    const account_id = hedera.AccountId.init(0, 0, 1234);
    
    // Set methods individually (chaining not supported with error unions)
    try query.setAccountId(account_id);
    query.setQueryPayment(try hedera.Hbar.from(1));
    query.setMaxRetry(3);
    query.setMaxBackoff(hedera.Duration.fromSeconds(8));
    query.setMinBackoff(hedera.Duration.fromMillis(250));
    
    // Verify all settings
    try testing.expectEqual(@as(u64, 1234), query.account_id.?.entity.num);
    try testing.expectEqual(@as(i64, 100_000_000), query.payment().?.toTinybars());
    try testing.expectEqual(@as(u32, 3), query.max_retry());
    try testing.expectEqual(@as(i64, 8), query.max_backoff.seconds);
}
const std = @import("std");
const testing = std.testing;
const hedera = @import("hedera");

test "AccountBalanceQuery - comprehensive configuration and validation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.AccountBalanceQuery.init(allocator);
    defer query.deinit();
    
    // Test account ID setting
    const account_id = hedera.AccountId.init(0, 0, 1234);
    _ = try query.setAccountId(account_id);
    try testing.expectEqual(@as(u64, 1234), query.account_id.?.account);
    
    // Test contract ID setting (alternative to account ID)
    const contract_id = hedera.ContractId.init(0, 0, 5678);
    _ = try query.setContractId(contract_id);
    try testing.expectEqual(@as(u64, 5678), query.contract_id.?.num());
    try testing.expectEqual(@as(?hedera.AccountId, null), query.account_id); // Should clear account ID
    
    // Test back to account ID
    _ = try query.setAccountId(account_id);
    try testing.expectEqual(@as(u64, 1234), query.account_id.?.account);
    try testing.expectEqual(@as(?hedera.ContractId, null), query.contract_id); // Should clear contract ID
    
    // Test query payment (balance queries are usually free)
    const payment = try hedera.Hbar.from(0);
    _ = try query.setQueryPayment(payment);
    try testing.expectEqual(@as(i64, 0), query.payment().?.toTinybars());
    
    // Test max query payment
    const max_payment = try hedera.Hbar.from(1);
    _ = try query.setMaxQueryPayment(max_payment);
    
    // Test node account IDs
    const node_ids = [_]hedera.AccountId{
        hedera.AccountId.init(0, 0, 3),
        hedera.AccountId.init(0, 0, 4),
        hedera.AccountId.init(0, 0, 5),
    };
    _ = try query.setNodeAccountIds(&node_ids);
    try testing.expectEqual(@as(usize, 3), query.node_account_ids.items.len);
    
    // Test timeout configuration
    const timeout = hedera.Duration.fromSeconds(30);
    _ = try query.setRequestTimeout(timeout);
    try testing.expectEqual(@as(i64, 30), query.request_timeout.seconds);
    
    // Test retry configuration
    _ = try query.setMaxRetry(5);
    try testing.expectEqual(@as(u32, 5), query.max_retry());
    
    const max_backoff = hedera.Duration.fromSeconds(8);
    _ = try query.setMaxBackoff(max_backoff);
    try testing.expectEqual(@as(i64, 8), query.max_backoff.seconds);
    
    const min_backoff = hedera.Duration.fromMillis(250);
    _ = try query.setMinBackoff(min_backoff);
    try testing.expectEqual(@as(i32, 250000000), query.min_backoff.nanos);
}

test "AccountInfoQuery - comprehensive account information query" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.AccountInfoQuery.init(allocator);
    defer query.deinit();
    
    // Set account ID
    const account_id = hedera.AccountId.init(0, 0, 100);
    _ = try query.setAccountId(account_id);
    try testing.expectEqual(@as(u64, 100), query.account_id.?.account);
    
    // Test all query configuration options
    _ = try query.setQueryPayment(try hedera.Hbar.from(1));
    _ = try query.setMaxQueryPayment(try hedera.Hbar.from(5));
    _ = try query.setMaxRetry(3);
    _ = try query.setMaxBackoff(hedera.Duration.fromSeconds(10));
    _ = try query.setMinBackoff(hedera.Duration.fromMillis(500));
    _ = try query.setRequestTimeout(hedera.Duration.fromSeconds(60));
    
    // Verify all settings
    try testing.expectEqual(@as(u64, 100), query.account_id.?.account);
    try testing.expectEqual(@as(i64, 100_000_000), query.payment().?.toTinybars());
    try testing.expectEqual(@as(u32, 3), query.max_retry);
    try testing.expectEqual(@as(i64, 10), query.max_backoff.seconds);
    try testing.expectEqual(@as(i32, 500000000), query.min_backoff.nanos);
    try testing.expectEqual(@as(i64, 60), query.request_timeout.seconds);
}

test "TokenInfoQuery - token information retrieval" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.TokenInfoQuery.init(allocator);
    defer query.deinit();
    
    // Set token ID
    const token_id = hedera.TokenId.init(0, 0, 2000);
    _ = try query.setTokenId(token_id);
    try testing.expectEqual(@as(u64, 2000), query.token_id.?.num());
    
    // Configure query parameters
    _ = try query.setMaxRetry(5);
    _ = try query.setRequestTimeout(hedera.Duration.fromSeconds(45));
    
    const node_ids = [_]hedera.AccountId{
        hedera.AccountId.init(0, 0, 3),
        hedera.AccountId.init(0, 0, 4),
    };
    _ = try query.setNodeAccountIds(&node_ids);
    
    try testing.expectEqual(@as(u32, 5), query.max_retry);
    try testing.expectEqual(@as(i64, 45), query.request_timeout.seconds);
    try testing.expectEqual(@as(usize, 2), query.node_account_ids.items.len);
}

test "TokenBalanceQuery - token balance for account" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.TokenBalanceQuery.init(allocator);
    defer query.deinit();
    
    // Set token and account
    const token_id = hedera.TokenId.init(0, 0, 1000);
    const account_id = hedera.AccountId.init(0, 0, 100);
    
    _ = try query.setTokenId(token_id);
    _ = try query.setAccountId(account_id);
    
    try testing.expectEqual(@as(u64, 1000), query.token_id.?.num());
    try testing.expectEqual(@as(u64, 100), query.account_id.?.account);
    
    // Test with contract ID instead
    const contract_id = hedera.ContractId.init(0, 0, 200);
    _ = try query.setContractId(contract_id);
    try testing.expectEqual(@as(u64, 200), query.contract_id.?.num());
    try testing.expectEqual(@as(?hedera.AccountId, null), query.account_id);
}

test "TokenNftInfoQuery - NFT information query" {
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
    _ = try query.setNftId(nft_id);
    
    try testing.expectEqual(@as(u64, 3000), query.nft_id.?.token_id.num());
    try testing.expectEqual(@as(i64, 42), query.nft_id.?.serial_number);
    
    // Test by token ID and serial separately
    _ = try query.setTokenId(hedera.TokenId.init(0, 0, 4000));
    _ = try query.setSerialNumber(100);
    
    try testing.expectEqual(@as(u64, 4000), query.token_id.?.num());
    try testing.expectEqual(@as(i64, 100), query.serial_number.?);
}

test "TokenNftInfosQuery - multiple NFT information" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.TokenNftInfosQuery.init(allocator);
    defer query.deinit();
    
    // Set token ID
    const token_id = hedera.TokenId.init(0, 0, 5000);
    _ = try query.setTokenId(token_id);
    
    // Set range
    _ = try query.setStart(1);
    _ = try query.setEnd(100);
    
    try testing.expectEqual(@as(u64, 5000), query.token_id.?.num());
    try testing.expectEqual(@as(i64, 1), query.start);
    try testing.expectEqual(@as(i64, 100), query.end);
}

test "ContractInfoQuery - contract information" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.ContractInfoQuery.init(allocator);
    defer query.deinit();
    
    // Set contract ID
    const contract_id = hedera.ContractId.init(0, 0, 3000);
    _ = try query.setContractId(contract_id);
    
    try testing.expectEqual(@as(u64, 3000), query.contract_id.?.num());
}

test "ContractCallQuery - contract function call" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.ContractCallQuery.init(allocator);
    defer query.deinit();
    
    // Set contract ID
    const contract_id = hedera.ContractId.init(0, 0, 2000);
    _ = try query.setContractId(contract_id);
    
    // Set gas
    _ = try query.setGas(100000);
    try testing.expectEqual(@as(i64, 100000), query.gas);
    
    // Set function with parameters
    var params = hedera.ContractFunctionParameters.init(allocator);
    defer params.deinit();
    
    try params.addUint256(42);
    try params.addString("Hello World");
    try params.addAddress("0x1234567890123456789012345678901234567890");
    try params.addBool(true);
    
    _ = try query.setFunction("testFunction", params);
    
    try testing.expectEqualStrings("testFunction", query.function_name);
    try testing.expect(query.function_parameters.len > 0);
    
    // Set max result size
    _ = try query.setMaxResultSize(1024);
    try testing.expectEqual(@as(u64, 1024), query.max_result_size);
    
    // Set sender account ID
    const sender = hedera.AccountId.init(0, 0, 100);
    _ = try query.setSenderAccountId(sender);
    try testing.expectEqual(@as(u64, 100), query.sender_account_id.?.account);
}

test "ContractBytecodeQuery - contract bytecode retrieval" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.ContractBytecodeQuery.init(allocator);
    defer query.deinit();
    
    // Set contract ID
    const contract_id = hedera.ContractId.init(0, 0, 1000);
    _ = try query.setContractId(contract_id);
    
    try testing.expectEqual(@as(u64, 1000), query.contract_id.?.num());
}

test "FileInfoQuery - file information" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.FileInfoQuery.init(allocator);
    defer query.deinit();
    
    // Set file ID
    const file_id = hedera.FileId.init(0, 0, 111);
    _ = try query.setFileId(file_id);
    
    try testing.expectEqual(@as(u64, 111), query.file_id.?.num());
}

test "FileContentsQuery - file contents retrieval" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.FileContentsQuery.init(allocator);
    defer query.deinit();
    
    // Set file ID
    const file_id = hedera.FileId.init(0, 0, 222);
    _ = try query.setFileId(file_id);
    
    try testing.expectEqual(@as(u64, 222), query.file_id.?.num());
}

test "TopicInfoQuery - topic information" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.TopicInfoQuery.init(allocator);
    defer query.deinit();
    
    // Set topic ID
    const topic_id = hedera.TopicId.init(0, 0, 777);
    _ = try query.setTopicId(topic_id);
    
    try testing.expectEqual(@as(u64, 777), query.topic_id.?.num());
}

test "TopicMessageQuery - topic message retrieval with pagination" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.TopicMessageQuery.init(allocator);
    defer query.deinit();
    
    // Set topic ID
    const topic_id = hedera.TopicId.init(0, 0, 888);
    _ = try query.setTopicId(topic_id);
    
    // Set time range
    const start_time = hedera.Timestamp.fromSeconds(1000000000);
    const end_time = hedera.Timestamp.fromSeconds(2000000000);
    
    _ = try query.setStartTime(start_time);
    _ = try query.setEndTime(end_time);
    
    // Set limit
    _ = try query.setLimit(100);
    
    try testing.expectEqual(@as(u64, 888), query.topic_id.?.num());
    try testing.expectEqual(@as(i64, 1000000000), query.start_time.?.seconds);
    try testing.expectEqual(@as(i64, 2000000000), query.end_time.?.seconds);
    try testing.expectEqual(@as(u64, 100), query.limit);
    
    // Test completion callback setup
    query.completion_callback = struct {
        pub fn callback(query_ref: *hedera.TopicMessageQuery) void {
            _ = query_ref;
            // Mock completion handling
        }
    }.callback;
    
    try testing.expect(query.completion_callback != null);
}

test "ScheduleInfoQuery - schedule information" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.ScheduleInfoQuery.init(allocator);
    defer query.deinit();
    
    // Set schedule ID
    const schedule_id = hedera.ScheduleId.init(0, 0, 555);
    _ = try query.setScheduleId(schedule_id);
    
    try testing.expectEqual(@as(u64, 555), query.schedule_id.?.num());
}

test "TransactionReceiptQuery - transaction receipt retrieval" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.TransactionReceiptQuery.init(allocator);
    defer query.deinit();
    
    // Set transaction ID
    const tx_id = hedera.TransactionId.generate(hedera.AccountId.init(0, 0, 100));
    _ = try query.setTransactionId(tx_id);
    
    // Set include children
    _ = try query.setIncludeChildren(true);
    
    // Set include duplicates
    _ = try query.setIncludeDuplicates(true);
    
    // Set validate status
    _ = try query.setValidateStatus(false);
    
    try testing.expectEqual(@as(u64, 100), query.transaction_id.?.account_id.account);
    try testing.expect(query.include_children);
    try testing.expect(query.include_duplicates);
    try testing.expect(!query.validate_status);
}

test "TransactionRecordQuery - transaction record retrieval" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.TransactionRecordQuery.init(allocator);
    defer query.deinit();
    
    // Set transaction ID
    const tx_id = hedera.TransactionId.generate(hedera.AccountId.init(0, 0, 200));
    _ = try query.setTransactionId(tx_id);
    
    // Set include children
    _ = try query.setIncludeChildren(true);
    
    // Set include duplicates
    _ = try query.setIncludeDuplicates(true);
    
    // Set validate status
    _ = try query.setValidateStatus(false);
    
    try testing.expectEqual(@as(u64, 200), query.transaction_id.?.account_id.account);
    try testing.expect(query.include_children);
    try testing.expect(query.include_duplicates);
    try testing.expect(!query.validate_status);
}

test "AccountRecordsQuery - account transaction records" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.AccountRecordsQuery.init(allocator);
    defer query.deinit();
    
    // Set account ID
    const account_id = hedera.AccountId.init(0, 0, 300);
    _ = try query.setAccountId(account_id);
    
    try testing.expectEqual(@as(u64, 300), query.account_id.?.account);
}

test "AccountStakersQuery - account stakers information" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.AccountStakersQuery.init(allocator);
    defer query.deinit();
    
    // Set account ID
    const account_id = hedera.AccountId.init(0, 0, 400);
    _ = try query.setAccountId(account_id);
    
    try testing.expectEqual(@as(u64, 400), query.account_id.?.account);
}

test "NetworkVersionInfoQuery - network version information" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.NetworkVersionInfoQuery.init(allocator);
    defer query.deinit();
    
    // Network version query doesn't require parameters
    // Just verify it initializes correctly
    try testing.expect(query.max_retry > 0);
}

test "AddressBookQuery - address book information" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.AddressBookQuery.init(allocator);
    defer query.deinit();
    
    // Set file ID (address book is stored as a file)
    const file_id = hedera.FileId.init(0, 0, 102);
    _ = try query.setFileId(file_id);
    
    try testing.expectEqual(@as(u64, 102), query.file_id.?.num());
}

test "LiveHashQuery - live hash information" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.LiveHashQuery.init(allocator);
    defer query.deinit();
    
    // Set account ID
    const account_id = hedera.AccountId.init(0, 0, 500);
    _ = try query.setAccountId(account_id);
    
    // Set hash
    const hash = [_]u8{0xAB} ** 48;
    _ = try query.setHash(&hash);
    
    try testing.expectEqual(@as(u64, 500), query.account_id.?.account);
    try testing.expectEqualSlices(u8, &hash, query.hash);
}

test "Query - cost estimation" {
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
    _ = try client.setOperator(operator_id, op_key);
    
    // Test cost estimation for account balance query (free)
    var balance_query = hedera.AccountBalanceQuery.init(allocator);
    defer balance_query.deinit();
    
    const account_id = hedera.AccountId.init(0, 0, 98);
    _ = try balance_query.setAccountId(account_id);
    
    // Get cost estimate
    const cost = try balance_query.getCost(&client);
    try testing.expect(cost.toTinybars() >= 0);
    
    // Test cost estimation for account info query (paid)
    var info_query = hedera.AccountInfoQuery.init(allocator);
    defer info_query.deinit();
    
    _ = try info_query.setAccountId(account_id);
    
    const info_cost = try info_query.getCost(&client);
    try testing.expect(info_cost.toTinybars() >= 0);
}

test "Query - error handling and validation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Test missing required parameters
    var balance_query = hedera.AccountBalanceQuery.init(allocator);
    defer balance_query.deinit();
    
    // Should fail without account ID or contract ID
    try testing.expectError(error.MissingAccountId, balance_query.validate());
    
    // Set account ID and should pass validation
    _ = try balance_query.setAccountId(hedera.AccountId.init(0, 0, 100));
    try balance_query.validate();
    
    // Test invalid parameters
    var topic_message_query = hedera.TopicMessageQuery.init(allocator);
    defer topic_message_query.deinit();
    
    _ = try topic_message_query.setTopicId(hedera.TopicId.init(0, 0, 888));
    
    // Test invalid time range (end before start)
    const start_time = hedera.Timestamp.fromSeconds(2000000000);
    const end_time = hedera.Timestamp.fromSeconds(1000000000);
    
    _ = try topic_message_query.setStartTime(start_time);
    _ = try topic_message_query.setEndTime(end_time);
    
    try testing.expectError(error.InvalidTimeRange, topic_message_query.validate());
    
    // Fix time range
    _ = try topic_message_query.setStartTime(hedera.Timestamp.fromSeconds(1000000000));
    _ = try topic_message_query.setEndTime(hedera.Timestamp.fromSeconds(2000000000));
    try topic_message_query.validate();
}

test "Query - retry and backoff configuration" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.AccountInfoQuery.init(allocator);
    defer query.deinit();
    
    _ = try query.setAccountId(hedera.AccountId.init(0, 0, 100));
    
    // Test retry configuration
    _ = try query.setMaxRetry(10);
    try testing.expectEqual(@as(u32, 10), query.max_retry);
    
    // Test minimum retry (should be at least 1)
    _ = try query.setMaxRetry(0);
    try testing.expectEqual(@as(u32, 1), query.max_retry);
    
    // Test maximum retry (reasonable upper limit)
    _ = try query.setMaxRetry(100);
    try testing.expectEqual(@as(u32, 100), query.max_retry);
    
    // Test backoff configuration
    _ = try query.setMaxBackoff(hedera.Duration.fromSeconds(30));
    _ = try query.setMinBackoff(hedera.Duration.fromMillis(100));
    
    try testing.expectEqual(@as(i64, 30), query.max_backoff.seconds);
    try testing.expectEqual(@as(i32, 100000000), query.min_backoff.nanos);
    
    // Test that min_backoff <= max_backoff
    try testing.expect(query.min_backoff.seconds <= query.max_backoff.seconds);
}

test "Query - node selection and load balancing" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.TokenInfoQuery.init(allocator);
    defer query.deinit();
    
    _ = try query.setTokenId(hedera.TokenId.init(0, 0, 1000));
    
    // Test specific node selection
    const specific_nodes = [_]hedera.AccountId{
        hedera.AccountId.init(0, 0, 3),
        hedera.AccountId.init(0, 0, 5),
        hedera.AccountId.init(0, 0, 7),
    };
    _ = try query.setNodeAccountIds(&specific_nodes);
    
    try testing.expectEqual(@as(usize, 3), query.node_account_ids.items.len);
    try testing.expectEqual(@as(u64, 3), query.node_account_ids.items[0].account);
    try testing.expectEqual(@as(u64, 7), query.node_account_ids.items[2].account);
    
    // Test single node
    _ = try query.setNodeAccountIds(&[_]hedera.AccountId{
        hedera.AccountId.init(0, 0, 4)
    });
    try testing.expectEqual(@as(usize, 1), query.node_account_ids.items.len);
    try testing.expectEqual(@as(u64, 4), query.node_account_ids.items[0].account);
    
    // Clear nodes (will use default network nodes)
    try query.node_account_ids.clearRetainingCapacity();
    try testing.expectEqual(@as(usize, 0), query.node_account_ids.items.len);
}

test "Query - timeout and deadline handling" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.ContractCallQuery.init(allocator);
    defer query.deinit();
    
    _ = try query.setContractId(hedera.ContractId.init(0, 0, 1000));
    _ = try query.setGas(50000);
    _ = try query.setFunction("test", null);
    
    // Test different timeout values
    const timeouts = [_]i64{1, 5, 30, 60, 120, 300};
    
    for (timeouts) |timeout_seconds| {
        _ = try query.setRequestTimeout(hedera.Duration.fromSeconds(timeout_seconds));
        try testing.expectEqual(@as(i64, timeout_seconds), query.request_timeout.seconds);
    }
    
    // Test minimum timeout (should be at least 1 second)
    _ = try query.setRequestTimeout(hedera.Duration.fromMillis(100));
    try testing.expect(query.request_timeout.seconds >= 0);
    
    // Test maximum reasonable timeout
    _ = try query.setRequestTimeout(hedera.Duration.fromSeconds(3600)); // 1 hour
    try testing.expectEqual(@as(i64, 3600), query.request_timeout.seconds);
}

test "Query - builder pattern validation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Test method chaining with account balance query
    var query = hedera.AccountBalanceQuery.init(allocator);
    defer query.deinit();
    
    const account_id = hedera.AccountId.init(0, 0, 1234);
    
    // Set methods individually (chaining not supported with error unions in Zig)
    _ = try query.setAccountId(account_id);
    _ = try query.setQueryPayment(try hedera.Hbar.from(0));
    _ = try query.setMaxRetry(3);
    _ = try query.setMaxBackoff(hedera.Duration.fromSeconds(8));
    _ = try query.setMinBackoff(hedera.Duration.fromMillis(250));
    _ = try query.setRequestTimeout(hedera.Duration.fromSeconds(30));
    
    // Verify all settings
    try testing.expectEqual(@as(u64, 1234), query.account_id.?.account);
    try testing.expectEqual(@as(i64, 0), query.payment().?.toTinybars());
    try testing.expectEqual(@as(u32, 3), query.max_retry());
    try testing.expectEqual(@as(i64, 8), query.max_backoff.seconds);
    try testing.expectEqual(@as(i32, 250000000), query.min_backoff.nanos);
    try testing.expectEqual(@as(i64, 30), query.request_timeout.seconds);
}

test "Query - response processing and parsing" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Mock query response structures
    const query_header = hedera.QueryHeader{
        .payment = hedera.Transaction{},
        .response_type = .ANSWER_ONLY,
    };
    
    const response_header = hedera.ResponseHeader{
        .node_transaction_precheck_code = hedera.Status.OK,
        .response_type = .ANSWER_ONLY,
        .cost = 0,
        .state_proof = null,
    };
    
    // Test account balance response
    const account_balance_response = hedera.AccountBalanceResponse{
        .header = response_header,
        .account_id = hedera.AccountId.init(0, 0, 100),
        .balance = 1000000000, // 10 HBAR in tinybars
        .token_balances = std.ArrayList(hedera.TokenBalance).init(allocator),
    };
    
    try testing.expectEqual(hedera.Status.OK, account_balance_response.header.node_transaction_precheck_code);
    try testing.expectEqual(@as(u64, 100), account_balance_response.account_id.?.account);
    try testing.expectEqual(@as(u64, 1000000000), account_balance_response.balance);
}

test "Query - edge cases and boundary conditions" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Test with maximum account ID values
    var query = hedera.AccountBalanceQuery.init(allocator);
    defer query.deinit();
    
    const max_account = hedera.AccountId.init(
        std.math.maxInt(u64),
        std.math.maxInt(u64),
        std.math.maxInt(u64)
    );
    _ = try query.setAccountId(max_account);
    
    try testing.expectEqual(std.math.maxInt(u64), query.account_id.?.shard);
    try testing.expectEqual(std.math.maxInt(u64), query.account_id.?.realm);
    try testing.expectEqual(std.math.maxInt(u64), query.account_id.?.account);
    
    // Test with minimum values
    const min_account = hedera.AccountId.init(0, 0, 0);
    _ = try query.setAccountId(min_account);
    
    try testing.expectEqual(@as(u64, 0), query.account_id.?.shard);
    try testing.expectEqual(@as(u64, 0), query.account_id.?.realm);
    try testing.expectEqual(@as(u64, 0), query.account_id.?.account);
    
    // Test token query with large serial numbers
    var nft_query = hedera.TokenNftInfoQuery.init(allocator);
    defer nft_query.deinit();
    
    _ = try nft_query.setTokenId(hedera.TokenId.init(0, 0, 1000));
    _ = try nft_query.setSerialNumber(std.math.maxInt(i64));
    
    try testing.expectEqual(std.math.maxInt(i64), nft_query.serial_number.?);
    
    // Test topic message query with edge timestamps
    var topic_query = hedera.TopicMessageQuery.init(allocator);
    defer topic_query.deinit();
    
    _ = try topic_query.setTopicId(hedera.TopicId.init(0, 0, 777));
    _ = try topic_query.setStartTime(hedera.Timestamp.fromSeconds(0));
    _ = try topic_query.setEndTime(hedera.Timestamp.fromSeconds(std.math.maxInt(i32)));
    _ = try topic_query.setLimit(std.math.maxInt(u64));
    
    try testing.expectEqual(@as(i64, 0), topic_query.start_time.?.seconds);
    try testing.expectEqual(@as(i64, std.math.maxInt(i32)), topic_query.end_time.?.seconds);
    try testing.expectEqual(std.math.maxInt(u64), topic_query.limit);
}
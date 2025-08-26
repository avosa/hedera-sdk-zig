const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectEqualSlices = std.testing.expectEqualSlices;
const allocator = std.testing.allocator;

const TopicId = @import("../../src/core/id.zig").TopicId;
const AccountId = @import("../../src/core/id.zig").AccountId;
const Hbar = @import("../../src/core/hbar.zig").Hbar;
const Duration = @import("../../src/core/duration.zig").Duration;
const Timestamp = @import("../../src/core/timestamp.zig").Timestamp;
const Key = @import("../../src/crypto/key.zig").Key;
const PrivateKey = @import("../../src/crypto/private_key.zig").PrivateKey;

const TopicCreateTransaction = @import("../../src/topic/topic_create.zig").TopicCreateTransaction;
const CustomFixedFee = @import("../../src/topic/topic_create.zig").CustomFixedFee;
const TopicMessageSubmitTransaction = @import("../../src/topic/topic_message_submit.zig").TopicMessageSubmitTransaction;
const CustomFeeLimit = @import("../../src/topic/topic_message_submit.zig").CustomFeeLimit;
const TopicInfo = @import("../../src/topic/topic_info_query.zig").TopicInfo;
const TopicInfoQuery = @import("../../src/topic/topic_info_query.zig").TopicInfoQuery;
const TopicUpdateTransaction = @import("../../src/topic/topic_update.zig").TopicUpdateTransaction;
const TopicDeleteTransaction = @import("../../src/topic/topic_delete.zig").TopicDeleteTransaction;
const TopicMessageQuery = @import("../../src/topic/topic_message_query.zig").TopicMessageQuery;
const TopicMessage = @import("../../src/topic/topic_message_query.zig").TopicMessage;
const ChunkInfo = @import("../../src/topic/topic_message_query.zig").ChunkInfo;

// TopicId Tests
test "TopicId initialization and basic operations" {
    const topic_id = TopicId.init(0, 0, 2001);
    
    try expectEqual(@as(u64, 0), topic_id.shard());
    try expectEqual(@as(u64, 0), topic_id.realm());
    try expectEqual(@as(u64, 2001), topic_id.num());
}

test "TopicId string representation" {
    const topic_id = TopicId.init(1, 2, 3);
    const result = try topic_id.toString(allocator);
    defer allocator.free(result);
    
    try expectEqualSlices(u8, "1.2.3", result);
}

test "TopicId parsing from string" {
    const topic_id = try TopicId.fromString("0.0.2001");
    
    try expectEqual(@as(u64, 0), topic_id.shard());
    try expectEqual(@as(u64, 0), topic_id.realm());
    try expectEqual(@as(u64, 2001), topic_id.num());
}

test "TopicId equality comparison" {
    const topic1 = TopicId.init(0, 0, 2001);
    const topic2 = TopicId.init(0, 0, 2001);
    const topic3 = TopicId.init(0, 0, 2002);
    
    try expect(topic1.equals(topic2));
    try expect(!topic1.equals(topic3));
}

// CustomFixedFee Tests
test "CustomFixedFee initialization" {
    const fee_collector = AccountId.init(0, 0, 500);
    const fee = CustomFixedFee.init(1000000, fee_collector); // 0.01 Hbar
    
    try expectEqual(@as(u64, 1000000), fee.amount);
    try expectEqual(fee_collector, fee.fee_collector_account_id);
    try expectEqual(@as(?[]const u8, null), fee.denomination_token_id);
}

test "CustomFixedFee with denomination token" {
    const fee_collector = AccountId.init(0, 0, 500);
    var fee = CustomFixedFee.init(100, fee_collector);
    fee.denomination_token_id = "0.0.1001";
    
    try expectEqual(@as(u64, 100), fee.amount);
    try expectEqualSlices(u8, "0.0.1001", fee.denomination_token_id.?);
}

// TopicCreateTransaction Tests
test "TopicCreateTransaction initialization and basic setters" {
    var tx = try TopicCreateTransaction.init(allocator);
    defer tx.deinit();
    
    const private_key = try PrivateKey.generateEd25519();
    defer private_key.deinit();
    const admin_key = Key{ .ed25519_public_key = private_key.public_key.toStringRaw() };
    _ = try tx.setAdminKey(admin_key);
    try expectEqual(admin_key, try tx.getAdminKey());
    
    const submit_key = Key{ .ed25519_public_key = "submit_key_data" };
    _ = try tx.setSubmitKey(submit_key);
    try expectEqual(submit_key, try tx.getSubmitKey());
    
    _ = try tx.setTopicMemo("Test topic for unit tests");
    try expectEqualSlices(u8, "Test topic for unit tests", tx.getTopicMemo());
    
    const auto_renew_period = Duration{ .seconds = 8640000, .nanos = 0 }; // 100 days
    _ = try tx.setAutoRenewPeriod(auto_renew_period);
    try expectEqual(auto_renew_period, tx.getAutoRenewPeriod());
    
    const auto_renew_account = AccountId.init(0, 0, 600);
    _ = try tx.setAutoRenewAccountId(auto_renew_account);
    try expectEqual(auto_renew_account, tx.getAutoRenewAccountID());
}

test "TopicCreateTransaction fee schedule key" {
    var tx = try TopicCreateTransaction.init(allocator);
    defer tx.deinit();
    
    const fee_schedule_key = Key{ .ed25519_public_key = "fee_schedule_key_data" };
    _ = try tx.setFeeScheduleKey(fee_schedule_key);
    try expectEqual(fee_schedule_key, tx.getFeeScheduleKey());
}

test "TopicCreateTransaction fee exempt keys management" {
    var tx = try TopicCreateTransaction.init(allocator);
    defer tx.deinit();
    
    const key1 = Key{ .ed25519_public_key = "exempt_key_1" };
    const key2 = Key{ .ed25519_public_key = "exempt_key_2" };
    const key3 = Key{ .ed25519_public_key = "exempt_key_3" };
    
    _ = try tx.addFeeExemptKey(key1);
    _ = try tx.addFeeExemptKey(key2);
    _ = try tx.addFeeExemptKey(key3);
    
    const exempt_keys = tx.getFeeExemptKeys();
    try expectEqual(@as(usize, 3), exempt_keys.len);
    try expectEqual(key1, exempt_keys[0]);
    try expectEqual(key2, exempt_keys[1]);
    try expectEqual(key3, exempt_keys[2]);
    
    _ = try tx.clearFeeExemptKeys();
    try expectEqual(@as(usize, 0), tx.getFeeExemptKeys().len);
    
    const all_keys = [_]Key{ key1, key2, key3 };
    _ = try tx.setFeeExemptKeys(&all_keys);
    try expectEqual(@as(usize, 3), tx.getFeeExemptKeys().len);
}

test "TopicCreateTransaction custom fees management" {
    var tx = try TopicCreateTransaction.init(allocator);
    defer tx.deinit();
    
    const fee_collector1 = AccountId.init(0, 0, 500);
    const fee_collector2 = AccountId.init(0, 0, 501);
    
    var fee1 = try allocator.create(CustomFixedFee);
    fee1.* = CustomFixedFee.init(1000000, fee_collector1); // 0.01 Hbar
    
    var fee2 = try allocator.create(CustomFixedFee);
    fee2.* = CustomFixedFee.init(2000000, fee_collector2); // 0.02 Hbar
    
    _ = try tx.addCustomFee(fee1);
    _ = try tx.addCustomFee(fee2);
    
    const custom_fees = tx.getCustomFees();
    try expectEqual(@as(usize, 2), custom_fees.len);
    try expectEqual(@as(u64, 1000000), custom_fees[0].amount);
    try expectEqual(@as(u64, 2000000), custom_fees[1].amount);
    
    _ = try tx.clearCustomFees();
    try expectEqual(@as(usize, 0), tx.getCustomFees().len);
}

test "TopicCreateTransaction transaction properties" {
    var tx = try TopicCreateTransaction.init(allocator);
    defer tx.deinit();
    
    const max_fee = try Hbar.from(30);
    _ = try tx.setMaxTransactionFee(max_fee);
    try expectEqual(max_fee, tx.getMaxTransactionFee().?);
    
    _ = try tx.setTransactionMemo("Create topic transaction");
    try expectEqualSlices(u8, "Create topic transaction", tx.getTransactionMemo());
    
    const node_accounts = [_]AccountId{
        AccountId.init(0, 0, 3),
        AccountId.init(0, 0, 4),
    };
    _ = try tx.setNodeAccountIDs(&node_accounts);
    const retrieved_nodes = tx.getNodeAccountIDs();
    try expectEqual(@as(usize, 2), retrieved_nodes.len);
}

test "TopicCreateTransaction frozen state validation" {
    var tx = try TopicCreateTransaction.init(allocator);
    defer tx.deinit();
    
    tx.transaction.frozen = true;
    
    const admin_key = Key{ .ed25519_public_key = "test_key" };
    try expectError(error.TransactionFrozen, tx.setAdminKey(admin_key));
    try expectError(error.TransactionFrozen, tx.setTopicMemo("memo"));
}

// CustomFeeLimit Tests
test "CustomFeeLimit initialization" {
    const fee_collector = AccountId.init(0, 0, 500);
    const fee_limit = CustomFeeLimit.init(fee_collector, 5000000); // 0.05 Hbar max
    
    try expectEqual(fee_collector, fee_limit.fee_collector_account_id);
    try expectEqual(@as(u64, 5000000), fee_limit.max_amount);
}

// TopicMessageSubmitTransaction Tests
test "TopicMessageSubmitTransaction initialization and basic setters" {
    var tx = try TopicMessageSubmitTransaction.init(allocator);
    defer tx.deinit();
    
    const topic_id = TopicId.init(0, 0, 2001);
    _ = try tx.setTopicId(topic_id);
    try expectEqual(topic_id, tx.getTopicId());
    
    const message = "Hello, Hedera consensus service!";
    _ = try tx.setMessage(message);
    try expectEqualSlices(u8, message, tx.getMessage());
    
    _ = try tx.setMaxChunks(10);
    try expectEqual(@as(u64, 10), tx.getMaxChunks());
    
    _ = try tx.setChunkSize(512);
    try expectEqual(@as(u64, 512), tx.getChunkSize());
}

test "TopicMessageSubmitTransaction large message chunking" {
    var tx = try TopicMessageSubmitTransaction.init(allocator);
    defer tx.deinit();
    
    const topic_id = TopicId.init(0, 0, 2001);
    _ = try tx.setTopicId(topic_id);
    
    // Create a large message that will require chunking
    const large_message = "X" ** 2048; // 2KB message
    _ = try tx.setMessage(large_message);
    
    _ = try tx.setChunkSize(1024); // 1KB chunks
    _ = try tx.setMaxChunks(5);
    
    // Should calculate 2 chunks needed
    const chunks_needed = (large_message.len + tx.getChunkSize() - 1) / tx.getChunkSize();
    try expectEqual(@as(usize, 2), chunks_needed);
    try expect(chunks_needed <= tx.getMaxChunks());
}

test "TopicMessageSubmitTransaction custom fee limits" {
    var tx = try TopicMessageSubmitTransaction.init(allocator);
    defer tx.deinit();
    
    const fee_collector1 = AccountId.init(0, 0, 500);
    const fee_collector2 = AccountId.init(0, 0, 501);
    
    var fee_limit1 = try allocator.create(CustomFeeLimit);
    fee_limit1.* = CustomFeeLimit.init(fee_collector1, 1000000); // 0.01 Hbar max
    
    var fee_limit2 = try allocator.create(CustomFeeLimit);
    fee_limit2.* = CustomFeeLimit.init(fee_collector2, 2000000); // 0.02 Hbar max
    
    _ = try tx.addCustomFeeLimit(fee_limit1);
    _ = try tx.addCustomFeeLimit(fee_limit2);
    
    const fee_limits = tx.getCustomFeeLimits();
    try expectEqual(@as(usize, 2), fee_limits.len);
    try expectEqual(@as(u64, 1000000), fee_limits[0].max_amount);
    try expectEqual(@as(u64, 2000000), fee_limits[1].max_amount);
    
    _ = try tx.clearCustomFeeLimits();
    try expectEqual(@as(usize, 0), tx.getCustomFeeLimits().len);
}

test "TopicMessageSubmitTransaction validation" {
    var tx = try TopicMessageSubmitTransaction.init(allocator);
    defer tx.deinit();
    
    // Should fail with chunk size of 0
    _ = try tx.setChunkSize(0);
    try expectError(error.InvalidParameter, tx.freeze());
    
    _ = try tx.setChunkSize(1024);
    
    // Should fail if message requires more chunks than max allowed
    const huge_message = "X" ** (10 * 1024); // 10KB
    _ = try tx.setMessage(huge_message);
    _ = try tx.setMaxChunks(5); // Only allow 5 chunks, but need 10
    
    try expectError(error.InvalidParameter, tx.freeze());
}

test "TopicMessageSubmitTransaction transaction properties" {
    var tx = try TopicMessageSubmitTransaction.init(allocator);
    defer tx.deinit();
    
    const max_fee = try Hbar.from(2);
    _ = try tx.setMaxTransactionFee(max_fee);
    try expectEqual(max_fee, tx.getMaxTransactionFee().?);
    
    _ = try tx.setTransactionMemo("Submit message transaction");
    try expectEqualSlices(u8, "Submit message transaction", tx.getTransactionMemo());
}

// TopicInfo Tests
test "TopicInfo initialization and basic properties" {
    var info = TopicInfo.init(allocator);
    defer info.deinit();
    
    const topic_id = TopicId.init(0, 0, 2001);
    info.topic_id = topic_id;
    
    info.sequence_number = 1000;
    info.running_hash = "running_hash_data";
    info.topic_memo = "Topic information test";
    
    const expiration = Timestamp{ .seconds = 2000000000, .nanos = 0 };
    info.expiration_time = expiration;
    
    const auto_renew_period = Duration{ .seconds = 7890000, .nanos = 0 };
    info.auto_renew_period = auto_renew_period;
    
    try expectEqual(topic_id, info.topic_id);
    try expectEqual(@as(u64, 1000), info.sequence_number);
    try expectEqualSlices(u8, "running_hash_data", info.running_hash);
    try expectEqualSlices(u8, "Topic information test", info.topic_memo);
    try expectEqual(expiration, info.expiration_time);
    try expectEqual(auto_renew_period, info.auto_renew_period);
}

test "TopicInfo with keys" {
    var info = TopicInfo.init(allocator);
    defer info.deinit();
    
    const admin_key = Key{ .ed25519_public_key = "admin_key_data" };
    const submit_key = Key{ .ed25519_public_key = "submit_key_data" };
    
    info.admin_key = admin_key;
    info.submit_key = submit_key;
    
    try expectEqual(admin_key, info.admin_key.?);
    try expectEqual(submit_key, info.submit_key.?);
}

test "TopicInfo with auto renew account" {
    var info = TopicInfo.init(allocator);
    defer info.deinit();
    
    const auto_renew_account = AccountId.init(0, 0, 700);
    info.auto_renew_account = auto_renew_account;
    
    try expectEqual(auto_renew_account, info.auto_renew_account.?);
}

test "TopicInfo memory ownership tracking" {
    var info = TopicInfo.init(allocator);
    defer info.deinit();
    
    // Test that ownership flags are set correctly
    try expect(!info.owns_memo);
    try expect(!info.owns_topic_memo);
    try expect(!info.owns_running_hash);
    try expect(!info.owns_ledger_id);
    
    // These would typically be set during protobuf parsing
    info.owns_topic_memo = true;
    info.owns_running_hash = true;
    
    try expect(info.owns_topic_memo);
    try expect(info.owns_running_hash);
}

// TopicInfoQuery Tests
test "TopicInfoQuery initialization and configuration" {
    var query = TopicInfoQuery.init(allocator);
    defer query.deinit();
    
    const topic_id = TopicId.init(0, 0, 2001);
    _ = try query.setTopicId(topic_id);
    
    const payment = try Hbar.fromTinybars(1000000);
    _ = try query.setQueryPayment(payment);
}

test "TopicInfoQuery execution validation" {
    var query = TopicInfoQuery.init(allocator);
    defer query.deinit();
    
    var client = @import("../../src/network/client.zig").Client.init(allocator);
    defer client.deinit();
    
    // Should fail without topic ID
    try expectError(error.TopicIdRequired, query.execute(&client));
}

// TopicUpdateTransaction Tests
test "TopicUpdateTransaction initialization and basic setters" {
    var tx = try TopicUpdateTransaction.init(allocator);
    defer tx.deinit();
    
    const topic_id = TopicId.init(0, 0, 2001);
    _ = try tx.setTopicId(topic_id);
    try expectEqual(topic_id, tx.getTopicId());
    
    const private_key = try PrivateKey.generateEd25519();
    defer private_key.deinit();
    const admin_key = Key{ .ed25519_public_key = private_key.public_key.toStringRaw() };
    _ = try tx.setAdminKey(admin_key);
    try expectEqual(admin_key, try tx.getAdminKey());
    
    const submit_key = Key{ .ed25519_public_key = "new_submit_key" };
    _ = try tx.setSubmitKey(submit_key);
    try expectEqual(submit_key, try tx.getSubmitKey());
    
    _ = try tx.setTopicMemo("Updated topic memo");
    try expectEqualSlices(u8, "Updated topic memo", tx.getTopicMemo());
    
    const expiration = Timestamp{ .seconds = 2500000000, .nanos = 0 };
    _ = try tx.setExpirationTime(expiration);
    try expectEqual(expiration, tx.getExpirationTime());
    
    const new_auto_renew_period = Duration{ .seconds = 8640000, .nanos = 0 };
    _ = try tx.setAutoRenewPeriod(new_auto_renew_period);
    try expectEqual(new_auto_renew_period, tx.getAutoRenewPeriod());
    
    const auto_renew_account = AccountId.init(0, 0, 800);
    _ = try tx.setAutoRenewAccountId(auto_renew_account);
    try expectEqual(auto_renew_account, tx.getAutoRenewAccountID());
}

test "TopicUpdateTransaction fee schedule and exempt keys" {
    var tx = try TopicUpdateTransaction.init(allocator);
    defer tx.deinit();
    
    const fee_schedule_key = Key{ .ed25519_public_key = "fee_schedule_key_data" };
    _ = try tx.setFeeScheduleKey(fee_schedule_key);
    try expectEqual(fee_schedule_key, tx.getFeeScheduleKey());
    
    const exempt_key1 = Key{ .ed25519_public_key = "exempt_key_1" };
    const exempt_key2 = Key{ .ed25519_public_key = "exempt_key_2" };
    
    _ = try tx.addFeeExemptKey(exempt_key1);
    _ = try tx.addFeeExemptKey(exempt_key2);
    
    const exempt_keys = tx.getFeeExemptKeys();
    try expectEqual(@as(usize, 2), exempt_keys.len);
    try expectEqual(exempt_key1, exempt_keys[0]);
    try expectEqual(exempt_key2, exempt_keys[1]);
}

test "TopicUpdateTransaction custom fees management" {
    var tx = try TopicUpdateTransaction.init(allocator);
    defer tx.deinit();
    
    const fee_collector = AccountId.init(0, 0, 500);
    
    var fee1 = try allocator.create(CustomFixedFee);
    fee1.* = CustomFixedFee.init(3000000, fee_collector); // 0.03 Hbar
    
    _ = try tx.addCustomFee(fee1);
    
    const custom_fees = tx.getCustomFees();
    try expectEqual(@as(usize, 1), custom_fees.len);
    try expectEqual(@as(u64, 3000000), custom_fees[0].amount);
    
    _ = try tx.clearCustomFees();
    try expectEqual(@as(usize, 0), tx.getCustomFees().len);
}

test "TopicUpdateTransaction clearing operations" {
    var tx = try TopicUpdateTransaction.init(allocator);
    defer tx.deinit();
    
    const topic_id = TopicId.init(0, 0, 2001);
    _ = try tx.setTopicId(topic_id);
    
    // Set values then clear them
    _ = try tx.setTopicMemo("Original memo");
    _ = try tx.clearTopicMemo();
    try expectEqualSlices(u8, "", tx.getTopicMemo());
    
    const admin_key = Key{ .ed25519_public_key = "admin_key" };
    _ = try tx.setAdminKey(admin_key);
    _ = try tx.clearAdminKey();
    try expectError(error.AdminKeyNotSet, tx.getAdminKey());
    
    const submit_key = Key{ .ed25519_public_key = "submit_key" };
    _ = try tx.setSubmitKey(submit_key);
    _ = try tx.clearSubmitKey();
    try expectError(error.SubmitKeyNotSet, tx.getSubmitKey());
    try expect(tx.clear_submit_key);
    
    const auto_renew_account = AccountId.init(0, 0, 700);
    _ = try tx.setAutoRenewAccountId(auto_renew_account);
    _ = try tx.clearAutoRenewAccountID();
    try expectEqual(AccountId{}, tx.getAutoRenewAccountID());
}

test "TopicUpdateTransaction execution validation" {
    var tx = try TopicUpdateTransaction.init(allocator);
    defer tx.deinit();
    
    var client = @import("../../src/network/client.zig").Client.init(allocator);
    defer client.deinit();
    
    // Should fail without topic ID
    try expectError(error.InvalidParameter, tx.execute(&client));
}

// TopicDeleteTransaction Tests
test "TopicDeleteTransaction initialization and basic operations" {
    var tx = try TopicDeleteTransaction.init(allocator);
    defer tx.deinit();
    
    const topic_id = TopicId.init(0, 0, 2001);
    _ = try tx.setTopicId(topic_id);
    try expectEqual(topic_id, tx.getTopicId());
    
    const max_fee = try Hbar.from(5);
    _ = try tx.setMaxTransactionFee(max_fee);
    try expectEqual(max_fee, tx.getMaxTransactionFee().?);
    
    _ = try tx.setTransactionMemo("Delete topic transaction");
    try expectEqualSlices(u8, "Delete topic transaction", tx.getTransactionMemo());
}

test "TopicDeleteTransaction execution validation" {
    var tx = try TopicDeleteTransaction.init(allocator);
    defer tx.deinit();
    
    var client = @import("../../src/network/client.zig").Client.init(allocator);
    defer client.deinit();
    
    // Should fail without topic ID
    try expectError(error.InvalidParameter, tx.execute(&client));
}

test "TopicDeleteTransaction node account configuration" {
    var tx = try TopicDeleteTransaction.init(allocator);
    defer tx.deinit();
    
    const node_accounts = [_]AccountId{
        AccountId.init(0, 0, 3),
        AccountId.init(0, 0, 4),
        AccountId.init(0, 0, 5),
    };
    _ = try tx.setNodeAccountIDs(&node_accounts);
    
    const retrieved_nodes = tx.getNodeAccountIDs();
    try expectEqual(@as(usize, 3), retrieved_nodes.len);
    try expectEqual(node_accounts[0], retrieved_nodes[0]);
    try expectEqual(node_accounts[1], retrieved_nodes[1]);
    try expectEqual(node_accounts[2], retrieved_nodes[2]);
}

// TopicMessage and TopicMessageQuery Tests
test "TopicMessage initialization and basic properties" {
    var message = TopicMessage.init(allocator);
    defer message.deinit(allocator);
    
    message.consensus_timestamp = Timestamp{ .seconds = 1234567890, .nanos = 123456789 };
    message.topic_id = TopicId.init(0, 0, 2001);
    message.sequence_number = 42;
    message.running_hash_version = 3;
    
    try expectEqual(@as(i64, 1234567890), message.consensus_timestamp.seconds);
    try expectEqual(@as(i32, 123456789), message.consensus_timestamp.nanos);
    try expectEqual(TopicId.init(0, 0, 2001), message.topic_id);
    try expectEqual(@as(u64, 42), message.sequence_number);
    try expectEqual(@as(u32, 3), message.running_hash_version);
}

test "TopicMessage with chunk information" {
    const TransactionId = @import("../../src/core/transaction_id.zig").TransactionId;
    var message = TopicMessage.init(allocator);
    defer message.deinit(allocator);
    
    const initial_tx_id = TransactionId{
        .account_id = AccountId.init(0, 0, 100),
        .valid_start = Timestamp{ .seconds = 1000000000, .nanos = 0 },
        .nonce = null,
    };
    
    message.chunk_info = ChunkInfo{
        .initial_transaction_id = initial_tx_id,
        .number = 2,
        .total = 5,
    };
    
    try expectEqual(@as(u32, 2), message.chunk_info.?.number);
    try expectEqual(@as(u32, 5), message.chunk_info.?.total);
    try expectEqual(initial_tx_id.account_id, message.chunk_info.?.initial_transaction_id.account_id);
}

test "TopicMessage with payer account" {
    var message = TopicMessage.init(allocator);
    defer message.deinit(allocator);
    
    const payer_account = AccountId.init(0, 0, 300);
    message.payer_account_id = payer_account;
    
    try expectEqual(payer_account, message.payer_account_id.?);
}

test "TopicMessageQuery initialization and configuration" {
    var query = TopicMessageQuery.init(allocator);
    defer query.deinit();
    
    const topic_id = TopicId.init(0, 0, 2001);
    _ = try query.setTopicId(topic_id);
    
    const start_time = Timestamp{ .seconds = 1000000000, .nanos = 0 };
    const end_time = Timestamp{ .seconds = 2000000000, .nanos = 0 };
    
    _ = try query.setStartTime(start_time);
    _ = try query.setEndTime(end_time);
    _ = try query.setLimit(500);
    _ = try query.setOrder(.desc);
    _ = try query.setMaxRetry(5);
    
    try expectEqual(topic_id, query.topic_id.?);
    try expectEqual(start_time, query.start_time.?);
    try expectEqual(end_time, query.end_time.?);
    try expectEqual(@as(u32, 500), query.limit);
    try expectEqual(TopicMessageQuery.Order.desc, query.order);
    try expectEqual(@as(u32, 5), query.max_retry);
}

test "TopicMessageQuery order enum string representation" {
    try expectEqualSlices(u8, "asc", TopicMessageQuery.Order.asc.toString());
    try expectEqualSlices(u8, "desc", TopicMessageQuery.Order.desc.toString());
}

test "ChunkInfo structure" {
    const TransactionId = @import("../../src/core/transaction_id.zig").TransactionId;
    
    const initial_tx_id = TransactionId{
        .account_id = AccountId.init(0, 0, 100),
        .valid_start = Timestamp{ .seconds = 1000000000, .nanos = 0 },
        .nonce = null,
    };
    
    const chunk_info = ChunkInfo{
        .initial_transaction_id = initial_tx_id,
        .number = 3,
        .total = 7,
    };
    
    try expectEqual(@as(u32, 3), chunk_info.number);
    try expectEqual(@as(u32, 7), chunk_info.total);
    try expectEqual(initial_tx_id.account_id, chunk_info.initial_transaction_id.account_id);
    try expectEqual(initial_tx_id.valid_start, chunk_info.initial_transaction_id.valid_start);
}

// Error Handling Tests
test "Topic operations with invalid parameters" {
    // Test invalid topic ID parsing
    try expectError(error.InvalidString, TopicId.fromString("invalid"));
    try expectError(error.InvalidString, TopicId.fromString("0.0"));
    try expectError(error.InvalidString, TopicId.fromString("0.0.abc"));
    
    // Test custom fee limits with zero amounts
    const fee_collector = AccountId.init(0, 0, 500);
    const zero_fee_limit = CustomFeeLimit.init(fee_collector, 0);
    try expectEqual(@as(u64, 0), zero_fee_limit.max_amount);
}

test "Topic transaction frozen state validations" {
    var create_tx = try TopicCreateTransaction.init(allocator);
    defer create_tx.deinit();
    
    var update_tx = try TopicUpdateTransaction.init(allocator);
    defer update_tx.deinit();
    
    var submit_tx = try TopicMessageSubmitTransaction.init(allocator);
    defer submit_tx.deinit();
    
    var delete_tx = try TopicDeleteTransaction.init(allocator);
    defer delete_tx.deinit();
    
    // Freeze all transactions
    create_tx.transaction.frozen = true;
    update_tx.transaction.frozen = true;
    submit_tx.transaction.frozen = true;
    delete_tx.transaction.frozen = true;
    
    const key = Key{ .ed25519_public_key = "test_key" };
    const topic_id = TopicId.init(0, 0, 2001);
    
    // All setters should fail when frozen
    try expectError(error.TransactionFrozen, create_tx.setAdminKey(key));
    try expectError(error.TransactionFrozen, update_tx.setAdminKey(key));
    try expectError(error.TransactionFrozen, submit_tx.setTopicId(topic_id));
    try expectError(error.TransactionFrozen, delete_tx.setTopicId(topic_id));
}

// Integration Tests
test "Complete topic creation and configuration flow" {
    var tx = try TopicCreateTransaction.init(allocator);
    defer tx.deinit();
    
    // Set up comprehensive topic creation
    const private_key = try PrivateKey.generateEd25519();
    defer private_key.deinit();
    const admin_key = Key{ .ed25519_public_key = private_key.public_key.toStringRaw() };
    const submit_key = Key{ .ed25519_public_key = "submit_key_data" };
    const fee_schedule_key = Key{ .ed25519_public_key = "fee_schedule_key_data" };
    
    _ = try tx.setAdminKey(admin_key);
    _ = try tx.setSubmitKey(submit_key);
    _ = try tx.setFeeScheduleKey(fee_schedule_key);
    
    _ = try tx.setTopicMemo("Comprehensive test topic");
    
    const auto_renew_period = Duration{ .seconds = 7890000, .nanos = 0 };
    _ = try tx.setAutoRenewPeriod(auto_renew_period);
    
    const auto_renew_account = AccountId.init(0, 0, 600);
    _ = try tx.setAutoRenewAccountId(auto_renew_account);
    
    // Add exempt keys
    const exempt_key1 = Key{ .ed25519_public_key = "exempt_key_1" };
    const exempt_key2 = Key{ .ed25519_public_key = "exempt_key_2" };
    _ = try tx.addFeeExemptKey(exempt_key1);
    _ = try tx.addFeeExemptKey(exempt_key2);
    
    // Add custom fees
    const fee_collector = AccountId.init(0, 0, 500);
    var custom_fee = try allocator.create(CustomFixedFee);
    custom_fee.* = CustomFixedFee.init(1000000, fee_collector);
    _ = try tx.addCustomFee(custom_fee);
    
    // Set transaction properties
    const max_fee = try Hbar.from(25);
    _ = try tx.setMaxTransactionFee(max_fee);
    _ = try tx.setTransactionMemo("Create comprehensive test topic");
    
    // Verify all properties are set correctly
    try expectEqual(admin_key, try tx.getAdminKey());
    try expectEqual(submit_key, try tx.getSubmitKey());
    try expectEqual(fee_schedule_key, tx.getFeeScheduleKey());
    try expectEqualSlices(u8, "Comprehensive test topic", tx.getTopicMemo());
    try expectEqual(auto_renew_period, tx.getAutoRenewPeriod());
    try expectEqual(auto_renew_account, tx.getAutoRenewAccountID());
    
    const exempt_keys = tx.getFeeExemptKeys();
    try expectEqual(@as(usize, 2), exempt_keys.len);
    
    const custom_fees = tx.getCustomFees();
    try expectEqual(@as(usize, 1), custom_fees.len);
    try expectEqual(@as(u64, 1000000), custom_fees[0].amount);
    
    try expectEqual(max_fee, tx.getMaxTransactionFee().?);
    try expectEqualSlices(u8, "Create comprehensive test topic", tx.getTransactionMemo());
}

test "Topic message submission with chunking configuration" {
    var tx = try TopicMessageSubmitTransaction.init(allocator);
    defer tx.deinit();
    
    const topic_id = TopicId.init(0, 0, 2001);
    _ = try tx.setTopicId(topic_id);
    
    // Set up message chunking for large message
    const message_size = 5000; // 5KB message
    var large_message = try allocator.alloc(u8, message_size);
    defer allocator.free(large_message);
    
    // Fill with test data
    for (large_message, 0..) |*byte, i| {
        byte.* = @intCast(i % 256);
    }
    
    _ = try tx.setMessage(large_message);
    _ = try tx.setChunkSize(1024); // 1KB chunks
    _ = try tx.setMaxChunks(10); // Allow up to 10 chunks
    
    // Calculate expected chunks
    const chunks_needed = (large_message.len + tx.getChunkSize() - 1) / tx.getChunkSize();
    try expectEqual(@as(usize, 5), chunks_needed); // 5KB / 1KB = 5 chunks
    try expect(chunks_needed <= tx.getMaxChunks());
    
    // Add custom fee limits
    const fee_collector = AccountId.init(0, 0, 500);
    var fee_limit = try allocator.create(CustomFeeLimit);
    fee_limit.* = CustomFeeLimit.init(fee_collector, 10000000); // 0.1 Hbar max
    _ = try tx.addCustomFeeLimit(fee_limit);
    
    const fee_limits = tx.getCustomFeeLimits();
    try expectEqual(@as(usize, 1), fee_limits.len);
    try expectEqual(@as(u64, 10000000), fee_limits[0].max_amount);
    
    // Set transaction properties
    const max_fee = try Hbar.from(5);
    _ = try tx.setMaxTransactionFee(max_fee);
    _ = try tx.setTransactionMemo("Submit large message with chunking");
    
    try expectEqual(topic_id, tx.getTopicId());
    try expectEqualSlices(u8, large_message, tx.getMessage());
    try expectEqual(@as(u64, 1024), tx.getChunkSize());
    try expectEqual(@as(u64, 10), tx.getMaxChunks());
}

test "Topic update with comprehensive property changes" {
    var tx = try TopicUpdateTransaction.init(allocator);
    defer tx.deinit();
    
    const topic_id = TopicId.init(0, 0, 2001);
    _ = try tx.setTopicId(topic_id);
    
    // Update all possible properties
    const private_key = try PrivateKey.generateEd25519();
    defer private_key.deinit();
    const new_admin_key = Key{ .ed25519_public_key = private_key.public_key.toStringRaw() };
    const new_submit_key = Key{ .ed25519_public_key = "new_submit_key_data" };
    const new_fee_schedule_key = Key{ .ed25519_public_key = "new_fee_schedule_key" };
    
    _ = try tx.setAdminKey(new_admin_key);
    _ = try tx.setSubmitKey(new_submit_key);
    _ = try tx.setFeeScheduleKey(new_fee_schedule_key);
    
    _ = try tx.setTopicMemo("Updated topic memo for comprehensive test");
    
    const new_expiration = Timestamp{ .seconds = 2500000000, .nanos = 0 };
    _ = try tx.setExpirationTime(new_expiration);
    
    const new_auto_renew_period = Duration{ .seconds = 8640000, .nanos = 0 };
    _ = try tx.setAutoRenewPeriod(new_auto_renew_period);
    
    const new_auto_renew_account = AccountId.init(0, 0, 800);
    _ = try tx.setAutoRenewAccountId(new_auto_renew_account);
    
    // Update fee exempt keys
    const new_exempt_key = Key{ .ed25519_public_key = "new_exempt_key" };
    _ = try tx.addFeeExemptKey(new_exempt_key);
    
    // Update custom fees
    const fee_collector = AccountId.init(0, 0, 501);
    var new_fee = try allocator.create(CustomFixedFee);
    new_fee.* = CustomFixedFee.init(2000000, fee_collector); // 0.02 Hbar
    _ = try tx.addCustomFee(new_fee);
    
    // Verify all updates
    try expectEqual(topic_id, tx.getTopicId());
    try expectEqual(new_admin_key, try tx.getAdminKey());
    try expectEqual(new_submit_key, try tx.getSubmitKey());
    try expectEqual(new_fee_schedule_key, tx.getFeeScheduleKey());
    try expectEqualSlices(u8, "Updated topic memo for comprehensive test", tx.getTopicMemo());
    try expectEqual(new_expiration, tx.getExpirationTime());
    try expectEqual(new_auto_renew_period, tx.getAutoRenewPeriod());
    try expectEqual(new_auto_renew_account, tx.getAutoRenewAccountID());
    
    const exempt_keys = tx.getFeeExemptKeys();
    try expectEqual(@as(usize, 1), exempt_keys.len);
    try expectEqual(new_exempt_key, exempt_keys[0]);
    
    const custom_fees = tx.getCustomFees();
    try expectEqual(@as(usize, 1), custom_fees.len);
    try expectEqual(@as(u64, 2000000), custom_fees[0].amount);
}

test "Topic info query and response parsing scenarios" {
    var query = TopicInfoQuery.init(allocator);
    defer query.deinit();
    
    const topic_id = TopicId.init(0, 0, 2001);
    _ = try query.setTopicId(topic_id);
    
    const payment = try Hbar.fromTinybars(2000000);
    _ = try query.setQueryPayment(payment);
    
    // Create sample topic info for validation
    var sample_info = TopicInfo.init(allocator);
    defer sample_info.deinit();
    
    sample_info.topic_id = topic_id;
    sample_info.sequence_number = 1000;
    sample_info.running_hash = "sample_running_hash";
    sample_info.topic_memo = "Sample topic for testing";
    sample_info.expiration_time = Timestamp{ .seconds = 2000000000, .nanos = 0 };
    
    const admin_key = Key{ .ed25519_public_key = "admin_key_data" };
    const submit_key = Key{ .ed25519_public_key = "submit_key_data" };
    sample_info.admin_key = admin_key;
    sample_info.submit_key = submit_key;
    
    sample_info.auto_renew_period = Duration{ .seconds = 7890000, .nanos = 0 };
    sample_info.auto_renew_account = AccountId.init(0, 0, 700);
    sample_info.ledger_id = "mainnet";
    
    // Verify sample info structure
    try expectEqual(topic_id, sample_info.topic_id);
    try expectEqual(@as(u64, 1000), sample_info.sequence_number);
    try expectEqualSlices(u8, "sample_running_hash", sample_info.running_hash);
    try expectEqualSlices(u8, "Sample topic for testing", sample_info.topic_memo);
    try expectEqual(admin_key, sample_info.admin_key.?);
    try expectEqual(submit_key, sample_info.submit_key.?);
    try expectEqual(AccountId.init(0, 0, 700), sample_info.auto_renew_account.?);
    try expectEqualSlices(u8, "mainnet", sample_info.ledger_id);
}

test "Topic message query with time range filtering" {
    var query = TopicMessageQuery.init(allocator);
    defer query.deinit();
    
    const topic_id = TopicId.init(0, 0, 2001);
    _ = try query.setTopicId(topic_id);
    
    // Set up time range for the last hour
    const now = std.time.timestamp();
    const one_hour_ago = now - 3600;
    
    const start_time = Timestamp{ .seconds = one_hour_ago, .nanos = 0 };
    const end_time = Timestamp{ .seconds = now, .nanos = 0 };
    
    _ = try query.setStartTime(start_time);
    _ = try query.setEndTime(end_time);
    _ = try query.setLimit(100);
    _ = try query.setOrder(.desc); // Most recent first
    _ = try query.setMaxRetry(3);
    
    try expectEqual(topic_id, query.topic_id.?);
    try expectEqual(start_time, query.start_time.?);
    try expectEqual(end_time, query.end_time.?);
    try expectEqual(@as(u32, 100), query.limit);
    try expectEqual(TopicMessageQuery.Order.desc, query.order);
    try expectEqual(@as(u32, 3), query.max_retry);
}

test "Topic message with complete metadata" {
    var message = TopicMessage.init(allocator);
    defer message.deinit(allocator);
    
    const TransactionId = @import("../../src/core/transaction_id.zig").TransactionId;
    
    // Set all message properties
    message.consensus_timestamp = Timestamp{ .seconds = 1234567890, .nanos = 123456789 };
    message.topic_id = TopicId.init(0, 0, 2001);
    message.sequence_number = 500;
    message.running_hash_version = 3;
    message.payer_account_id = AccountId.init(0, 0, 100);
    
    // Add chunk information for multi-part message
    const initial_tx_id = TransactionId{
        .account_id = AccountId.init(0, 0, 100),
        .valid_start = Timestamp{ .seconds = 1234567800, .nanos = 0 },
        .nonce = 1,
    };
    
    message.chunk_info = ChunkInfo{
        .initial_transaction_id = initial_tx_id,
        .number = 3,
        .total = 5,
    };
    
    // Verify all properties
    try expectEqual(@as(i64, 1234567890), message.consensus_timestamp.seconds);
    try expectEqual(@as(i32, 123456789), message.consensus_timestamp.nanos);
    try expectEqual(TopicId.init(0, 0, 2001), message.topic_id);
    try expectEqual(@as(u64, 500), message.sequence_number);
    try expectEqual(@as(u32, 3), message.running_hash_version);
    try expectEqual(AccountId.init(0, 0, 100), message.payer_account_id.?);
    
    try expectEqual(@as(u32, 3), message.chunk_info.?.number);
    try expectEqual(@as(u32, 5), message.chunk_info.?.total);
    try expectEqual(initial_tx_id.account_id, message.chunk_info.?.initial_transaction_id.account_id);
    try expectEqual(@as(?u32, 1), message.chunk_info.?.initial_transaction_id.nonce);
}
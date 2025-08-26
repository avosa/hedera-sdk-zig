const std = @import("std");
const testing = std.testing;
const hedera = @import("hedera");

test "Topic create transaction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = try hedera.TopicCreateTransaction.init(allocator);
    defer tx.deinit();
    
    // Set topic memo
    _ = try tx.setTopicMemo("Test consensus topic");
    
    // Generate keys
    var admin_key = try hedera.generatePrivateKey(allocator);
    defer admin_key.deinit();
    
    var submit_key = try hedera.generatePrivateKey(allocator);
    defer submit_key.deinit();
    
    // Set keys
    _ = try tx.setAdminKey(hedera.Key.fromPublicKey(admin_key.getPublicKey()));
    _ = try tx.setSubmitKey(hedera.Key.fromPublicKey(submit_key.getPublicKey()));
    
    // Set auto renew
    _ = try tx.setAutoRenewAccountId(hedera.AccountId.init(0, 0, 100));
    _ = try tx.setAutoRenewPeriod(hedera.Duration.fromDays(90));
    
    // Verify settings
    try testing.expectEqualStrings("Test consensus topic", tx.memo);
    try testing.expect(tx.admin_key != null);
    try testing.expect(tx.submit_key != null);
    try testing.expectEqual(@as(u64, 100), tx.auto_renew_account_id.?.account);
    try testing.expectEqual(@as(i64, 7776000), tx.auto_renew_period.seconds);
}

test "Topic update transaction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = try hedera.TopicUpdateTransaction.init(allocator);
    defer tx.deinit();
    
    // Set topic to update
    const topic_id = hedera.TopicId.init(0, 0, 777);
    _ = try tx.setTopicId(topic_id);
    
    // Update memo
    _ = try tx.setTopicMemo("Updated topic memo");
    
    // Update keys
    var new_admin_key = try hedera.generatePrivateKey(allocator);
    defer new_admin_key.deinit();
    
    var new_submit_key = try hedera.generatePrivateKey(allocator);
    defer new_submit_key.deinit();
    
    _ = try tx.setAdminKey(hedera.Key.fromPublicKey(new_admin_key.getPublicKey()));
    _ = try tx.setSubmitKey(hedera.Key.fromPublicKey(new_submit_key.getPublicKey()));
    
    // Update auto renew
    _ = try tx.setAutoRenewAccountId(hedera.AccountId.init(0, 0, 200));
    _ = try tx.setAutoRenewPeriod(hedera.Duration.fromDays(120));
    
    // Clear submit key
    _ = try tx.clearSubmitKey();
    
    // Verify settings
    try testing.expectEqual(@as(u64, 777), tx.topic_id.?.num());
    try testing.expectEqualStrings("Updated topic memo", tx.memo.?);
    try testing.expect(tx.admin_key != null);
    try testing.expect(tx.clear_submit_key);
    try testing.expectEqual(@as(u64, 200), tx.auto_renew_account_id.?.account);
    try testing.expectEqual(@as(i64, 10368000), tx.auto_renew_period.?.seconds);
}

test "Topic delete transaction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = try hedera.TopicDeleteTransaction.init(allocator);
    defer tx.deinit();
    
    // Set topic to delete
    const topic_id = hedera.TopicId.init(0, 0, 888);
    _ = try tx.setTopicId(topic_id);
    
    try testing.expectEqual(@as(u64, 888), tx.topic_id.?.num());
}

test "Topic message submit transaction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.TopicMessageSubmitTransaction.init(allocator);
    defer tx.deinit();
    
    // Set topic ID
    const topic_id = hedera.TopicId.init(0, 0, 999);
    _ = try tx.setTopicId(topic_id);
    
    // Set message
    const message = "Hello from consensus service!";
    _ = try tx.setMessage(message);
    
    // Set max chunks for large messages
    _ = try tx.setMaxChunks(5);
    
    // Set chunk size
    _ = try tx.setChunkSize(1024);
    
    try testing.expectEqual(@as(u64, 999), tx.topic_id.?.num());
    try testing.expectEqualStrings(message, tx.message);
    try testing.expectEqual(@as(u32, 5), tx.max_chunks);
    try testing.expectEqual(@as(u32, 1024), tx.chunk_size);
}

test "Topic message chunking" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.TopicMessageSubmitTransaction.init(allocator);
    defer tx.deinit();
    
    // Set topic ID
    const topic_id = hedera.TopicId.init(0, 0, 1111);
    _ = try tx.setTopicId(topic_id);
    
    // Create large message (5KB)
    const large_message = try allocator.alloc(u8, 5120);
    defer allocator.free(large_message);
    @memset(large_message, 'M');
    
    // Set large message
    _ = try tx.setMessage(large_message);
    
    // Set chunk size (1KB)
    _ = try tx.setChunkSize(1024);
    
    // Calculate expected chunks
    const expected_chunks = (large_message.len + 1023) / 1024;
    
    try testing.expectEqual(@as(u64, 1111), tx.topic_id.?.num());
    try testing.expectEqual(@as(usize, 5120), tx.message.len);
    try testing.expectEqual(@as(u32, 1024), tx.chunk_size);
    try testing.expectEqual(@as(usize, 5), expected_chunks);
}

test "Topic info structure" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var info = hedera.TopicInfo.init(allocator);
    defer info.deinit();
    
    // Set topic info fields
    info.topic_id = hedera.TopicId.init(0, 0, 2222);
    info.memo = "Consensus topic info";
    const running_hash = try allocator.alloc(u8, 48);
    @memset(running_hash, 0xAB);
    info.running_hash = running_hash;
    info.sequence_number = 12345;
    info.expiration_time = hedera.Timestamp.fromSeconds(1234567890);
    
    // Set keys
    var admin_key = try hedera.generatePrivateKey(allocator);
    defer admin_key.deinit();
    
    var submit_key = try hedera.generatePrivateKey(allocator);
    defer submit_key.deinit();
    
    info.admin_key = hedera.Key.fromPublicKey(admin_key.getPublicKey());
    info.submit_key = hedera.Key.fromPublicKey(submit_key.getPublicKey());
    
    // Set auto renew
    info.auto_renew_account = hedera.AccountId.init(0, 0, 300);
    info.auto_renew_period = hedera.Duration.fromDays(90);
    
    info.ledger_id = "mainnet";
    
    // Verify fields
    try testing.expectEqual(@as(u64, 2222), info.topic_id.num());
    try testing.expectEqualStrings("Consensus topic info", info.memo);
    try testing.expectEqual(@as(usize, 48), info.running_hash.len);
    try testing.expectEqual(@as(u64, 12345), info.sequence_number);
    try testing.expectEqual(@as(i64, 1234567890), info.expiration_time.seconds);
    try testing.expect(info.admin_key != null);
    try testing.expect(info.submit_key != null);
    try testing.expectEqual(@as(u64, 300), info.auto_renew_account.?.account);
    try testing.expectEqual(@as(i64, 7776000), info.auto_renew_period.seconds);
    try testing.expectEqualStrings("mainnet", info.ledger_id);
}

test "Topic message structure" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var message = hedera.TopicMessage.init(allocator);
    defer message.deinit(allocator);
    
    // Set message fields
    message.consensus_timestamp = hedera.Timestamp.fromSeconds(1234567890);
    message.contents = try allocator.dupe(u8, "Message contents");
    const msg_hash = try allocator.alloc(u8, 48);
    @memset(msg_hash, 0xCD);
    message.running_hash = msg_hash;
    message.sequence_number = 67890;
    
    // Set chunk info for chunked messages
    message.chunk_info = hedera.ChunkInfo{
        .initial_transaction_id = hedera.TransactionId.generate(hedera.AccountId.init(0, 0, 400)),
        .total = 5,
        .number = 2,
    };
    
    // Verify fields
    try testing.expectEqual(@as(i64, 1234567890), message.consensus_timestamp.seconds);
    try testing.expectEqualStrings("Message contents", message.contents);
    try testing.expectEqual(@as(usize, 48), message.running_hash.len);
    try testing.expectEqual(@as(u64, 67890), message.sequence_number);
    try testing.expect(message.chunk_info != null);
    try testing.expectEqual(@as(u32, 5), message.chunk_info.?.total);
    try testing.expectEqual(@as(u32, 2), message.chunk_info.?.number);
}

test "Topic message query" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.TopicMessageQuery.init(allocator);
    defer query.deinit();
    
    // Set topic ID
    const topic_id = hedera.TopicId.init(0, 0, 3333);
    _ = try query.setTopicId(topic_id);
    
    // Set time range
    const start_time = hedera.Timestamp.fromSeconds(1000000000);
    const end_time = hedera.Timestamp.fromSeconds(2000000000);
    
    _ = try query.setStartTime(start_time);
    _ = try query.setEndTime(end_time);
    
    // Set limit
    _ = try query.setLimit(100);
    
    // Subscribe to topic (would set up subscription handler)
    // This would typically involve a callback function
    
    try testing.expectEqual(@as(u64, 3333), query.topic_id.?.num());
    try testing.expectEqual(@as(i64, 1000000000), query.start_time.?.seconds);
    try testing.expectEqual(@as(i64, 2000000000), query.end_time.?.seconds);
    try testing.expectEqual(@as(u32, 100), query.limit);
}

test "Topic memo limits" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = try hedera.TopicCreateTransaction.init(allocator);
    defer tx.deinit();
    
    // Valid memo (under 100 bytes)
    const valid_memo = "This is a valid topic memo";
    _ = try tx.setTopicMemo(valid_memo);
    try testing.expectEqualStrings(valid_memo, tx.memo);
    
    // Long memo (exactly 100 bytes)
    const long_memo = "a" ** 100;
    _ = try tx.setTopicMemo(long_memo);
    try testing.expectEqualStrings(long_memo, tx.memo);
    
    // Too long memo would panic (removed test as setters use @panic not errors)
}

test "Topic submit key requirements" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = try hedera.TopicCreateTransaction.init(allocator);
    defer tx.deinit();
    
    // Topic without submit key (public topic)
    _ = try tx.setTopicMemo("Public topic");
    try testing.expect(tx.submit_key == null);
    
    // Topic with submit key (restricted topic)
    var submit_key = try hedera.generatePrivateKey(allocator);
    defer submit_key.deinit();
    
    _ = try tx.setSubmitKey(hedera.Key.fromPublicKey(submit_key.getPublicKey()));
    try testing.expect(tx.submit_key != null);
    
    // Topic with threshold submit key
    var key1 = try hedera.generatePrivateKey(allocator);
    defer key1.deinit();
    
    var key2 = try hedera.generatePrivateKey(allocator);
    defer key2.deinit();
    
    var threshold_key = hedera.KeyList.init(allocator);
    defer threshold_key.deinit();
    threshold_key.threshold = 1;
    
    try threshold_key.add(hedera.Key.fromPublicKey(key1.getPublicKey()));
    try threshold_key.add(hedera.Key.fromPublicKey(key2.getPublicKey()));
    
    _ = try tx.setSubmitKey(hedera.Key.fromKeyList(threshold_key));
    try testing.expect(tx.submit_key != null);
}

test "Topic message with running hash verification" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create sequence of messages
    var messages = std.ArrayList(hedera.TopicMessage).init(allocator);
    defer messages.deinit();
    
    // First message
    var msg1 = hedera.TopicMessage.init(allocator);
    msg1.sequence_number = 1;
    msg1.contents = try allocator.dupe(u8, "First message");
    const hash1 = try allocator.alloc(u8, 48);
    @memset(hash1, 0x01);
    msg1.running_hash = hash1;
    msg1.consensus_timestamp = hedera.Timestamp.fromSeconds(1000);
    try messages.append(msg1);
    
    // Second message
    var msg2 = hedera.TopicMessage.init(allocator);
    msg2.sequence_number = 2;
    msg2.contents = try allocator.dupe(u8, "Second message");
    const hash2 = try allocator.alloc(u8, 48);
    @memset(hash2, 0x02);
    msg2.running_hash = hash2;
    msg2.consensus_timestamp = hedera.Timestamp.fromSeconds(1001);
    try messages.append(msg2);
    
    // Verify sequence
    try testing.expectEqual(@as(u64, 1), messages.items[0].sequence_number);
    try testing.expectEqual(@as(u64, 2), messages.items[1].sequence_number);
    
    // Verify timestamps are in order
    try testing.expect(messages.items[0].consensus_timestamp.seconds < messages.items[1].consensus_timestamp.seconds);
    
    // Cleanup
    for (messages.items) |*msg| {
        msg.deinit(allocator);
    }
}

test "Topic subscription handling" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = hedera.TopicMessageQuery.init(allocator);
    defer query.deinit();
    
    const topic_id = hedera.TopicId.init(0, 0, 4444);
    _ = try query.setTopicId(topic_id);
    
    // Set retry configuration
    _ = try query.setMaxRetry(5);
    
    // Verify settings
    try testing.expectEqual(@as(u64, 4444), query.topic_id.?.num());
    try testing.expectEqual(@as(u32, 5), query.max_retry);
}


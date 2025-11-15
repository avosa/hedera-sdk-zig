const std = @import("std");
const hedera = @import("hedera");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Initialize client for testnet
    var client = try hedera.Client.forTestnet();
    defer client.deinit();

    // Set operator account from environment variables
    const operator_id_str = std.posix.getenv("HEDERA_OPERATOR_ID") orelse {
        std.log.err("HEDERA_OPERATOR_ID environment variable not set", .{});
        return;
    };
    const operator_key_str = std.posix.getenv("HEDERA_OPERATOR_KEY") orelse {
        std.log.err("HEDERA_OPERATOR_KEY environment variable not set", .{});
        return;
    };

    const operator_id = try hedera.AccountId.fromString(allocator, operator_id_str);
    const operator_key = try hedera.PrivateKey.fromString(allocator, operator_key_str);

    const operator_key_converted = try operator_key.toOperatorKey();
    _ = try client.setOperator(operator_id, operator_key_converted);

    std.log.info("Consensus Service (HCS) Example", .{});
    std.log.info("==============================", .{});

    // Example 1: Create a new topic
    std.log.info("\n1. Creating new topic...", .{});

    var topic_create_tx = try hedera.TopicCreateTransaction.init(allocator);
    defer topic_create_tx.deinit();

    _ = try topic_create_tx.setTopicMemo("Created by Hedera Zig SDK example");
    _ = try topic_create_tx.setAdminKey(hedera.Key.fromPublicKey(operator_key.getPublicKey()));
    _ = try topic_create_tx.setSubmitKey(hedera.Key.fromPublicKey(operator_key.getPublicKey()));
    _ = try topic_create_tx.setAutoRenewAccountId(operator_id);
    _ = try topic_create_tx.setAutoRenewPeriod(hedera.Duration.fromDays(90));

    var create_response = try topic_create_tx.execute(&client);
    const create_receipt = try create_response.getReceipt(&client);
    
    if (create_receipt.topic_id) |topic_id| {
        std.log.info("✓ Topic created: {}", .{topic_id});
        
        // Example 2: Query topic info
        std.log.info("\n2. Querying topic info...", .{});
        
        var topic_info_query = hedera.TopicInfoQuery.init(allocator);
        defer topic_info_query.deinit();
        
        _ = try topic_info_query.setTopicId(topic_id);
        const topic_info = try topic_info_query.execute(&client);
        
        std.log.info("✓ Topic ID: {}", .{topic_info.topic_id});
        std.log.info("✓ Topic memo: {s}", .{topic_info.topic_memo});
        std.log.info("✓ Sequence number: {}", .{topic_info.sequence_number});
        std.log.info("✓ Running hash length: {}", .{topic_info.running_hash.len});
        std.log.info("✓ Auto renew period: {} seconds", .{topic_info.auto_renew_period.seconds});
        
        // Example 3: Submit messages to topic
        std.log.info("\n3. Submitting messages to topic...", .{});
        
        const messages = [_][]const u8{
            "Hello from Hedera Zig SDK!",
            "This is message number 2",
            "Consensus service is working great!",
            "Message #4 - testing chunking",
            "Final test message from the Hedera Zig SDK example",
        };
        
        for (messages, 0..) |message, i| {
            var message_submit_tx = hedera.TopicMessageSubmitTransaction.init(allocator);
            defer message_submit_tx.deinit();
            
            _ = try message_submit_tx.setTopicId(topic_id);
            _ = try message_submit_tx.setMessage(message);
            
            var submit_response = try message_submit_tx.execute(&client);
            const submit_receipt = try submit_response.getReceipt(&client);
            
            std.log.info("✓ Message {} submitted with status: {}", .{ i + 1, submit_receipt.status });
            std.log.info("  Sequence number: {}", .{submit_receipt.topic_sequence_number});
            std.log.info("  Running hash: {} bytes", .{submit_receipt.topic_running_hash.len});
            
            // Small delay between messages
            std.time.sleep(1000000000); // 1 second
        }
        
        // Example 4: Submit a large message that will be chunked
        std.log.info("\n4. Submitting large message (will be chunked)...", .{});
        
        // Create a message larger than 1024 bytes to trigger chunking
        var large_message = std.ArrayList(u8).init(allocator);
        defer large_message.deinit();
        
        var chunk_num: u32 = 0;
        while (chunk_num < 5) : (chunk_num += 1) {
            const chunk_content = try std.fmt.allocPrint(allocator, 
                "This is chunk number {} of a large message. " ++
                "Each chunk contains exactly this much text to demonstrate " ++
                "the chunking mechanism in the Hedera Consensus Service. " ++
                "The Hedera Zig SDK automatically handles message chunking " ++
                "when messages exceed the 1024 byte limit. This ensures " ++
                "that large messages can be submitted to topics without " ++
                "hitting size restrictions. The chunks are submitted in " ++
                "sequence and can be reassembled by subscribers. " ++
                "This is chunk {} out of 5 total chunks. " ++
                "Padding content to reach the desired chunk size... " ++
                "Additional padding text to make this chunk longer... " ++
                "Even more padding to ensure we exceed 1024 bytes total... " ++
                "Final padding for chunk {} " ++
                "End of chunk content.\n", .{ chunk_num + 1, chunk_num + 1, chunk_num + 1 });
            defer allocator.free(chunk_content);
            
            try large_message.appendSlice(chunk_content);
        }
        
        var large_message_tx = hedera.TopicMessageSubmitTransaction.init(allocator);
        defer large_message_tx.deinit();
        
        _ = try large_message_tx.setTopicId(topic_id);
        _ = try large_message_tx.setMessage(large_message.items);
        
        var large_submit_response = try large_message_tx.execute(&client);
        const large_submit_receipt = try large_submit_response.getReceipt(&client);
        
        std.log.info("✓ Large message submitted with status: {}", .{large_submit_receipt.status});
        std.log.info("  Message size: {} bytes", .{large_message.items.len});
        
        // Example 5: Update topic
        std.log.info("\n5. Updating topic...", .{});
        
        var topic_update_tx = try hedera.TopicUpdateTransaction.init(allocator);
        defer topic_update_tx.deinit();

        _ = try topic_update_tx.setTopicId(topic_id);
        _ = try topic_update_tx.setTopicMemo("Updated by Hedera Zig SDK example");
        _ = try topic_update_tx.setAutoRenewPeriod(hedera.Duration.fromDays(120));
        
        var update_response = try topic_update_tx.execute(&client);
        const update_receipt = try update_response.getReceipt(&client);
        
        std.log.info("✓ Topic updated with status: {}", .{update_receipt.status});
        
        // Example 6: Query updated topic info
        std.log.info("\n6. Querying updated topic info...", .{});
        
        var updated_info_query = hedera.TopicInfoQuery.init(allocator);
        defer updated_info_query.deinit();
        
        _ = try updated_info_query.setTopicId(topic_id);
        const updated_info = try updated_info_query.execute(&client);
        
        std.log.info("✓ Updated topic memo: {s}", .{updated_info.topic_memo});
        std.log.info("✓ Current sequence number: {}", .{updated_info.sequence_number});
        std.log.info("✓ Updated auto renew period: {} seconds", .{updated_info.auto_renew_period.seconds});
        
        // Example 7: Submit message with metadata
        std.log.info("\n7. Submitting message with metadata...", .{});
        
        const json_message = 
            \\{
            \\  "type": "sensor_data",
            \\  "device_id": "sensor_001",
            \\  "timestamp": "2024-01-15T10:30:00Z",
            \\  "temperature": 23.5,
            \\  "humidity": 60.2,
            \\  "location": {
            \\    "lat": 40.7128,
            \\    "lng": -74.0060
            \\  }
            \\}
        ;
        
        var json_submit_tx = hedera.TopicMessageSubmitTransaction.init(allocator);
        defer json_submit_tx.deinit();
        
        _ = try json_submit_tx.setTopicId(topic_id);
        _ = try json_submit_tx.setMessage(json_message);
        
        var json_response = try json_submit_tx.execute(&client);
        const json_receipt = try json_response.getReceipt(&client);
        
        std.log.info("✓ JSON message submitted with status: {}", .{json_receipt.status});
        
        // Example 8: Submit binary data
        std.log.info("\n8. Submitting binary data...", .{});
        
        const binary_data = [_]u8{ 0xFF, 0xFE, 0xFD, 0xFC, 0x00, 0x01, 0x02, 0x03, 
                                   0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B };
        
        var binary_submit_tx = hedera.TopicMessageSubmitTransaction.init(allocator);
        defer binary_submit_tx.deinit();
        
        _ = try binary_submit_tx.setTopicId(topic_id);
        _ = try binary_submit_tx.setMessage(&binary_data);
        
        var binary_response = try binary_submit_tx.execute(&client);
        const binary_receipt = try binary_response.getReceipt(&client);
        
        std.log.info("✓ Binary data submitted with status: {}", .{binary_receipt.status});
        std.log.info("  Binary data length: {} bytes", .{binary_data.len});
        
        // Example 9: Final topic info query
        std.log.info("\n9. Final topic state...", .{});
        
        var final_info_query = hedera.TopicInfoQuery.init(allocator);
        defer final_info_query.deinit();
        
        _ = try final_info_query.setTopicId(topic_id);
        const final_info = try final_info_query.execute(&client);
        
        std.log.info("✓ Final sequence number: {}", .{final_info.sequence_number});
        std.log.info("✓ Total messages submitted: {}", .{final_info.sequence_number});
        
        // Example 10: Delete topic
        std.log.info("\n10. Deleting topic...", .{});
        
        var topic_delete_tx = try hedera.TopicDeleteTransaction.init(allocator);
        defer topic_delete_tx.deinit();

        _ = try topic_delete_tx.setTopicId(topic_id);
        
        var delete_response = try topic_delete_tx.execute(&client);
        const delete_receipt = try delete_response.getReceipt(&client);
        
        std.log.info("✓ Topic deleted with status: {}", .{delete_receipt.status});
        
    } else {
        std.log.err("Failed to get topic ID from receipt", .{});
    }
    
    std.log.info("\nConsensus service example completed successfully!", .{});
}
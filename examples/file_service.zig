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
    client.setOperator(operator_id, operator_key_converted);

    std.log.info("File Service Example", .{});
    std.log.info("===================", .{});

    // Example 1: Create a file with initial content
    std.log.info("\n1. Creating file with initial content...", .{});
    
    const initial_content = "Hello from Hedera File Service!\nThis is the initial content of our file.\nCreated by the Hedera Zig SDK example.";
    
    var file_create_tx = hedera.FileCreateTransaction.init(allocator);
    defer file_create_tx.deinit();
    
    try file_create_tx.setContents(initial_content);
    try file_create_tx.addKey(operator_key.getPublicKey());
    try file_create_tx.setMemo("Created by Hedera Zig SDK example");
    try file_create_tx.setExpirationTime(hedera.Timestamp.fromUnixSeconds(std.time.timestamp() + 7776000)); // 90 days
    
    const create_response = try file_create_tx.execute(&client);
    const create_receipt = try create_response.getReceipt(&client);
    
    if (create_receipt.file_id) |file_id| {
        std.log.info("✓ File created: {}", .{file_id});
        
        // Example 2: Query file info
        std.log.info("\n2. Querying file info...", .{});
        
        var file_info_query = hedera.FileInfoQuery.init(allocator);
        defer file_info_query.deinit();
        
        try file_info_query.setFileId(file_id);
        const file_info = try file_info_query.execute(&client);
        
        std.log.info("✓ File ID: {}", .{file_info.file_id});
        std.log.info("✓ File size: {} bytes", .{file_info.size});
        std.log.info("✓ File memo: {s}", .{file_info.file_memo});
        std.log.info("✓ Expiration time: {}", .{file_info.expiration_time.seconds});
        std.log.info("✓ Deleted: {}", .{file_info.deleted});
        std.log.info("✓ Number of keys: {}", .{file_info.keys.len});
        
        // Example 3: Query file contents
        std.log.info("\n3. Querying file contents...", .{});
        
        var file_contents_query = hedera.FileContentsQuery.init(allocator);
        defer file_contents_query.deinit();
        
        try file_contents_query.setFileId(file_id);
        const file_contents = try file_contents_query.execute(&client);
        
        std.log.info("✓ File contents retrieved: {} bytes", .{file_contents.contents.len});
        std.log.info("✓ Content preview: {s}", .{file_contents.contents[0..@min(50, file_contents.contents.len)]});
        
        // Example 4: Append content to file
        std.log.info("\n4. Appending content to file...", .{});
        
        const append_content = "\n\nThis content was appended to the file.\nAppend operation #1 via Hedera Zig SDK.";
        
        var file_append_tx = hedera.FileAppendTransaction.init(allocator);
        defer file_append_tx.deinit();
        
        try file_append_tx.setFileId(file_id);
        try file_append_tx.setContents(append_content);
        
        const append_response = try file_append_tx.execute(&client);
        const append_receipt = try append_response.getReceipt(&client);
        
        std.log.info("✓ Content appended with status: {}", .{append_receipt.status});
        
        // Example 5: Query updated file info
        std.log.info("\n5. Querying updated file info...", .{});
        
        var updated_info_query = hedera.FileInfoQuery.init(allocator);
        defer updated_info_query.deinit();
        
        try updated_info_query.setFileId(file_id);
        const updated_info = try updated_info_query.execute(&client);
        
        std.log.info("✓ Updated file size: {} bytes", .{updated_info.size});
        
        // Example 6: Query updated file contents
        std.log.info("\n6. Querying updated file contents...", .{});
        
        var updated_contents_query = hedera.FileContentsQuery.init(allocator);
        defer updated_contents_query.deinit();
        
        try updated_contents_query.setFileId(file_id);
        const updated_contents = try updated_contents_query.execute(&client);
        
        std.log.info("✓ Updated file contents: {} bytes", .{updated_contents.contents.len});
        
        // Show the last part to confirm append worked
        if (updated_contents.contents.len > 50) {
            const start_idx = updated_contents.contents.len - 50;
            std.log.info("✓ Content suffix: {s}", .{updated_contents.contents[start_idx..]});
        }
        
        // Example 7: Append large content (testing chunking)
        std.log.info("\n7. Appending large content...", .{});
        
        var large_content = std.ArrayList(u8).init(allocator);
        defer large_content.deinit();
        
        try large_content.appendSlice("\n\n=== LARGE CONTENT SECTION ===\n");
        
        var chunk_idx: u32 = 0;
        while (chunk_idx < 10) : (chunk_idx += 1) {
            const chunk_text = try std.fmt.allocPrint(allocator,
                "This is chunk #{} of large content being appended to the file. " ++
                "Each chunk contains substantial text to test the file append " ++
                "functionality with larger data. The Hedera File Service can " ++
                "handle files up to approximately 1024 KB in size. This chunk " ++
                "is designed to be substantial enough to test the append mechanism " ++
                "with meaningful data. Chunk #{} completed successfully.\n",
                .{ chunk_idx + 1, chunk_idx + 1 });
            defer allocator.free(chunk_text);
            
            try large_content.appendSlice(chunk_text);
        }
        
        try large_content.appendSlice("=== END OF LARGE CONTENT ===\n");
        
        var large_append_tx = hedera.FileAppendTransaction.init(allocator);
        defer large_append_tx.deinit();
        
        try large_append_tx.setFileId(file_id);
        try large_append_tx.setContents(large_content.items);
        
        const large_append_response = try large_append_tx.execute(&client);
        const large_append_receipt = try large_append_response.getReceipt(&client);
        
        std.log.info("✓ Large content appended with status: {}", .{large_append_receipt.status});
        std.log.info("✓ Appended content size: {} bytes", .{large_content.items.len});
        
        // Example 8: Query final file info
        std.log.info("\n8. Querying final file info...", .{});
        
        var final_info_query = hedera.FileInfoQuery.init(allocator);
        defer final_info_query.deinit();
        
        try final_info_query.setFileId(file_id);
        const final_info = try final_info_query.execute(&client);
        
        std.log.info("✓ Final file size: {} bytes", .{final_info.size});
        
        // Example 9: Create a binary file
        std.log.info("\n9. Creating binary file...", .{});
        
        const binary_data = [_]u8{
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR chunk start
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // 1x1 pixel
            0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, // RGB, no compression
            0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, // IDAT chunk
            0x54, 0x08, 0x99, 0x01, 0x01, 0x00, 0x00, 0xFF, // Compressed data
            0xFF, 0x00, 0x00, 0x00, 0x02, 0x00, 0x01, 0xE5, // More data
            0x27, 0xDE, 0xFC, 0x00, 0x00, 0x00, 0x00, 0x49, // IEND chunk
            0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82          // PNG end
        };
        
        var binary_create_tx = hedera.FileCreateTransaction.init(allocator);
        defer binary_create_tx.deinit();
        
        try binary_create_tx.setContents(&binary_data);
        try binary_create_tx.addKey(operator_key.getPublicKey());
        try binary_create_tx.setMemo("Binary PNG file created by Hedera Zig SDK");
        try binary_create_tx.setExpirationTime(hedera.Timestamp.fromUnixSeconds(std.time.timestamp() + 7776000));
        
        const binary_response = try binary_create_tx.execute(&client);
        const binary_receipt = try binary_response.getReceipt(&client);
        
        if (binary_receipt.file_id) |binary_file_id| {
            std.log.info("✓ Binary file created: {}", .{binary_file_id});
            
            // Query binary file info
            var binary_info_query = hedera.FileInfoQuery.init(allocator);
            defer binary_info_query.deinit();
            
            try binary_info_query.setFileId(binary_file_id);
            const binary_info = try binary_info_query.execute(&client);
            
            std.log.info("✓ Binary file size: {} bytes", .{binary_info.size});
            
            // Delete binary file
            var binary_delete_tx = hedera.FileDeleteTransaction.init(allocator);
            defer binary_delete_tx.deinit();
            
            try binary_delete_tx.setFileId(binary_file_id);
            
            const binary_delete_response = try binary_delete_tx.execute(&client);
            const binary_delete_receipt = try binary_delete_response.getReceipt(&client);
            
            std.log.info("✓ Binary file deleted with status: {}", .{binary_delete_receipt.status});
        }
        
        // Example 10: Delete the main file
        std.log.info("\n10. Deleting main file...", .{});
        
        var file_delete_tx = hedera.FileDeleteTransaction.init(allocator);
        defer file_delete_tx.deinit();
        
        try file_delete_tx.setFileId(file_id);
        
        const delete_response = try file_delete_tx.execute(&client);
        const delete_receipt = try delete_response.getReceipt(&client);
        
        std.log.info("✓ File deleted with status: {}", .{delete_receipt.status});
        
        // Example 11: Verify file deletion
        std.log.info("\n11. Verifying file deletion...", .{});
        
        var verify_info_query = hedera.FileInfoQuery.init(allocator);
        defer verify_info_query.deinit();
        
        try verify_info_query.setFileId(file_id);
        
        // This should show the file as deleted
        if (verify_info_query.execute(&client)) |verify_info| {
            std.log.info("✓ File deletion verified - deleted: {}", .{verify_info.deleted});
        } else |err| {
            std.log.info("✓ File successfully deleted (query failed as expected): {}", .{err});
        }
        
    } else {
        std.log.err("Failed to get file ID from receipt", .{});
    }
    
    std.log.info("\nFile service example completed successfully!", .{});
}
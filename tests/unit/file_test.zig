const std = @import("std");
const testing = std.testing;
const hedera = @import("hedera");

test "File create transaction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.FileCreateTransaction.init(allocator);
    defer tx.deinit();
    
    // Set file contents
    const contents = "Hello, Hedera File Service!";
    try tx.setContents(contents);
    
    // Generate keys
    var key1 = try hedera.generate_private_key(allocator);
    defer key1.deinit();
    
    var key2 = try hedera.generate_private_key(allocator);
    defer key2.deinit();
    
    // Create key list
    var key_list = hedera.KeyList.init(allocator);
    defer key_list.deinit();
    key_list.threshold = 1;
    
    try key_list.add(hedera.Key.fromPublicKey(key1.getPublicKey()));
    try key_list.add(hedera.Key.fromPublicKey(key2.getPublicKey()));
    
    // Set keys
    try tx.setKeys(hedera.Key.fromKeyList(key_list));
    
    // Set expiration time
    const expiration = hedera.Timestamp.fromSeconds(1234567890);
    try tx.setExpirationTime(expiration);
    
    // Set memo
    try tx.setFileMemo("Test file");
    
    // Verify settings
    try testing.expectEqualStrings(contents, tx.contents);
    try testing.expect(tx.keys.items.len > 0);
    try testing.expectEqual(@as(i64, 1234567890), tx.expiration_time.?.seconds);
    try testing.expectEqualStrings("Test file", tx.memo.?);
}

test "File append transaction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.FileAppendTransaction.init(allocator);
    defer tx.deinit();
    
    // Set file ID
    const file_id = hedera.FileId.init(0, 0, 111);
    try tx.setFileId(file_id);
    
    // Set contents to append
    const contents = " Additional content";
    try tx.setContents(contents);
    
    // Set chunk size for large files
    try tx.setChunkSize(4096);
    
    // Set max chunks
    try tx.setMaxChunks(5);
    
    try testing.expectEqual(@as(u64, 111), tx.file_id.?.entity.num);
    try testing.expectEqualStrings(contents, tx.contents);
    try testing.expectEqual(@as(u32, 4096), tx.chunk_size);
    try testing.expectEqual(@as(u32, 5), tx.max_chunks);
}

test "File update transaction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.FileUpdateTransaction.init(allocator);
    defer tx.deinit();
    
    // Set file ID
    const file_id = hedera.FileId.init(0, 0, 222);
    try tx.setFileId(file_id);
    
    // Update contents
    const new_contents = "Updated file contents";
    try tx.setContents(new_contents);
    
    // Update keys
    var new_key = try hedera.generate_private_key(allocator);
    defer new_key.deinit();
    try tx.setKeys(hedera.Key.fromPublicKey(new_key.getPublicKey()));
    
    // Update expiration
    const new_expiration = hedera.Timestamp.fromSeconds(2345678901);
    try tx.setExpirationTime(new_expiration);
    
    // Update memo
    try tx.setFileMemo("Updated file memo");
    
    try testing.expectEqual(@as(u64, 222), tx.file_id.?.entity.num);
    try testing.expectEqualStrings(new_contents, tx.contents.?);
    try testing.expect(tx.keys.?.items.len > 0);
    try testing.expectEqual(@as(i64, 2345678901), tx.expiration_time.?.seconds);
    try testing.expectEqualStrings("Updated file memo", tx.memo.?);
}

test "File delete transaction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.FileDeleteTransaction.init(allocator);
    defer tx.deinit();
    
    // Set file to delete
    const file_id = hedera.FileId.init(0, 0, 333);
    try tx.setFileId(file_id);
    
    try testing.expectEqual(@as(u64, 333), tx.file_id.?.entity.num);
}

test "File info structure" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var info = hedera.FileInfo.init(allocator);
    defer info.deinit();
    
    // Set file info fields
    info.file_id = hedera.FileId.init(0, 0, 444);
    info.size = 1024;
    info.expiration_time = hedera.Timestamp.fromSeconds(1234567890);
    info.deleted = false;
    
    // Set keys
    var key1 = try hedera.generate_private_key(allocator);
    defer key1.deinit();
    
    var key2 = try hedera.generate_private_key(allocator);
    defer key2.deinit();
    
    var key_list = hedera.KeyList.init(allocator);
    defer key_list.deinit();
    
    try key_list.add(hedera.Key.fromPublicKey(key1.getPublicKey()));
    try key_list.add(hedera.Key.fromPublicKey(key2.getPublicKey()));
    
    var keys_list = std.ArrayList(hedera.Key).init(allocator);
    try keys_list.append(hedera.Key.fromKeyList(key_list));
    info.keys = keys_list;
    info.memo = try allocator.dupe(u8, "File information");
    info.ledger_id = try allocator.dupe(u8, "mainnet");
    
    // Verify fields
    try testing.expectEqual(@as(u64, 444), info.file_id.entity.num);
    try testing.expectEqual(@as(i64, 1024), info.size);
    try testing.expectEqual(@as(i64, 1234567890), info.expiration_time.seconds);
    try testing.expect(!info.deleted);
    try testing.expectEqualStrings("File information", info.memo);
    try testing.expectEqualStrings("mainnet", info.ledger_id);
}

test "File contents response" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var response = hedera.FileContentsResponse.init(allocator);
    defer response.deinit();
    
    // Set file ID
    response.file_id = hedera.FileId.init(0, 0, 555);
    
    // Set contents
    const contents = "File contents from query";
    response.contents = try allocator.dupe(u8, contents);
    
    // Verify fields
    try testing.expectEqual(@as(u64, 555), response.file_id.entity.num);
    try testing.expectEqualStrings(contents, response.contents);
}

test "System file IDs" {
    // Test well-known system file IDs
    const address_book = hedera.FileId.ADDRESS_BOOK;
    const fee_schedule = hedera.FileId.FEE_SCHEDULE;
    const exchange_rates = hedera.FileId.EXCHANGE_RATES;
    
    try testing.expectEqual(@as(u64, 101), address_book.entity.num);
    try testing.expectEqual(@as(u64, 111), fee_schedule.entity.num);
    try testing.expectEqual(@as(u64, 112), exchange_rates.entity.num);
}

test "File chunking for large files" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.FileAppendTransaction.init(allocator);
    defer tx.deinit();
    
    // Create large content (10KB)
    const large_content = try allocator.alloc(u8, 10240);
    defer allocator.free(large_content);
    @memset(large_content, 'X');
    
    // Set file ID
    const file_id = hedera.FileId.init(0, 0, 666);
    try tx.setFileId(file_id);
    
    // Set large content
    try tx.setContents(large_content);
    
    // Set chunk size (4KB)
    try tx.setChunkSize(4096);
    
    // Calculate expected chunks
    const expected_chunks = (large_content.len + 4095) / 4096;
    
    try testing.expectEqual(@as(u64, 666), tx.file_id.?.entity.num);
    try testing.expectEqual(@as(usize, 10240), tx.contents.len);
    try testing.expectEqual(@as(u32, 4096), tx.chunk_size);
    try testing.expectEqual(@as(usize, 3), expected_chunks);
}

test "File transaction validation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Test file create without contents should be valid (empty file)
    var create_tx = hedera.FileCreateTransaction.init(allocator);
    defer create_tx.deinit();
    
    // Empty file is valid
    try testing.expectEqualStrings("", create_tx.contents);
    
    // Test file append without file ID should fail when executed
    var append_tx = hedera.FileAppendTransaction.init(allocator);
    defer append_tx.deinit();
    
    try append_tx.setContents("content");
    try testing.expect(append_tx.file_id == null);
    
    // Test file update without file ID should fail when executed
    var update_tx = hedera.FileUpdateTransaction.init(allocator);
    defer update_tx.deinit();
    
    try update_tx.setContents("new content");
    try testing.expect(update_tx.file_id == null);
    
    // Test file delete without file ID should fail when executed
    var delete_tx = hedera.FileDeleteTransaction.init(allocator);
    defer delete_tx.deinit();
    
    try testing.expect(delete_tx.file_id == null);
}

test "File memo limits" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.FileCreateTransaction.init(allocator);
    defer tx.deinit();
    
    // Valid memo (under 100 bytes)
    const valid_memo = "This is a valid file memo";
    try tx.setFileMemo(valid_memo);
    try testing.expectEqualStrings(valid_memo, tx.memo.?);
    
    // Long memo (exactly 100 bytes)
    const long_memo = "a" ** 100;
    try tx.setFileMemo(long_memo);
    try testing.expectEqualStrings(long_memo, tx.memo.?);
    
    // Too long memo should fail
    const too_long_memo = "a" ** 101;
    try testing.expectError(error.MemoTooLong, tx.setFileMemo(too_long_memo));
}

test "File key requirements" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.FileUpdateTransaction.init(allocator);
    defer tx.deinit();
    
    const file_id = hedera.FileId.init(0, 0, 777);
    try tx.setFileId(file_id);
    
    // Create complex key structure
    var admin_key = try hedera.generate_private_key(allocator);
    defer admin_key.deinit();
    
    var wipe_key = try hedera.generate_private_key(allocator);
    defer wipe_key.deinit();
    
    // Create threshold key
    var threshold_key = hedera.KeyList.init(allocator);
    defer threshold_key.deinit();
    threshold_key.threshold = 2;
    
    try threshold_key.add(hedera.Key.fromPublicKey(admin_key.getPublicKey()));
    try threshold_key.add(hedera.Key.fromPublicKey(wipe_key.getPublicKey()));
    
    // Add third key
    var third_key = try hedera.generate_private_key(allocator);
    defer third_key.deinit();
    try threshold_key.add(hedera.Key.fromPublicKey(third_key.getPublicKey()));
    
    // Set threshold key
    try tx.setKeys(hedera.Key.fromKeyList(threshold_key));
    
    try testing.expect(tx.keys.?.items.len > 0);
    // Keys is an ArrayList in FileUpdateTransaction
    try testing.expectEqual(@as(usize, 1), tx.keys.?.items.len);
}

test "File special contents" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.FileCreateTransaction.init(allocator);
    defer tx.deinit();
    
    // Binary contents
    const binary_content = [_]u8{ 0x00, 0xFF, 0xDE, 0xAD, 0xBE, 0xEF };
    try tx.setContents(&binary_content);
    try testing.expectEqualSlices(u8, &binary_content, tx.contents);
    
    // UTF-8 contents
    const utf8_content = "Hello 世界 🌍";
    try tx.setContents(utf8_content);
    try testing.expectEqualStrings(utf8_content, tx.contents);
    
    // Empty contents
    try tx.setContents("");
    try testing.expectEqualStrings("", tx.contents);
}
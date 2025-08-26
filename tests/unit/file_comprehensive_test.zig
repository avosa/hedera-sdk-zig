const std = @import("std");
const testing = std.testing;
const hedera = @import("hedera");

test "FileId - initialization and operations" {
    // Test standard initialization
    const file1 = hedera.FileId.init(0, 0, 111);
    try testing.expectEqual(@as(u64, 0), file1.shard);
    try testing.expectEqual(@as(u64, 0), file1.realm);
    try testing.expectEqual(@as(u64, 111), file1.file);
    
    // Test with different shard and realm
    const file2 = hedera.FileId.init(5, 10, 999999);
    try testing.expectEqual(@as(u64, 5), file2.shard);
    try testing.expectEqual(@as(u64, 10), file2.realm);
    try testing.expectEqual(@as(u64, 999999), file2.file);
    
    // Test num() helper
    try testing.expectEqual(@as(u64, 111), file1.num());
    try testing.expectEqual(@as(u64, 999999), file2.num());
    
    // Test equals
    const file3 = hedera.FileId.init(0, 0, 111);
    try testing.expect(file1.equals(file3));
    try testing.expect(!file1.equals(file2));
}

test "FileId - string conversions" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Test toString
    const file = hedera.FileId.init(1, 2, 3456);
    const str = try file.toString(allocator);
    defer allocator.free(str);
    try testing.expectEqualStrings("1.2.3456", str);
    
    // Test fromString
    const parsed = try hedera.fileIdFromString(allocator, "5.10.999");
    try testing.expectEqual(@as(u64, 5), parsed.shard);
    try testing.expectEqual(@as(u64, 10), parsed.realm);
    try testing.expectEqual(@as(u64, 999), parsed.file);
    
    // Test invalid formats
    try testing.expectError(error.InvalidFileId, hedera.fileIdFromString(allocator, "invalid"));
    try testing.expectError(error.InvalidFileId, hedera.fileIdFromString(allocator, "0.0"));
    try testing.expectError(error.InvalidFileId, hedera.fileIdFromString(allocator, ""));
}

test "FileCreateTransaction - comprehensive file creation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.fileCreateTransaction(allocator);
    defer tx.deinit();
    
    // Set file contents
    const contents = "Hello, Hedera File Service! This is a test file with some content.";
    _ = try tx.setContents(contents);
    try testing.expectEqualStrings(contents, tx.contents);
    
    // Set keys
    var key1 = try hedera.generatePrivateKey(allocator);
    defer key1.deinit();
    var key2 = try hedera.generatePrivateKey(allocator);
    defer key2.deinit();
    var key3 = try hedera.generatePrivateKey(allocator);
    defer key3.deinit();
    
    _ = try tx.addKey(hedera.Key.fromPublicKey(key1.getPublicKey()));
    _ = try tx.addKey(hedera.Key.fromPublicKey(key2.getPublicKey()));
    _ = try tx.addKey(hedera.Key.fromPublicKey(key3.getPublicKey()));
    
    try testing.expectEqual(@as(usize, 3), tx.keys.items.len);
    
    // Set expiration time
    const expiration = hedera.Timestamp.fromSeconds(1234567890);
    _ = try tx.setExpirationTime(expiration);
    try testing.expectEqual(@as(i64, 1234567890), tx.expiration_time.?.seconds);
    
    // Set memo
    _ = try tx.setMemo("Test file creation memo with special chars: ");
    try testing.expectEqualStrings("Test file creation memo with special chars: ", tx.memo.?);
    
    // Set auto renew period
    _ = try tx.setAutoRenewPeriod(hedera.Duration.fromDays(30));
    try testing.expectEqual(@as(i64, 2592000), tx.auto_renew_period.?.seconds);
    
    // Set auto renew account
    const auto_renew_account = hedera.AccountId.init(0, 0, 200);
    _ = try tx.setAutoRenewAccount(auto_renew_account);
    try testing.expectEqual(@as(u64, 200), tx.auto_renew_account.?.account);
    
    // Test transaction properties
    _ = try tx.setMaxTransactionFee(try hedera.Hbar.from(2));
    _ = try tx.setTransactionValidDuration(hedera.Duration.fromSeconds(120));
    _ = try tx.setTransactionMemo("File creation transaction");
    
    try testing.expectEqual(@as(i64, 200_000_000), tx.max_transaction_fee.?.toTinybars());
    try testing.expectEqual(@as(i64, 120), tx.transaction_valid_duration.?.seconds);
    try testing.expectEqualStrings("File creation transaction", tx.transaction_memo.?);
}

test "FileCreateTransaction - different content types" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Test with binary content
    var tx_binary = hedera.fileCreateTransaction(allocator);
    defer tx_binary.deinit();
    
    const binary_content = [_]u8{0x00, 0x01, 0x02, 0xFF, 0xFE, 0xFD};
    _ = try tx_binary.setContents(&binary_content);
    try testing.expectEqualSlices(u8, &binary_content, tx_binary.contents);
    
    // Test with JSON content
    var tx_json = hedera.fileCreateTransaction(allocator);
    defer tx_json.deinit();
    
    const json_content = 
        \\{
        \\  "name": "test",
        \\  "version": "1.0.0",
        \\  "data": {
        \\    "items": [1, 2, 3, 4, 5],
        \\    "enabled": true
        \\  }
        \\}
    ;
    _ = try tx_json.setContents(json_content);
    try testing.expectEqualStrings(json_content, tx_json.contents);
    
    // Test with large content (up to file size limits)
    var tx_large = hedera.fileCreateTransaction(allocator);
    defer tx_large.deinit();
    
    const large_content = "A" ** 1024; // 1KB
    _ = try tx_large.setContents(large_content);
    try testing.expectEqual(@as(usize, 1024), tx_large.contents.len);
    
    // Test with empty content
    var tx_empty = hedera.fileCreateTransaction(allocator);
    defer tx_empty.deinit();
    
    _ = try tx_empty.setContents("");
    try testing.expectEqualStrings("", tx_empty.contents);
}

test "FileUpdateTransaction - comprehensive file updates" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.FileUpdateTransaction.init(allocator);
    defer tx.deinit();
    
    // Set file ID
    const file_id = hedera.FileId.init(0, 0, 1000);
    _ = try tx.setFileId(file_id);
    try testing.expectEqual(@as(u64, 1000), tx.file_id.?.num());
    
    // Update contents
    const new_contents = "Updated file content with new information and data.";
    _ = try tx.setContents(new_contents);
    try testing.expectEqualStrings(new_contents, tx.contents.?);
    
    // Update keys
    var new_key1 = try hedera.generatePrivateKey(allocator);
    defer new_key1.deinit();
    var new_key2 = try hedera.generatePrivateKey(allocator);
    defer new_key2.deinit();
    
    _ = try tx.addKey(hedera.Key.fromPublicKey(new_key1.getPublicKey()));
    _ = try tx.addKey(hedera.Key.fromPublicKey(new_key2.getPublicKey()));
    
    try testing.expectEqual(@as(usize, 2), tx.keys.items.len);
    
    // Update expiration time
    const new_expiration = hedera.Timestamp.fromSeconds(9999999999);
    _ = try tx.setExpirationTime(new_expiration);
    try testing.expectEqual(@as(i64, 9999999999), tx.expiration_time.?.seconds);
    
    // Update memo
    _ = try tx.setMemo("Updated file memo FILE:");
    try testing.expectEqualStrings("Updated file memo FILE:", tx.memo.?);
    
    // Update auto renew period
    _ = try tx.setAutoRenewPeriod(hedera.Duration.fromDays(60));
    try testing.expectEqual(@as(i64, 5184000), tx.auto_renew_period.?.seconds);
    
    // Update auto renew account
    const new_auto_renew = hedera.AccountId.init(0, 0, 300);
    _ = try tx.setAutoRenewAccount(new_auto_renew);
    try testing.expectEqual(@as(u64, 300), tx.auto_renew_account.?.account);
    
    // Clear memo
    _ = try tx.clearMemo();
    try testing.expectEqual(@as(?[]const u8, null), tx.memo);
    
    // Clear contents
    _ = try tx.clearContents();
    try testing.expectEqual(@as(?[]const u8, null), tx.contents);
}

test "FileAppendTransaction - appending to existing files" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.FileAppendTransaction.init(allocator);
    defer tx.deinit();
    
    // Set file ID
    const file_id = hedera.FileId.init(0, 0, 2000);
    _ = try tx.setFileId(file_id);
    try testing.expectEqual(@as(u64, 2000), tx.file_id.?.num());
    
    // Set contents to append
    const append_contents = "\n\nThis is additional content being appended to the file.";
    _ = try tx.setContents(append_contents);
    try testing.expectEqualStrings(append_contents, tx.contents);
    
    // Test chunked appending for large content
    const chunk_size = 1024;
    const large_content = "B" ** (chunk_size * 3); // 3KB content
    
    var tx_chunked = hedera.FileAppendTransaction.init(allocator);
    defer tx_chunked.deinit();
    
    _ = try tx_chunked.setFileId(file_id);
    _ = try tx_chunked.setContents(large_content);
    _ = try tx_chunked.setChunkSize(chunk_size);
    
    try testing.expectEqual(@as(usize, chunk_size), tx_chunked.chunk_size);
    try testing.expectEqual(@as(usize, large_content.len), tx_chunked.contents.len);
}

test "FileDeleteTransaction - file deletion" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.FileDeleteTransaction.init(allocator);
    defer tx.deinit();
    
    // Set file ID
    const file_id = hedera.FileId.init(0, 0, 5000);
    _ = try tx.setFileId(file_id);
    
    try testing.expectEqual(@as(u64, 5000), tx.file_id.?.num());
    
    // Test transaction properties
    _ = try tx.setMaxTransactionFee(try hedera.Hbar.from(1));
    _ = try tx.setTransactionMemo("Deleting test file");
    
    try testing.expectEqual(@as(i64, 100_000_000), tx.max_transaction_fee.?.toTinybars());
    try testing.expectEqualStrings("Deleting test file", tx.transaction_memo.?);
}

test "FileInfo - comprehensive file information structure" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var info = hedera.FileInfo.init(allocator);
    defer info.deinit();
    
    // Set file properties
    info.file_id = hedera.FileId.init(0, 0, 1000);
    info.size = 2048;
    info.expiration_time = hedera.Timestamp.fromSeconds(1234567890);
    info.deleted = false;
    info.memo = "Test file information";
    
    // Set keys
    var key1 = try hedera.generatePrivateKey(allocator);
    defer key1.deinit();
    var key2 = try hedera.generatePrivateKey(allocator);
    defer key2.deinit();
    
    try info.keys.append(hedera.Key.fromPublicKey(key1.getPublicKey()));
    try info.keys.append(hedera.Key.fromPublicKey(key2.getPublicKey()));
    
    info.auto_renew_period = hedera.Duration.fromDays(30);
    info.auto_renew_account = hedera.AccountId.init(0, 0, 100);
    info.ledger_id = "mainnet";
    
    // Verify all fields
    try testing.expectEqual(@as(u64, 1000), info.file_id.num());
    try testing.expectEqual(@as(i64, 2048), info.size);
    try testing.expectEqual(@as(i64, 1234567890), info.expiration_time.seconds);
    try testing.expect(!info.deleted);
    try testing.expectEqualStrings("Test file information", info.memo);
    try testing.expectEqual(@as(usize, 2), info.keys.items.len);
    try testing.expectEqual(@as(i64, 2592000), info.auto_renew_period.?.seconds);
    try testing.expectEqual(@as(u64, 100), info.auto_renew_account.?.account);
    try testing.expectEqualStrings("mainnet", info.ledger_id);
}

test "FileContents - file content structure and operations" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var contents = hedera.FileContents.init(allocator);
    defer contents.deinit();
    
    // Set file ID and contents
    contents.file_id = hedera.FileId.init(0, 0, 2000);
    
    const data = "File content data with various information and binary data.";
    contents.contents = try allocator.dupe(u8, data);
    
    // Verify properties
    try testing.expectEqual(@as(u64, 2000), contents.file_id.num());
    try testing.expectEqualStrings(data, contents.contents);
    
    // Test with binary data
    var binary_contents = hedera.FileContents.init(allocator);
    defer binary_contents.deinit();
    
    binary_contents.file_id = hedera.FileId.init(0, 0, 3000);
    const binary_data = [_]u8{0x00, 0x01, 0x02, 0x03, 0xFF, 0xFE, 0xFD, 0xFC};
    binary_contents.contents = try allocator.dupe(u8, &binary_data);
    
    try testing.expectEqualSlices(u8, &binary_data, binary_contents.contents);
}

test "File - system file operations" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Use system file IDs from centralized config
    const address_book_id = hedera.SystemFiles.ADDRESS_BOOK;
    const node_details_id = hedera.SystemFiles.NODE_DETAILS;
    const fee_schedule_id = hedera.SystemFiles.FEE_SCHEDULE;
    const exchange_rates_id = hedera.SystemFiles.EXCHANGE_RATES;
    const software_version_id = hedera.SystemFiles.APPLICATION_PROPERTIES;
    const network_properties_id = hedera.SystemFiles.API_PERMISSIONS;
    const hapi_permissions_id = hedera.SystemFiles.THROTTLES;
    
    // System files are read-only and have special properties
    const system_files = [_]hedera.FileId{
        address_book_id,
        node_details_id,
        fee_schedule_id,
        exchange_rates_id,
        software_version_id,
        network_properties_id,
        hapi_permissions_id,
    };
    
    for (system_files) |system_file| {
        try testing.expect(system_file.num() >= 100 and system_file.num() <= 199);
    }
    
    // Test querying system files
    var info_query = hedera.FileInfoQuery.init(allocator);
    defer info_query.deinit();
    
    _ = try info_query.setFileId(address_book_id);
    try testing.expectEqual(@as(u64, 101), info_query.file_id.?.num());
    
    var contents_query = hedera.FileContentsQuery.init(allocator);
    defer contents_query.deinit();
    
    _ = try contents_query.setFileId(fee_schedule_id);
    try testing.expectEqual(@as(u64, 111), contents_query.file_id.?.num());
}

test "File - key management and permissions" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.fileCreateTransaction(allocator);
    defer tx.deinit();
    
    // Test different key configurations
    
    // Single key
    var single_key = try hedera.generatePrivateKey(allocator);
    defer single_key.deinit();
    
    _ = try tx.addKey(hedera.Key.fromPublicKey(single_key.getPublicKey()));
    try testing.expectEqual(@as(usize, 1), tx.keys.items.len);
    
    // Multiple keys (all required)
    var key2 = try hedera.generatePrivateKey(allocator);
    defer key2.deinit();
    var key3 = try hedera.generatePrivateKey(allocator);
    defer key3.deinit();
    
    _ = try tx.addKey(hedera.Key.fromPublicKey(key2.getPublicKey()));
    _ = try tx.addKey(hedera.Key.fromPublicKey(key3.getPublicKey()));
    try testing.expectEqual(@as(usize, 3), tx.keys.items.len);
    
    // Test key removal
    try tx.keys.clearRetainingCapacity();
    try testing.expectEqual(@as(usize, 0), tx.keys.items.len);
    
    // Test threshold key (M of N)
    var threshold_key = hedera.Key.initThresholdKey(2, allocator); // 2 of 3 required
    defer threshold_key.deinit();
    
    try threshold_key.addKey(hedera.Key.fromPublicKey(single_key.getPublicKey()));
    try threshold_key.addKey(hedera.Key.fromPublicKey(key2.getPublicKey()));
    try threshold_key.addKey(hedera.Key.fromPublicKey(key3.getPublicKey()));
    
    _ = try tx.addKey(threshold_key);
    try testing.expectEqual(@as(usize, 1), tx.keys.items.len);
}

test "File - transaction lifecycle and state management" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create file transaction
    var create_tx = hedera.fileCreateTransaction(allocator);
    defer create_tx.deinit();
    
    const initial_content = "Initial file content.";
    _ = try create_tx.setContents(initial_content);
    
    var key = try hedera.generatePrivateKey(allocator);
    defer key.deinit();
    _ = try create_tx.addKey(hedera.Key.fromPublicKey(key.getPublicKey()));
    
    // Update file transaction
    var update_tx = hedera.FileUpdateTransaction.init(allocator);
    defer update_tx.deinit();
    
    const file_id = hedera.FileId.init(0, 0, 1000);
    _ = try update_tx.setFileId(file_id);
    
    const updated_content = "Updated file content with new information.";
    _ = try update_tx.setContents(updated_content);
    
    // Append to file transaction
    var append_tx = hedera.FileAppendTransaction.init(allocator);
    defer append_tx.deinit();
    
    _ = try append_tx.setFileId(file_id);
    const append_content = "\nAppended content.";
    _ = try append_tx.setContents(append_content);
    
    // Delete file transaction
    var delete_tx = hedera.FileDeleteTransaction.init(allocator);
    defer delete_tx.deinit();
    
    _ = try delete_tx.setFileId(file_id);
    
    // Verify transaction sequence
    try testing.expectEqualStrings(initial_content, create_tx.contents);
    try testing.expectEqualStrings(updated_content, update_tx.contents.?);
    try testing.expectEqualStrings(append_content, append_tx.contents);
    try testing.expectEqual(@as(u64, 1000), delete_tx.file_id.?.num());
}

test "File - serialization and network operations" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.fileCreateTransaction(allocator);
    defer tx.deinit();
    
    // Set up transaction
    const contents = "Serialization test content with special characters: àáâãäå";
    _ = try tx.setContents(contents);
    
    var key = try hedera.generatePrivateKey(allocator);
    defer key.deinit();
    _ = try tx.addKey(hedera.Key.fromPublicKey(key.getPublicKey()));
    
    _ = try tx.setMemo("Serialization test");
    _ = try tx.setMaxTransactionFee(try hedera.Hbar.from(2));
    
    const tx_id = hedera.TransactionId.generate(hedera.AccountId.init(0, 0, 100));
    _ = try tx.setTransactionId(tx_id);
    
    // Serialize to bytes
    const bytes = try tx.toBytes(allocator);
    defer allocator.free(bytes);
    
    try testing.expect(bytes.len > 0);
    
    // Deserialize from bytes
    var tx2 = try hedera.FileCreateTransaction.fromBytes(allocator, bytes);
    defer tx2.deinit();
    
    // Verify deserialized transaction
    try testing.expectEqualStrings(contents, tx2.contents);
    try testing.expectEqualStrings("Serialization test", tx2.memo.?);
    try testing.expectEqual(@as(usize, 1), tx2.keys.items.len);
    try testing.expectEqual(@as(u64, 100), tx2.transaction_id.?.account_id.account);
}

test "File - error handling and edge cases" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Test empty file creation
    var empty_tx = hedera.fileCreateTransaction(allocator);
    defer empty_tx.deinit();
    
    _ = try empty_tx.setContents("");
    try testing.expectEqualStrings("", empty_tx.contents);
    
    // Test maximum content size (note: actual limits depend on network)
    var large_tx = hedera.fileCreateTransaction(allocator);
    defer large_tx.deinit();
    
    const max_content = "A" ** 4096; // 4KB test
    _ = try large_tx.setContents(max_content);
    try testing.expectEqual(@as(usize, 4096), large_tx.contents.len);
    
    // Test file operations without required fields
    var incomplete_tx = hedera.FileUpdateTransaction.init(allocator);
    defer incomplete_tx.deinit();
    
    // Should fail validation without file ID
    try testing.expectError(error.MissingFileId, incomplete_tx.validate());
    
    // Set file ID and should pass
    _ = try incomplete_tx.setFileId(hedera.FileId.init(0, 0, 1000));
    try incomplete_tx.validate();
    
    // Test with invalid file IDs
    const invalid_file_id = hedera.FileId.init(999, 999, 999999);
    _ = try incomplete_tx.setFileId(invalid_file_id);
    try testing.expectEqual(@as(u64, 999), incomplete_tx.file_id.?.shard);
    
    // Test memo length limits (100 bytes)
    var memo_tx = hedera.fileCreateTransaction(allocator);
    defer memo_tx.deinit();
    
    const long_memo = "a" ** 100;
    _ = try memo_tx.setMemo(long_memo);
    try testing.expectEqual(@as(usize, 100), memo_tx.memo.?.len);
    
    // Test clearing memo
    _ = try memo_tx.clearMemo();
    try testing.expectEqual(@as(?[]const u8, null), memo_tx.memo);
}

test "File - query operations and responses" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Test file info query
    var info_query = hedera.FileInfoQuery.init(allocator);
    defer info_query.deinit();
    
    const file_id = hedera.FileId.init(0, 0, 2000);
    _ = try info_query.setFileId(file_id);
    
    // Configure query
    _ = try info_query.setMaxRetry(3);
    _ = try info_query.setRequestTimeout(hedera.Duration.fromSeconds(30));
    
    try testing.expectEqual(@as(u64, 2000), info_query.file_id.?.num());
    try testing.expectEqual(@as(u32, 3), info_query.max_retry);
    
    // Test file contents query
    var contents_query = hedera.FileContentsQuery.init(allocator);
    defer contents_query.deinit();
    
    _ = try contents_query.setFileId(file_id);
    _ = try contents_query.setMaxQueryPayment(try hedera.Hbar.from(1));
    
    try testing.expectEqual(@as(u64, 2000), contents_query.file_id.?.num());
    
    // Test query cost estimation
    var client = try hedera.Client.forTestnet();
    defer client.deinit();
    
    var operator_key = try hedera.generatePrivateKey(allocator);
    defer operator_key.deinit();
    const op_key = try operator_key.toOperatorKey();
    _ = try client.setOperator(hedera.AccountId.init(0, 0, 100), op_key);
    
    const cost = try contents_query.getCost(&client);
    try testing.expect(cost.toTinybars() >= 0);
}

test "File - chunked operations for large files" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Test chunked file append
    var append_tx = hedera.FileAppendTransaction.init(allocator);
    defer append_tx.deinit();
    
    const file_id = hedera.FileId.init(0, 0, 3000);
    _ = try append_tx.setFileId(file_id);
    
    // Create large content that needs chunking
    const chunk_size = 1024;
    const total_size = chunk_size * 5; // 5KB
    const large_content = "X" ** total_size;
    
    _ = try append_tx.setContents(large_content);
    _ = try append_tx.setChunkSize(chunk_size);
    _ = try append_tx.setMaxChunks(10);
    
    try testing.expectEqual(@as(usize, total_size), append_tx.contents.len);
    try testing.expectEqual(@as(usize, chunk_size), append_tx.chunk_size);
    try testing.expectEqual(@as(u32, 10), append_tx.max_chunks);
    
    // Calculate expected number of chunks
    const expected_chunks = (total_size + chunk_size - 1) / chunk_size;
    try testing.expectEqual(@as(usize, 5), expected_chunks);
    
    // Test chunked update
    var update_tx = hedera.FileUpdateTransaction.init(allocator);
    defer update_tx.deinit();
    
    _ = try update_tx.setFileId(file_id);
    _ = try update_tx.setContents(large_content);
    _ = try update_tx.setChunkSize(chunk_size);
    
    try testing.expectEqual(@as(usize, total_size), update_tx.contents.?.len);
}

test "File - network file system integration" {
    // Use centralized config for network files
    const mainnet_files = hedera.NetworkFiles.mainnet;
    const testnet_files = hedera.NetworkFiles.testnet;
    const previewnet_files = hedera.NetworkFiles.previewnet;
    
    // All networks use same system file IDs
    try testing.expectEqual(mainnet_files.address_book.num(), testnet_files.address_book.num());
    try testing.expectEqual(testnet_files.fee_schedule.num(), previewnet_files.fee_schedule.num());
    
    // Test user file ID ranges (typically > 1000)
    const user_file = hedera.FileId.init(0, 0, 10000);
    try testing.expect(user_file.num() > 1000);
    
    // Test contract bytecode files (typically very large IDs)
    const contract_bytecode = hedera.FileId.init(0, 0, 999999999);
    try testing.expect(contract_bytecode.num() > 1000000);
}
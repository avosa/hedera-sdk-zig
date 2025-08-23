const std = @import("std");
const testing = std.testing;
const hedera = @import("hedera");

test "FileCreateTransaction factory creates valid instance" {
    const allocator = testing.allocator;
    
    // Create transaction using factory
    const tx = hedera.newFileCreateTransaction(allocator);
    defer tx.deinit();
    
    // Verify it's properly initialized
    try testing.expect(tx.expiration_time == null);
    try testing.expectEqual(tx.keys.items.len, 0);
    try testing.expectEqualStrings(tx.contents, "");
    try testing.expect(tx.memo == null);
}

test "FileCreateTransaction basic file creation" {
    const allocator = testing.allocator;
    
    const tx = hedera.newFileCreateTransaction(allocator);
    defer tx.deinit();
    
    // Set file contents
    const content = "Hello, Hedera File System!";
    _ = try tx.setContents(content);
    try testing.expectEqualStrings(tx.contents, content);
    
    // Set file memo
    _ = try tx.setMemo("Test file memo");
    try testing.expectEqualStrings(tx.memo.?, "Test file memo");
    
    // Set expiration time
    const expiration = hedera.Timestamp{
        .seconds = 1234567890,
        .nanos = 500000000,
    };
    _ = try tx.setExpirationTime(expiration);
    try testing.expectEqual(tx.expiration_time.?.seconds, expiration.seconds);
    try testing.expectEqual(tx.expiration_time.?.nanos, expiration.nanos);
}

test "FileCreateTransaction with single key" {
    const allocator = testing.allocator;
    
    const tx = hedera.newFileCreateTransaction(allocator);
    defer tx.deinit();
    
    // Create a test key
    const private_key = try hedera.Ed25519PrivateKey.generate();
    defer private_key.deinit();
    const public_key = private_key.getPublicKey();
    const key = hedera.Key.fromPublicKey(public_key);
    
    // Set single key
    _ = try tx.setKeys(key);
    try testing.expectEqual(tx.keys.items.len, 1);
    
    // Add another key
    const private_key2 = try hedera.Ed25519PrivateKey.generate();
    defer private_key2.deinit();
    const public_key2 = private_key2.getPublicKey();
    const key2 = hedera.Key.fromPublicKey(public_key2);
    
    try tx.addKey(key2);
    try testing.expectEqual(tx.keys.items.len, 2);
}

test "FileCreateTransaction with multiple keys" {
    const allocator = testing.allocator;
    
    const tx = hedera.newFileCreateTransaction(allocator);
    defer tx.deinit();
    
    // Create test keys
    const private_key1 = try hedera.Ed25519PrivateKey.generate();
    defer private_key1.deinit();
    const private_key2 = try hedera.Ed25519PrivateKey.generate();
    defer private_key2.deinit();
    const private_key3 = try hedera.Ed25519PrivateKey.generate();
    defer private_key3.deinit();
    
    const keys = [_]hedera.Key{
        hedera.Key.fromPublicKey(private_key1.getPublicKey()),
        hedera.Key.fromPublicKey(private_key2.getPublicKey()),
        hedera.Key.fromPublicKey(private_key3.getPublicKey()),
    };
    
    // Set key array
    _ = try tx.setKeysArray(&keys);
    try testing.expectEqual(tx.keys.items.len, 3);
}

test "FileCreateTransaction content size validation" {
    const allocator = testing.allocator;
    
    const tx = hedera.newFileCreateTransaction(allocator);
    defer tx.deinit();
    
    // Test valid content
    const valid_content = "Valid file content";
    _ = try tx.setContents(valid_content);
    try testing.expectEqualStrings(tx.contents, valid_content);
    
    // Test oversized content
    const large_content = try allocator.alloc(u8, hedera.MAX_FILE_SIZE + 1);
    defer allocator.free(large_content);
    @memset(large_content, 'A');
    
    const result = tx.setContents(large_content);
    try testing.expectError(hedera.errors.HederaError.MaxFileSizeExceeded, result);
    
    // Test content at max size
    const max_content = large_content[0..hedera.MAX_FILE_SIZE];
    _ = try tx.setContents(max_content);
    try testing.expectEqual(tx.contents.len, hedera.MAX_FILE_SIZE);
}

test "FileCreateTransaction memo validation" {
    const allocator = testing.allocator;
    
    const tx = hedera.newFileCreateTransaction(allocator);
    defer tx.deinit();
    
    // Test valid memo
    const valid_memo = "Valid memo";
    _ = try tx.setMemo(valid_memo);
    try testing.expectEqualStrings(tx.memo.?, valid_memo);
    
    // Test memo that's too long
    const long_memo = "A" ** 101; // 101 characters
    const result = tx.setMemo(long_memo);
    try testing.expectError(hedera.errors.HederaError.MemoTooLong, result);
    
    // Test memo at max length (100 characters)
    const max_memo = "B" ** 100;
    _ = try tx.setMemo(max_memo);
    try testing.expectEqualStrings(tx.memo.?, max_memo);
}

test "FileCreateTransaction setFileMemo alias" {
    const allocator = testing.allocator;
    
    const tx = hedera.newFileCreateTransaction(allocator);
    defer tx.deinit();
    
    // Test setFileMemo alias method
    _ = try tx.setFileMemo("Alias memo test");
    try testing.expectEqualStrings(tx.memo.?, "Alias memo test");
}

test "FileCreateTransaction validation" {
    const allocator = testing.allocator;
    
    const tx = hedera.newFileCreateTransaction(allocator);
    defer tx.deinit();
    
    // Test execution without keys (should fail)
    const result = tx.execute(null);
    try testing.expectError(error.KeyRequired, result);
    
    // Add a key
    const private_key = try hedera.Ed25519PrivateKey.generate();
    defer private_key.deinit();
    const key = hedera.Key.fromPublicKey(private_key.getPublicKey());
    _ = try tx.setKeys(key);
    
    // Now execution should not fail due to missing keys
    try testing.expectEqual(tx.keys.items.len, 1);
}

test "FileCreateTransaction default expiration" {
    const allocator = testing.allocator;
    
    const tx = hedera.newFileCreateTransaction(allocator);
    defer tx.deinit();
    
    // Add required key
    const private_key = try hedera.Ed25519PrivateKey.generate();
    defer private_key.deinit();
    const key = hedera.Key.fromPublicKey(private_key.getPublicKey());
    _ = try tx.setKeys(key);
    
    // Initially no expiration time
    try testing.expect(tx.expiration_time == null);
    
    // Execute should set default expiration (90 days)
    // Note: This would fail in real execution, but we test the logic path
    _ = tx.execute(null) catch {};
    
    // Check if expiration was set
    try testing.expect(tx.expiration_time != null);
}

test "FileCreateTransaction freezeWith" {
    const allocator = testing.allocator;
    
    const tx = hedera.newFileCreateTransaction(allocator);
    defer tx.deinit();
    
    // Set required fields
    const private_key = try hedera.Ed25519PrivateKey.generate();
    defer private_key.deinit();
    const key = hedera.Key.fromPublicKey(private_key.getPublicKey());
    _ = try tx.setKeys(key);
    _ = try tx.setContents("Test file");
    
    // Freeze without client (should use defaults)
    try tx.freezeWith(null);
    
    // Verify transaction is frozen
    try testing.expect(tx.base.frozen);
    try testing.expect(tx.base.transaction_id != null);
}

test "FileCreateTransaction builds transaction body" {
    const allocator = testing.allocator;
    
    const tx = hedera.newFileCreateTransaction(allocator);
    defer tx.deinit();
    
    // Configure transaction
    const private_key = try hedera.Ed25519PrivateKey.generate();
    defer private_key.deinit();
    const key = hedera.Key.fromPublicKey(private_key.getPublicKey());
    _ = try tx.setKeys(key);
    _ = try tx.setContents("Test file content");
    _ = try tx.setMemo("Test memo");
    
    const expiration = hedera.Timestamp{
        .seconds = 2000000000,
        .nanos = 0,
    };
    _ = try tx.setExpirationTime(expiration);
    
    // Set transaction ID
    tx.base.transaction_id = hedera.TransactionId.generate(hedera.AccountId.init(0, 0, 2));
    
    // Build transaction body
    const body_bytes = try tx.buildTransactionBody();
    defer allocator.free(body_bytes);
    
    // Verify body was built
    try testing.expect(body_bytes.len > 0);
    
    // Parse to verify structure
    var reader = hedera.ProtoReader.init(body_bytes);
    var found_file_create = false;
    
    while (reader.hasMore()) {
        const tag = try reader.readTag();
        if (tag.field_number == 19) { // fileCreate field
            found_file_create = true;
            break;
        }
        try reader.skipField(tag.wire_type);
    }
    
    try testing.expect(found_file_create);
}

test "FileCreateTransaction empty file creation" {
    const allocator = testing.allocator;
    
    const tx = hedera.newFileCreateTransaction(allocator);
    defer tx.deinit();
    
    // Create empty file
    const private_key = try hedera.Ed25519PrivateKey.generate();
    defer private_key.deinit();
    const key = hedera.Key.fromPublicKey(private_key.getPublicKey());
    _ = try tx.setKeys(key);
    _ = try tx.setContents("");
    
    // Should work with empty contents
    try testing.expectEqualStrings(tx.contents, "");
    try testing.expectEqual(tx.keys.items.len, 1);
}

test "FileCreateTransaction with binary content" {
    const allocator = testing.allocator;
    
    const tx = hedera.newFileCreateTransaction(allocator);
    defer tx.deinit();
    
    // Create binary content
    const binary_content = [_]u8{ 0x00, 0x01, 0x02, 0x03, 0xFF, 0xFE, 0xFD };
    _ = try tx.setContents(&binary_content);
    
    try testing.expectEqual(tx.contents.len, binary_content.len);
    try testing.expectEqualSlices(u8, tx.contents, &binary_content);
}

test "FileCreateTransaction frozen state protection" {
    const allocator = testing.allocator;
    
    const tx = hedera.newFileCreateTransaction(allocator);
    defer tx.deinit();
    
    // Manually freeze the transaction
    tx.base.frozen = true;
    
    // Verify all setters fail when frozen
    const expiration = hedera.Timestamp{ .seconds = 1234567890, .nanos = 0 };
    const exp_result = tx.setExpirationTime(expiration);
    try testing.expectError(hedera.errors.HederaError.TransactionIsFrozen, exp_result);
    
    const private_key = try hedera.Ed25519PrivateKey.generate();
    defer private_key.deinit();
    const key = hedera.Key.fromPublicKey(private_key.getPublicKey());
    const key_result = tx.setKeys(key);
    try testing.expectError(hedera.errors.HederaError.TransactionIsFrozen, key_result);
    
    const add_key_result = tx.addKey(key);
    try testing.expectError(hedera.errors.HederaError.TransactionIsFrozen, add_key_result);
    
    const content_result = tx.setContents("test");
    try testing.expectError(hedera.errors.HederaError.TransactionIsFrozen, content_result);
    
    const memo_result = tx.setMemo("test memo");
    try testing.expectError(hedera.errors.HederaError.TransactionIsFrozen, memo_result);
}

test "FileCreateTransaction key array replacement" {
    const allocator = testing.allocator;
    
    const tx = hedera.newFileCreateTransaction(allocator);
    defer tx.deinit();
    
    // Add initial key
    const private_key1 = try hedera.Ed25519PrivateKey.generate();
    defer private_key1.deinit();
    const key1 = hedera.Key.fromPublicKey(private_key1.getPublicKey());
    try tx.addKey(key1);
    try testing.expectEqual(tx.keys.items.len, 1);
    
    // Replace with new key array
    const private_key2 = try hedera.Ed25519PrivateKey.generate();
    defer private_key2.deinit();
    const private_key3 = try hedera.Ed25519PrivateKey.generate();
    defer private_key3.deinit();
    
    const new_keys = [_]hedera.Key{
        hedera.Key.fromPublicKey(private_key2.getPublicKey()),
        hedera.Key.fromPublicKey(private_key3.getPublicKey()),
    };
    
    _ = try tx.setKeysArray(&new_keys);
    try testing.expectEqual(tx.keys.items.len, 2);
}

test "FileCreateTransaction constants validation" {
    // Verify constants are reasonable
    try testing.expect(hedera.MAX_FILE_SIZE > 0);
    try testing.expect(hedera.MAX_FILE_SIZE <= 10 * 1024 * 1024); // 10MB upper bound
    try testing.expect(hedera.MAX_CHUNK_SIZE > 0);
    try testing.expect(hedera.MAX_CHUNK_SIZE <= hedera.MAX_FILE_SIZE);
}

test "FileCreateTransaction complex scenario" {
    const allocator = testing.allocator;
    
    const tx = hedera.newFileCreateTransaction(allocator);
    defer tx.deinit();
    
    // Complex file with multiple keys, content, memo, and expiration
    const private_key1 = try hedera.Ed25519PrivateKey.generate();
    defer private_key1.deinit();
    const private_key2 = try hedera.Ed25519PrivateKey.generate();
    defer private_key2.deinit();
    
    const keys = [_]hedera.Key{
        hedera.Key.fromPublicKey(private_key1.getPublicKey()),
        hedera.Key.fromPublicKey(private_key2.getPublicKey()),
    };
    
    _ = try tx.setKeysArray(&keys);
    _ = try tx.setContents("Complex file with multiple signatures required");
    _ = try tx.setMemo("Multi-sig file");
    
    const future_time = hedera.Timestamp{
        .seconds = 2147483647, // Year 2038
        .nanos = 999999999,
    };
    _ = try tx.setExpirationTime(future_time);
    
    // Verify all fields are set correctly
    try testing.expectEqual(tx.keys.items.len, 2);
    try testing.expectEqualStrings(tx.contents, "Complex file with multiple signatures required");
    try testing.expectEqualStrings(tx.memo.?, "Multi-sig file");
    try testing.expectEqual(tx.expiration_time.?.seconds, future_time.seconds);
    try testing.expectEqual(tx.expiration_time.?.nanos, future_time.nanos);
}

test "FileCreateTransaction edge cases" {
    const allocator = testing.allocator;
    
    const tx = hedera.newFileCreateTransaction(allocator);
    defer tx.deinit();
    
    // Test overwriting keys with setKeys after adding keys
    const private_key1 = try hedera.Ed25519PrivateKey.generate();
    defer private_key1.deinit();
    const private_key2 = try hedera.Ed25519PrivateKey.generate();
    defer private_key2.deinit();
    
    // Add multiple keys
    const key1 = hedera.Key.fromPublicKey(private_key1.getPublicKey());
    const key2 = hedera.Key.fromPublicKey(private_key2.getPublicKey());
    try tx.addKey(key1);
    try tx.addKey(key2);
    try testing.expectEqual(tx.keys.items.len, 2);
    
    // setKeys should replace all keys
    const private_key3 = try hedera.Ed25519PrivateKey.generate();
    defer private_key3.deinit();
    const key3 = hedera.Key.fromPublicKey(private_key3.getPublicKey());
    _ = try tx.setKeys(key3);
    try testing.expectEqual(tx.keys.items.len, 1);
}
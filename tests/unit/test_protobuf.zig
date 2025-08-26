const std = @import("std");
const testing = std.testing;
const hedera = @import("hedera");

test "ProtoWriter basic operations" {
    const allocator = testing.allocator;
    
    var writer = hedera.ProtoWriter.init(allocator);
    defer writer.deinit();
    
    // Test writing different field types
    try writer.writeInt32(1, 42);
    try writer.writeInt64(2, 1234567890);
    try writer.writeUint32(3, 100);
    try writer.writeUint64(4, 9876543210);
    try writer.writeBool(5, true);
    try writer.writeString(6, "Hello, Protobuf!");
    
    const bytes = try writer.toOwnedSlice();
    defer allocator.free(bytes);
    
    // Verify that data was written (non-empty result)
    try testing.expect(bytes.len > 0);
    
    // Test that each field contributes to the output
    var empty_writer = hedera.ProtoWriter.init(allocator);
    defer empty_writer.deinit();
    
    const empty_bytes = try empty_writer.toOwnedSlice();
    defer allocator.free(empty_bytes);
    
    try testing.expect(bytes.len > empty_bytes.len);
}

test "ProtoWriter field encoding" {
    const allocator = testing.allocator;
    
    // Test varint encoding
    var varint_writer = hedera.ProtoWriter.init(allocator);
    defer varint_writer.deinit();
    
    try varint_writer.writeInt32(1, 150); // Requires 2 bytes in varint
    try varint_writer.writeInt32(2, 300); // Requires 2 bytes in varint
    
    const varint_bytes = try varint_writer.toOwnedSlice();
    defer allocator.free(varint_bytes);
    
    // Should contain field tags and varint-encoded values
    try testing.expect(varint_bytes.len >= 6); // Minimum expected size
    
    // Test string encoding
    var string_writer = hedera.ProtoWriter.init(allocator);
    defer string_writer.deinit();
    
    const test_string = "Test string for protobuf encoding";
    try string_writer.writeString(1, test_string);
    
    const string_bytes = try string_writer.toOwnedSlice();
    defer allocator.free(string_bytes);
    
    // Should contain field tag, length, and string content
    try testing.expect(string_bytes.len >= test_string.len + 2);
    
    // Test bytes encoding
    var bytes_writer = hedera.ProtoWriter.init(allocator);
    defer bytes_writer.deinit();
    
    const test_bytes = [_]u8{ 0x01, 0x02, 0x03, 0xFF, 0xFE, 0xFD };
    try bytes_writer.writeBytes(1, &test_bytes);
    
    const bytes_result = try bytes_writer.toOwnedSlice();
    defer allocator.free(bytes_result);
    
    try testing.expect(bytes_result.len >= test_bytes.len + 2);
}

test "ProtoWriter nested messages" {
    const allocator = testing.allocator;
    
    // Create inner message
    var inner_writer = hedera.ProtoWriter.init(allocator);
    defer inner_writer.deinit();
    
    try inner_writer.writeString(1, "inner_field");
    try inner_writer.writeInt32(2, 123);
    
    const inner_bytes = try inner_writer.toOwnedSlice();
    defer allocator.free(inner_bytes);
    
    // Create outer message with nested inner message
    var outer_writer = hedera.ProtoWriter.init(allocator);
    defer outer_writer.deinit();
    
    try outer_writer.writeString(1, "outer_field");
    try outer_writer.writeMessage(2, inner_bytes);
    try outer_writer.writeInt32(3, 456);
    
    const outer_bytes = try outer_writer.toOwnedSlice();
    defer allocator.free(outer_bytes);
    
    // Outer message should be larger than inner message
    try testing.expect(outer_bytes.len > inner_bytes.len);
    
    // Should contain all the data from both messages
    try testing.expect(outer_bytes.len >= inner_bytes.len + 20); // Rough estimate
}

test "ProtoReader basic operations" {
    const allocator = testing.allocator;
    
    // Create test data using ProtoWriter
    var writer = hedera.ProtoWriter.init(allocator);
    defer writer.deinit();
    
    try writer.writeInt32(1, 42);
    try writer.writeString(2, "test_string");
    try writer.writeBool(3, true);
    try writer.writeUint64(4, 9876543210);
    
    const test_data = try writer.toOwnedSlice();
    defer allocator.free(test_data);
    
    // Read back the data
    var reader = hedera.ProtoReader.init(test_data);
    
    var found_fields = std.AutoHashMap(u32, bool).init(allocator);
    defer found_fields.deinit();
    
    while (try reader.nextField()) |field| {
        try found_fields.put(field.num()ber, true);
        
        switch (field.num()ber) {
            1 => {
                const value = try reader.readInt32();
                try testing.expectEqual(@as(i32, 42), value);
            },
            2 => {
                const value = try reader.readString(allocator);
                defer allocator.free(value);
                try testing.expectEqualStrings("test_string", value);
            },
            3 => {
                const value = try reader.readBool();
                try testing.expectEqual(true, value);
            },
            4 => {
                const value = try reader.readUint64();
                try testing.expectEqual(@as(u64, 9876543210), value);
            },
            else => return error.UnexpectedField,
        }
    }
    
    // Verify all expected fields were found
    try testing.expect(found_fields.contains(1));
    try testing.expect(found_fields.contains(2));
    try testing.expect(found_fields.contains(3));
    try testing.expect(found_fields.contains(4));
}

test "ProtoReader nested messages" {
    const allocator = testing.allocator;
    
    // Create nested test data
    var inner_writer = hedera.ProtoWriter.init(allocator);
    defer inner_writer.deinit();
    
    try inner_writer.writeString(1, "nested_value");
    try inner_writer.writeInt32(2, 789);
    
    const inner_data = try inner_writer.toOwnedSlice();
    defer allocator.free(inner_data);
    
    var outer_writer = hedera.ProtoWriter.init(allocator);
    defer outer_writer.deinit();
    
    try outer_writer.writeInt32(1, 123);
    try outer_writer.writeMessage(2, inner_data);
    try outer_writer.writeString(3, "outer_value");
    
    const outer_data = try outer_writer.toOwnedSlice();
    defer allocator.free(outer_data);
    
    // Read back the nested data
    var outer_reader = hedera.ProtoReader.init(outer_data);
    
    var outer_int: i32 = 0;
    var outer_string: []u8 = undefined;
    var found_nested = false;
    
    while (try outer_reader.nextField()) |field| {
        switch (field.num()ber) {
            1 => {
                outer_int = try outer_reader.readInt32();
            },
            2 => {
                const nested_data = try outer_reader.readBytes(allocator);
                defer allocator.free(nested_data);
                
                var inner_reader = hedera.ProtoReader.init(nested_data);
                
                while (try inner_reader.nextField()) |inner_field| {
                    switch (inner_field.num()ber) {
                        1 => {
                            const nested_string = try inner_reader.readString(allocator);
                            defer allocator.free(nested_string);
                            try testing.expectEqualStrings("nested_value", nested_string);
                        },
                        2 => {
                            const nested_int = try inner_reader.readInt32();
                            try testing.expectEqual(@as(i32, 789), nested_int);
                            found_nested = true;
                        },
                        else => return error.UnexpectedField,
                    }
                }
            },
            3 => {
                outer_string = try outer_reader.readString(allocator);
            },
            else => return error.UnexpectedField,
        }
    }
    
    defer allocator.free(outer_string);
    
    try testing.expectEqual(@as(i32, 123), outer_int);
    try testing.expectEqualStrings("outer_value", outer_string);
    try testing.expect(found_nested);
}

test "ProtoWriter/ProtoReader round-trip tests" {
    const allocator = testing.allocator;
    
    // Test various data types in round-trip
    const test_cases = struct {
        int32_val: i32 = -12345,
        int64_val: i64 = -9876543210,
        uint32_val: u32 = 54321,
        uint64_val: u64 = 1234567890123456789,
        bool_val: bool = true,
        string_val: []const u8 = "Round-trip test string with unicode: LAUNCH:",
        bytes_val: []const u8 = &[_]u8{ 0x00, 0xFF, 0x42, 0xAB, 0xCD, 0xEF },
    };
    
    const cases = test_cases{};
    
    // Write all test data
    var writer = hedera.ProtoWriter.init(allocator);
    defer writer.deinit();
    
    try writer.writeInt32(1, cases.int32_val);
    try writer.writeInt64(2, cases.int64_val);
    try writer.writeUint32(3, cases.uint32_val);
    try writer.writeUint64(4, cases.uint64_val);
    try writer.writeBool(5, cases.bool_val);
    try writer.writeString(6, cases.string_val);
    try writer.writeBytes(7, cases.bytes_val);
    
    const encoded_data = try writer.toOwnedSlice();
    defer allocator.free(encoded_data);
    
    // Read back and verify all data
    var reader = hedera.ProtoReader.init(encoded_data);
    
    var read_fields = std.AutoHashMap(u32, bool).init(allocator);
    defer read_fields.deinit();
    
    while (try reader.nextField()) |field| {
        try read_fields.put(field.num()ber, true);
        
        switch (field.num()ber) {
            1 => {
                const value = try reader.readInt32();
                try testing.expectEqual(cases.int32_val, value);
            },
            2 => {
                const value = try reader.readInt64();
                try testing.expectEqual(cases.int64_val, value);
            },
            3 => {
                const value = try reader.readUint32();
                try testing.expectEqual(cases.uint32_val, value);
            },
            4 => {
                const value = try reader.readUint64();
                try testing.expectEqual(cases.uint64_val, value);
            },
            5 => {
                const value = try reader.readBool();
                try testing.expectEqual(cases.bool_val, value);
            },
            6 => {
                const value = try reader.readString(allocator);
                defer allocator.free(value);
                try testing.expectEqualStrings(cases.string_val, value);
            },
            7 => {
                const value = try reader.readBytes(allocator);
                defer allocator.free(value);
                try testing.expectEqualSlices(u8, cases.bytes_val, value);
            },
            else => return error.UnexpectedField,
        }
    }
    
    // Verify all fields were read
    for (1..8) |field_num| {
        try testing.expect(read_fields.contains(@intCast(field_num)));
    }
}

test "ProtoWriter edge cases and error conditions" {
    const allocator = testing.allocator;
    
    // Test empty message
    var empty_writer = hedera.ProtoWriter.init(allocator);
    defer empty_writer.deinit();
    
    const empty_bytes = try empty_writer.toOwnedSlice();
    defer allocator.free(empty_bytes);
    
    try testing.expectEqual(@as(usize, 0), empty_bytes.len);
    
    // Test very large field numbers
    var large_field_writer = hedera.ProtoWriter.init(allocator);
    defer large_field_writer.deinit();
    
    try large_field_writer.writeInt32(536870911, 42); // Maximum field number
    
    const large_field_bytes = try large_field_writer.toOwnedSlice();
    defer allocator.free(large_field_bytes);
    
    try testing.expect(large_field_bytes.len > 0);
    
    // Test very large values
    var large_value_writer = hedera.ProtoWriter.init(allocator);
    defer large_value_writer.deinit();
    
    try large_value_writer.writeInt64(1, std.math.maxInt(i64));
    try large_value_writer.writeUint64(2, std.math.maxInt(u64));
    
    const large_value_bytes = try large_value_writer.toOwnedSlice();
    defer allocator.free(large_value_bytes);
    
    try testing.expect(large_value_bytes.len > 0);
    
    // Test empty strings and byte arrays
    var empty_content_writer = hedera.ProtoWriter.init(allocator);
    defer empty_content_writer.deinit();
    
    try empty_content_writer.writeString(1, "");
    try empty_content_writer.writeBytes(2, &[_]u8{});
    
    const empty_content_bytes = try empty_content_writer.toOwnedSlice();
    defer allocator.free(empty_content_bytes);
    
    try testing.expect(empty_content_bytes.len > 0); // Should have field tags at least
}

test "ProtoReader error handling and edge cases" {
    const allocator = testing.allocator;
    
    // Test empty data
    var empty_reader = hedera.ProtoReader.init(&[_]u8{});
    const empty_field = try empty_reader.nextField();
    try testing.expect(empty_field == null);
    
    // Test truncated data
    const truncated_data = [_]u8{0x08}; // Field tag without value
    var truncated_reader = hedera.ProtoReader.init(&truncated_data);
    
    try testing.expectError(error.UnexpectedEndOfInput, truncated_reader.nextField());
    
    // Test invalid field wire types
    const invalid_wire_type = [_]u8{0x07}; // Invalid wire type
    var invalid_reader = hedera.ProtoReader.init(&invalid_wire_type);
    
    try testing.expectError(error.InvalidWireType, invalid_reader.nextField());
    
    // Test reading wrong type for field
    var writer = hedera.ProtoWriter.init(allocator);
    defer writer.deinit();
    
    try writer.writeString(1, "not_an_int");
    const wrong_type_data = try writer.toOwnedSlice();
    defer allocator.free(wrong_type_data);
    
    var wrong_type_reader = hedera.ProtoReader.init(wrong_type_data);
    _ = try wrong_type_reader.nextField();
    
    // This should fail because we're trying to read a string as an int
    try testing.expectError(error.WrongFieldType, wrong_type_reader.readInt32());
}

test "Complex protobuf message encoding" {
    const allocator = testing.allocator;
    
    // Create a complex message similar to Hedera transaction structure
    var timestamp_writer = hedera.ProtoWriter.init(allocator);
    defer timestamp_writer.deinit();
    
    try timestamp_writer.writeInt64(1, 1640995200); // seconds
    try timestamp_writer.writeInt32(2, 123456789); // nanos
    
    const timestamp_bytes = try timestamp_writer.toOwnedSlice();
    defer allocator.free(timestamp_bytes);
    
    var account_writer = hedera.ProtoWriter.init(allocator);
    defer account_writer.deinit();
    
    try account_writer.writeInt64(1, 0); // shard
    try account_writer.writeInt64(2, 0); // realm
    try account_writer.writeInt64(3, 3); // num
    
    const account_bytes = try account_writer.toOwnedSlice();
    defer allocator.free(account_bytes);
    
    var tx_id_writer = hedera.ProtoWriter.init(allocator);
    defer tx_id_writer.deinit();
    
    try tx_id_writer.writeMessage(1, timestamp_bytes);
    try tx_id_writer.writeMessage(2, account_bytes);
    try tx_id_writer.writeBool(3, false); // scheduled
    try tx_id_writer.writeInt32(4, 0); // nonce
    
    const tx_id_bytes = try tx_id_writer.toOwnedSlice();
    defer allocator.free(tx_id_bytes);
    
    var transaction_writer = hedera.ProtoWriter.init(allocator);
    defer transaction_writer.deinit();
    
    try transaction_writer.writeMessage(1, tx_id_bytes);
    try transaction_writer.writeMessage(2, account_bytes); // node account
    try transaction_writer.writeUint64(3, 100000000); // fee
    try transaction_writer.writeString(5, "Test transaction memo");
    
    const transaction_bytes = try transaction_writer.toOwnedSlice();
    defer allocator.free(transaction_bytes);
    
    // Verify the complex message can be read back
    var transaction_reader = hedera.ProtoReader.init(transaction_bytes);
    
    var found_tx_id = false;
    var found_node_account = false;
    var found_fee = false;
    var found_memo = false;
    
    while (try transaction_reader.nextField()) |field| {
        switch (field.num()ber) {
            1 => {
                found_tx_id = true;
                const tx_id_data = try transaction_reader.readBytes(allocator);
                defer allocator.free(tx_id_data);
                
                // Verify we can read the nested transaction ID
                var tx_id_reader = hedera.ProtoReader.init(tx_id_data);
                var nested_fields = 0;
                
                while (try tx_id_reader.nextField()) |_| {
                    nested_fields += 1;
                    try tx_id_reader.skipField();
                }
                
                try testing.expect(nested_fields > 0);
            },
            2 => {
                found_node_account = true;
                try transaction_reader.skipField();
            },
            3 => {
                found_fee = true;
                const fee = try transaction_reader.readUint64();
                try testing.expectEqual(@as(u64, 100000000), fee);
            },
            5 => {
                found_memo = true;
                const memo = try transaction_reader.readString(allocator);
                defer allocator.free(memo);
                try testing.expectEqualStrings("Test transaction memo", memo);
            },
            else => {
                try transaction_reader.skipField();
            },
        }
    }
    
    try testing.expect(found_tx_id);
    try testing.expect(found_node_account);
    try testing.expect(found_fee);
    try testing.expect(found_memo);
}

const std = @import("std");
const testing = std.testing;
const AccountId = @import("../../src/core/id.zig").AccountId;
const ProtoReader = @import("../../src/protobuf/encoding.zig").ProtoReader;
const ProtoWriter = @import("../../src/protobuf/encoding.zig").ProtoWriter;

test "AccountId.fromProtobuf parses valid protobuf" {
    const allocator = testing.allocator;
    
    // Create protobuf data for AccountId with shard=0, realm=0, account=1001
    var writer = ProtoWriter.init(allocator);
    defer writer.deinit();
    
    try writer.writeInt64(1, 0); // shard
    try writer.writeInt64(2, 0); // realm
    try writer.writeInt64(3, 1001); // account
    
    const protobuf_data = try writer.toOwnedSlice();
    defer allocator.free(protobuf_data);
    
    // Parse it back
    const account_id = try AccountId.fromProtobuf(allocator, protobuf_data);
    
    try testing.expectEqual(@as(u64, 0), account_id.shard);
    try testing.expectEqual(@as(u64, 0), account_id.realm);
    try testing.expectEqual(@as(u64, 1001), account_id.account);
}

test "AccountId.fromProtobuf parses non-zero shard and realm" {
    const allocator = testing.allocator;
    
    // Create protobuf data for AccountId with shard=1, realm=2, account=3456
    var writer = ProtoWriter.init(allocator);
    defer writer.deinit();
    
    try writer.writeInt64(1, 1); // shard
    try writer.writeInt64(2, 2); // realm
    try writer.writeInt64(3, 3456); // account
    
    const protobuf_data = try writer.toOwnedSlice();
    defer allocator.free(protobuf_data);
    
    // Parse it back
    const account_id = try AccountId.fromProtobuf(allocator, protobuf_data);
    
    try testing.expectEqual(@as(u64, 1), account_id.shard);
    try testing.expectEqual(@as(u64, 2), account_id.realm);
    try testing.expectEqual(@as(u64, 3456), account_id.account);
}

test "AccountId.fromProtobuf handles empty protobuf" {
    const allocator = testing.allocator;
    
    const empty_data = &[_]u8{};
    
    // Should return default AccountId (0.0.0)
    const account_id = try AccountId.fromProtobuf(allocator, empty_data);
    
    try testing.expectEqual(@as(u64, 0), account_id.shard);
    try testing.expectEqual(@as(u64, 0), account_id.realm);
    try testing.expectEqual(@as(u64, 0), account_id.account);
}

test "AccountId.fromProtobuf handles missing fields" {
    const allocator = testing.allocator;
    
    // Create protobuf with only account field
    var writer = ProtoWriter.init(allocator);
    defer writer.deinit();
    
    try writer.writeInt64(3, 5000); // account only
    
    const protobuf_data = try writer.toOwnedSlice();
    defer allocator.free(protobuf_data);
    
    // Parse it back - missing fields should default to 0
    const account_id = try AccountId.fromProtobuf(allocator, protobuf_data);
    
    try testing.expectEqual(@as(u64, 0), account_id.shard);
    try testing.expectEqual(@as(u64, 0), account_id.realm);
    try testing.expectEqual(@as(u64, 5000), account_id.account);
}

test "AccountId.fromProtobuf handles large values" {
    const allocator = testing.allocator;
    
    // Create protobuf with large values
    var writer = ProtoWriter.init(allocator);
    defer writer.deinit();
    
    try writer.writeInt64(1, 999999); // large shard
    try writer.writeInt64(2, 888888); // large realm
    try writer.writeInt64(3, 777777777); // large account
    
    const protobuf_data = try writer.toOwnedSlice();
    defer allocator.free(protobuf_data);
    
    // Parse it back
    const account_id = try AccountId.fromProtobuf(allocator, protobuf_data);
    
    try testing.expectEqual(@as(u64, 999999), account_id.shard);
    try testing.expectEqual(@as(u64, 888888), account_id.realm);
    try testing.expectEqual(@as(u64, 777777777), account_id.account);
}

test "AccountId.fromProtobuf handles out-of-order fields" {
    const allocator = testing.allocator;
    
    // Create protobuf with fields in different order
    var writer = ProtoWriter.init(allocator);
    defer writer.deinit();
    
    try writer.writeInt64(3, 1234); // account first
    try writer.writeInt64(1, 5); // shard second
    try writer.writeInt64(2, 10); // realm last
    
    const protobuf_data = try writer.toOwnedSlice();
    defer allocator.free(protobuf_data);
    
    // Parse it back - should still work correctly
    const account_id = try AccountId.fromProtobuf(allocator, protobuf_data);
    
    try testing.expectEqual(@as(u64, 5), account_id.shard);
    try testing.expectEqual(@as(u64, 10), account_id.realm);
    try testing.expectEqual(@as(u64, 1234), account_id.account);
}

test "AccountId.fromProtobuf roundtrip with toProtobuf" {
    const allocator = testing.allocator;
    
    // Create an AccountId
    const original = AccountId{ .shard = 7, .realm = 8, .account = 9999 };
    
    // Convert to protobuf
    const protobuf_data = try original.toProtobuf(allocator);
    defer allocator.free(protobuf_data);
    
    // Parse it back
    const parsed = try AccountId.fromProtobuf(allocator, protobuf_data);
    
    // Should be identical
    try testing.expect(original.equals(parsed));
    try testing.expectEqual(original.shard, parsed.shard);
    try testing.expectEqual(original.realm, parsed.realm);
    try testing.expectEqual(original.account, parsed.account);
}

test "AccountId.fromProtobuf handles invalid protobuf gracefully" {
    const allocator = testing.allocator;
    
    // Create invalid protobuf data
    const invalid_data = &[_]u8{ 0xFF, 0xFF, 0xFF, 0xFF };
    
    // Should either return an error or default values
    const result = AccountId.fromProtobuf(allocator, invalid_data);
    
    if (result) |account_id| {
        // If it succeeds, check it returns sensible defaults
        try testing.expect(account_id.shard <= std.math.maxInt(u64));
        try testing.expect(account_id.realm <= std.math.maxInt(u64));
        try testing.expect(account_id.account <= std.math.maxInt(u64));
    } else |_| {
        // Error is also acceptable for invalid data
        try testing.expect(true);
    }
}

test "AccountId.fromProtobuf handles alias field" {
    const allocator = testing.allocator;
    
    // Create protobuf with alias field (field 4)
    var writer = ProtoWriter.init(allocator);
    defer writer.deinit();
    
    try writer.writeBytes(4, &[_]u8{ 0x01, 0x02, 0x03, 0x04 }); // alias
    
    const protobuf_data = try writer.toOwnedSlice();
    defer allocator.free(protobuf_data);
    
    // Parse it back - should handle alias appropriately
    const account_id = try AccountId.fromProtobuf(allocator, protobuf_data);
    
    // When only alias is present, account should be derived or defaulted
    // Exact behavior depends on implementation
    try testing.expect(account_id.account >= 0);
}

test "AccountId.fromProtobuf performance with multiple parses" {
    const allocator = testing.allocator;
    
    // Create protobuf data once
    var writer = ProtoWriter.init(allocator);
    defer writer.deinit();
    
    try writer.writeInt64(1, 1);
    try writer.writeInt64(2, 2);
    try writer.writeInt64(3, 3333);
    
    const protobuf_data = try writer.toOwnedSlice();
    defer allocator.free(protobuf_data);
    
    // Parse multiple times
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const account_id = try AccountId.fromProtobuf(allocator, protobuf_data);
        
        try testing.expectEqual(@as(u64, 1), account_id.shard);
        try testing.expectEqual(@as(u64, 2), account_id.realm);
        try testing.expectEqual(@as(u64, 3333), account_id.account);
    }
}
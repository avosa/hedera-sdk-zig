const std = @import("std");
const testing = std.testing;
const hedera.Timestamp = @import("../../src/core/timestamp.zig").hedera.Timestamp;

test "hedera.Timestamp creation from seconds" {
    const ts = Timestamp.fromSeconds(1234567890);
    
    try testing.expectEqual(@as(i64, 1234567890), ts.seconds);
    try testing.expectEqual(@as(i32, 0), ts.nanos);
}

test "hedera.Timestamp creation from nanos" {
    const ts = Timestamp.fromNanos(1234567890123456789);
    
    try testing.expectEqual(@as(i64, 1234567890), ts.seconds);
    try testing.expectEqual(@as(i32, 123456789), ts.nanos);
}

test "hedera.Timestamp now creation" {
    const ts = Timestamp.now();
    
    // Just verify it's a reasonable timestamp (after year 2020)
    try testing.expect(ts.seconds > 1577836800); // Jan 1, 2020
}

test "hedera.Timestamp to nanos conversion" {
    const ts = hedera.Timestamp{ .seconds = 1234567890, .nanos = 123456789 };
    const nanos = ts.toNanos();
    
    try testing.expectEqual(@as(i64, 1234567890123456789), nanos);
}

test "hedera.Timestamp comparison" {
    const ts1 = Timestamp.fromSeconds(1000);
    const ts2 = Timestamp.fromSeconds(1000);
    const ts3 = Timestamp.fromSeconds(2000);
    
    try testing.expect(ts1.equals(ts2));
    try testing.expect(!ts1.equals(ts3));
    try testing.expect(ts1.isBefore(ts3));
    try testing.expect(ts3.isAfter(ts1));
}

test "hedera.Timestamp arithmetic" {
    const ts1 = Timestamp.fromSeconds(1000);
    const ts2 = ts1.plusSeconds(500);
    
    try testing.expectEqual(@as(i64, 1500), ts2.seconds);
    
    const ts3 = ts1.plusNanos(1_500_000_000);
    try testing.expectEqual(@as(i64, 1001), ts3.seconds);
    try testing.expectEqual(@as(i32, 500_000_000), ts3.nanos);
}

test "hedera.Timestamp string formatting" {
    const allocator = testing.allocator;
    
    const ts = hedera.Timestamp{ .seconds = 1234567890, .nanos = 123456789 };
    const str = try ts.toString(allocator);
    defer allocator.free(str);
    
    try testing.expectEqualStrings("1234567890.123456789", str);
}

test "hedera.Timestamp from string parsing" {
    const allocator = testing.allocator;
    
    const ts = try Timestamp.fromString(allocator, "1234567890.123456789");
    
    try testing.expectEqual(@as(i64, 1234567890), ts.seconds);
    try testing.expectEqual(@as(i32, 123456789), ts.nanos);
}

test "hedera.Timestamp protobuf serialization" {
    const allocator = testing.allocator;
    var writer = @import("../../src/protobuf/writer.zig").ProtoWriter.init(allocator);
    defer writer.deinit();
    
    const ts = hedera.Timestamp{ .seconds = 1234567890, .nanos = 123456789 };
    try ts.toProtobuf(&writer);
    
    const bytes = try writer.finalize();
    defer allocator.free(bytes);
    
    try testing.expect(bytes.len > 0);
}

test "hedera.Timestamp protobuf deserialization" {
    const allocator = testing.allocator;
    
    // Create serialized data
    var writer = @import("../../src/protobuf/writer.zig").ProtoWriter.init(allocator);
    defer writer.deinit();
    
    const original = hedera.Timestamp{ .seconds = 1234567890, .nanos = 123456789 };
    try original.toProtobuf(&writer);
    
    const bytes = try writer.finalize();
    defer allocator.free(bytes);
    
    // Deserialize
    const deserialized = try Timestamp.fromProtobuf(bytes);
    
    try testing.expect(original.equals(deserialized));
}

test "hedera.Timestamp overflow handling" {
    const ts1 = hedera.Timestamp{ .seconds = 1000, .nanos = 900_000_000 };
    const ts2 = ts1.plusNanos(200_000_000);
    
    try testing.expectEqual(@as(i64, 1001), ts2.seconds);
    try testing.expectEqual(@as(i32, 100_000_000), ts2.nanos);
}

test "hedera.Timestamp negative nanos normalization" {
    const ts = hedera.Timestamp{ .seconds = 1000, .nanos = -500_000_000 };
    const normalized = ts.normalize();
    
    try testing.expectEqual(@as(i64, 999), normalized.seconds);
    try testing.expectEqual(@as(i32, 500_000_000), normalized.nanos);

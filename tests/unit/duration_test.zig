const std = @import("std");
const testing = std.testing;
const hedera.Duration = @import("../../src/core/duration.zig").hedera.Duration;

test "hedera.Duration from seconds" {
    const d = Duration.fromSeconds(3600);
    
    try testing.expectEqual(@as(i64, 3600), d.seconds);
}

test "hedera.Duration from minutes" {
    const d = Duration.fromMinutes(60);
    
    try testing.expectEqual(@as(i64, 3600), d.seconds);
}

test "hedera.Duration from hours" {
    const d = Duration.fromHours(24);
    
    try testing.expectEqual(@as(i64, 86400), d.seconds);
}

test "hedera.Duration from days" {
    const d = Duration.fromDays(7);
    
    try testing.expectEqual(@as(i64, 604800), d.seconds);
}

test "hedera.Duration from millis" {
    const d = Duration.fromMillis(5000);
    
    try testing.expectEqual(@as(i64, 5), d.seconds);
}

test "hedera.Duration to various units" {
    const d = Duration.fromDays(1);
    
    try testing.expectEqual(@as(i64, 86400), d.toSeconds());
    try testing.expectEqual(@as(i64, 1440), d.toMinutes());
    try testing.expectEqual(@as(i64, 24), d.toHours());
    try testing.expectEqual(@as(i64, 1), d.toDays());
    try testing.expectEqual(@as(i64, 86400000), d.toMillis());
}

test "hedera.Duration comparison" {
    const d1 = Duration.fromSeconds(1000);
    const d2 = Duration.fromSeconds(1000);
    const d3 = Duration.fromSeconds(2000);
    
    try testing.expect(d1.equals(d2));
    try testing.expect(!d1.equals(d3));
    try testing.expect(d1.isLessThan(d3));
    try testing.expect(d3.isGreaterThan(d1));
}

test "hedera.Duration arithmetic" {
    const d1 = Duration.fromSeconds(1000);
    const d2 = Duration.fromSeconds(500);
    
    const sum = d1.plus(d2);
    try testing.expectEqual(@as(i64, 1500), sum.seconds);
    
    const diff = d1.minus(d2);
    try testing.expectEqual(@as(i64, 500), diff.seconds);
}

test "hedera.Duration string formatting" {
    const allocator = testing.allocator;
    
    const d = Duration.fromSeconds(3661); // 1 hour, 1 minute, 1 second
    const str = try d.toString(allocator);
    defer allocator.free(str);
    
    try testing.expect(str.len > 0);
}

test "hedera.Duration protobuf serialization" {
    const allocator = testing.allocator;
    var writer = @import("../../src/protobuf/writer.zig").ProtoWriter.init(allocator);
    defer writer.deinit();
    
    const d = Duration.fromSeconds(3600);
    try d.toProtobuf(&writer);
    
    const bytes = try writer.finalize();
    defer allocator.free(bytes);
    
    try testing.expect(bytes.len > 0);
}

test "hedera.Duration protobuf deserialization" {
    const allocator = testing.allocator;
    
    // Create serialized data
    var writer = @import("../../src/protobuf/writer.zig").ProtoWriter.init(allocator);
    defer writer.deinit();
    
    const original = Duration.fromSeconds(3600);
    try original.toProtobuf(&writer);
    
    const bytes = try writer.finalize();
    defer allocator.free(bytes);
    
    // Deserialize
    const deserialized = try Duration.fromProtobuf(bytes);
    
    try testing.expect(original.equals(deserialized));
}

test "hedera.Duration validation" {
    const d1 = Duration.fromSeconds(8000000000); // Valid
    const d2 = Duration.fromSeconds(-1); // Invalid (negative)
    
    try testing.expect(d1.isValid());
    try testing.expect(!d2.isValid());
}

test "hedera.Duration zero value" {
    const d = Duration.zero();
    
    try testing.expectEqual(@as(i64, 0), d.seconds);
    try testing.expect(d.isZero());
}

test "hedera.Duration max value" {
    const d = Duration.max();
    
    try testing.expect(d.seconds > 0);
    try testing.expect(!d.isZero());

const std = @import("std");
const testing = std.testing;
const Hbar = @import("../../src/core/hbar.zig").Hbar;
const HbarUnit = @import("../../src/core/hbar.zig").HbarUnit;

pub fn testFromTinybars() !void {
    const h = try Hbar.fromTinybars(100_000_000);
    
    try testing.expectEqual(@as(i64, 100_000_000), h.tinybars);
    try testing.expectEqual(@as(f64, 1.0), h.to(HbarUnit.Hbar));
}

test "Hbar from tinybars" {
    try testFromTinybars();
}

pub fn testFrom() !void {
    const h = try Hbar.from(10);
    
    try testing.expectEqual(@as(i64, 1_000_000_000), h.tinybars);
    try testing.expectEqual(@as(f64, 10.0), h.to(HbarUnit.Hbar));
}

test "Hbar from hbars" {
    try testFrom();
}

test "hedera.Hbar from microbar" {
    const h = Hbar.fromMicrobar(1_000_000);
    
    try testing.expectEqual(@as(i64, 100), h.tinybars);
}

test "hedera.Hbar from millibar" {
    const h = Hbar.fromMillibar(1000);
    
    try testing.expectEqual(@as(i64, 100_000), h.tinybars);
}

test "hedera.Hbar unit conversions" {
    const h = Hbar.from(1);
    
    try testing.expectEqual(@as(i64, 100_000_000), h.toTinybars());
    try testing.expectEqual(@as(f64, 1.0), h.toBar());
    try testing.expectEqual(@as(f64, 10_000_000.0), h.toMicrobar());
    try testing.expectEqual(@as(f64, 10_000.0), h.toMillibar());
}

pub fn testComparison() !void {
    const h1 = try Hbar.from(10);
    const h2 = try Hbar.from(10);
    const h3 = try Hbar.from(20);
    
    try testing.expect(h1.equals(h2));
    try testing.expect(!h1.equals(h3));
    try testing.expect(h1.isLessThan(h3));
    try testing.expect(h3.isGreaterThan(h1));
}

test "Hbar comparison" {
    try testComparison();
}

pub fn testArithmetic() !void {
    const h1 = try Hbar.from(10);
    const h2 = try Hbar.from(5);
    
    const sum = try h1.plus(h2);
    try testing.expectEqual(@as(f64, 15.0), sum.to(HbarUnit.Hbar));
    
    const diff = try h1.minus(h2);
    try testing.expectEqual(@as(f64, 5.0), diff.to(HbarUnit.Hbar));
    
    const neg = h1.negated();
    try testing.expectEqual(@as(f64, -10.0), neg.to(HbarUnit.Hbar));
}

test "Hbar arithmetic" {
    try testArithmetic();
}

pub fn testToString() !void {
    const allocator = testing.allocator;
    
    const h = try Hbar.fromFloat(10.5);
    const str = try h.toString(allocator);
    defer allocator.free(str);
    
    // Check if string contains the value
    try testing.expect(std.mem.indexOf(u8, str, "10.5") != null);
}

test "Hbar string formatting" {
    try testToString();
}

pub fn testFromString() !void {
    const h1 = try Hbar.fromString("10.5");
    try testing.expectEqual(@as(f64, 10.5), h1.to(HbarUnit.Hbar));
    
    const h2 = try Hbar.fromString("100t");
    try testing.expectEqual(@as(i64, 100), h2.tinybars);
    
    const h3 = try Hbar.fromString("1h");
    try testing.expectEqual(@as(f64, 1.0), h3.to(HbarUnit.Hbar));
}

test "Hbar from string parsing" {
    try testFromString();
}

test "hedera.Hbar zero and negative values" {
    const zero = Hbar.zero();
    try testing.expectEqual(@as(i64, 0), zero.tinybars);
    try testing.expect(zero.isZero());
    
    const negative = Hbar.from(-5);
    try testing.expectEqual(@as(i64, -500_000_000), negative.tinybars);
    try testing.expect(negative.isNegative());
}

test "hedera.Hbar max and min values" {
    const max = Hbar.max();
    const min = Hbar.min();
    
    try testing.expect(max.tinybars > 0);
    try testing.expect(min.tinybars < 0);
    try testing.expect(max.isPositive());
    try testing.expect(min.isNegative());
}

test "hedera.Hbar protobuf serialization" {
    const allocator = testing.allocator;
    var writer = @import("../../src/protobuf/writer.zig").ProtoWriter.init(allocator);
    defer writer.deinit();
    
    const h = Hbar.from(10);
    try h.toProtobuf(&writer);
    
    const bytes = try writer.finalize();
    defer allocator.free(bytes);
    
    try testing.expect(bytes.len > 0);
}

test "hedera.Hbar protobuf deserialization" {
    const allocator = testing.allocator;
    
    // Create serialized data
    var writer = @import("../../src/protobuf/writer.zig").ProtoWriter.init(allocator);
    defer writer.deinit();
    
    const original = Hbar.from(10);
    try original.toProtobuf(&writer);
    
    const bytes = try writer.finalize();
    defer allocator.free(bytes);
    
    // Deserialize
    const deserialized = try Hbar.fromProtobuf(bytes);
    
    try testing.expect(original.equals(deserialized));
}

test "hedera.Hbar overflow protection" {
    const h1 = Hbar.max();
    const h2 = Hbar.from(1);
    
    // Should handle overflow gracefully
    const result = h1.plus(h2);
    try testing.expect(result.tinybars == Hbar.max().tinybars);

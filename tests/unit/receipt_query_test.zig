const std = @import("std");
const testing = std.testing;

test "receipt_query basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/query/receipt_query.zig");
    try testing.expect(true);
}

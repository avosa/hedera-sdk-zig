const std = @import("std");
const testing = std.testing;

test "exchange_rate basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/core/exchange_rate.zig");
    try testing.expect(true);
}

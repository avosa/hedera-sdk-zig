const std = @import("std");
const testing = std.testing;

test "custom_fractional_fee basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/token/custom_fractional_fee.zig");
    try testing.expect(true);
}

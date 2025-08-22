const std = @import("std");
const testing = std.testing;

test "custom_royalty_fee basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/token/custom_royalty_fee.zig");
    try testing.expect(true);
}

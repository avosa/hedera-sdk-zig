const std = @import("std");
const testing = std.testing;

test "subscription_handle basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/utils/subscription_handle.zig");
    try testing.expect(true);
}

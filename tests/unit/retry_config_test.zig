const std = @import("std");
const testing = std.testing;

test "retry_config basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/network/retry_config.zig");
    try testing.expect(true);
}

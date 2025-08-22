const std = @import("std");
const testing = std.testing;

test "load_balancer basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/network/load_balancer.zig");
    try testing.expect(true);
}

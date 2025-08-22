const std = @import("std");
const testing = std.testing;

test "managed_network basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/network/managed_network.zig");
    try testing.expect(true);
}

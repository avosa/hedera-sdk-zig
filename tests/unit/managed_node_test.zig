const std = @import("std");
const testing = std.testing;

test "managed_node basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/network/managed_node.zig");
    try testing.expect(true);
}

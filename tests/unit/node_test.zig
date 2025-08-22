const std = @import("std");
const testing = std.testing;

test "node basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/network/node.zig");
    try testing.expect(true);
}

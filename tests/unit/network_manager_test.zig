const std = @import("std");
const testing = std.testing;

test "network_manager basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/network/network_manager.zig");
    try testing.expect(true);
}

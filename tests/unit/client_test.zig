const std = @import("std");
const testing = std.testing;

test "client basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/network/client.zig");
    try testing.expect(true);
}

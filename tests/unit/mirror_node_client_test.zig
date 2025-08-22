const std = @import("std");
const testing = std.testing;

test "mirror_node_client basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/mirror/mirror_node_client.zig");
    try testing.expect(true);
}

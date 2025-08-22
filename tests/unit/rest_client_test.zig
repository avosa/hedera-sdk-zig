const std = @import("std");
const testing = std.testing;

test "rest_client basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/mirror/rest_client.zig");
    try testing.expect(true);
}

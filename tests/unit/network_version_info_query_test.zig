const std = @import("std");
const testing = std.testing;

test "network_version_info_query basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/network/network_version_info_query.zig");
    try testing.expect(true);
}

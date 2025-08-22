const std = @import("std");
const testing = std.testing;

test "tls_config basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/network/tls_config.zig");
    try testing.expect(true);
}

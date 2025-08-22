const std = @import("std");
const testing = std.testing;

test "proxy_staker basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/staking/proxy_staker.zig");
    try testing.expect(true);
}

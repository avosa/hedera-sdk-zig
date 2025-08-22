const std = @import("std");
const testing = std.testing;

test "account_stakers_query basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/account/account_stakers_query.zig");
    try testing.expect(true);
}

const std = @import("std");
const testing = std.testing;

test "account_info_query basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/account/account_info_query.zig");
    try testing.expect(true);
}

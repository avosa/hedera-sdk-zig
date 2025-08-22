const std = @import("std");
const testing = std.testing;

test "token_balance_query basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/token/token_balance_query.zig");
    try testing.expect(true);
}

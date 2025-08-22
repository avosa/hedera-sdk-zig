const std = @import("std");
const testing = std.testing;

test "token_info_query basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/token/token_info_query.zig");
    try testing.expect(true);
}

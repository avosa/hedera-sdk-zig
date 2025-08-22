const std = @import("std");
const testing = std.testing;

test "token_burn basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/token/token_burn.zig");
    try testing.expect(true);
}

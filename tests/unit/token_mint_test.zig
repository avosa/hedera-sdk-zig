const std = @import("std");
const testing = std.testing;

test "token_mint basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/token/token_mint.zig");
    try testing.expect(true);
}

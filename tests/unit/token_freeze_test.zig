const std = @import("std");
const testing = std.testing;

test "token_freeze basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/token/token_freeze.zig");
    try testing.expect(true);
}

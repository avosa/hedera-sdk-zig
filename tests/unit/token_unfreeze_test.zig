const std = @import("std");
const testing = std.testing;

test "token_unfreeze basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/token/token_unfreeze.zig");
    try testing.expect(true);
}

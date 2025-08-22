const std = @import("std");
const testing = std.testing;

test "token_dissociate basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/token/token_dissociate.zig");
    try testing.expect(true);
}

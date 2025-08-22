const std = @import("std");
const testing = std.testing;

test "token_decimal_map basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/token/token_decimal_map.zig");
    try testing.expect(true);
}

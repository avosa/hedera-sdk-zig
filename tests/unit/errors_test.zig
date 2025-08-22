const std = @import("std");
const testing = std.testing;

test "errors basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/core/errors.zig");
    try testing.expect(true);
}

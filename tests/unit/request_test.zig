const std = @import("std");
const testing = std.testing;

test "request basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/network/request.zig");
    try testing.expect(true);
}

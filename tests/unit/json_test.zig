const std = @import("std");
const testing = std.testing;

test "json basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/utils/json.zig");
    try testing.expect(true);
}

const std = @import("std");
const testing = std.testing;

test "request_type basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/core/request_type.zig");
    try testing.expect(true);
}

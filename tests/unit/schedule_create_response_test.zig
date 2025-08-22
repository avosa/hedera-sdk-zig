const std = @import("std");
const testing = std.testing;

test "schedule_create_response basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/schedule/schedule_create_response.zig");
    try testing.expect(true);
}

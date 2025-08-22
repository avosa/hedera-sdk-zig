const std = @import("std");
const testing = std.testing;

test "topic_delete basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/topic/topic_delete.zig");
    try testing.expect(true);
}

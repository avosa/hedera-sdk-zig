const std = @import("std");
const testing = std.testing;

test "topic_create basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/topic/topic_create.zig");
    try testing.expect(true);
}

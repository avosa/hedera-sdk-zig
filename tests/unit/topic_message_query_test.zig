const std = @import("std");
const testing = std.testing;

test "topic_message_query basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/topic/topic_message_query.zig");
    try testing.expect(true);
}

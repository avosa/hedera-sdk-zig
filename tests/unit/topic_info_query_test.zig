const std = @import("std");
const testing = std.testing;

test "topic_info_query basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/topic/topic_info_query.zig");
    try testing.expect(true);
}

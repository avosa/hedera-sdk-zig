const std = @import("std");
const testing = std.testing;

test "file_contents_query basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/file/file_contents_query.zig");
    try testing.expect(true);
}

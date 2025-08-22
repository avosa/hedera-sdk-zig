const std = @import("std");
const testing = std.testing;

test "file_contents_response basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/file/file_contents_response.zig");
    try testing.expect(true);
}

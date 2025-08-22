const std = @import("std");
const testing = std.testing;

test "file_append basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/file/file_append.zig");
    try testing.expect(true);
}

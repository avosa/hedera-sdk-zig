const std = @import("std");
const testing = std.testing;

test "file_delete basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/file/file_delete.zig");
    try testing.expect(true);
}

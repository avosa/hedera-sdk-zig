const std = @import("std");
const testing = std.testing;

test "writer basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/protobuf/writer.zig");
    try testing.expect(true);
}

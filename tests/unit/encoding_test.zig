const std = @import("std");
const testing = std.testing;

test "encoding basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/protobuf/encoding.zig");
    try testing.expect(true);
}

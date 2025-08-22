const std = @import("std");
const testing = std.testing;

test "protobuf basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/protobuf/protobuf.zig");
    try testing.expect(true);
}

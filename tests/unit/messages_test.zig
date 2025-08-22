const std = @import("std");
const testing = std.testing;

test "messages basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/protobuf/messages.zig");
    try testing.expect(true);
}

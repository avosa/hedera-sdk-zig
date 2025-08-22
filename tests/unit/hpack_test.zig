const std = @import("std");
const testing = std.testing;

test "hpack basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/grpc/hpack.zig");
    try testing.expect(true);
}

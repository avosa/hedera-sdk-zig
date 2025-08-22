const std = @import("std");
const testing = std.testing;

test "grpc basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/network/grpc.zig");
    try testing.expect(true);
}

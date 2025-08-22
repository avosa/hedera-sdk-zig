const std = @import("std");
const testing = std.testing;

test "grpc_client basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/grpc/grpc_client.zig");
    try testing.expect(true);
}

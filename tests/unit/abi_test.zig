const std = @import("std");
const testing = std.testing;

test "abi basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/contract/abi.zig");
    try testing.expect(true);
}

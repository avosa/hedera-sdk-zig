const std = @import("std");
const testing = std.testing;

test "transfer basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/transfer/transfer.zig");
    try testing.expect(true);
}

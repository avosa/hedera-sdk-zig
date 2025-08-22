const std = @import("std");
const testing = std.testing;

test "rlp basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/ethereum/rlp.zig");
    try testing.expect(true);
}

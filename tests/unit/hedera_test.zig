const std = @import("std");
const testing = std.testing;

test "hedera basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/hedera.zig");
    try testing.expect(true);
}

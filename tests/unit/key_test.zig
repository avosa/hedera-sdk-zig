const std = @import("std");
const testing = std.testing;

test "key basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/crypto/key.zig");
    try testing.expect(true);
}

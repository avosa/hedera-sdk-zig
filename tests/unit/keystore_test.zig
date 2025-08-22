const std = @import("std");
const testing = std.testing;

test "keystore basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/crypto/keystore.zig");
    try testing.expect(true);
}

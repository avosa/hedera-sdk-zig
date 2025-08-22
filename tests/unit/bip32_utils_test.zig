const std = @import("std");
const testing = std.testing;

test "bip32_utils basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/crypto/bip32_utils.zig");
    try testing.expect(true);
}

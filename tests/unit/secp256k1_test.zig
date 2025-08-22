const std = @import("std");
const testing = std.testing;

test "secp256k1 basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/crypto/secp256k1.zig");
    try testing.expect(true);
}

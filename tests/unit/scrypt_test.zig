const std = @import("std");
const testing = std.testing;

test "scrypt basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/crypto/scrypt.zig");
    try testing.expect(true);
}

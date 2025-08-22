const std = @import("std");
const testing = std.testing;

test "pbkdf2 basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/crypto/pbkdf2.zig");
    try testing.expect(true);
}

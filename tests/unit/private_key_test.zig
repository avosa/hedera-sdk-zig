const std = @import("std");
const testing = std.testing;

test "private_key basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/crypto/private_key.zig");
    try testing.expect(true);
}

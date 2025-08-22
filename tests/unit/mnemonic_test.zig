const std = @import("std");
const testing = std.testing;

test "mnemonic basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/crypto/mnemonic.zig");
    try testing.expect(true);
}

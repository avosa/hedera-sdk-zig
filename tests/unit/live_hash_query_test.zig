const std = @import("std");
const testing = std.testing;

test "live_hash_query basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/crypto/live_hash_query.zig");
    try testing.expect(true);
}

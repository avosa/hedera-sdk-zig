const std = @import("std");
const testing = std.testing;

test "live_hash_delete_transaction basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/crypto/live_hash_delete_transaction.zig");
    try testing.expect(true);
}

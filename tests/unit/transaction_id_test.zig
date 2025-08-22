const std = @import("std");
const testing = std.testing;

test "transaction_id basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/core/transaction_id.zig");
    try testing.expect(true);
}

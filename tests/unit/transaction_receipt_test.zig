const std = @import("std");
const testing = std.testing;

test "transaction_receipt basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/transaction/transaction_receipt.zig");
    try testing.expect(true);
}

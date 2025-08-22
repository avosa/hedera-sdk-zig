const std = @import("std");
const testing = std.testing;

test "transaction_receipt_query basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/query/transaction_receipt_query.zig");
    try testing.expect(true);
}

const std = @import("std");
const testing = std.testing;

test "transaction_record basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/transaction/transaction_record.zig");
    try testing.expect(true);
}

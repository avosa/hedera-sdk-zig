const std = @import("std");
const testing = std.testing;

test "transaction_response basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/transaction/transaction_response.zig");
    try testing.expect(true);
}

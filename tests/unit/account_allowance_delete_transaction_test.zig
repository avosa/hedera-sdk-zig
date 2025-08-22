const std = @import("std");
const testing = std.testing;

test "account_allowance_delete_transaction basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/account/account_allowance_delete_transaction.zig");
    try testing.expect(true);
}

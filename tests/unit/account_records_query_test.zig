const std = @import("std");
const testing = std.testing;

test "account_records_query basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/account/account_records_query.zig");
    try testing.expect(true);
}

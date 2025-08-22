const std = @import("std");
const testing = std.testing;

test "account_records basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/account/account_records.zig");
    try testing.expect(true);
}

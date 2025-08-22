const std = @import("std");
const testing = std.testing;

test "account_delete basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/account/account_delete.zig");
    try testing.expect(true);
}

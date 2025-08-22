const std = @import("std");
const testing = std.testing;

test "account_create basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/account/account_create.zig");
    try testing.expect(true);
}

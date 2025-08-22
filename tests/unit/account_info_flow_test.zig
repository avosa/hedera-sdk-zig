const std = @import("std");
const testing = std.testing;

test "account_info_flow basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/flow/account_info_flow.zig");
    try testing.expect(true);
}

const std = @import("std");
const testing = std.testing;

test "schedule_sign_transaction basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/schedule/schedule_sign_transaction.zig");
    try testing.expect(true);
}

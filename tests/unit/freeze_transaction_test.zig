const std = @import("std");
const testing = std.testing;

test "freeze_transaction basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/freeze/freeze_transaction.zig");
    try testing.expect(true);
}

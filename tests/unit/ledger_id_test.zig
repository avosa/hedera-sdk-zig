const std = @import("std");
const testing = std.testing;

test "ledger_id basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/core/ledger_id.zig");
    try testing.expect(true);
}

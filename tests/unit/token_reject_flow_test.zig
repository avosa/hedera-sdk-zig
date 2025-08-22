const std = @import("std");
const testing = std.testing;

test "token_reject_flow basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/flow/token_reject_flow.zig");
    try testing.expect(true);
}

const std = @import("std");
const testing = std.testing;

test "function_selector basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/contract/function_selector.zig");
    try testing.expect(true);
}

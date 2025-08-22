const std = @import("std");
const testing = std.testing;

test "contract_abi basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/contract/contract_abi.zig");
    try testing.expect(true);
}

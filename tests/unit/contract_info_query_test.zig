const std = @import("std");
const testing = std.testing;

test "contract_info_query basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/contract/contract_info_query.zig");
    try testing.expect(true);
}

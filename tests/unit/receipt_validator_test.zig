const std = @import("std");
const testing = std.testing;

test "receipt_validator basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/utils/receipt_validator.zig");
    try testing.expect(true);
}

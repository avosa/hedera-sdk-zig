const std = @import("std");
const testing = std.testing;

test "prng_transaction basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/utils/prng_transaction.zig");
    try testing.expect(true);
}

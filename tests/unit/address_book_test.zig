const std = @import("std");
const testing = std.testing;

test "address_book basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/network/address_book.zig");
    try testing.expect(true);
}

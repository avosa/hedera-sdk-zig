const std = @import("std");
const testing = std.testing;

test "reader basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/protobuf/reader.zig");
    try testing.expect(true);
}

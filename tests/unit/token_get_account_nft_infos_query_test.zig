const std = @import("std");
const testing = std.testing;

test "token_get_account_nft_infos_query basic test" {
    // This test ensures the module compiles
    _ = @import("../../src/token/token_get_account_nft_infos_query.zig");
    try testing.expect(true);
}

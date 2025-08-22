const std = @import("std");
const testing = std.testing;
const hedera = @import("hedera");

// Main test runner for unit tests
test "Hedera SDK Unit Tests" {
    std.log.info("Running Hedera SDK Unit Tests", .{});
    
    // Core tests
    _ = @import("core_test.zig");
    _ = @import("crypto_test.zig");
    _ = @import("transaction_test.zig");
    _ = @import("query_test.zig");
    _ = @import("account_test.zig");
    _ = @import("token_test.zig");
    _ = @import("contract_test.zig");
    _ = @import("topic_test.zig");
    _ = @import("file_test.zig");
    _ = @import("schedule_test.zig");
    _ = @import("network_test.zig");
}

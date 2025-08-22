const std = @import("std");
const testing = std.testing;

// Main test runner that includes all test files
test "Hedera SDK Tests" {
    std.log.info("Running Hedera SDK Tests", .{});
    
    // Unit tests
    _ = @import("unit/core_test.zig");
    _ = @import("unit/crypto_test.zig");
    _ = @import("unit/transaction_test.zig");
    _ = @import("unit/query_test.zig");
    _ = @import("unit/account_test.zig");
    _ = @import("unit/token_test.zig");
    _ = @import("unit/contract_test.zig");
    _ = @import("unit/topic_test.zig");
    _ = @import("unit/file_test.zig");
    _ = @import("unit/schedule_test.zig");
    _ = @import("unit/network_test.zig");
    _ = @import("unit/main_test.zig");
    
    // Integration tests
    _ = @import("integration/integration_test.zig");
}
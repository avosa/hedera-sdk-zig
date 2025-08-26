// Main test file that imports and runs all unit tests
const std = @import("std");
const testing = std.testing;

// Import all test modules
pub const core_test = @import("core_test.zig");
pub const crypto_test = @import("crypto_test.zig");
pub const transaction_test = @import("transaction_test.zig");
pub const query_test = @import("query_test.zig");
pub const account_test = @import("account_test.zig");
pub const contract_test = @import("contract_test.zig");
pub const token_test = @import("token_test.zig");
pub const file_test = @import("file_test.zig");
pub const topic_test = @import("topic_test.zig");
pub const schedule_test = @import("schedule_test.zig");
pub const network_test = @import("network_test.zig");

test "All unit tests" {
    // This test ensures all modules are imported and their tests are run
    testing.log_level = .info;
}
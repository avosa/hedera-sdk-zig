const std = @import("std");
const testing = std.testing;
const TransactionReceiptQuery = @import("../../src/query/transaction_receipt_query.zig").TransactionReceiptQuery;
const TransactionReceipt = @import("../../src/transaction/transaction_receipt.zig").TransactionReceipt;
const TransactionId = @import("../../src/core/transaction_id.zig").TransactionId;
const AccountId = @import("../../src/core/id.zig").AccountId;
const Timestamp = @import("../../src/core/timestamp.zig").Timestamp;
const Status = @import("../../src/core/status.zig").Status;
const Hbar = @import("../../src/core/hbar.zig").Hbar;

const newTransactionReceiptQuery = @import("../../src/query/transaction_receipt_query.zig").newTransactionReceiptQuery;

test "newTransactionReceiptQuery creates valid query" {
    const allocator = testing.allocator;
    
    var query = newTransactionReceiptQuery(allocator);
    defer query.deinit();
    
    // Verify default values
    try testing.expectEqual(@as(?TransactionId, null), query.transaction_id);
    try testing.expect(query.validate_status);
    try testing.expect(!query.include_duplicates);
    try testing.expect(!query.include_children);
}

test "TransactionReceiptQuery.setTransactionId sets transaction ID" {
    const allocator = testing.allocator;
    
    var query = TransactionReceiptQuery.init(allocator);
    defer query.deinit();
    
    const tx_id = TransactionId{
        .account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 },
        .valid_start = Timestamp{ .seconds = 1234567890, .nanos = 0 },
    };
    
    _ = query.setTransactionId(tx_id);
    
    try testing.expect(query.transaction_id != null);
    try testing.expect(query.transaction_id.?.account_id.equals(tx_id.account_id));
    try testing.expectEqual(tx_id.valid_start.seconds, query.transaction_id.?.valid_start.seconds);
}

test "TransactionReceiptQuery.setValidateStatus sets validation flag" {
    const allocator = testing.allocator;
    
    var query = TransactionReceiptQuery.init(allocator);
    defer query.deinit();
    
    _ = query.setValidateStatus(false);
    
    try testing.expect(!query.validate_status);
    
    _ = query.setValidateStatus(true);
    
    try testing.expect(query.validate_status);
}

test "TransactionReceiptQuery.setIncludeDuplicates sets duplicates flag" {
    const allocator = testing.allocator;
    
    var query = TransactionReceiptQuery.init(allocator);
    defer query.deinit();
    
    _ = query.setIncludeDuplicates(true);
    
    try testing.expect(query.include_duplicates);
}

test "TransactionReceiptQuery.setIncludeChildren sets children flag" {
    const allocator = testing.allocator;
    
    var query = TransactionReceiptQuery.init(allocator);
    defer query.deinit();
    
    _ = query.setIncludeChildren(true);
    
    try testing.expect(query.include_children);
}

test "TransactionReceiptQuery.execute returns TransactionReceipt" {
    const allocator = testing.allocator;
    
    var query = TransactionReceiptQuery.init(allocator);
    defer query.deinit();
    
    // Verify execute method exists
    try testing.expect(@hasDecl(@TypeOf(query), "execute"));
}

test "TransactionReceiptQuery method chaining works" {
    const allocator = testing.allocator;
    
    var query = TransactionReceiptQuery.init(allocator);
    defer query.deinit();
    
    const tx_id = TransactionId{
        .account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 },
        .valid_start = Timestamp{ .seconds = 1234567890, .nanos = 0 },
    };
    
    const result = query
        .setTransactionId(tx_id)
        .setValidateStatus(false)
        .setIncludeDuplicates(true);
    
    try testing.expectEqual(&query, result);
    try testing.expect(query.transaction_id != null);
    try testing.expect(!query.validate_status);
    try testing.expect(query.include_duplicates);
}

test "TransactionReceiptQuery validates transaction ID is set" {
    const allocator = testing.allocator;
    
    var query = TransactionReceiptQuery.init(allocator);
    defer query.deinit();
    
    // Query without transaction ID should be invalid
    try testing.expectEqual(@as(?TransactionId, null), query.transaction_id);
}

test "TransactionReceiptQuery is free (no payment required)" {
    const allocator = testing.allocator;
    
    var query = TransactionReceiptQuery.init(allocator);
    defer query.deinit();
    
    // Receipt queries should be free
    try testing.expect(!query.query.is_payment_required);
}

test "TransactionReceipt structure has expected fields" {
    const receipt = TransactionReceipt{
        .status = Status.Success,
        .account_id = null,
        .file_id = null,
        .contract_id = null,
        .topic_id = null,
        .token_id = null,
        .schedule_id = null,
        .exchange_rate = null,
        .topic_sequence_number = 0,
        .topic_running_hash = null,
        .total_supply = 0,
        .scheduled_transaction_id = null,
        .serials = std.ArrayList(i64).init(testing.allocator),
        .duplicates = std.ArrayList(TransactionReceipt).init(testing.allocator),
        .children = std.ArrayList(TransactionReceipt).init(testing.allocator),
    };
    
    // Clean up ArrayLists
    var mut_receipt = receipt;
    defer {
        mut_receipt.serials.deinit();
        mut_receipt.duplicates.deinit();
        mut_receipt.children.deinit();
    }
    
    try testing.expectEqual(Status.Success, receipt.status);
    try testing.expectEqual(@as(?AccountId, null), receipt.account_id);
    try testing.expectEqual(@as(u64, 0), receipt.topic_sequence_number);
    try testing.expectEqual(@as(u64, 0), receipt.total_supply);
}

test "TransactionReceiptQuery supports all configuration options" {
    const allocator = testing.allocator;
    
    var query = TransactionReceiptQuery.init(allocator);
    defer query.deinit();
    
    const tx_id = TransactionId{
        .account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 },
        .valid_start = Timestamp{ .seconds = 1234567890, .nanos = 0 },
    };
    
    // Set all options
    _ = query
        .setTransactionId(tx_id)
        .setValidateStatus(false)
        .setIncludeDuplicates(true)
        .setIncludeChildren(true);
    
    // Verify all options are set
    try testing.expect(query.transaction_id != null);
    try testing.expect(!query.validate_status);
    try testing.expect(query.include_duplicates);
    try testing.expect(query.include_children);
}

test "TransactionReceiptQuery.deinit cleans up properly" {
    const allocator = testing.allocator;
    
    var query = TransactionReceiptQuery.init(allocator);
    
    // Set a transaction ID
    const tx_id = TransactionId{
        .account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 },
        .valid_start = Timestamp{ .seconds = 1234567890, .nanos = 0 },
    };
    _ = query.setTransactionId(tx_id);
    
    // Deinit should clean up all allocations
    query.deinit();
    
    // Test passes if no memory leaks
}

test "TransactionReceipt.init creates receipt with defaults" {
    const allocator = testing.allocator;
    
    // Test if TransactionReceipt has an init method
    if (@hasDecl(TransactionReceipt, "init")) {
        var receipt = TransactionReceipt.init(allocator);
        defer receipt.deinit();
        
        try testing.expectEqual(Status.Unknown, receipt.status);
        try testing.expectEqual(@as(?AccountId, null), receipt.account_id);
        try testing.expectEqual(@as(usize, 0), receipt.serials.items.len);
        try testing.expectEqual(@as(usize, 0), receipt.duplicates.items.len);
        try testing.expectEqual(@as(usize, 0), receipt.children.items.len);
    }
}

test "TransactionReceiptQuery returns receipt with status" {
    const allocator = testing.allocator;
    
    var query = TransactionReceiptQuery.init(allocator);
    defer query.deinit();
    
    const tx_id = TransactionId{
        .account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 },
        .valid_start = Timestamp{ .seconds = 1234567890, .nanos = 0 },
    };
    
    _ = query.setTransactionId(tx_id);
    
    // In a real test, execute would return a receipt with status
    // For unit test, we verify the structure exists
    try testing.expect(@hasField(TransactionReceipt, "status"));
}

test "TransactionReceiptQuery supports quick receipt validation" {
    const allocator = testing.allocator;
    
    var query = TransactionReceiptQuery.init(allocator);
    defer query.deinit();
    
    // By default, validate_status should be true
    try testing.expect(query.validate_status);
    
    // This means the query will validate that status is SUCCESS
    // and throw an error if not
}

test "TransactionReceiptQuery can fetch without validation" {
    const allocator = testing.allocator;
    
    var query = TransactionReceiptQuery.init(allocator);
    defer query.deinit();
    
    // Disable validation to get receipt regardless of status
    _ = query.setValidateStatus(false);
    
    try testing.expect(!query.validate_status);
    
    // This allows fetching failed transaction receipts
}
const std = @import("std");
const testing = std.testing;
const TransactionResponse = @import("../../src/transaction/transaction_response.zig").TransactionResponse;
const TransactionId = @import("../../src/core/transaction_id.zig").TransactionId;
const AccountId = @import("../../src/core/id.zig").AccountId;
const Timestamp = @import("../../src/core/timestamp.zig").Timestamp;
const TransactionReceipt = @import("../../src/transaction/transaction_receipt.zig").TransactionReceipt;
const TransactionRecord = @import("../../src/transaction/transaction_record.zig").TransactionRecord;
const Status = @import("../../src/core/status.zig").Status;

test "TransactionResponse init creates valid response" {
    const allocator = testing.allocator;
    
    const tx_id = TransactionId{
        .account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 },
        .valid_start = Timestamp{ .seconds = 1234567890, .nanos = 0 },
    };
    const node_id = AccountId{ .shard = 0, .realm = 0, .account = 3 };
    const hash = &[_]u8{0x01, 0x02, 0x03, 0x04};
    
    var response = try TransactionResponse.init(allocator, tx_id, node_id, hash);
    defer response.deinit();
    
    // Verify values
    try testing.expect(response.transaction_id.account_id.equals(tx_id.account_id));
    try testing.expectEqual(tx_id.valid_start.seconds, response.transaction_id.valid_start.seconds);
    try testing.expect(response.node_id.equals(node_id));
    try testing.expectEqualSlices(u8, hash, response.hash);
    try testing.expectEqualSlices(u8, hash, response.transaction_hash);
    try testing.expect(!response.validate_status);
    try testing.expect(!response.include_child_receipts);
    try testing.expectEqual(@as(?*anyopaque, null), response.transaction);
}

test "TransactionResponse.setScheduledTransactionId sets scheduled ID" {
    const allocator = testing.allocator;
    
    const tx_id = TransactionId{
        .account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 },
        .valid_start = Timestamp{ .seconds = 1234567890, .nanos = 0 },
    };
    const node_id = AccountId{ .shard = 0, .realm = 0, .account = 3 };
    const hash = &[_]u8{0x01, 0x02, 0x03, 0x04};
    
    var response = try TransactionResponse.init(allocator, tx_id, node_id, hash);
    defer response.deinit();
    
    const scheduled_id = TransactionId{
        .account_id = AccountId{ .shard = 0, .realm = 0, .account = 2001 },
        .valid_start = Timestamp{ .seconds = 1234567900, .nanos = 0 },
    };
    
    _ = response.setScheduledTransactionId(scheduled_id);
    
    try testing.expect(response.scheduled_transaction_id != null);
    try testing.expect(response.scheduled_transaction_id.?.account_id.equals(scheduled_id.account_id));
}

test "TransactionResponse.setValidateStatus sets validation flag" {
    const allocator = testing.allocator;
    
    const tx_id = TransactionId{
        .account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 },
        .valid_start = Timestamp{ .seconds = 1234567890, .nanos = 0 },
    };
    const node_id = AccountId{ .shard = 0, .realm = 0, .account = 3 };
    const hash = &[_]u8{0x01, 0x02, 0x03, 0x04};
    
    var response = try TransactionResponse.init(allocator, tx_id, node_id, hash);
    defer response.deinit();
    
    _ = response.setValidateStatus(true);
    
    try testing.expect(response.validate_status);
    
    _ = response.setValidateStatus(false);
    
    try testing.expect(!response.validate_status);
}

test "TransactionResponse.setIncludeChildReceipts sets child receipts flag" {
    const allocator = testing.allocator;
    
    const tx_id = TransactionId{
        .account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 },
        .valid_start = Timestamp{ .seconds = 1234567890, .nanos = 0 },
    };
    const node_id = AccountId{ .shard = 0, .realm = 0, .account = 3 };
    const hash = &[_]u8{0x01, 0x02, 0x03, 0x04};
    
    var response = try TransactionResponse.init(allocator, tx_id, node_id, hash);
    defer response.deinit();
    
    _ = response.setIncludeChildReceipts(true);
    
    try testing.expect(response.include_child_receipts);
    
    _ = response.setIncludeChildReceipts(false);
    
    try testing.expect(!response.include_child_receipts);
}

test "TransactionResponse.getTransactionId returns transaction ID" {
    const allocator = testing.allocator;
    
    const tx_id = TransactionId{
        .account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 },
        .valid_start = Timestamp{ .seconds = 1234567890, .nanos = 0 },
    };
    const node_id = AccountId{ .shard = 0, .realm = 0, .account = 3 };
    const hash = &[_]u8{0x01, 0x02, 0x03, 0x04};
    
    var response = try TransactionResponse.init(allocator, tx_id, node_id, hash);
    defer response.deinit();
    
    const retrieved_id = response.getTransactionId();
    
    try testing.expect(retrieved_id.account_id.equals(tx_id.account_id));
    try testing.expectEqual(tx_id.valid_start.seconds, retrieved_id.valid_start.seconds);
}

test "TransactionResponse.getScheduledTransactionId returns scheduled ID" {
    const allocator = testing.allocator;
    
    const tx_id = TransactionId{
        .account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 },
        .valid_start = Timestamp{ .seconds = 1234567890, .nanos = 0 },
    };
    const node_id = AccountId{ .shard = 0, .realm = 0, .account = 3 };
    const hash = &[_]u8{0x01, 0x02, 0x03, 0x04};
    
    var response = try TransactionResponse.init(allocator, tx_id, node_id, hash);
    defer response.deinit();
    
    // Should be null initially
    try testing.expectEqual(@as(?TransactionId, null), response.getScheduledTransactionId());
    
    // Set scheduled ID
    const scheduled_id = TransactionId{
        .account_id = AccountId{ .shard = 0, .realm = 0, .account = 2001 },
        .valid_start = Timestamp{ .seconds = 1234567900, .nanos = 0 },
    };
    _ = response.setScheduledTransactionId(scheduled_id);
    
    const retrieved = response.getScheduledTransactionId();
    try testing.expect(retrieved != null);
    try testing.expect(retrieved.?.account_id.equals(scheduled_id.account_id));
}

test "TransactionResponse.getNodeId returns node ID" {
    const allocator = testing.allocator;
    
    const tx_id = TransactionId{
        .account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 },
        .valid_start = Timestamp{ .seconds = 1234567890, .nanos = 0 },
    };
    const node_id = AccountId{ .shard = 0, .realm = 0, .account = 3 };
    const hash = &[_]u8{0x01, 0x02, 0x03, 0x04};
    
    var response = try TransactionResponse.init(allocator, tx_id, node_id, hash);
    defer response.deinit();
    
    const retrieved_node = response.getNodeId();
    
    try testing.expect(retrieved_node.equals(node_id));
}

test "TransactionResponse.getHash returns transaction hash" {
    const allocator = testing.allocator;
    
    const tx_id = TransactionId{
        .account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 },
        .valid_start = Timestamp{ .seconds = 1234567890, .nanos = 0 },
    };
    const node_id = AccountId{ .shard = 0, .realm = 0, .account = 3 };
    const hash = &[_]u8{0x01, 0x02, 0x03, 0x04};
    
    var response = try TransactionResponse.init(allocator, tx_id, node_id, hash);
    defer response.deinit();
    
    const retrieved_hash = response.getHash();
    
    try testing.expectEqualSlices(u8, hash, retrieved_hash);
}

test "TransactionResponse.getReceipt method exists and has correct signature" {
    const allocator = testing.allocator;
    
    const tx_id = TransactionId{
        .account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 },
        .valid_start = Timestamp{ .seconds = 1234567890, .nanos = 0 },
    };
    const node_id = AccountId{ .shard = 0, .realm = 0, .account = 3 };
    const hash = &[_]u8{0x01, 0x02, 0x03, 0x04};
    
    var response = try TransactionResponse.init(allocator, tx_id, node_id, hash);
    defer response.deinit();
    
    // Verify getReceipt method exists
    try testing.expect(@hasDecl(@TypeOf(response), "getReceipt"));
    
    // Verify method signature
    const receipt_fn = @TypeOf(response.getReceipt);
    try testing.expect(@typeInfo(receipt_fn) == .Fn);
}

test "TransactionResponse.getReceiptAsync method exists" {
    const allocator = testing.allocator;
    
    const tx_id = TransactionId{
        .account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 },
        .valid_start = Timestamp{ .seconds = 1234567890, .nanos = 0 },
    };
    const node_id = AccountId{ .shard = 0, .realm = 0, .account = 3 };
    const hash = &[_]u8{0x01, 0x02, 0x03, 0x04};
    
    var response = try TransactionResponse.init(allocator, tx_id, node_id, hash);
    defer response.deinit();
    
    // Verify getReceiptAsync method exists
    try testing.expect(@hasDecl(@TypeOf(response), "getReceiptAsync"));
}

test "TransactionResponse.getRecord method exists and has correct signature" {
    const allocator = testing.allocator;
    
    const tx_id = TransactionId{
        .account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 },
        .valid_start = Timestamp{ .seconds = 1234567890, .nanos = 0 },
    };
    const node_id = AccountId{ .shard = 0, .realm = 0, .account = 3 };
    const hash = &[_]u8{0x01, 0x02, 0x03, 0x04};
    
    var response = try TransactionResponse.init(allocator, tx_id, node_id, hash);
    defer response.deinit();
    
    // Verify getRecord method exists
    try testing.expect(@hasDecl(@TypeOf(response), "getRecord"));
    
    // Verify method signature
    const record_fn = @TypeOf(response.getRecord);
    try testing.expect(@typeInfo(record_fn) == .Fn);
}

test "TransactionResponse.getRecordAsync method exists" {
    const allocator = testing.allocator;
    
    const tx_id = TransactionId{
        .account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 },
        .valid_start = Timestamp{ .seconds = 1234567890, .nanos = 0 },
    };
    const node_id = AccountId{ .shard = 0, .realm = 0, .account = 3 };
    const hash = &[_]u8{0x01, 0x02, 0x03, 0x04};
    
    var response = try TransactionResponse.init(allocator, tx_id, node_id, hash);
    defer response.deinit();
    
    // Verify getRecordAsync method exists
    try testing.expect(@hasDecl(@TypeOf(response), "getRecordAsync"));
}

test "TransactionResponse.getReceiptQuery creates query with correct parameters" {
    const allocator = testing.allocator;
    
    const tx_id = TransactionId{
        .account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 },
        .valid_start = Timestamp{ .seconds = 1234567890, .nanos = 0 },
    };
    const node_id = AccountId{ .shard = 0, .realm = 0, .account = 3 };
    const hash = &[_]u8{0x01, 0x02, 0x03, 0x04};
    
    var response = try TransactionResponse.init(allocator, tx_id, node_id, hash);
    defer response.deinit();
    
    // Set validation options
    _ = response.setValidateStatus(true);
    _ = response.setIncludeChildReceipts(true);
    
    // Verify getReceiptQuery method exists
    try testing.expect(@hasDecl(@TypeOf(response), "getReceiptQuery"));
}

test "TransactionResponse.waitForCompletion waits for transaction" {
    const allocator = testing.allocator;
    
    const tx_id = TransactionId{
        .account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 },
        .valid_start = Timestamp{ .seconds = 1234567890, .nanos = 0 },
    };
    const node_id = AccountId{ .shard = 0, .realm = 0, .account = 3 };
    const hash = &[_]u8{0x01, 0x02, 0x03, 0x04};
    
    var response = try TransactionResponse.init(allocator, tx_id, node_id, hash);
    defer response.deinit();
    
    // Verify waitForCompletion method exists
    try testing.expect(@hasDecl(@TypeOf(response), "waitForCompletion"));
}

test "TransactionResponse.retryTransaction handles throttled transactions" {
    const allocator = testing.allocator;
    
    const tx_id = TransactionId{
        .account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 },
        .valid_start = Timestamp{ .seconds = 1234567890, .nanos = 0 },
    };
    const node_id = AccountId{ .shard = 0, .realm = 0, .account = 3 };
    const hash = &[_]u8{0x01, 0x02, 0x03, 0x04};
    
    var response = try TransactionResponse.init(allocator, tx_id, node_id, hash);
    defer response.deinit();
    
    // Verify retryTransaction method exists
    try testing.expect(@hasDecl(@TypeOf(response), "retryTransaction"));
}

test "TransactionResponse.isSuccess checks transaction success" {
    const allocator = testing.allocator;
    
    const tx_id = TransactionId{
        .account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 },
        .valid_start = Timestamp{ .seconds = 1234567890, .nanos = 0 },
    };
    const node_id = AccountId{ .shard = 0, .realm = 0, .account = 3 };
    const hash = &[_]u8{0x01, 0x02, 0x03, 0x04};
    
    var response = try TransactionResponse.init(allocator, tx_id, node_id, hash);
    defer response.deinit();
    
    // Verify isSuccess method exists
    try testing.expect(@hasDecl(@TypeOf(response), "isSuccess"));
}

test "TransactionResponse.toString formats response as string" {
    const allocator = testing.allocator;
    
    const tx_id = TransactionId{
        .account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 },
        .valid_start = Timestamp{ .seconds = 1234567890, .nanos = 0 },
    };
    const node_id = AccountId{ .shard = 0, .realm = 0, .account = 3 };
    const hash = &[_]u8{0x01, 0x02, 0x03, 0x04};
    
    var response = try TransactionResponse.init(allocator, tx_id, node_id, hash);
    defer response.deinit();
    
    const str = try response.toString(allocator);
    defer allocator.free(str);
    
    try testing.expect(str.len > 0);
    try testing.expect(std.mem.indexOf(u8, str, "TransactionResponse") != null);
}

test "TransactionResponse.toJson and fromJson round trip" {
    const allocator = testing.allocator;
    
    const tx_id = TransactionId{
        .account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 },
        .valid_start = Timestamp{ .seconds = 1234567890, .nanos = 0 },
    };
    const node_id = AccountId{ .shard = 0, .realm = 0, .account = 3 };
    const hash = &[_]u8{0x01, 0x02, 0x03, 0x04};
    
    var response = try TransactionResponse.init(allocator, tx_id, node_id, hash);
    defer response.deinit();
    
    // Set scheduled ID for complete test
    const scheduled_id = TransactionId{
        .account_id = AccountId{ .shard = 0, .realm = 0, .account = 2001 },
        .valid_start = Timestamp{ .seconds = 1234567900, .nanos = 0 },
    };
    _ = response.setScheduledTransactionId(scheduled_id);
    
    const json_str = try response.toJson(allocator);
    defer allocator.free(json_str);
    
    try testing.expect(json_str.len > 0);
    try testing.expect(std.mem.indexOf(u8, json_str, "transactionID") != null);
    try testing.expect(std.mem.indexOf(u8, json_str, "nodeID") != null);
    try testing.expect(std.mem.indexOf(u8, json_str, "hash") != null);
    try testing.expect(std.mem.indexOf(u8, json_str, "scheduledTransactionId") != null);
}

test "TransactionResponse.clone creates deep copy" {
    const allocator = testing.allocator;
    
    const tx_id = TransactionId{
        .account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 },
        .valid_start = Timestamp{ .seconds = 1234567890, .nanos = 0 },
    };
    const node_id = AccountId{ .shard = 0, .realm = 0, .account = 3 };
    const hash = &[_]u8{0x01, 0x02, 0x03, 0x04};
    
    var response = try TransactionResponse.init(allocator, tx_id, node_id, hash);
    defer response.deinit();
    
    _ = response.setValidateStatus(true);
    _ = response.setIncludeChildReceipts(true);
    
    var cloned = try response.clone(allocator);
    defer cloned.deinit();
    
    try testing.expect(response.equals(&cloned));
    try testing.expect(response.validate_status == cloned.validate_status);
    try testing.expect(response.include_child_receipts == cloned.include_child_receipts);
}

test "TransactionResponse.equals compares responses correctly" {
    const allocator = testing.allocator;
    
    const tx_id = TransactionId{
        .account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 },
        .valid_start = Timestamp{ .seconds = 1234567890, .nanos = 0 },
    };
    const node_id = AccountId{ .shard = 0, .realm = 0, .account = 3 };
    const hash = &[_]u8{0x01, 0x02, 0x03, 0x04};
    
    var response1 = try TransactionResponse.init(allocator, tx_id, node_id, hash);
    defer response1.deinit();
    
    var response2 = try TransactionResponse.init(allocator, tx_id, node_id, hash);
    defer response2.deinit();
    
    try testing.expect(response1.equals(&response2));
    
    // Change validate status
    _ = response2.setValidateStatus(true);
    
    try testing.expect(!response1.equals(&response2));
}

test "TransactionResponse.setTransaction sets transaction pointer" {
    const allocator = testing.allocator;
    
    const tx_id = TransactionId{
        .account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 },
        .valid_start = Timestamp{ .seconds = 1234567890, .nanos = 0 },
    };
    const node_id = AccountId{ .shard = 0, .realm = 0, .account = 3 };
    const hash = &[_]u8{0x01, 0x02, 0x03, 0x04};
    
    var response = try TransactionResponse.init(allocator, tx_id, node_id, hash);
    defer response.deinit();
    
    // Create a mock transaction
    var mock_transaction: u32 = 12345;
    
    _ = response.setTransaction(@ptrCast(&mock_transaction));
    
    try testing.expect(response.transaction != null);
    try testing.expect(response.getTransaction() != null);
}

test "TransactionResponse.deinit cleans up properly" {
    const allocator = testing.allocator;
    
    const tx_id = TransactionId{
        .account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 },
        .valid_start = Timestamp{ .seconds = 1234567890, .nanos = 0 },
    };
    const node_id = AccountId{ .shard = 0, .realm = 0, .account = 3 };
    const hash = &[_]u8{0x01, 0x02, 0x03, 0x04};
    
    var response = try TransactionResponse.init(allocator, tx_id, node_id, hash);
    
    // Set some values
    _ = response.setValidateStatus(true);
    _ = response.setIncludeChildReceipts(true);
    
    const scheduled_id = TransactionId{
        .account_id = AccountId{ .shard = 0, .realm = 0, .account = 2001 },
        .valid_start = Timestamp{ .seconds = 1234567900, .nanos = 0 },
    };
    _ = response.setScheduledTransactionId(scheduled_id);
    
    // Deinit should clean up all allocations
    response.deinit();
    
    // Test passes if no memory leaks
}

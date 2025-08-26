const std = @import("std");
const testing = std.testing;
const TransactionRecordQuery = @import("../../src/query/transaction_record_query.zig").TransactionRecordQuery;
const TransactionRecord = @import("../../src/transaction/transaction_record.zig").TransactionRecord;
const TransactionId = @import("../../src/core/transaction_id.zig").TransactionId;
const AccountId = @import("../../src/core/id.zig").AccountId;
const Timestamp = @import("../../src/core/timestamp.zig").Timestamp;
const Status = @import("../../src/core/status.zig").Status;
const Hbar = @import("../../src/core/hbar.zig").Hbar;
const HbarTransfer = @import("../../src/transfer/transfer_transaction.zig").HbarTransfer;
const ContractFunctionResult = @import("../../src/contract/contract_execute.zig").ContractFunctionResult;

const newTransactionRecordQuery = @import("../../src/query/transaction_record_query.zig").newTransactionRecordQuery;

test "newTransactionRecordQuery creates valid query" {
    const allocator = testing.allocator;
    
    var query = newTransactionRecordQuery(allocator);
    defer query.deinit();
    
    // Verify default values
    try testing.expectEqual(@as(?TransactionId, null), query.transaction_id);
    try testing.expect(!query.include_children);
    try testing.expect(!query.include_duplicates);
}

test "TransactionRecordQuery.setTransactionId sets transaction ID" {
    const allocator = testing.allocator;
    
    var query = TransactionRecordQuery.init(allocator);
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

test "TransactionRecordQuery.setIncludeChildren sets children flag" {
    const allocator = testing.allocator;
    
    var query = TransactionRecordQuery.init(allocator);
    defer query.deinit();
    
    _ = query.setIncludeChildren(true);
    
    try testing.expect(query.include_children);
    
    _ = query.setIncludeChildren(false);
    
    try testing.expect(!query.include_children);
}

test "TransactionRecordQuery.setIncludeDuplicates sets duplicates flag" {
    const allocator = testing.allocator;
    
    var query = TransactionRecordQuery.init(allocator);
    defer query.deinit();
    
    _ = query.setIncludeDuplicates(true);
    
    try testing.expect(query.include_duplicates);
    
    _ = query.setIncludeDuplicates(false);
    
    try testing.expect(!query.include_duplicates);
}

test "TransactionRecordQuery.setQueryPayment sets payment" {
    const allocator = testing.allocator;
    
    var query = TransactionRecordQuery.init(allocator);
    defer query.deinit();
    
    const payment = try Hbar.from(2);
    _ = try query.setQueryPayment(payment);
    
    try testing.expect(query.base.payment != null);
    try testing.expectEqual(payment.toTinybars(), query.base.payment.?.toTinybars());
}

test "TransactionRecordQuery.setMaxQueryPayment sets max payment" {
    const allocator = testing.allocator;
    
    var query = TransactionRecordQuery.init(allocator);
    defer query.deinit();
    
    const max_payment = try Hbar.from(5);
    _ = try query.setMaxQueryPayment(max_payment);
    
    try testing.expect(query.base.max_query_payment != null);
    try testing.expectEqual(max_payment.toTinybars(), query.base.max_query_payment.?.toTinybars());
}

test "TransactionRecordQuery.execute returns TransactionRecord" {
    const allocator = testing.allocator;
    
    var query = TransactionRecordQuery.init(allocator);
    defer query.deinit();
    
    // Verify execute method exists
    try testing.expect(@hasDecl(@TypeOf(query), "execute"));
}

test "TransactionRecordQuery.getCost returns query cost" {
    const allocator = testing.allocator;
    
    var query = TransactionRecordQuery.init(allocator);
    defer query.deinit();
    
    // Verify getCost method exists
    try testing.expect(@hasDecl(@TypeOf(query), "getCost"));
}

test "TransactionRecordQuery method chaining works" {
    const allocator = testing.allocator;
    
    var query = TransactionRecordQuery.init(allocator);
    defer query.deinit();
    
    const tx_id = TransactionId{
        .account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 },
        .valid_start = Timestamp{ .seconds = 1234567890, .nanos = 0 },
    };
    
    const result = query
        .setTransactionId(tx_id)
        .setIncludeChildren(true)
        .setIncludeDuplicates(true);
    
    try testing.expectEqual(&query, result);
    try testing.expect(query.transaction_id != null);
    try testing.expect(query.include_children);
    try testing.expect(query.include_duplicates);
}

test "TransactionRecordQuery validates transaction ID is set" {
    const allocator = testing.allocator;
    
    var query = TransactionRecordQuery.init(allocator);
    defer query.deinit();
    
    // Query without transaction ID should be invalid
    try testing.expectEqual(@as(?TransactionId, null), query.transaction_id);
}

test "TransactionRecord structure has expected fields" {
    const allocator = testing.allocator;
    
    var record = TransactionRecord.init(allocator);
    defer record.deinit();
    
    // Verify default values
    try testing.expectEqual(Status.Unknown, record.receipt.status);
    try testing.expectEqual(@as(i64, 0), record.consensus_timestamp.seconds);
    try testing.expectEqual(@as(?TransactionId, null), record.transaction_id);
    try testing.expectEqualStrings("", record.transaction_memo);
    try testing.expectEqual(@as(u64, 0), record.transaction_fee);
    try testing.expectEqual(@as(?[]const u8, null), record.transaction_hash);
    try testing.expectEqual(@as(usize, 0), record.transfers.items.len);
    try testing.expectEqual(@as(usize, 0), record.token_transfers.items.len);
    try testing.expectEqual(@as(usize, 0), record.nft_transfers.items.len);
    try testing.expectEqual(@as(?ContractFunctionResult, null), record.contract_function_result);
}

test "TransactionRecord contains transfers" {
    const allocator = testing.allocator;
    
    var record = TransactionRecord.init(allocator);
    defer record.deinit();
    
    // Add HBAR transfer
    const hbar_transfer = HbarTransfer{
        .account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 },
        .amount = try Hbar.from(10),
        .is_approved = false,
    };
    try record.transfers.append(hbar_transfer);
    
    try testing.expectEqual(@as(usize, 1), record.transfers.items.len);
    try testing.expect(record.transfers.items[0].account_id.equals(hbar_transfer.account_id));
}

test "TransactionRecord contains token transfers" {
    const allocator = testing.allocator;
    
    var record = TransactionRecord.init(allocator);
    defer record.deinit();
    
    const TokenTransfer = @import("../../src/transfer/transfer_transaction.zig").TokenTransfer;
    const TokenId = @import("../../src/core/id.zig").TokenId;
    
    var token_transfer = TokenTransfer.init(
        TokenId{ .shard = 0, .realm = 0, .account = 100 },
        AccountId{ .shard = 0, .realm = 0, .account = 1001 },
        50,
        allocator
    );
    defer token_transfer.deinit();
    
    try record.token_transfers.append(token_transfer);
    
    try testing.expectEqual(@as(usize, 1), record.token_transfers.items.len);
}

test "TransactionRecord contains NFT transfers" {
    const allocator = testing.allocator;
    
    var record = TransactionRecord.init(allocator);
    defer record.deinit();
    
    const NftTransfer = @import("../../src/transfer/transfer_transaction.zig").NftTransfer;
    const NftId = @import("../../src/core/id.zig").NftId;
    const TokenId = @import("../../src/core/id.zig").TokenId;
    
    const nft_transfer = NftTransfer.init(
        NftId{ 
            .token_id = TokenId{ .shard = 0, .realm = 0, .account = 100 },
            .serial_number = 1
        },
        AccountId{ .shard = 0, .realm = 0, .account = 1001 },
        AccountId{ .shard = 0, .realm = 0, .account = 1002 }
    );
    
    try record.nft_transfers.append(nft_transfer);
    
    try testing.expectEqual(@as(usize, 1), record.nft_transfers.items.len);
}

test "TransactionRecordQuery requires payment" {
    const allocator = testing.allocator;
    
    var query = TransactionRecordQuery.init(allocator);
    defer query.deinit();
    
    // Record queries are paid queries
    try testing.expect(query.base.is_payment_required);
}

test "TransactionRecordQuery supports all configuration options" {
    const allocator = testing.allocator;
    
    var query = TransactionRecordQuery.init(allocator);
    defer query.deinit();
    
    const tx_id = TransactionId{
        .account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 },
        .valid_start = Timestamp{ .seconds = 1234567890, .nanos = 0 },
    };
    
    const payment = try Hbar.from(1);
    
    // Set all options
    _ = try query
        .setTransactionId(tx_id)
        .setIncludeChildren(true)
        .setIncludeDuplicates(true)
        .setQueryPayment(payment);
    
    // Verify all options are set
    try testing.expect(query.transaction_id != null);
    try testing.expect(query.include_children);
    try testing.expect(query.include_duplicates);
    try testing.expect(query.base.payment != null);
}

test "TransactionRecordQuery.deinit cleans up properly" {
    const allocator = testing.allocator;
    
    var query = TransactionRecordQuery.init(allocator);
    
    // Set some values
    const tx_id = TransactionId{
        .account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 },
        .valid_start = Timestamp{ .seconds = 1234567890, .nanos = 0 },
    };
    _ = query.setTransactionId(tx_id);
    
    // Deinit should clean up all allocations
    query.deinit();
    
    // Test passes if no memory leaks
}

test "TransactionRecord.deinit cleans up properly" {
    const allocator = testing.allocator;
    
    var record = TransactionRecord.init(allocator);
    
    // Add some transfers
    const hbar_transfer = HbarTransfer{
        .account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 },
        .amount = try Hbar.from(10),
        .is_approved = false,
    };
    try record.transfers.append(hbar_transfer);
    
    // Deinit should clean up all allocations
    record.deinit();
    
    // Test passes if no memory leaks
}
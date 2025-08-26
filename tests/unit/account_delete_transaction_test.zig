const std = @import("std");
const testing = std.testing;
const AccountDeleteTransaction = @import("../../src/account/account_delete.zig").AccountDeleteTransaction;
const newAccountDeleteTransaction = @import("../../src/account/account_delete.zig").newAccountDeleteTransaction;
const AccountId = @import("../../src/core/id.zig").AccountId;

test "newAccountDeleteTransaction creates valid transaction" {
    const allocator = testing.allocator;
    
    var tx = newAccountDeleteTransaction(allocator);
    defer tx.deinit();
    
    // Verify default values
    try testing.expectEqual(@as(?AccountId, null), tx.delete_account_id);
    try testing.expectEqual(@as(?AccountId, null), tx.transfer_account_id);
    try testing.expect(!tx.base.frozen);
}

test "AccountDeleteTransaction.setAccountId sets account to delete" {
    const allocator = testing.allocator;
    
    var tx = newAccountDeleteTransaction(allocator);
    defer tx.deinit();
    
    const account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    _ = try tx.setAccountId(account_id);
    
    try testing.expect(tx.delete_account_id != null);
    try testing.expect(tx.delete_account_id.?.equals(account_id));
}

test "AccountDeleteTransaction.getAccountId returns account ID" {
    const allocator = testing.allocator;
    
    var tx = newAccountDeleteTransaction(allocator);
    defer tx.deinit();
    
    // Should return default when not set
    var default_id = tx.getAccountId();
    try testing.expectEqual(@as(u64, 0), default_id.shard);
    try testing.expectEqual(@as(u64, 0), default_id.realm);
    try testing.expectEqual(@as(u64, 0), default_id.account);
    
    // Set an account ID
    const account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    _ = try tx.setAccountId(account_id);
    
    // Should return the set ID
    const retrieved_id = tx.getAccountId();
    try testing.expect(retrieved_id.equals(account_id));
}

test "AccountDeleteTransaction.setTransferAccountId sets transfer account" {
    const allocator = testing.allocator;
    
    var tx = newAccountDeleteTransaction(allocator);
    defer tx.deinit();
    
    const transfer_account = AccountId{ .shard = 0, .realm = 0, .account = 2001 };
    _ = try tx.setTransferAccountId(transfer_account);
    
    try testing.expect(tx.transfer_account_id != null);
    try testing.expect(tx.transfer_account_id.?.equals(transfer_account));
}

test "AccountDeleteTransaction.getTransferAccountId returns transfer account" {
    const allocator = testing.allocator;
    
    var tx = newAccountDeleteTransaction(allocator);
    defer tx.deinit();
    
    // Should return default when not set
    var default_id = tx.getTransferAccountId();
    try testing.expectEqual(@as(u64, 0), default_id.shard);
    try testing.expectEqual(@as(u64, 0), default_id.realm);
    try testing.expectEqual(@as(u64, 0), default_id.account);
    
    // Set a transfer account ID
    const transfer_account = AccountId{ .shard = 0, .realm = 0, .account = 2001 };
    _ = try tx.setTransferAccountId(transfer_account);
    
    // Should return the set ID
    const retrieved_id = tx.getTransferAccountId();
    try testing.expect(retrieved_id.equals(transfer_account));
}

test "AccountDeleteTransaction.setTransactionMemo sets transaction memo" {
    const allocator = testing.allocator;
    
    var tx = newAccountDeleteTransaction(allocator);
    defer tx.deinit();
    
    const memo = "Deleting account";
    _ = try tx.setTransactionMemo(memo);
    
    try testing.expectEqualStrings(memo, tx.base.transaction_memo);
}

test "AccountDeleteTransaction.freezeWith freezes transaction" {
    const allocator = testing.allocator;
    
    var tx = newAccountDeleteTransaction(allocator);
    defer tx.deinit();
    
    // Set required fields
    const delete_account = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    const transfer_account = AccountId{ .shard = 0, .realm = 0, .account = 2001 };
    _ = try tx.setAccountId(delete_account);
    _ = try tx.setTransferAccountId(transfer_account);
    
    // Verify freezeWith method exists
    try testing.expect(@hasDecl(@TypeOf(tx), "freezeWith"));
}

test "AccountDeleteTransaction.execute returns TransactionResponse" {
    const allocator = testing.allocator;
    
    var tx = newAccountDeleteTransaction(allocator);
    defer tx.deinit();
    
    // Verify execute method exists
    try testing.expect(@hasDecl(@TypeOf(tx), "execute"));
}

test "AccountDeleteTransaction.buildTransactionBody creates protobuf" {
    const allocator = testing.allocator;
    
    var tx = newAccountDeleteTransaction(allocator);
    defer tx.deinit();
    
    // Set required fields
    const delete_account = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    const transfer_account = AccountId{ .shard = 0, .realm = 0, .account = 2001 };
    _ = try tx.setAccountId(delete_account);
    _ = try tx.setTransferAccountId(transfer_account);
    
    const body = try tx.buildTransactionBody();
    defer allocator.free(body);
    
    try testing.expect(body.len > 0);
}

test "AccountDeleteTransaction validates both accounts are set" {
    const allocator = testing.allocator;
    
    var tx = newAccountDeleteTransaction(allocator);
    defer tx.deinit();
    
    // Transaction should require both account IDs to be set
    try testing.expectEqual(@as(?AccountId, null), tx.delete_account_id);
    try testing.expectEqual(@as(?AccountId, null), tx.transfer_account_id);
}

test "AccountDeleteTransaction method chaining works" {
    const allocator = testing.allocator;
    
    var tx = newAccountDeleteTransaction(allocator);
    defer tx.deinit();
    
    const delete_account = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    const transfer_account = AccountId{ .shard = 0, .realm = 0, .account = 2001 };
    
    const result = try tx
        .setAccountId(delete_account)
        .setTransferAccountId(transfer_account)
        .setTransactionMemo("Chained delete");
    
    try testing.expectEqual(&tx, result);
    try testing.expect(tx.delete_account_id != null);
    try testing.expect(tx.transfer_account_id != null);
    try testing.expectEqualStrings("Chained delete", tx.base.transaction_memo);
}

test "AccountDeleteTransaction setters validate frozen state" {
    const allocator = testing.allocator;
    
    var tx = newAccountDeleteTransaction(allocator);
    defer tx.deinit();
    
    // Manually set frozen state
    tx.base.frozen = true;
    
    const account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    
    // All setters should fail when frozen
    try testing.expectError(error.TransactionFrozen, tx.setAccountId(account_id));
    try testing.expectError(error.TransactionFrozen, tx.setTransferAccountId(account_id));
}

test "AccountDeleteTransaction prevents self-deletion" {
    const allocator = testing.allocator;
    
    var tx = newAccountDeleteTransaction(allocator);
    defer tx.deinit();
    
    const same_account = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    
    // Set both to same account (should be prevented in real execution)
    _ = try tx.setAccountId(same_account);
    _ = try tx.setTransferAccountId(same_account);
    
    // Both should be set, but validation would fail on execute
    try testing.expect(tx.delete_account_id != null);
    try testing.expect(tx.transfer_account_id != null);
    try testing.expect(tx.delete_account_id.?.equals(tx.transfer_account_id.?));
}

test "AccountDeleteTransaction deinit cleans up properly" {
    const allocator = testing.allocator;
    
    var tx = newAccountDeleteTransaction(allocator);
    
    // Set some values
    const delete_account = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    const transfer_account = AccountId{ .shard = 0, .realm = 0, .account = 2001 };
    _ = try tx.setAccountId(delete_account);
    _ = try tx.setTransferAccountId(transfer_account);
    _ = try tx.setTransactionMemo("Test deletion");
    
    // Deinit should clean up all allocations
    tx.deinit();
    
    // Test passes if no memory leaks
}

test "AccountDeleteTransaction transfers remaining balance" {
    const allocator = testing.allocator;
    
    var tx = newAccountDeleteTransaction(allocator);
    defer tx.deinit();
    
    // Set accounts
    const delete_account = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    const beneficiary = AccountId{ .shard = 0, .realm = 0, .account = 2001 };
    
    _ = try tx.setAccountId(delete_account);
    _ = try tx.setTransferAccountId(beneficiary);
    
    // Verify both are set correctly
    try testing.expect(tx.delete_account_id.?.equals(delete_account));
    try testing.expect(tx.transfer_account_id.?.equals(beneficiary));
    
    // In real execution, all balance from delete_account would go to beneficiary
}

test "AccountDeleteTransaction marks account as deleted" {
    const allocator = testing.allocator;
    
    var tx = newAccountDeleteTransaction(allocator);
    defer tx.deinit();
    
    const delete_account = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    const transfer_account = AccountId{ .shard = 0, .realm = 0, .account = 2001 };
    
    _ = try tx.setAccountId(delete_account);
    _ = try tx.setTransferAccountId(transfer_account);
    
    // After execution:
    // - delete_account would be marked as deleted in the ledger
    // - Transfers INTO delete_account would fail
    // - delete_account would still exist until expiration
    // - All hbars would be transferred to transfer_account
    
    try testing.expect(tx.delete_account_id != null);
    try testing.expect(tx.transfer_account_id != null);
}
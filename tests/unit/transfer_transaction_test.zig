const std = @import("std");
const testing = std.testing;
const TransferTransaction = @import("../../src/transfer/transfer_transaction.zig").TransferTransaction;
const newTransferTransaction = @import("../../src/transfer/transfer_transaction.zig").newTransferTransaction;
const HbarTransfer = @import("../../src/transfer/transfer_transaction.zig").HbarTransfer;
const TokenTransfer = @import("../../src/transfer/transfer_transaction.zig").TokenTransfer;
const NftTransfer = @import("../../src/transfer/transfer_transaction.zig").NftTransfer;
const AccountId = @import("../../src/core/id.zig").AccountId;
const TokenId = @import("../../src/core/id.zig").TokenId;
const NftId = @import("../../src/core/id.zig").NftId;
const Hbar = @import("../../src/core/hbar.zig").Hbar;

test "newTransferTransaction creates valid transaction" {
    const allocator = testing.allocator;
    
    var tx = newTransferTransaction(allocator);
    defer tx.deinit();
    
    try testing.expectEqual(@as(usize, 0), tx.hbar_transfers.items.len);
    try testing.expectEqual(@as(usize, 0), tx.token_transfers.items.len);
    try testing.expectEqual(@as(usize, 0), tx.nft_transfers.items.len);
    try testing.expect(!tx.base.frozen);
}

test "TransferTransaction.addHbarTransfer adds HBAR transfer" {
    const allocator = testing.allocator;
    
    var tx = newTransferTransaction(allocator);
    defer tx.deinit();
    
    const account1 = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    const account2 = AccountId{ .shard = 0, .realm = 0, .account = 1002 };
    const amount1 = try Hbar.fromTinybars(1000);
    const amount2 = try Hbar.fromTinybars(-1000);
    
    try tx.addHbarTransfer(account1, amount1);
    try tx.addHbarTransfer(account2, amount2);
    
    try testing.expectEqual(@as(usize, 2), tx.hbar_transfers.items.len);
    try testing.expect(tx.hbar_transfers.items[0].account_id.equals(account1));
    try testing.expectEqual(amount1.toTinybars(), tx.hbar_transfers.items[0].amount.toTinybars());
    try testing.expect(tx.hbar_transfers.items[1].account_id.equals(account2));
    try testing.expectEqual(amount2.toTinybars(), tx.hbar_transfers.items[1].amount.toTinybars());
}

test "TransferTransaction.addHbarTransfer combines amounts for same account" {
    const allocator = testing.allocator;
    
    var tx = newTransferTransaction(allocator);
    defer tx.deinit();
    
    const account = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    const amount1 = try Hbar.fromTinybars(1000);
    const amount2 = try Hbar.fromTinybars(500);
    
    try tx.addHbarTransfer(account, amount1);
    try tx.addHbarTransfer(account, amount2);
    
    try testing.expectEqual(@as(usize, 1), tx.hbar_transfers.items.len);
    try testing.expect(tx.hbar_transfers.items[0].account_id.equals(account));
    try testing.expectEqual(@as(i64, 1500), tx.hbar_transfers.items[0].amount.toTinybars());
}

test "TransferTransaction.addApprovedHbarTransfer adds approved transfer" {
    const allocator = testing.allocator;
    
    var tx = newTransferTransaction(allocator);
    defer tx.deinit();
    
    const account = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    const amount = try Hbar.fromTinybars(1000);
    
    try tx.addApprovedHbarTransfer(account, amount);
    
    try testing.expectEqual(@as(usize, 1), tx.hbar_transfers.items.len);
    try testing.expect(tx.hbar_transfers.items[0].is_approved);
}

test "TransferTransaction.addTokenTransfer adds token transfer" {
    const allocator = testing.allocator;
    
    var tx = newTransferTransaction(allocator);
    defer tx.deinit();
    
    const token_id = TokenId{ .shard = 0, .realm = 0, .account = 100 };
    const account = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    const amount: i64 = 50;
    
    try tx.addTokenTransfer(token_id, account, amount);
    
    try testing.expectEqual(@as(usize, 1), tx.token_transfers.items.len);
    try testing.expect(tx.token_transfers.items[0].token_id.equals(token_id));
    try testing.expect(tx.token_transfers.items[0].account_id.equals(account));
    try testing.expectEqual(amount, tx.token_transfers.items[0].amount);
}

test "TransferTransaction.addTokenTransfer combines amounts for same token-account pair" {
    const allocator = testing.allocator;
    
    var tx = newTransferTransaction(allocator);
    defer tx.deinit();
    
    const token_id = TokenId{ .shard = 0, .realm = 0, .account = 100 };
    const account = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    
    try tx.addTokenTransfer(token_id, account, 50);
    try tx.addTokenTransfer(token_id, account, 30);
    
    try testing.expectEqual(@as(usize, 1), tx.token_transfers.items.len);
    try testing.expectEqual(@as(i64, 80), tx.token_transfers.items[0].amount);
}

test "TransferTransaction.addTokenTransferWithDecimals stores expected decimals" {
    const allocator = testing.allocator;
    
    var tx = newTransferTransaction(allocator);
    defer tx.deinit();
    
    const token_id = TokenId{ .shard = 0, .realm = 0, .account = 100 };
    const account = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    const decimals: u32 = 8;
    
    try tx.addTokenTransferWithDecimals(token_id, account, 50, decimals);
    
    try testing.expectEqual(@as(usize, 1), tx.token_transfers.items.len);
    try testing.expectEqual(decimals, tx.token_transfers.items[0].expected_decimals.?);
    try testing.expectEqual(decimals, tx.token_decimals.get(token_id).?);
}

test "TransferTransaction.addApprovedTokenTransfer adds approved token transfer" {
    const allocator = testing.allocator;
    
    var tx = newTransferTransaction(allocator);
    defer tx.deinit();
    
    const token_id = TokenId{ .shard = 0, .realm = 0, .account = 100 };
    const account = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    
    try tx.addApprovedTokenTransfer(token_id, account, 50);
    
    try testing.expectEqual(@as(usize, 1), tx.token_transfers.items.len);
    try testing.expect(tx.token_transfers.items[0].is_approved);
}

test "TransferTransaction.addNftTransfer adds NFT transfer" {
    const allocator = testing.allocator;
    
    var tx = newTransferTransaction(allocator);
    defer tx.deinit();
    
    const token_id = TokenId{ .shard = 0, .realm = 0, .account = 100 };
    const nft_id = NftId{ .token_id = token_id, .serial_number = 1 };
    const sender = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    const receiver = AccountId{ .shard = 0, .realm = 0, .account = 1002 };
    
    try tx.addNftTransfer(nft_id, sender, receiver);
    
    try testing.expectEqual(@as(usize, 1), tx.nft_transfers.items.len);
    try testing.expect(tx.nft_transfers.items[0].nft_id.equals(nft_id));
    try testing.expect(tx.nft_transfers.items[0].sender_account_id.equals(sender));
    try testing.expect(tx.nft_transfers.items[0].receiver_account_id.equals(receiver));
}

test "TransferTransaction.addNftTransfer rejects duplicate NFT transfer" {
    const allocator = testing.allocator;
    
    var tx = newTransferTransaction(allocator);
    defer tx.deinit();
    
    const token_id = TokenId{ .shard = 0, .realm = 0, .account = 100 };
    const nft_id = NftId{ .token_id = token_id, .serial_number = 1 };
    const sender = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    const receiver = AccountId{ .shard = 0, .realm = 0, .account = 1002 };
    
    try tx.addNftTransfer(nft_id, sender, receiver);
    const result = tx.addNftTransfer(nft_id, sender, receiver);
    
    try testing.expectError(error.InvalidParameter, result);
}

test "TransferTransaction.addApprovedNftTransfer adds approved NFT transfer" {
    const allocator = testing.allocator;
    
    var tx = newTransferTransaction(allocator);
    defer tx.deinit();
    
    const token_id = TokenId{ .shard = 0, .realm = 0, .account = 100 };
    const nft_id = NftId{ .token_id = token_id, .serial_number = 1 };
    const sender = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    const receiver = AccountId{ .shard = 0, .realm = 0, .account = 1002 };
    
    try tx.addApprovedNftTransfer(nft_id, sender, receiver);
    
    try testing.expectEqual(@as(usize, 1), tx.nft_transfers.items.len);
    try testing.expect(tx.nft_transfers.items[0].is_approved);
}

test "TransferTransaction.validateTransfers validates HBAR transfers sum to zero" {
    const allocator = testing.allocator;
    
    var tx = newTransferTransaction(allocator);
    defer tx.deinit();
    
    const account1 = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    const account2 = AccountId{ .shard = 0, .realm = 0, .account = 1002 };
    
    // Add unbalanced transfers
    try tx.addHbarTransfer(account1, try Hbar.fromTinybars(1000));
    
    const result = tx.validateTransfers();
    try testing.expectError(error.InvalidAccountAmounts, result);
    
    // Balance the transfers
    try tx.addHbarTransfer(account2, try Hbar.fromTinybars(-1000));
    
    try tx.validateTransfers();
}

test "TransferTransaction.validateTransfers validates token transfers sum to zero" {
    const allocator = testing.allocator;
    
    var tx = newTransferTransaction(allocator);
    defer tx.deinit();
    
    const token_id = TokenId{ .shard = 0, .realm = 0, .account = 100 };
    const account1 = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    const account2 = AccountId{ .shard = 0, .realm = 0, .account = 1002 };
    
    // Add unbalanced token transfers
    try tx.addTokenTransfer(token_id, account1, 100);
    
    const result = tx.validateTransfers();
    try testing.expectError(error.TransfersNotZeroSumForToken, result);
    
    // Balance the transfers
    try tx.addTokenTransfer(token_id, account2, -100);
    
    try tx.validateTransfers();
}

test "TransferTransaction.freeze validates transfers before freezing" {
    const allocator = testing.allocator;
    
    var tx = newTransferTransaction(allocator);
    defer tx.deinit();
    
    const account = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    
    // Add unbalanced transfer
    try tx.addHbarTransfer(account, try Hbar.fromTinybars(1000));
    
    const result = tx.freeze();
    try testing.expectError(error.InvalidAccountAmounts, result);
}

test "TransferTransaction.setTransactionMemo sets memo" {
    const allocator = testing.allocator;
    
    var tx = newTransferTransaction(allocator);
    defer tx.deinit();
    
    const memo = "Test memo";
    _ = try tx.setTransactionMemo(memo);
    
    try testing.expectEqualStrings(memo, tx.base.transaction_memo);
}

test "HbarTransfer.init creates transfer with default approval" {
    const account = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    const amount = try Hbar.fromTinybars(1000);
    
    const transfer = HbarTransfer.init(account, amount);
    
    try testing.expect(transfer.account_id.equals(account));
    try testing.expectEqual(amount.toTinybars(), transfer.amount.toTinybars());
    try testing.expect(!transfer.is_approved);
}

test "HbarTransfer.initApproved creates approved transfer" {
    const account = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    const amount = try Hbar.fromTinybars(1000);
    
    const transfer = HbarTransfer.initApproved(account, amount);
    
    try testing.expect(transfer.is_approved);
}

test "TokenTransfer.init creates transfer with defaults" {
    const allocator = testing.allocator;
    
    const token_id = TokenId{ .shard = 0, .realm = 0, .account = 100 };
    const account = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    const amount: i64 = 50;
    
    var transfer = TokenTransfer.init(token_id, account, amount, allocator);
    defer transfer.deinit();
    
    try testing.expect(transfer.token_id.equals(token_id));
    try testing.expect(transfer.account_id.equals(account));
    try testing.expectEqual(amount, transfer.amount);
    try testing.expect(!transfer.is_approved);
    try testing.expectEqual(@as(?u32, null), transfer.expected_decimals);
}

test "TokenTransfer.initWithDecimals creates transfer with decimals" {
    const allocator = testing.allocator;
    
    const token_id = TokenId{ .shard = 0, .realm = 0, .account = 100 };
    const account = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    const amount: i64 = 50;
    const decimals: u32 = 8;
    
    var transfer = TokenTransfer.initWithDecimals(token_id, account, amount, decimals, allocator);
    defer transfer.deinit();
    
    try testing.expectEqual(decimals, transfer.expected_decimals.?);
}

test "TokenTransfer.initApproved creates approved transfer" {
    const allocator = testing.allocator;
    
    const token_id = TokenId{ .shard = 0, .realm = 0, .account = 100 };
    const account = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    const amount: i64 = 50;
    
    var transfer = TokenTransfer.initApproved(token_id, account, amount, allocator);
    defer transfer.deinit();
    
    try testing.expect(transfer.is_approved);
}

test "NftTransfer.init creates transfer with defaults" {
    const token_id = TokenId{ .shard = 0, .realm = 0, .account = 100 };
    const nft_id = NftId{ .token_id = token_id, .serial_number = 1 };
    const sender = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    const receiver = AccountId{ .shard = 0, .realm = 0, .account = 1002 };
    
    const transfer = NftTransfer.init(nft_id, sender, receiver);
    
    try testing.expect(transfer.nft_id.equals(nft_id));
    try testing.expect(transfer.sender_account_id.equals(sender));
    try testing.expect(transfer.receiver_account_id.equals(receiver));
    try testing.expect(!transfer.is_approved);
}

test "NftTransfer.initApproved creates approved transfer" {
    const token_id = TokenId{ .shard = 0, .realm = 0, .account = 100 };
    const nft_id = NftId{ .token_id = token_id, .serial_number = 1 };
    const sender = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    const receiver = AccountId{ .shard = 0, .realm = 0, .account = 1002 };
    
    const transfer = NftTransfer.initApproved(nft_id, sender, receiver);
    
    try testing.expect(transfer.is_approved);
}

test "TransferTransaction method chaining works" {
    const allocator = testing.allocator;
    
    var tx = newTransferTransaction(allocator);
    defer tx.deinit();
    
    const result = try tx.setTransactionMemo("Test");
    
    try testing.expectEqual(&tx, result);
}

test "TransferTransaction.buildTransactionBody creates protobuf" {
    const allocator = testing.allocator;
    
    var tx = newTransferTransaction(allocator);
    defer tx.deinit();
    
    const account1 = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    const account2 = AccountId{ .shard = 0, .realm = 0, .account = 1002 };
    
    try tx.addHbarTransfer(account1, try Hbar.fromTinybars(1000));
    try tx.addHbarTransfer(account2, try Hbar.fromTinybars(-1000));
    
    const body = try tx.buildTransactionBody();
    defer allocator.free(body);
    
    try testing.expect(body.len > 0);
}
const std = @import("std");
const testing = std.testing;
const AccountAllowance = @import("account_allowance.zig").AccountAllowance;
const AccountId = @import("account_id.zig").AccountId;
const TokenId = @import("../token/token_id.zig").TokenId;
const NftId = @import("../token/nft_id.zig").NftId;
const Hbar = @import("../core/hbar.zig").Hbar;

test "HbarAllowance creation and methods" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const owner = AccountId.init(0, 0, 100);
    const spender = AccountId.init(0, 0, 200);
    const amount = try Hbar.from(50);
    
    const allowance = AccountAllowance.HbarAllowance{
        .owner_account_id = owner,
        .spender_account_id = spender,
        .amount = amount,
    };
    
    try testing.expectEqual(owner.num, allowance.owner_account_id.num);
    try testing.expectEqual(spender.num, allowance.spender_account_id.num);
    try testing.expectEqual(amount.tinybar, allowance.amount.tinybar);
    
    // Test serialization
    var writer = @import("../protobuf/writer.zig").ProtobufWriter.init(allocator);
    defer writer.deinit();
    
    try allowance.serialize(&writer);
    const bytes = writer.toBytes();
    try testing.expect(bytes.len > 0);
}

test "TokenAllowance creation and validation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const owner = AccountId.init(0, 0, 100);
    const spender = AccountId.init(0, 0, 200);
    const token = TokenId.init(0, 0, 500);
    
    const allowance = AccountAllowance.TokenAllowance{
        .token_id = token,
        .owner_account_id = owner,
        .spender_account_id = spender,
        .amount = 1000,
    };
    
    try testing.expectEqual(token.num, allowance.token_id.num);
    try testing.expectEqual(@as(i64, 1000), allowance.amount);
    
    // Test serialization
    var writer = @import("../protobuf/writer.zig").ProtobufWriter.init(allocator);
    defer writer.deinit();
    
    try allowance.serialize(&writer);
    const bytes = writer.toBytes();
    try testing.expect(bytes.len > 0);
}

test "NftAllowance with approved for all" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const owner = AccountId.init(0, 0, 100);
    const spender = AccountId.init(0, 0, 200);
    const token = TokenId.init(0, 0, 500);
    
    var allowance = AccountAllowance.NftAllowance.init(allocator);
    defer allowance.deinit();
    
    allowance.token_id = token;
    allowance.owner_account_id = owner;
    allowance.spender_account_id = spender;
    allowance.approved_for_all = true;
    
    try allowance.addSerialNumber(1);
    try allowance.addSerialNumber(2);
    try allowance.addSerialNumber(3);
    
    try testing.expect(allowance.approved_for_all.?);
    try testing.expectEqual(@as(usize, 3), allowance.serial_numbers.items.len);
    
    // Test contains
    try testing.expect(allowance.containsSerialNumber(2));
    try testing.expect(!allowance.containsSerialNumber(4));
}

test "AccountAllowance list operations" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var list = AccountAllowance.AllowanceList.init(allocator);
    defer list.deinit();
    
    // Add Hbar allowance
    const hbar_allowance = AccountAllowance.HbarAllowance{
        .owner_account_id = AccountId.init(0, 0, 100),
        .spender_account_id = AccountId.init(0, 0, 200),
        .amount = try Hbar.from(50),
    };
    try list.addHbarAllowance(hbar_allowance);
    
    // Add Token allowance
    const token_allowance = AccountAllowance.TokenAllowance{
        .token_id = TokenId.init(0, 0, 500),
        .owner_account_id = AccountId.init(0, 0, 100),
        .spender_account_id = AccountId.init(0, 0, 200),
        .amount = 1000,
    };
    try list.addTokenAllowance(token_allowance);
    
    try testing.expectEqual(@as(usize, 1), list.hbar_allowances.items.len);
    try testing.expectEqual(@as(usize, 1), list.token_allowances.items.len);
}

test "AccountAllowance approval and deletion" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var approval = AccountAllowance.ApprovalTransaction.init(allocator);
    defer approval.deinit();
    
    const owner = AccountId.init(0, 0, 100);
    const spender = AccountId.init(0, 0, 200);
    
    // Approve Hbar allowance
    try approval.approveHbarAllowance(owner, spender, try Hbar.from(100));
    
    // Approve token allowance
    const token = TokenId.init(0, 0, 500);
    try approval.approveTokenAllowance(token, owner, spender, 5000);
    
    // Approve NFT allowance
    try approval.approveNftAllowance(token, owner, spender, &[_]i64{1, 2, 3});
    
    try testing.expectEqual(@as(usize, 1), approval.hbar_approvals.items.len);
    try testing.expectEqual(@as(usize, 1), approval.token_approvals.items.len);
    try testing.expectEqual(@as(usize, 1), approval.nft_approvals.items.len);
    
    // Test deletion
    var deletion = AccountAllowance.DeletionTransaction.init(allocator);
    defer deletion.deinit();
    
    try deletion.deleteAllTokenNftAllowances(token, owner);
    try testing.expectEqual(@as(usize, 1), deletion.nft_deletions.items.len);
}
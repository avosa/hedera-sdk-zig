const std = @import("std");
const testing = std.testing;
const AccountBalance = @import("account_balance.zig").AccountBalance;
const hedera.AccountId = @import("delete_account_id.zig").hedera.AccountId;
const hedera.TokenId = @import("../token/token_id.zig").hedera.TokenId;
const hedera.Hbar = @import("../core/hbar.zig").hedera.Hbar;

test "AccountBalance initialization and fields" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var balance = AccountBalance.init(allocator);
    defer balance.deinit();
    
    balance.account_id = AccountId.init(0, 0, 100);
    balance.hbars = try Hbar.from(1000);
    
    try testing.expectEqual(@as(u64, 100), balance.account_id.?.account);
    try testing.expectEqual(@as(i64, 100000000000), balance.hbars.tinybar);
}

test "AccountBalance token balances" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var balance = AccountBalance.init(allocator);
    defer balance.deinit();
    
    // Add token balances
    const token1 = TokenId.init(0, 0, 500);
    const token2 = TokenId.init(0, 0, 501);
    
    _ = balance.setTokenBalance(token1, 1000);
    _ = balance.setTokenBalance(token2, 2000);
    
    try testing.expectEqual(@as(?u64, 1000), balance.getTokenBalance(token1));
    try testing.expectEqual(@as(?u64, 2000), balance.getTokenBalance(token2));
    try testing.expectEqual(@as(?u64, null), balance.getTokenBalance(TokenId.init(0, 0, 999)));
}

test "AccountBalance decimal balances" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var balance = AccountBalance.init(allocator);
    defer balance.deinit();
    
    const token = TokenId.init(0, 0, 500);
    
    // Set token balance with decimals
    _ = balance.setTokenBalanceWithDecimals(token, 1000, 8);
    
    const decimal_balance = balance.getTokenBalanceDecimal(token);
    try testing.expect(decimal_balance != null);
    try testing.expectEqual(@as(u64, 1000), decimal_balance.?.balance);
    try testing.expectEqual(@as(u32, 8), decimal_balance.?.decimals);
}

test "AccountBalance serialization" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var balance = AccountBalance.init(allocator);
    defer balance.deinit();
    
    balance.account_id = AccountId.init(0, 0, 100);
    balance.hbars = try Hbar.from(500);
    
    _ = balance.setTokenBalance(TokenId.init(0, 0, 600), 3000);
    
    // Serialize
    var writer = @import("../protobuf/writer.zig").ProtobufWriter.init(allocator);
    defer writer.deinit();
    
    try balance.serialize(&writer);
    const bytes = writer.toBytes();
    try testing.expect(bytes.len > 0);
    
    // Test deserialization
    var reader = @import("../protobuf/reader.zig").ProtobufReader.init(bytes);
    var deserialized = AccountBalance.init(allocator);
    defer deserialized.deinit();
    
    try deserialized.deserialize(&reader);
    try testing.expectEqual(balance.account_id.?.account, deserialized.account_id.?.account);
    try testing.expectEqual(balance.hbars.tinybar, deserialized.hbars.tinybar);
}

test "AccountBalance pending airdrops" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var balance = AccountBalance.init(allocator);
    defer balance.deinit();
    
    // Add pending airdrop
    const airdrop = AccountBalance.PendingAirdrop{
        .airdrop_id = @import("../token/token_airdrop.zig").AirdropId{
            .sender_id = AccountId.init(0, 0, 50),
            .receiver_id = AccountId.init(0, 0, 100),
            .token_id = TokenId.init(0, 0, 500),
            .serial_number = null,
        },
        .amount = 1000,
    };
    
    try balance.addPendingAirdrop(airdrop);
    try testing.expectEqual(@as(usize, 1), balance.pending_airdrops.items.len);
    
    const first_airdrop = balance.pending_airdrops.items[0];
    try testing.expectEqual(@as(u64, 50), first_airdrop.airdrop_id.sender_id.num());
    try testing.expectEqual(@as(u64, 100), first_airdrop.airdrop_id.receiver_id.num());
    try testing.expectEqual(@as(u64, 1000), first_airdrop.amount);
}

test "AccountBalance comparison" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var balance1 = AccountBalance.init(allocator);
    defer balance1.deinit();
    balance1.hbars = try Hbar.from(1000);
    
    var balance2 = AccountBalance.init(allocator);
    defer balance2.deinit();
    balance2.hbars = try Hbar.from(500);
    
    try testing.expect(balance1.hbars.tinybar > balance2.hbars.tinybar);
    
    // Test equal balances
    balance2.hbars = try Hbar.from(1000);
    try testing.expectEqual(balance1.hbars.tinybar, balance2.hbars.tinybar);
}

test "AccountBalance toString" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var balance = AccountBalance.init(allocator);
    defer balance.deinit();
    
    balance.account_id = AccountId.init(0, 0, 100);
    balance.hbars = try Hbar.from(50);
    
    const str = try balance.toString(allocator);
    defer allocator.free(str);
    
    try testing.expect(str.len > 0);
    try testing.expect(std.mem.indexOf(u8, str, "0.0.100") != null);
    try testing.expect(std.mem.indexOf(u8, str, "50") != null);
}


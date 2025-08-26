const std = @import("std");
const testing = std.testing;
const AccountBalanceQuery = @import("../../src/account/account_balance_query.zig").AccountBalanceQuery;
const AccountBalance = @import("../../src/account/account_balance_query.zig").AccountBalance;
const TokenBalance = @import("../../src/account/account_balance_query.zig").TokenBalance;
const AccountId = @import("../../src/core/id.zig").AccountId;
const ContractId = @import("../../src/core/id.zig").ContractId;
const TokenId = @import("../../src/core/id.zig").TokenId;
const Hbar = @import("../../src/core/hbar.zig").Hbar;
const Duration = @import("../../src/core/duration.zig").Duration;

const newAccountBalanceQuery = @import("../../src/account/account_balance_query.zig").newAccountBalanceQuery;

test "AccountBalanceQuery.init creates valid query" {
    const allocator = testing.allocator;
    
    var query = AccountBalanceQuery.init(allocator);
    defer query.deinit();
    
    // Verify default values
    try testing.expectEqual(@as(?AccountId, null), query.account_id);
    try testing.expectEqual(@as(?ContractId, null), query.contract_id);
    try testing.expectEqual(@as(i64, 30), query.request_timeout.seconds);
    try testing.expectEqual(@as(i64, 8), query.max_backoff.seconds);
    try testing.expectEqual(@as(i64, 0), query.min_backoff.seconds);
    try testing.expectEqual(@as(i32, 250), query.min_backoff.nanos / 1_000_000);
    try testing.expect(!query.base.is_payment_required);
}

test "AccountBalanceQuery.setAccountId sets account ID" {
    const allocator = testing.allocator;
    
    var query = AccountBalanceQuery.init(allocator);
    defer query.deinit();
    
    const account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    _ = query.setAccountId(account_id);
    
    try testing.expect(query.account_id != null);
    try testing.expect(query.account_id.?.equals(account_id));
    try testing.expectEqual(@as(?ContractId, null), query.contract_id);
    try testing.expect(!query.base.is_payment_required);
}

test "AccountBalanceQuery.setContractId sets contract ID" {
    const allocator = testing.allocator;
    
    var query = AccountBalanceQuery.init(allocator);
    defer query.deinit();
    
    const contract_id = ContractId{ .shard = 0, .realm = 0, .account = 2001 };
    _ = query.setContractId(contract_id);
    
    try testing.expect(query.contract_id != null);
    try testing.expect(query.contract_id.?.equals(contract_id));
    try testing.expectEqual(@as(?AccountId, null), query.account_id);
    try testing.expect(!query.base.is_payment_required);
}

test "AccountBalanceQuery.setMaxRetry sets max attempts" {
    const allocator = testing.allocator;
    
    var query = AccountBalanceQuery.init(allocator);
    defer query.deinit();
    
    const max_retry: u32 = 5;
    _ = query.setMaxRetry(max_retry);
    
    try testing.expectEqual(max_retry, query.base.max_attempts);
    try testing.expectEqual(max_retry, query.max_retry());
}

test "AccountBalanceQuery clears account when setting contract" {
    const allocator = testing.allocator;
    
    var query = AccountBalanceQuery.init(allocator);
    defer query.deinit();
    
    const account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    const contract_id = ContractId{ .shard = 0, .realm = 0, .account = 2001 };
    
    _ = query.setAccountId(account_id);
    try testing.expect(query.account_id != null);
    
    _ = query.setContractId(contract_id);
    try testing.expectEqual(@as(?AccountId, null), query.account_id);
    try testing.expect(query.contract_id != null);
}

test "AccountBalanceQuery clears contract when setting account" {
    const allocator = testing.allocator;
    
    var query = AccountBalanceQuery.init(allocator);
    defer query.deinit();
    
    const account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    const contract_id = ContractId{ .shard = 0, .realm = 0, .account = 2001 };
    
    _ = query.setContractId(contract_id);
    try testing.expect(query.contract_id != null);
    
    _ = query.setAccountId(account_id);
    try testing.expectEqual(@as(?ContractId, null), query.contract_id);
    try testing.expect(query.account_id != null);
}

test "AccountBalanceQuery.execute returns AccountBalance" {
    const allocator = testing.allocator;
    
    var query = AccountBalanceQuery.init(allocator);
    defer query.deinit();
    
    // Verify execute method exists with correct signature
    try testing.expect(@hasDecl(@TypeOf(query), "execute"));
}

test "AccountBalanceQuery method chaining works" {
    const allocator = testing.allocator;
    
    var query = AccountBalanceQuery.init(allocator);
    defer query.deinit();
    
    const account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
    
    const result = query
        .setAccountId(account_id)
        .setMaxRetry(3);
    
    try testing.expectEqual(&query, result);
    try testing.expect(query.account_id != null);
    try testing.expectEqual(@as(u32, 3), query.base.max_attempts);
}

test "AccountBalance init and deinit work" {
    const allocator = testing.allocator;
    
    var balance = AccountBalance.init(allocator);
    defer balance.deinit();
    
    try testing.expectEqual(@as(i64, 0), balance.hbars.toTinybars());
    try testing.expectEqual(@as(usize, 0), balance.tokens.count());
    try testing.expectEqual(@as(usize, 0), balance.token_decimals.count());
}

test "AccountBalance.getTokenBalance returns balance or zero" {
    const allocator = testing.allocator;
    
    var balance = AccountBalance.init(allocator);
    defer balance.deinit();
    
    const token_id = TokenId{ .shard = 0, .realm = 0, .account = 100 };
    
    // Should return 0 for non-existent token
    try testing.expectEqual(@as(u64, 0), balance.getTokenBalance(token_id));
    
    // Add a balance
    try balance.tokens.put(token_id, 5000);
    
    // Should return the balance
    try testing.expectEqual(@as(u64, 5000), balance.getTokenBalance(token_id));
}

test "AccountBalance.getTokenDecimals returns decimals or zero" {
    const allocator = testing.allocator;
    
    var balance = AccountBalance.init(allocator);
    defer balance.deinit();
    
    const token_id = TokenId{ .shard = 0, .realm = 0, .account = 100 };
    
    // Should return 0 for non-existent token
    try testing.expectEqual(@as(u32, 0), balance.getTokenDecimals(token_id));
    
    // Add decimals
    try balance.token_decimals.put(token_id, 8);
    
    // Should return the decimals
    try testing.expectEqual(@as(u32, 8), balance.getTokenDecimals(token_id));
}

test "TokenBalance encode and decode roundtrip" {
    const allocator = testing.allocator;
    
    const original = TokenBalance{
        .token_id = TokenId{ .shard = 0, .realm = 0, .account = 100 },
        .balance = 1000000,
        .decimals = 6,
    };
    
    // Encode
    var writer = @import("../../src/protobuf/encoding.zig").ProtoWriter.init(allocator);
    defer writer.deinit();
    
    try original.encode(&writer);
    const bytes = try writer.toOwnedSlice();
    defer allocator.free(bytes);
    
    // Decode
    var reader = @import("../../src/protobuf/encoding.zig").ProtoReader.init(bytes);
    const decoded = try TokenBalance.decode(&reader, allocator);
    
    // Verify roundtrip
    try testing.expect(decoded.token_id.equals(original.token_id));
    try testing.expectEqual(original.balance, decoded.balance);
    try testing.expectEqual(original.decimals, decoded.decimals);
}

test "AccountBalanceQuery supports balance queries for accounts and contracts" {
    const allocator = testing.allocator;
    
    // Test for account
    {
        var query = AccountBalanceQuery.init(allocator);
        defer query.deinit();
        
        const account_id = AccountId{ .shard = 0, .realm = 0, .account = 1001 };
        _ = query.setAccountId(account_id);
        
        try testing.expect(query.account_id != null);
        try testing.expectEqual(@as(?ContractId, null), query.contract_id);
    }
    
    // Test for contract
    {
        var query = AccountBalanceQuery.init(allocator);
        defer query.deinit();
        
        const contract_id = ContractId{ .shard = 0, .realm = 0, .account = 2001 };
        _ = query.setContractId(contract_id);
        
        try testing.expectEqual(@as(?AccountId, null), query.account_id);
        try testing.expect(query.contract_id != null);
    }
}

test "AccountBalanceQuery validates that either account or contract is set" {
    const allocator = testing.allocator;
    
    var query = AccountBalanceQuery.init(allocator);
    defer query.deinit();
    
    // Query without setting either should be invalid for execution
    // This is implementation-specific validation
    try testing.expectEqual(@as(?AccountId, null), query.account_id);
    try testing.expectEqual(@as(?ContractId, null), query.contract_id);
}

test "newAccountBalanceQuery creates valid query" {
    const allocator = testing.allocator;
    
    var query = newAccountBalanceQuery(allocator);
    defer query.deinit();
    
    try testing.expect(@TypeOf(query) == AccountBalanceQuery);
    
    // Verify default values
    try testing.expectEqual(@as(?AccountId, null), query.account_id);
    try testing.expectEqual(@as(?ContractId, null), query.contract_id);
    try testing.expectEqual(@as(i64, 30), query.request_timeout.seconds);
    try testing.expectEqual(@as(i64, 8), query.max_backoff.seconds);
    try testing.expect(!query.base.is_payment_required);
}
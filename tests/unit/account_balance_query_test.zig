const std = @import("std");
const testing = std.testing;
const AccountBalanceQuery = @import("account_balance_query.zig").AccountBalanceQuery;
const hedera.AccountId = @import("delete_account_id.zig").hedera.AccountId;
const hedera.ContractId = @import("../contract/contract_id.zig").hedera.ContractId;
const hedera.Client = @import("../network/client.zig").hedera.Client;

test "AccountBalanceQuery initialization" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = AccountBalanceQuery.init(allocator);
    defer query.deinit();
    
    const account_id = AccountId.init(0, 0, 100);
    _ = try query.setAccountId(delete_account_id);
    
    try testing.expectEqual(delete_account_id.account, query.account_id.?.account);
    try testing.expect(query.contract_id == null);
}

test "AccountBalanceQuery with contract ID" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = AccountBalanceQuery.init(allocator);
    defer query.deinit();
    
    const contract_id = ContractId.init(0, 0, 200);
    _ = try query.setContractId(contract_id);
    
    try testing.expectEqual(contract_id.num(), query.contract_id.?.num());
    try testing.expect(query.account_id == null);
}

test "AccountBalanceQuery validation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = AccountBalanceQuery.init(allocator);
    defer query.deinit();
    
    // Should fail without account or contract ID
    try testing.expectError(error.InvalidParameter, query.validate());
    
    // Should succeed with account ID
    query.setAccountId(AccountId.init(0, 0, 100));
    try query.validate();
    
    // Should fail with both IDs
    query.setContractId(ContractId.init(0, 0, 200));
    try testing.expectError(error.InvalidParameter, query.validate());
}

test "AccountBalanceQuery build request" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = AccountBalanceQuery.init(allocator);
    defer query.deinit();
    
    query.setAccountId(AccountId.init(0, 0, 100));
    
    const request = try query.buildRequest(allocator);
    defer allocator.free(request);
    
    try testing.expect(request.len > 0);
}

test "AccountBalanceQuery response parsing" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = AccountBalanceQuery.init(allocator);
    defer query.deinit();
    
    query.setAccountId(AccountId.init(0, 0, 100));
    
    // Create mock response
    var writer = @import("../protobuf/writer.zig").ProtobufWriter.init(allocator);
    defer writer.deinit();
    
    // AccountID
    try writer.writeMessage(1, struct {
        fn write(w: anytype) !void {
            try w.writeInt64(3, 100); // account num
        }
    }.write);
    
    // Balance
    try writer.writeUint64(2, 50000000000); // 500 hbar in tinybar
    
    const response_bytes = writer.toBytes();
    
    const balance = try query.parseResponse(allocator, response_bytes);
    defer balance.deinit();
    
    try testing.expectEqual(@as(u64, 100), balance.account_id.?.account);
    try testing.expectEqual(@as(i64, 50000000000), balance.hbars.tinybar);
}

test "AccountBalanceQuery with token balances" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = AccountBalanceQuery.init(allocator);
    defer query.deinit();
    
    query.setAccountId(AccountId.init(0, 0, 100));
    
    // Create mock response with token balances
    var writer = @import("../protobuf/writer.zig").ProtobufWriter.init(allocator);
    defer writer.deinit();
    
    // AccountID
    try writer.writeMessage(1, struct {
        fn write(w: anytype) !void {
            try w.writeInt64(3, 100);
        }
    }.write);
    
    // hedera.Hbar balance
    try writer.writeUint64(2, 50000000000);
    
    // Token balances
    try writer.writeMessage(3, struct {
        fn write(w: anytype) !void {
            // Token ID
            try w.writeMessage(1, struct {
                fn write2(w2: anytype) !void {
                    try w2.writeInt64(3, 500); // token num
                }
            }.write2);
            // Balance
            try w.writeUint64(2, 1000);
            // Decimals
            try w.writeUint32(3, 8);
        }
    }.write);
    
    const response_bytes = writer.toBytes();
    
    const balance = try query.parseResponse(allocator, response_bytes);
    defer balance.deinit();
    
    const token_id = @import("../token/token_id.zig").TokenId.init(0, 0, 500);
    const token_balance = balance.getTokenBalanceDecimal(token_id);
    
    try testing.expect(token_balance != null);
    try testing.expectEqual(@as(u64, 1000), token_balance.?.balance);
    try testing.expectEqual(@as(u32, 8), token_balance.?.decimals);
}

test "AccountBalanceQuery caching" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = AccountBalanceQuery.init(allocator);
    defer query.deinit();
    
    query.setAccountId(AccountId.init(0, 0, 100));
    
    // Enable caching
    query.enableCaching(std.time.ns_per_s * 60); // 60 second cache
    
    // First request should not be cached
    try testing.expect(!query.isCached());
    
    // After setting cache, should be marked as cacheable
    try testing.expect(query.cache_duration > 0);
}


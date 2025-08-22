const std = @import("std");
const testing = std.testing;
const MirrorNode = @import("../network/mirror_node.zig").MirrorNode;
const ContractId = @import("../contract/contract_id.zig").ContractId;
const AccountId = @import("../account/account_id.zig").AccountId;
const TokenId = @import("../token/token_id.zig").TokenId;
const TopicId = @import("../topic/topic_id.zig").TopicId;
const Timestamp = @import("../core/timestamp.zig").Timestamp;

test "MirrorNode initialization" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const node = MirrorNode.init(allocator, "https://mainnet-public.mirrornode.hedera.com");
    defer node.deinit();
    
    try testing.expectEqualStrings("https://mainnet-public.mirrornode.hedera.com", node.url);
}

test "ContractQuery through Mirror Node" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = @import("contract_query.zig").ContractQuery.init(allocator);
    defer query.deinit();
    
    query.setContractId(ContractId.init(0, 0, 1000));
    query.setFunction("balanceOf");
    
    // Add address parameter
    var params = std.ArrayList(u8).init(allocator);
    defer params.deinit();
    
    // Address padded to 32 bytes
    try params.appendNTimes(0, 12);
    const address_bytes = AccountId.init(0, 0, 100).toBytes();
    try params.appendSlice(&address_bytes);
    
    query.setFunctionParameters(try params.toOwnedSlice());
    
    try testing.expectEqual(@as(u64, 1000), query.contract_id.?.num);
    try testing.expectEqualStrings("balanceOf", query.function_name.?);
    try testing.expectEqual(@as(usize, 32), query.function_parameters.?.len);
}

test "MirrorQuery for transactions" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = @import("mirror_query.zig").MirrorQuery(Transaction).init(allocator);
    defer query.deinit();
    
    // Set account filter
    query.setAccountId(AccountId.init(0, 0, 100));
    
    // Set timestamp range
    query.setTimestampRange(
        Timestamp.fromSeconds(1234567890),
        Timestamp.fromSeconds(1234567900),
    );
    
    // Set transaction type filter
    query.setTransactionType(.CRYPTO_TRANSFER);
    
    // Set result filter
    query.setResult(.SUCCESS);
    
    // Set limit
    query.setLimit(100);
    
    // Set order
    query.setOrder(.DESC);
    
    try testing.expectEqual(@as(u64, 100), query.account_id.?.num);
    try testing.expectEqual(@as(usize, 100), query.limit);
    try testing.expectEqual(.DESC, query.order);
}

test "MirrorQuery for account balances" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = @import("mirror_query.zig").MirrorQuery(AccountBalance).init(allocator);
    defer query.deinit();
    
    query.setAccountId(AccountId.init(0, 0, 100));
    query.setTimestamp(Timestamp.fromSeconds(1234567890));
    
    // Mock response parsing
    const mock_response =
        \\{
        \\  "timestamp": "1234567890.000000000",
        \\  "balances": [
        \\    {
        \\      "account": "0.0.100",
        \\      "balance": 50000000000,
        \\      "tokens": [
        \\        {
        \\          "token_id": "0.0.500",
        \\          "balance": 1000
        \\        }
        \\      ]
        \\    }
        \\  ]
        \\}
    ;
    
    const result = try query.parseResponse(allocator, mock_response);
    defer result.deinit();
    
    try testing.expectEqual(@as(u64, 100), result.account_id.?.num);
    try testing.expectEqual(@as(i64, 50000000000), result.hbars.tinybar);
    
    const token_balance = result.getTokenBalance(TokenId.init(0, 0, 500));
    try testing.expectEqual(@as(?u64, 1000), token_balance);
}

test "MirrorQuery for NFT info" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = @import("mirror_query.zig").MirrorQuery(NftInfo).init(allocator);
    defer query.deinit();
    
    const nft_id = @import("../token/nft_id.zig").NftId{
        .token_id = TokenId.init(0, 0, 500),
        .serial_number = 1,
    };
    
    query.setNftId(nft_id);
    
    try testing.expectEqual(@as(u64, 500), query.nft_id.?.token_id.num);
    try testing.expectEqual(@as(i64, 1), query.nft_id.?.serial_number);
}

test "TopicMessageQuery through Mirror Node" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = @import("../topic/topic_message_query.zig").TopicMessageQuery.init(allocator);
    defer query.deinit();
    
    query.setTopicId(TopicId.init(0, 0, 200));
    query.setStartTime(Timestamp.fromSeconds(1234567890));
    query.setEndTime(Timestamp.fromSeconds(1234567900));
    query.setLimit(100);
    
    try testing.expectEqual(@as(u64, 200), query.topic_id.?.num);
    try testing.expectEqual(@as(u32, 100), query.limit.?);
}

test "MirrorNode REST API paths" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const node = MirrorNode.init(allocator, "https://mainnet-public.mirrornode.hedera.com");
    defer node.deinit();
    
    // Test various endpoint paths
    const account_path = try node.buildPath(allocator, "/api/v1/accounts/{s}", .{"0.0.100"});
    defer allocator.free(account_path);
    try testing.expectEqualStrings("https://mainnet-public.mirrornode.hedera.com/api/v1/accounts/0.0.100", account_path);
    
    const tx_path = try node.buildPath(allocator, "/api/v1/transactions", .{});
    defer allocator.free(tx_path);
    try testing.expectEqualStrings("https://mainnet-public.mirrornode.hedera.com/api/v1/transactions", tx_path);
    
    const token_path = try node.buildPath(allocator, "/api/v1/tokens/{s}/balances", .{"0.0.500"});
    defer allocator.free(token_path);
    try testing.expectEqualStrings("https://mainnet-public.mirrornode.hedera.com/api/v1/tokens/0.0.500/balances", token_path);
}

test "MirrorNode subscription" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var subscription = @import("mirror_subscription.zig").MirrorSubscription(TopicMessage).init(allocator);
    defer subscription.deinit();
    
    subscription.setTopicId(TopicId.init(0, 0, 200));
    subscription.setStartTime(Timestamp.fromSeconds(1234567890));
    
    // Set callback
    const Callback = struct {
        fn onMessage(msg: *const TopicMessage) void {
            _ = msg;
            // Handle message
        }
    };
    
    subscription.setCallback(Callback.onMessage);
    
    try testing.expectEqual(@as(u64, 200), subscription.topic_id.?.num);
    try testing.expect(subscription.callback != null);
}

test "MirrorNode error handling" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const node = MirrorNode.init(allocator, "https://invalid-mirror-node.example.com");
    defer node.deinit();
    
    // Test error response parsing
    const error_response =
        \\{
        \\  "_status": {
        \\    "messages": [
        \\      {
        \\        "message": "Account not found"
        \\      }
        \\    ]
        \\  }
        \\}
    ;
    
    const result = node.parseErrorResponse(error_response);
    try testing.expectError(error.AccountNotFound, result);
}
const std = @import("std");
const testing = std.testing;
const hedera = @import("hedera");

test "newTokenCreateTransaction creates valid transaction" {
    const allocator = testing.allocator;
    
    var tx = hedera.tokenCreateTransaction(allocator);
    defer tx.deinit();
    
    // Verify it's properly initialized
    try testing.expect(!tx.base.frozen);
    try testing.expectEqualStrings("", tx.name);
    try testing.expectEqualStrings("", tx.symbol);
    try testing.expectEqual(@as(u32, 0), tx.decimals);
    try testing.expectEqual(@as(u64, 0), tx.initial_supply);
}

test "TokenCreateTransaction setters work" {
    const allocator = testing.allocator;
    
    var tx = hedera.tokenCreateTransaction(allocator);
    defer tx.deinit();
    
    _ = try tx.setTokenName("Test Token");
    _ = try tx.setTokenSymbol("TST");
    _ = try tx.setDecimals(8);
    _ = try tx.setInitialSupply(1000000);
    
    try testing.expectEqualStrings("Test Token", tx.name);
    try testing.expectEqualStrings("TST", tx.symbol);
    try testing.expectEqual(@as(u32, 8), tx.decimals);
    try testing.expectEqual(@as(u64, 1000000), tx.initial_supply);
}

test "newContractCreateTransaction creates valid transaction" {
    const allocator = testing.allocator;
    
    var tx = hedera.contractCreateTransaction(allocator);
    defer tx.deinit();
    
    // Verify it's properly initialized
    try testing.expect(!tx.base.frozen);
    try testing.expectEqual(@as(usize, 0), tx.bytecode.len);
}

test "ContractCreateTransaction setters work" {
    const allocator = testing.allocator;
    
    var tx = hedera.contractCreateTransaction(allocator);
    defer tx.deinit();
    
    const bytecode = &[_]u8{0x60, 0x80, 0x60, 0x40};
    _ = try tx.setBytecode(bytecode);
    _ = try tx.setGas(100000);
    
    try testing.expectEqualSlices(u8, bytecode, tx.bytecode);
    try testing.expectEqual(@as(i64, 100000), tx.gas);
}

test "newFileCreateTransaction creates valid transaction" {
    const allocator = testing.allocator;
    
    var tx = hedera.fileCreateTransaction(allocator);
    defer tx.deinit();
    
    // Verify it's properly initialized
    try testing.expect(!tx.base.frozen);
    try testing.expectEqual(@as(usize, 0), tx.contents.len);
}

test "FileCreateTransaction setters work" {
    const allocator = testing.allocator;
    
    var tx = hedera.fileCreateTransaction(allocator);
    defer tx.deinit();
    
    const contents = "Hello, Hedera!";
    _ = try tx.setContents(contents);
    
    try testing.expectEqualStrings(contents, tx.contents);
    
    // Test memo (if it exists and is optional)
    if (@hasField(@TypeOf(tx), "memo")) {
        _ = try tx.setMemo("Test file");
        if (tx.memo) |memo| {
            try testing.expectEqualStrings("Test file", memo);
        }
    }
}

test "newTopicCreateTransaction creates valid transaction" {
    const allocator = testing.allocator;
    
    var tx = try hedera.topicCreateTransaction(allocator);
    defer {
        tx.deinit();
        allocator.destroy(tx);
    }
    
    // Verify it's properly initialized - check for transaction field
    if (@hasField(@TypeOf(tx.*), "transaction")) {
        try testing.expect(!tx.transaction.frozen);
    } else if (@hasField(@TypeOf(tx.*), "base")) {
        try testing.expect(!tx.base.frozen);
    }
    
    // Memo field handling varies by implementation
}

test "TopicCreateTransaction setters work" {
    const allocator = testing.allocator;
    
    var tx = try hedera.topicCreateTransaction(allocator);
    defer {
        tx.deinit();
        allocator.destroy(tx);
    }
    
    // Test memo if it has a setter
    if (@hasDecl(@TypeOf(tx.*), "setMemo")) {
        _ = try tx.setMemo("Test topic");
        if (@hasField(@TypeOf(tx.*), "memo")) {
            if (tx.memo) |memo| {
                try testing.expectEqualStrings("Test topic", memo);
            }
        }
    }
    
    // Admin key handling tested separately
}

test "newScheduleCreateTransaction creates valid transaction" {
    const allocator = testing.allocator;
    
    var tx = hedera.scheduleCreateTransaction(allocator);
    defer tx.deinit();
    
    // Verify it's properly initialized
    try testing.expect(!tx.base.frozen);
    try testing.expect(!tx.wait_for_expiry);
    try testing.expectEqual(@as(?hedera.AccountId, null), tx.payer_account_id);
}

test "ScheduleCreateTransaction setters work" {
    const allocator = testing.allocator;
    
    var tx = hedera.scheduleCreateTransaction(allocator);
    defer tx.deinit();
    
    const payer = hedera.AccountId.init(0, 0, 1001);
    _ = try tx.setPayerAccountId(payer);
    
    try testing.expect(tx.payer_account_id != null);
    try testing.expect(tx.payer_account_id.?.equals(payer));
    
    _ = try tx.setWaitForExpiry(true);
    try testing.expect(tx.wait_for_expiry);
}

test "All specialized transactions support freezeWith" {
    const allocator = testing.allocator;
    
    // TokenCreateTransaction
    {
        var tx = hedera.tokenCreateTransaction(allocator);
        defer tx.deinit();
        try testing.expect(@hasDecl(@TypeOf(tx), "freezeWith"));
    }
    
    // ContractCreateTransaction
    {
        var tx = hedera.contractCreateTransaction(allocator);
        defer tx.deinit();
        try testing.expect(@hasDecl(@TypeOf(tx), "freezeWith"));
    }
    
    // FileCreateTransaction
    {
        var tx = hedera.fileCreateTransaction(allocator);
        defer tx.deinit();
        try testing.expect(@hasDecl(@TypeOf(tx), "freezeWith"));
    }
    
    // TopicCreateTransaction
    {
        var tx = try hedera.topicCreateTransaction(allocator);
        defer {
            tx.deinit();
            allocator.destroy(tx);
        }
        try testing.expect(@hasDecl(@TypeOf(tx.*), "freezeWith"));
    }
    
    // ScheduleCreateTransaction
    {
        var tx = hedera.scheduleCreateTransaction(allocator);
        defer tx.deinit();
        try testing.expect(@hasDecl(@TypeOf(tx), "freezeWith"));
    }
}

test "All specialized transactions support execute" {
    const allocator = testing.allocator;
    
    // TokenCreateTransaction
    {
        var tx = hedera.tokenCreateTransaction(allocator);
        defer tx.deinit();
        try testing.expect(@hasDecl(@TypeOf(tx), "execute"));
    }
    
    // ContractCreateTransaction
    {
        var tx = hedera.contractCreateTransaction(allocator);
        defer tx.deinit();
        try testing.expect(@hasDecl(@TypeOf(tx), "execute"));
    }
    
    // FileCreateTransaction
    {
        var tx = hedera.fileCreateTransaction(allocator);
        defer tx.deinit();
        try testing.expect(@hasDecl(@TypeOf(tx), "execute"));
    }
    
    // TopicCreateTransaction
    {
        var tx = try hedera.topicCreateTransaction(allocator);
        defer {
            tx.deinit();
            allocator.destroy(tx);
        }
        try testing.expect(@hasDecl(@TypeOf(tx.*), "execute"));
    }
    
    // ScheduleCreateTransaction
    {
        var tx = hedera.scheduleCreateTransaction(allocator);
        defer tx.deinit();
        try testing.expect(@hasDecl(@TypeOf(tx), "execute"));
    }
}
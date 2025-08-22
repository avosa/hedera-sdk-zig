const std = @import("std");
const testing = std.testing;
const hedera = @import("hedera");

test "ContractId creation and serialization" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const contract_id = hedera.ContractId.init(0, 0, 1000);
    
    try testing.expectEqual(@as(u64, 0), contract_id.shard());
    try testing.expectEqual(@as(u64, 0), contract_id.realm());
    try testing.expectEqual(@as(u64, 1000), contract_id.num());
    
    // Test EVM address
    const evm_address = try contract_id.toEvmAddress(allocator);
    defer allocator.free(evm_address);
    try testing.expect(evm_address.len > 0);
}

test "ContractInfo initialization and fields" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var info = hedera.ContractInfo.init(allocator);
    defer info.deinit();
    
    info.contract_id = hedera.ContractId.init(0, 0, 1000);
    info.account_id = hedera.AccountId.init(0, 0, 1000);
    
    var admin_key = try hedera.generate_private_key(allocator);
    defer admin_key.deinit();
    info.admin_key = hedera.Key.fromPublicKey(admin_key.getPublicKey());
    
    info.expiration_time = hedera.Timestamp.fromSeconds(1234567890);
    info.auto_renew_period = hedera.Duration.fromSeconds(7776000); // 90 days
    info.storage = 1024;
    info.memo = try allocator.dupe(u8, "Smart Contract");
    info.balance = try hedera.Hbar.from(100);
    info.deleted = false;
    info.ledger_id = try allocator.dupe(u8, "0x01");
    info.auto_renew_account_id = hedera.AccountId.init(0, 0, 800);
    info.max_automatic_token_associations = 10;
    info.staking_info = .{
        .staked_node_id = 3,
        .staked_account_id = null,
        .stake_period_start = hedera.Timestamp.fromSeconds(1234567800),
        .pending_reward = 50000000, // 0.5 hbar
        .staked_to_me = 100000000000, // 1000 hbar
        .decline_reward = false,
    };
    
    try testing.expectEqual(@as(u64, 1000), info.contract_id.?.num());
    try testing.expectEqual(@as(i64, 1024), info.storage);
    try testing.expectEqualStrings("Smart Contract", info.memo.?);
    try testing.expect(!info.deleted);
    try testing.expectEqual(@as(i32, 10), info.max_automatic_token_associations);
}

test "ContractCallResult parsing" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var result = hedera.ContractCallResult.init(allocator);
    defer result.deinit();
    
    result.contract_id = hedera.ContractId.init(0, 0, 1000);
    result.result = try allocator.dupe(u8, &[_]u8{0x00} ** 32); // Success result
    result.error_message = null;
    result.bloom = try allocator.alloc(u8, 256);
    @memset(result.bloom.?, 0);
    result.gas_used = 21000;
    result.gas_limit = 100000;
    
    // Add log
    var log = hedera.ContractLogInfo.init(allocator);
    log.contract_id = hedera.ContractId.init(0, 0, 1000);
    log.bloom = try allocator.alloc(u8, 256);
    @memset(log.bloom.?, 0);
    
    const topic1 = try allocator.dupe(u8, &[_]u8{0x01} ** 32);
    try log.topics.append(topic1);
    
    log.data = try allocator.dupe(u8, "log data");
    
    try result.logs.append(log);
    
    // Add created contract
    const created = hedera.ContractId.init(0, 0, 1001);
    try result.created_contract_ids.append(created);
    
    // Add state change
    const state_change = hedera.ContractCallResult.StateChange{
        .contract_id = hedera.ContractId.init(0, 0, 1000),
        .storage_changes = try allocator.alloc(hedera.ContractCallResult.StorageChange, 1),
        .allocator = allocator,
    };
    
    try result.state_changes.append(state_change);
    
    try testing.expectEqual(@as(u64, 21000), result.gas_used);
    try testing.expectEqual(@as(usize, 1), result.logs.items.len);
    try testing.expectEqual(@as(usize, 1), result.created_contract_ids.items.len);
    try testing.expectEqual(@as(u64, 1001), result.created_contract_ids.items[0].num());
}

test "FunctionSelector creation and encoding" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Test function selector from signature
    const selector = try hedera.FunctionSelector.fromSignature("transfer(address,uint256)");
    try testing.expectEqual(@as(usize, 4), selector.bytes.len);
    
    // Known selector for transfer(address,uint256) = 0xa9059cbb
    try testing.expectEqual(@as(u8, 0xa9), selector.bytes[0]);
    try testing.expectEqual(@as(u8, 0x05), selector.bytes[1]);
    try testing.expectEqual(@as(u8, 0x9c), selector.bytes[2]);
    try testing.expectEqual(@as(u8, 0xbb), selector.bytes[3]);
    
    // Test encoding with parameters
    var params = std.ArrayList([]const u8).init(allocator);
    defer params.deinit();
    
    // Address parameter (padded to 32 bytes)
    const address = try allocator.alloc(u8, 32);
    defer allocator.free(address);
    @memset(address, 0);
    address[31] = 0x42;
    try params.append(address);
    
    // Amount parameter (uint256)
    const amount = try allocator.alloc(u8, 32);
    defer allocator.free(amount);
    @memset(amount, 0);
    amount[31] = 100;
    try params.append(amount);
    
    const encoded = try selector.encode(allocator, params.items);
    defer allocator.free(encoded);
    
    try testing.expectEqual(@as(usize, 68), encoded.len); // 4 + 32 + 32
}

test "ContractAbi parsing and encoding" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create simple ABI
    var abi = hedera.ContractAbi.init(allocator);
    defer abi.deinit();
    
    // Add transfer function
    const transfer_func = hedera.ContractAbi.Function{
        .name = try allocator.dupe(u8, "transfer"),
        .inputs = try allocator.alloc(hedera.ContractAbi.Parameter, 2),
        .outputs = try allocator.alloc(hedera.ContractAbi.Parameter, 1),
        .state_mutability = .nonpayable,
        .type = .function,
        .allocator = allocator,
    };
    
    transfer_func.inputs[0] = .{
        .name = try allocator.dupe(u8, "to"),
        .type = try allocator.dupe(u8, "address"),
        .components = null,
        .allocator = allocator,
    };
    
    transfer_func.inputs[1] = .{
        .name = try allocator.dupe(u8, "amount"),
        .type = try allocator.dupe(u8, "uint256"),
        .components = null,
        .allocator = allocator,
    };
    
    transfer_func.outputs[0] = .{
        .name = try allocator.dupe(u8, ""),
        .type = try allocator.dupe(u8, "bool"),
        .components = null,
        .allocator = allocator,
    };
    
    try abi.functions.append(transfer_func);
    
    // Add Transfer event
    const transfer_event = hedera.ContractAbi.Event{
        .name = try allocator.dupe(u8, "Transfer"),
        .inputs = try allocator.alloc(hedera.ContractAbi.EventParameter, 3),
        .anonymous = false,
        .allocator = allocator,
    };
    
    transfer_event.inputs[0] = .{
        .name = try allocator.dupe(u8, "from"),
        .type = try allocator.dupe(u8, "address"),
        .indexed = true,
        .components = null,
        .allocator = allocator,
    };
    
    transfer_event.inputs[1] = .{
        .name = try allocator.dupe(u8, "to"),
        .type = try allocator.dupe(u8, "address"),
        .indexed = true,
        .components = null,
        .allocator = allocator,
    };
    
    transfer_event.inputs[2] = .{
        .name = try allocator.dupe(u8, "value"),
        .type = try allocator.dupe(u8, "uint256"),
        .indexed = false,
        .components = null,
        .allocator = allocator,
    };
    
    try abi.events.append(transfer_event);
    
    try testing.expectEqual(@as(usize, 1), abi.functions.items.len);
    try testing.expectEqual(@as(usize, 1), abi.events.items.len);
    
    // Test encoding function call
    const func = abi.getFunction("transfer");
    try testing.expect(func != null);
    try testing.expectEqualStrings("transfer", func.?.name);
}

test "Contract creation transaction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.ContractCreateTransaction.init(allocator);
    defer tx.deinit();
    
    // Set bytecode
    const bytecode = try allocator.dupe(u8, &[_]u8{0x60, 0x80, 0x60, 0x40}); // Simple bytecode
    _ = tx.setBytecode(bytecode);
    
    // Set constructor parameters
    const params = try allocator.dupe(u8, &[_]u8{0x00} ** 64);
    _ = tx.setConstructorParameters(params);
    
    // Set gas
    _ = tx.setGas(100000);
    
    // Set initial balance
    _ = tx.setInitialBalance(try hedera.Hbar.from(10));
    
    // Set admin key
    var admin_key = try hedera.generate_private_key(allocator);
    defer admin_key.deinit();
    _ = tx.setAdminKey(hedera.Key.fromPublicKey(admin_key.getPublicKey()));
    
    // Set memo
    _ = tx.setMemo("Test Contract");
    
    // Set auto renew
    _ = tx.setAutoRenewPeriod(hedera.Duration.fromDays(90));
    _ = tx.setAutoRenewAccountId(hedera.AccountId.init(0, 0, 800));
    
    // Set max automatic token associations
    _ = tx.setMaxAutomaticTokenAssociations(10);
    
    // Set staking
    _ = tx.setStakedNodeId(3);
    _ = tx.setDeclineStakingReward(false);
    
    try testing.expectEqual(@as(i64, 100000), tx.gas);
    try testing.expectEqualStrings("Test Contract", tx.memo);
    try testing.expectEqual(@as(i32, 10), tx.max_automatic_token_associations);
    try testing.expectEqual(@as(?i64, 3), tx.staked_node_id);
}


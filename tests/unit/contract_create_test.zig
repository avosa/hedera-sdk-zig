const std = @import("std");
const testing = std.testing;
const hedera = @import("hedera");

test "ContractCreateTransaction factory creates valid instance" {
    const allocator = testing.allocator;
    
    // Create transaction using factory
    const tx = hedera.newContractCreateTransaction(allocator);
    defer tx.deinit();
    
    // Verify it's properly initialized
    try testing.expect(tx.bytecode_file_id == null);
    try testing.expectEqualStrings(tx.bytecode, "");
    try testing.expect(tx.admin_key == null);
    try testing.expectEqual(tx.gas, 100000);
    try testing.expect(tx.initial_balance.equals(hedera.Hbar.zero()));
    try testing.expect(tx.proxy_account_id == null);
    try testing.expectEqualStrings(tx.constructor_parameters, "");
    try testing.expectEqualStrings(tx.memo, "");
    try testing.expectEqual(tx.max_automatic_token_associations, 0);
    try testing.expect(tx.auto_renew_account_id == null);
    try testing.expect(tx.staked_account_id == null);
    try testing.expect(tx.staked_node_id == null);
    try testing.expectEqual(tx.decline_staking_reward, false);
    try testing.expect(tx.auto_renew_period.seconds > 0); // Has default value
}

test "ContractCreateTransaction with bytecode file ID" {
    const allocator = testing.allocator;
    
    const tx = hedera.newContractCreateTransaction(allocator);
    defer tx.deinit();
    
    // Set bytecode file ID
    const file_id = hedera.FileId.init(0, 0, 100);
    _ = try tx.setBytecodeFileId(file_id);
    try testing.expect(tx.getBytecodeFileID().equals(file_id));
    try testing.expectEqualStrings(tx.getBytecode(), ""); // Bytecode cleared when file ID set
}

test "ContractCreateTransaction with direct bytecode" {
    const allocator = testing.allocator;
    
    const tx = hedera.newContractCreateTransaction(allocator);
    defer tx.deinit();
    
    // Set bytecode directly
    const bytecode = [_]u8{ 0x60, 0x80, 0x60, 0x40, 0x52 }; // Example EVM bytecode
    _ = try tx.setBytecode(&bytecode);
    try testing.expectEqualSlices(u8, tx.getBytecode(), &bytecode);
    try testing.expect(tx.getBytecodeFileID().isEmpty()); // File ID cleared when bytecode set
}

test "ContractCreateTransaction bytecode vs file ID mutual exclusion" {
    const allocator = testing.allocator;
    
    const tx = hedera.newContractCreateTransaction(allocator);
    defer tx.deinit();
    
    // First set bytecode
    const bytecode = [_]u8{ 0x60, 0x80, 0x60, 0x40, 0x52 };
    _ = try tx.setBytecode(&bytecode);
    try testing.expectEqualSlices(u8, tx.getBytecode(), &bytecode);
    
    // Then set file ID - should clear bytecode
    const file_id = hedera.FileId.init(0, 0, 200);
    _ = try tx.setBytecodeFileId(file_id);
    try testing.expect(tx.getBytecodeFileID().equals(file_id));
    try testing.expectEqualStrings(tx.getBytecode(), "");
    
    // Set bytecode again - should clear file ID
    _ = try tx.setBytecode(&bytecode);
    try testing.expectEqualSlices(u8, tx.getBytecode(), &bytecode);
    try testing.expect(tx.getBytecodeFileID().isEmpty());
}

test "ContractCreateTransaction admin key" {
    const allocator = testing.allocator;
    
    const tx = hedera.newContractCreateTransaction(allocator);
    defer tx.deinit();
    
    // Create test key
    const private_key = try hedera.Ed25519PrivateKey.generate();
    defer private_key.deinit();
    const public_key = private_key.getPublicKey();
    const key = hedera.Key.fromPublicKey(public_key);
    
    // Set admin key
    _ = try tx.setAdminKey(key);
    const retrieved_key = tx.getAdminKey();
    try testing.expect(retrieved_key != null);
    try testing.expect(retrieved_key.?.equals(key));
}

test "ContractCreateTransaction gas settings" {
    const allocator = testing.allocator;
    
    const tx = hedera.newContractCreateTransaction(allocator);
    defer tx.deinit();
    
    // Test default gas
    try testing.expectEqual(tx.getGas(), 100000);
    
    // Set custom gas
    _ = try tx.setGas(250000);
    try testing.expectEqual(tx.getGas(), 250000);
    
    // Test maximum gas value
    _ = try tx.setGas(15000000);
    try testing.expectEqual(tx.getGas(), 15000000);
}

test "ContractCreateTransaction initial balance" {
    const allocator = testing.allocator;
    
    const tx = hedera.newContractCreateTransaction(allocator);
    defer tx.deinit();
    
    // Test default initial balance (zero)
    try testing.expect(tx.getInitialBalance().equals(hedera.Hbar.zero()));
    
    // Set custom initial balance
    const balance = try hedera.Hbar.fromHbars(10);
    _ = try tx.setInitialBalance(balance);
    try testing.expect(tx.getInitialBalance().equals(balance));
    
    // Test with tinybars
    const tiny_balance = try hedera.Hbar.fromTinybars(5000000);
    _ = try tx.setInitialBalance(tiny_balance);
    try testing.expect(tx.getInitialBalance().equals(tiny_balance));
}

test "ContractCreateTransaction proxy account (deprecated)" {
    const allocator = testing.allocator;
    
    const tx = hedera.newContractCreateTransaction(allocator);
    defer tx.deinit();
    
    // Test default proxy account ID (empty)
    try testing.expect(tx.getProxyAccountID().isEmpty());
    
    // Set proxy account ID
    const proxy_account = hedera.AccountId.init(0, 0, 300);
    _ = try tx.setProxyAccountId(proxy_account);
    try testing.expect(tx.getProxyAccountID().equals(proxy_account));
}

test "ContractCreateTransaction auto renew period" {
    const allocator = testing.allocator;
    
    const tx = hedera.newContractCreateTransaction(allocator);
    defer tx.deinit();
    
    // Test default auto renew period (131500 minutes)
    const expected_seconds = 131500 * 60;
    try testing.expectEqual(tx.getAutoRenewPeriod().seconds, expected_seconds);
    
    // Set custom auto renew period
    const custom_period = hedera.Duration.fromDays(30);
    _ = try tx.setAutoRenewPeriod(custom_period);
    try testing.expectEqual(tx.getAutoRenewPeriod().seconds, custom_period.seconds);
}

test "ContractCreateTransaction constructor parameters" {
    const allocator = testing.allocator;
    
    const tx = hedera.newContractCreateTransaction(allocator);
    defer tx.deinit();
    
    // Test default constructor parameters (empty)
    try testing.expectEqualStrings(tx.getConstructorParameters(), "");
    
    // Set constructor parameters
    const params = [_]u8{ 0x00, 0x00, 0x00, 0x20, 0x48, 0x65, 0x6c, 0x6c, 0x6f };
    _ = try tx.setConstructorParameters(&params);
    try testing.expectEqualSlices(u8, tx.getConstructorParameters(), &params);
}

test "ContractCreateTransaction memo" {
    const allocator = testing.allocator;
    
    const tx = hedera.newContractCreateTransaction(allocator);
    defer tx.deinit();
    
    // Test default memo (empty)
    try testing.expectEqualStrings(tx.getContractMemo(), "");
    
    // Set custom memo
    const memo = "Smart contract for token management";
    _ = try tx.setMemo(memo);
    try testing.expectEqualStrings(tx.getContractMemo(), memo);
}

test "ContractCreateTransaction max automatic token associations" {
    const allocator = testing.allocator;
    
    const tx = hedera.newContractCreateTransaction(allocator);
    defer tx.deinit();
    
    // Test default value
    try testing.expectEqual(tx.getMaxAutomaticTokenAssociations(), 0);
    
    // Set custom value
    _ = try tx.setMaxAutomaticTokenAssociations(100);
    try testing.expectEqual(tx.getMaxAutomaticTokenAssociations(), 100);
    
    // Test negative value (edge case)
    _ = try tx.setMaxAutomaticTokenAssociations(-1);
    try testing.expectEqual(tx.getMaxAutomaticTokenAssociations(), -1);
}

test "ContractCreateTransaction auto renew account ID" {
    const allocator = testing.allocator;
    
    const tx = hedera.newContractCreateTransaction(allocator);
    defer tx.deinit();
    
    // Test default auto renew account ID (empty)
    try testing.expect(tx.getAutoRenewAccountID().isEmpty());
    
    // Set auto renew account ID
    const account_id = hedera.AccountId.init(0, 0, 400);
    _ = try tx.setAutoRenewAccountId(account_id);
    try testing.expect(tx.getAutoRenewAccountID().equals(account_id));
}

test "ContractCreateTransaction staking configuration" {
    const allocator = testing.allocator;
    
    const tx = hedera.newContractCreateTransaction(allocator);
    defer tx.deinit();
    
    // Test default values
    try testing.expect(tx.getStakedAccountID().isEmpty());
    try testing.expectEqual(tx.getStakedNodeID(), 0);
    try testing.expectEqual(tx.getDeclineStakingReward(), false);
    
    // Set staked account ID
    const staked_account = hedera.AccountId.init(0, 0, 500);
    _ = try tx.setStakedAccountID(staked_account);
    try testing.expect(tx.getStakedAccountID().equals(staked_account));
    try testing.expectEqual(tx.getStakedNodeID(), 0); // Should be cleared
    
    // Set staked node ID - should clear account ID
    _ = try tx.setStakedNodeId(3);
    try testing.expectEqual(tx.getStakedNodeID(), 3);
    try testing.expect(tx.getStakedAccountID().isEmpty()); // Should be cleared
    
    // Set decline staking reward
    _ = try tx.setDeclineStakingReward(true);
    try testing.expectEqual(tx.getDeclineStakingReward(), true);
}

test "ContractCreateTransaction staking mutual exclusion" {
    const allocator = testing.allocator;
    
    const tx = hedera.newContractCreateTransaction(allocator);
    defer tx.deinit();
    
    // Set staked account ID first
    const staked_account = hedera.AccountId.init(0, 0, 600);
    _ = try tx.setStakedAccountID(staked_account);
    try testing.expect(tx.getStakedAccountID().equals(staked_account));
    try testing.expectEqual(tx.staked_node_id, null);
    
    // Set staked node ID - should clear account ID
    _ = try tx.setStakedNodeId(5);
    try testing.expectEqual(tx.getStakedNodeID(), 5);
    try testing.expectEqual(tx.staked_account_id, null);
    
    // Set staked account ID again - should clear node ID
    _ = try tx.setStakedAccountID(staked_account);
    try testing.expect(tx.getStakedAccountID().equals(staked_account));
    try testing.expectEqual(tx.staked_node_id, null);
}

test "ContractCreateTransaction validation" {
    const allocator = testing.allocator;
    
    const tx = hedera.newContractCreateTransaction(allocator);
    defer tx.deinit();
    
    // Test execution without bytecode or file ID (should fail)
    const result = tx.execute(null);
    try testing.expectError(error.BytecodeRequired, result);
    
    // Set bytecode file ID
    const file_id = hedera.FileId.init(0, 0, 700);
    _ = try tx.setBytecodeFileId(file_id);
    
    // Now execution should not fail due to missing bytecode
    const result2 = tx.execute(null);
    try testing.expectError(error.ClientNotProvided, result2); // Different error now
}

test "ContractCreateTransaction freezeWith" {
    const allocator = testing.allocator;
    
    const tx = hedera.newContractCreateTransaction(allocator);
    defer tx.deinit();
    
    // Set required fields
    const file_id = hedera.FileId.init(0, 0, 800);
    _ = try tx.setBytecodeFileId(file_id);
    _ = try tx.setGas(200000);
    
    // Freeze without client (should use defaults)
    try tx.freezeWith(null);
    
    // Verify transaction is frozen
    try testing.expect(tx.base.frozen);
    try testing.expect(tx.base.transaction_id != null);
}

test "ContractCreateTransaction builds transaction body with file ID" {
    const allocator = testing.allocator;
    
    const tx = hedera.newContractCreateTransaction(allocator);
    defer tx.deinit();
    
    // Configure transaction with file ID
    const file_id = hedera.FileId.init(0, 0, 900);
    _ = try tx.setBytecodeFileId(file_id);
    _ = try tx.setGas(300000);
    _ = try tx.setInitialBalance(try hedera.Hbar.fromHbars(5));
    _ = try tx.setMemo("File-based contract");
    
    // Set transaction ID
    tx.base.transaction_id = hedera.TransactionId.generate(hedera.AccountId.init(0, 0, 2));
    
    // Build transaction body
    const body_bytes = try tx.buildTransactionBody();
    defer allocator.free(body_bytes);
    
    // Verify body was built
    try testing.expect(body_bytes.len > 0);
    
    // Parse to verify structure
    var reader = hedera.ProtoReader.init(body_bytes);
    var found_contract_create = false;
    
    while (reader.hasMore()) {
        const tag = try reader.readTag();
        if (tag.field_number == 7) { // contractCreateInstance field
            found_contract_create = true;
            break;
        }
        try reader.skipField(tag.wire_type);
    }
    
    try testing.expect(found_contract_create);
}

test "ContractCreateTransaction builds transaction body with direct bytecode" {
    const allocator = testing.allocator;
    
    const tx = hedera.newContractCreateTransaction(allocator);
    defer tx.deinit();
    
    // Configure transaction with direct bytecode
    const bytecode = [_]u8{ 0x60, 0x80, 0x60, 0x40, 0x52, 0x34, 0x80 };
    _ = try tx.setBytecode(&bytecode);
    _ = try tx.setGas(400000);
    
    const private_key = try hedera.Ed25519PrivateKey.generate();
    defer private_key.deinit();
    const admin_key = hedera.Key.fromPublicKey(private_key.getPublicKey());
    _ = try tx.setAdminKey(admin_key);
    
    _ = try tx.setMemo("Direct bytecode contract");
    _ = try tx.setMaxAutomaticTokenAssociations(50);
    
    // Set transaction ID
    tx.base.transaction_id = hedera.TransactionId.generate(hedera.AccountId.init(0, 0, 2));
    
    // Build transaction body
    const body_bytes = try tx.buildTransactionBody();
    defer allocator.free(body_bytes);
    
    // Verify body was built
    try testing.expect(body_bytes.len > 0);
    
    // Parse to verify structure
    var reader = hedera.ProtoReader.init(body_bytes);
    var found_contract_create = false;
    
    while (reader.hasMore()) {
        const tag = try reader.readTag();
        if (tag.field_number == 7) { // contractCreateInstance field
            found_contract_create = true;
            break;
        }
        try reader.skipField(tag.wire_type);
    }
    
    try testing.expect(found_contract_create);
}

test "ContractCreateTransaction frozen state protection" {
    const allocator = testing.allocator;
    
    const tx = hedera.newContractCreateTransaction(allocator);
    defer tx.deinit();
    
    // Manually freeze the transaction
    tx.base.frozen = true;
    
    // Verify all setters fail when frozen
    const file_id = hedera.FileId.init(0, 0, 1000);
    const file_result = tx.setBytecodeFileId(file_id);
    try testing.expectError(hedera.errors.HederaError.TransactionIsFrozen, file_result);
    
    const bytecode = [_]u8{ 0x60, 0x80 };
    const bytecode_result = tx.setBytecode(&bytecode);
    try testing.expectError(hedera.errors.HederaError.TransactionIsFrozen, bytecode_result);
    
    const private_key = try hedera.Ed25519PrivateKey.generate();
    defer private_key.deinit();
    const key = hedera.Key.fromPublicKey(private_key.getPublicKey());
    const admin_result = tx.setAdminKey(key);
    try testing.expectError(hedera.errors.HederaError.TransactionIsFrozen, admin_result);
    
    const gas_result = tx.setGas(500000);
    try testing.expectError(hedera.errors.HederaError.TransactionIsFrozen, gas_result);
    
    const balance_result = tx.setInitialBalance(try hedera.Hbar.fromHbars(1));
    try testing.expectError(hedera.errors.HederaError.TransactionIsFrozen, balance_result);
    
    const memo_result = tx.setMemo("frozen");
    try testing.expectError(hedera.errors.HederaError.TransactionIsFrozen, memo_result);
}

test "ContractCreateTransaction default values" {
    const allocator = testing.allocator;
    
    const tx = hedera.newContractCreateTransaction(allocator);
    defer tx.deinit();
    
    // Verify default gas is 100000
    try testing.expectEqual(tx.getGas(), 100000);
    
    // Verify default auto renew period (131500 minutes = 7890000 seconds)
    try testing.expectEqual(tx.getAutoRenewPeriod().seconds, 131500 * 60);
    
    // Verify default max transaction fee is 20 Hbar
    const default_fee = tx.base.max_transaction_fee;
    try testing.expect(default_fee != null);
    try testing.expectEqual(default_fee.?.toTinybars(), try hedera.Hbar.fromHbars(20).toTinybars());
}

test "ContractCreateTransaction complex scenario" {
    const allocator = testing.allocator;
    
    const tx = hedera.newContractCreateTransaction(allocator);
    defer tx.deinit();
    
    // Create comprehensive contract configuration
    const bytecode = [_]u8{ 
        0x60, 0x80, 0x60, 0x40, 0x52, 0x34, 0x80, 0x15, 
        0x61, 0x00, 0x10, 0x57, 0x60, 0x00, 0x80, 0xfd 
    };
    _ = try tx.setBytecode(&bytecode);
    
    // Set admin key
    const admin_private = try hedera.Ed25519PrivateKey.generate();
    defer admin_private.deinit();
    const admin_key = hedera.Key.fromPublicKey(admin_private.getPublicKey());
    _ = try tx.setAdminKey(admin_key);
    
    // Configure gas and balance
    _ = try tx.setGas(750000);
    _ = try tx.setInitialBalance(try hedera.Hbar.fromHbars(25));
    
    // Set constructor parameters
    const constructor_params = [_]u8{ 0x00, 0x00, 0x00, 0x20 };
    _ = try tx.setConstructorParameters(&constructor_params);
    
    // Set memo and token associations
    _ = try tx.setMemo("Complex DeFi smart contract");
    _ = try tx.setMaxAutomaticTokenAssociations(200);
    
    // Configure auto renewal
    _ = try tx.setAutoRenewPeriod(hedera.Duration.fromDays(90));
    const auto_renew_account = hedera.AccountId.init(0, 0, 1500);
    _ = try tx.setAutoRenewAccountId(auto_renew_account);
    
    // Configure staking
    _ = try tx.setStakedNodeId(7);
    _ = try tx.setDeclineStakingReward(true);
    
    // Verify all values are set correctly
    try testing.expectEqualSlices(u8, tx.getBytecode(), &bytecode);
    try testing.expect(tx.getAdminKey().?.equals(admin_key));
    try testing.expectEqual(tx.getGas(), 750000);
    try testing.expectEqual(tx.getInitialBalance().toTinybars(), try hedera.Hbar.fromHbars(25).toTinybars());
    try testing.expectEqualSlices(u8, tx.getConstructorParameters(), &constructor_params);
    try testing.expectEqualStrings(tx.getContractMemo(), "Complex DeFi smart contract");
    try testing.expectEqual(tx.getMaxAutomaticTokenAssociations(), 200);
    try testing.expectEqual(tx.getAutoRenewPeriod().seconds, hedera.Duration.fromDays(90).seconds);
    try testing.expect(tx.getAutoRenewAccountID().equals(auto_renew_account));
    try testing.expectEqual(tx.getStakedNodeID(), 7);
    try testing.expectEqual(tx.getDeclineStakingReward(), true);
}

test "ContractCreateTransaction empty getters" {
    const allocator = testing.allocator;
    
    const tx = hedera.newContractCreateTransaction(allocator);
    defer tx.deinit();
    
    // Test getters when optional values are not set
    try testing.expect(tx.getBytecodeFileID().isEmpty());
    try testing.expectEqualStrings(tx.getBytecode(), "");
    try testing.expect(tx.getAdminKey() == null);
    try testing.expect(tx.getProxyAccountID().isEmpty());
    try testing.expectEqualStrings(tx.getConstructorParameters(), "");
    try testing.expectEqualStrings(tx.getContractMemo(), "");
    try testing.expect(tx.getAutoRenewAccountID().isEmpty());
    try testing.expect(tx.getStakedAccountID().isEmpty());
    try testing.expectEqual(tx.getStakedNodeID(), 0);
}

test "ContractCreateTransaction edge cases" {
    const allocator = testing.allocator;
    
    const tx = hedera.newContractCreateTransaction(allocator);
    defer tx.deinit();
    
    // Test zero gas
    _ = try tx.setGas(0);
    try testing.expectEqual(tx.getGas(), 0);
    
    // Test empty bytecode
    _ = try tx.setBytecode("");
    try testing.expectEqualStrings(tx.getBytecode(), "");
    
    // Test zero initial balance
    _ = try tx.setInitialBalance(hedera.Hbar.zero());
    try testing.expect(tx.getInitialBalance().equals(hedera.Hbar.zero()));
    
    // Test empty constructor parameters
    _ = try tx.setConstructorParameters("");
    try testing.expectEqualStrings(tx.getConstructorParameters(), "");
    
    // Test empty memo
    _ = try tx.setMemo("");
    try testing.expectEqualStrings(tx.getContractMemo(), "");
    
    // Test zero max automatic token associations
    _ = try tx.setMaxAutomaticTokenAssociations(0);
    try testing.expectEqual(tx.getMaxAutomaticTokenAssociations(), 0);
}

test "ContractCreateTransaction large values" {
    const allocator = testing.allocator;
    
    const tx = hedera.newContractCreateTransaction(allocator);
    defer tx.deinit();
    
    // Test maximum gas value
    _ = try tx.setGas(std.math.maxInt(u32));
    try testing.expectEqual(tx.getGas(), std.math.maxInt(u32));
    
    // Test large initial balance
    const large_balance = try hedera.Hbar.fromTinybars(std.math.maxInt(u32));
    _ = try tx.setInitialBalance(large_balance);
    try testing.expect(tx.getInitialBalance().equals(large_balance));
    
    // Test large constructor parameters
    const large_params = try allocator.alloc(u8, 1000);
    defer allocator.free(large_params);
    @memset(large_params, 0xAB);
    
    _ = try tx.setConstructorParameters(large_params);
    try testing.expectEqualSlices(u8, tx.getConstructorParameters(), large_params);
    
    // Test large bytecode
    const large_bytecode = try allocator.alloc(u8, 2000);
    defer allocator.free(large_bytecode);
    for (large_bytecode, 0..) |_, i| {
        large_bytecode[i] = @intCast(i % 256);
    }
    
    _ = try tx.setBytecode(large_bytecode);
    try testing.expectEqualSlices(u8, tx.getBytecode(), large_bytecode);
}
const std = @import("std");
const testing = std.testing;
const hedera = @import("hedera");

test "TokenCreateTransaction factory creates valid instance" {
    const allocator = testing.allocator;
    
    // Create transaction using factory
    const tx = hedera.newTokenCreateTransaction(allocator);
    defer tx.deinit();
    
    // Verify it's properly initialized
    try testing.expect(tx.token_name == null);
    try testing.expect(tx.token_symbol == null);
    try testing.expect(tx.decimals == 0);
    try testing.expect(tx.initial_supply == 0);
    try testing.expect(tx.treasury == null);
    try testing.expect(tx.admin_key == null);
    try testing.expect(tx.freeze_key == null);
    try testing.expect(tx.wipe_key == null);
    try testing.expect(tx.supply_key == null);
    try testing.expect(tx.pause_key == null);
    try testing.expect(tx.fee_schedule_key == null);
    try testing.expect(tx.custom_fees.items.len == 0);
}

test "TokenCreateTransaction setters work correctly" {
    const allocator = testing.allocator;
    
    const tx = hedera.newTokenCreateTransaction(allocator);
    defer tx.deinit();
    
    // Test setting token name
    _ = try tx.setTokenName("Test Token");
    try testing.expectEqualStrings(tx.token_name.?, "Test Token");
    
    // Test setting token symbol
    _ = try tx.setTokenSymbol("TST");
    try testing.expectEqualStrings(tx.token_symbol.?, "TST");
    
    // Test setting decimals
    _ = try tx.setDecimals(8);
    try testing.expectEqual(tx.decimals, 8);
    
    // Test setting initial supply
    _ = try tx.setInitialSupply(1000000);
    try testing.expectEqual(tx.initial_supply, 1000000);
    
    // Test setting treasury account
    const treasury = hedera.AccountId.init(0, 0, 100);
    _ = try tx.setTreasuryAccountId(treasury);
    try testing.expect(tx.treasury.?.equals(treasury));
    
    // Test setting token type
    _ = try tx.setTokenType(.FungibleCommon);
    try testing.expectEqual(tx.token_type, .FungibleCommon);
    
    // Test setting supply type
    _ = try tx.setSupplyType(.Finite);
    try testing.expectEqual(tx.supply_type, .Finite);
    
    // Test setting max supply
    _ = try tx.setMaxSupply(10000000);
    try testing.expectEqual(tx.max_supply, 10000000);
    
    // Test setting freeze default
    _ = try tx.setFreezeDefault(true);
    try testing.expect(tx.freeze_default);
    
    // Test setting auto renew account
    const auto_renew = hedera.AccountId.init(0, 0, 200);
    _ = try tx.setAutoRenewAccount(auto_renew);
    try testing.expect(tx.auto_renew_account.?.equals(auto_renew));
    
    // Test setting auto renew period
    const period = hedera.Duration.fromDays(90);
    _ = try tx.setAutoRenewPeriod(period);
    try testing.expectEqual(tx.auto_renew_period.?.seconds, period.seconds);
    
    // Test setting memo
    _ = try tx.setTokenMemo("Test memo");
    try testing.expectEqualStrings(tx.token_memo.?, "Test memo");
}

test "TokenCreateTransaction with keys" {
    const allocator = testing.allocator;
    
    const tx = hedera.newTokenCreateTransaction(allocator);
    defer tx.deinit();
    
    // Create test keys
    const admin_key = try hedera.Ed25519PrivateKey.generate();
    defer admin_key.deinit();
    const freeze_key = try hedera.Ed25519PrivateKey.generate();
    defer freeze_key.deinit();
    const wipe_key = try hedera.Ed25519PrivateKey.generate();
    defer wipe_key.deinit();
    const supply_key = try hedera.Ed25519PrivateKey.generate();
    defer supply_key.deinit();
    const pause_key = try hedera.Ed25519PrivateKey.generate();
    defer pause_key.deinit();
    
    // Set keys
    _ = try tx.setAdminKey(hedera.Key.fromPublicKey(admin_key.getPublicKey()));
    _ = try tx.setFreezeKey(hedera.Key.fromPublicKey(freeze_key.getPublicKey()));
    _ = try tx.setWipeKey(hedera.Key.fromPublicKey(wipe_key.getPublicKey()));
    _ = try tx.setSupplyKey(hedera.Key.fromPublicKey(supply_key.getPublicKey()));
    _ = try tx.setPauseKey(hedera.Key.fromPublicKey(pause_key.getPublicKey()));
    
    // Verify keys are set
    try testing.expect(tx.admin_key != null);
    try testing.expect(tx.freeze_key != null);
    try testing.expect(tx.wipe_key != null);
    try testing.expect(tx.supply_key != null);
    try testing.expect(tx.pause_key != null);
}

test "TokenCreateTransaction custom fees" {
    const allocator = testing.allocator;
    
    const tx = hedera.newTokenCreateTransaction(allocator);
    defer tx.deinit();
    
    // Create custom fixed fee
    const fee_collector = hedera.AccountId.init(0, 0, 300);
    const fixed_fee = hedera.CustomFixedFee{
        .amount = 100,
        .denomination_token_id = null,
        .fee_collector_account_id = fee_collector,
        .all_collectors_are_exempt = false,
    };
    
    // Add custom fee
    _ = try tx.addCustomFee(hedera.CustomFee{ .fixed = fixed_fee });
    try testing.expectEqual(tx.custom_fees.items.len, 1);
    
    // Create custom fractional fee
    const fractional_fee = hedera.CustomFractionalFee{
        .numerator = 1,
        .denominator = 100,
        .minimum_amount = 1,
        .maximum_amount = 1000,
        .assessment_method = .Inclusive,
        .fee_collector_account_id = fee_collector,
        .all_collectors_are_exempt = false,
    };
    
    // Add fractional fee
    _ = try tx.addCustomFee(hedera.CustomFee{ .fractional = fractional_fee });
    try testing.expectEqual(tx.custom_fees.items.len, 2);
}

test "TokenCreateTransaction freezeWith" {
    const allocator = testing.allocator;
    
    const tx = hedera.newTokenCreateTransaction(allocator);
    defer tx.deinit();
    
    // Set required fields
    _ = try tx.setTokenName("Test Token");
    _ = try tx.setTokenSymbol("TST");
    _ = try tx.setTreasuryAccountId(hedera.AccountId.init(0, 0, 2));
    
    // Freeze without client (should use defaults)
    try tx.freezeWith(null);
    
    // Verify transaction is frozen
    try testing.expect(tx.base.frozen);
    try testing.expect(tx.base.transaction_id != null);
    try testing.expect(tx.base.node_account_ids.items.len > 0);
}

test "TokenCreateTransaction validation" {
    const allocator = testing.allocator;
    
    const tx = hedera.newTokenCreateTransaction(allocator);
    defer tx.deinit();
    
    // Test max token name length
    const long_name = "a" ** 101; // 101 characters
    const result = tx.setTokenName(long_name);
    try testing.expectError(hedera.errors.HederaError.InvalidParameter, result);
    
    // Test max token symbol length  
    const long_symbol = "A" ** 101; // 101 characters
    const symbol_result = tx.setTokenSymbol(long_symbol);
    try testing.expectError(hedera.errors.HederaError.InvalidParameter, symbol_result);
    
    // Test invalid decimals for NFT
    _ = try tx.setTokenType(.NonFungibleUnique);
    const decimals_result = tx.setDecimals(5);
    try testing.expectError(hedera.errors.HederaError.InvalidParameter, decimals_result);
}

test "TokenCreateTransaction NFT configuration" {
    const allocator = testing.allocator;
    
    const tx = hedera.newTokenCreateTransaction(allocator);
    defer tx.deinit();
    
    // Configure for NFT
    _ = try tx.setTokenName("Test NFT");
    _ = try tx.setTokenSymbol("TNFT");
    _ = try tx.setTokenType(.NonFungibleUnique);
    _ = try tx.setTreasuryAccountId(hedera.AccountId.init(0, 0, 2));
    _ = try tx.setSupplyType(.Finite);
    _ = try tx.setMaxSupply(10000);
    
    // Verify NFT configuration
    try testing.expectEqual(tx.token_type, .NonFungibleUnique);
    try testing.expectEqual(tx.decimals, 0); // NFTs have 0 decimals
    try testing.expectEqual(tx.initial_supply, 0); // NFTs start with 0 supply
    try testing.expectEqual(tx.supply_type, .Finite);
    try testing.expectEqual(tx.max_supply, 10000);
}

test "TokenCreateTransaction builds transaction body" {
    const allocator = testing.allocator;
    
    const tx = hedera.newTokenCreateTransaction(allocator);
    defer tx.deinit();
    
    // Set required fields
    _ = try tx.setTokenName("Test Token");
    _ = try tx.setTokenSymbol("TST");
    _ = try tx.setDecimals(2);
    _ = try tx.setInitialSupply(1000000);
    _ = try tx.setTreasuryAccountId(hedera.AccountId.init(0, 0, 2));
    
    // Set transaction ID
    tx.base.transaction_id = hedera.TransactionId.generate(hedera.AccountId.init(0, 0, 2));
    
    // Build transaction body
    const body_bytes = try tx.buildTransactionBody();
    defer allocator.free(body_bytes);
    
    // Verify body was built (non-empty)
    try testing.expect(body_bytes.len > 0);
    
    // Parse to verify structure
    var reader = hedera.ProtoReader.init(body_bytes);
    var found_token_creation = false;
    
    while (reader.hasMore()) {
        const tag = try reader.readTag();
        if (tag.field_number == 11) { // tokenCreation field
            found_token_creation = true;
            break;
        }
        try reader.skipField(tag.wire_type);
    }
    
    try testing.expect(found_token_creation);
}

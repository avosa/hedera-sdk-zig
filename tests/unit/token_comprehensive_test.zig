const std = @import("std");
const testing = std.testing;
const hedera = @import("hedera");

test "TokenId - initialization and operations" {
    // Test standard initialization
    const token1 = hedera.TokenId.init(0, 0, 1000);
    try testing.expectEqual(@as(u64, 0), token1.shard);
    try testing.expectEqual(@as(u64, 0), token1.realm);
    try testing.expectEqual(@as(u64, 1000), token1.token);
    
    // Test with different shard and realm
    const token2 = hedera.TokenId.init(5, 10, 999999);
    try testing.expectEqual(@as(u64, 5), token2.shard);
    try testing.expectEqual(@as(u64, 10), token2.realm);
    try testing.expectEqual(@as(u64, 999999), token2.token);
    
    // Test num() helper
    try testing.expectEqual(@as(u64, 1000), token1.num());
    try testing.expectEqual(@as(u64, 999999), token2.num());
    
    // Test equals
    const token3 = hedera.TokenId.init(0, 0, 1000);
    try testing.expect(token1.equals(token3));
    try testing.expect(!token1.equals(token2));
}

test "TokenId - string conversions" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Test toString
    const token = hedera.TokenId.init(1, 2, 3456);
    const str = try token.toString(allocator);
    defer allocator.free(str);
    try testing.expectEqualStrings("1.2.3456", str);
    
    // Test fromString
    const parsed = try hedera.tokenIdFromString(allocator, "5.10.999");
    try testing.expectEqual(@as(u64, 5), parsed.shard);
    try testing.expectEqual(@as(u64, 10), parsed.realm);
    try testing.expectEqual(@as(u64, 999), parsed.token);
    
    // Test invalid formats
    try testing.expectError(error.InvalidTokenId, hedera.tokenIdFromString(allocator, "invalid"));
    try testing.expectError(error.InvalidTokenId, hedera.tokenIdFromString(allocator, "0.0"));
    try testing.expectError(error.InvalidTokenId, hedera.tokenIdFromString(allocator, ""));
}

test "TokenCreateTransaction - all configuration options" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.tokenCreateTransaction(allocator);
    defer tx.deinit();
    
    // Basic token properties
    _ = try tx.setTokenName("Test Token");
    _ = try tx.setTokenSymbol("TST");
    _ = try tx.setDecimals(8);
    _ = try tx.setInitialSupply(1000000);
    _ = try tx.setTreasuryAccountId(hedera.AccountId.init(0, 0, 100));
    
    // Keys
    var admin_key = try hedera.generatePrivateKey(allocator);
    defer admin_key.deinit();
    var kyc_key = try hedera.generatePrivateKey(allocator);
    defer kyc_key.deinit();
    var freeze_key = try hedera.generatePrivateKey(allocator);
    defer freeze_key.deinit();
    var wipe_key = try hedera.generatePrivateKey(allocator);
    defer wipe_key.deinit();
    var supply_key = try hedera.generatePrivateKey(allocator);
    defer supply_key.deinit();
    var fee_schedule_key = try hedera.generatePrivateKey(allocator);
    defer fee_schedule_key.deinit();
    var pause_key = try hedera.generatePrivateKey(allocator);
    defer pause_key.deinit();
    var metadata_key = try hedera.generatePrivateKey(allocator);
    defer metadata_key.deinit();
    
    _ = try tx.setAdminKey(hedera.Key.fromPublicKey(admin_key.getPublicKey()));
    _ = try tx.setKycKey(hedera.Key.fromPublicKey(kyc_key.getPublicKey()));
    _ = try tx.setFreezeKey(hedera.Key.fromPublicKey(freeze_key.getPublicKey()));
    _ = try tx.setWipeKey(hedera.Key.fromPublicKey(wipe_key.getPublicKey()));
    _ = try tx.setSupplyKey(hedera.Key.fromPublicKey(supply_key.getPublicKey()));
    _ = try tx.setFeeScheduleKey(hedera.Key.fromPublicKey(fee_schedule_key.getPublicKey()));
    _ = try tx.setPauseKey(hedera.Key.fromPublicKey(pause_key.getPublicKey()));
    _ = try tx.setMetadataKey(hedera.Key.fromPublicKey(metadata_key.getPublicKey()));
    
    // Token type
    _ = try tx.setTokenType(hedera.TokenType.FUNGIBLE_COMMON);
    _ = try tx.setSupplyType(hedera.TokenSupplyType.FINITE);
    _ = try tx.setMaxSupply(10000000);
    
    // Freeze default
    _ = try tx.setFreezeDefault(false);
    
    // Auto renew
    _ = try tx.setAutoRenewAccount(hedera.AccountId.init(0, 0, 200));
    _ = try tx.setAutoRenewPeriod(hedera.Duration.fromDays(90));
    
    // Expiry
    _ = try tx.setExpirationTime(hedera.Timestamp.fromSeconds(1234567890));
    
    // Memo
    _ = try tx.setTokenMemo("Test token memo with special chars: SUCCESS!");
    
    // Custom fees
    var fixed_fee = hedera.CustomFee.initFixed();
    _ = try fixed_fee.setFeeCollectorAccountId(hedera.AccountId.init(0, 0, 300));
    switch (fixed_fee) {
        .fixed => |*fee| {
            fee.amount = 100;
            fee.denomination_token_id = null; // HBAR fee
        },
        else => {},
    }
    try tx.addCustomFee(fixed_fee);
    
    var fractional_fee = hedera.CustomFee.initFractional();
    _ = try fractional_fee.setFeeCollectorAccountId(hedera.AccountId.init(0, 0, 301));
    switch (fractional_fee) {
        .fractional => |*fee| {
            fee.numerator = 1;
            fee.denominator = 100;
            fee.minimum_amount = 1;
            fee.maximum_amount = 100;
            fee.assessment_method = .inclusive;
        },
        else => {},
    }
    try tx.addCustomFee(fractional_fee);
    
    var royalty_fee = hedera.CustomFee.initRoyalty();
    _ = try royalty_fee.setFeeCollectorAccountId(hedera.AccountId.init(0, 0, 302));
    switch (royalty_fee) {
        .royalty => |*fee| {
            fee.numerator = 5;
            fee.denominator = 100;
            fee.fallback_fee = null;
        },
        else => {},
    }
    try tx.addCustomFee(royalty_fee);
    
    // Metadata
    const metadata = [_]u8{0x01, 0x02, 0x03, 0x04};
    _ = try tx.setTokenMetadata(&metadata);
    
    // Verify all settings
    try testing.expectEqualStrings("Test Token", tx.name);
    try testing.expectEqualStrings("TST", tx.symbol);
    try testing.expectEqual(@as(u32, 8), tx.decimals);
    try testing.expectEqual(@as(u64, 1000000), tx.initial_supply);
    try testing.expectEqual(@as(u64, 100), tx.treasury_account_id.?.account);
    try testing.expect(tx.admin_key != null);
    try testing.expect(tx.kyc_key != null);
    try testing.expect(tx.freeze_key != null);
    try testing.expect(tx.wipe_key != null);
    try testing.expect(tx.supply_key != null);
    try testing.expect(tx.fee_schedule_key != null);
    try testing.expect(tx.pause_key != null);
    try testing.expect(tx.metadata_key != null);
    try testing.expectEqual(hedera.TokenType.FUNGIBLE_COMMON, tx.token_type);
    try testing.expectEqual(hedera.TokenSupplyType.FINITE, tx.supply_type);
    try testing.expectEqual(@as(i64, 10000000), tx.max_supply);
    try testing.expect(!tx.freeze_default);
    try testing.expectEqual(@as(u64, 200), tx.auto_renew_account.?.account);
    try testing.expectEqual(@as(i64, 7776000), tx.auto_renew_period.seconds);
    try testing.expectEqual(@as(i64, 1234567890), tx.expiration_time.?.seconds);
    try testing.expectEqualStrings("Test token memo with special chars: SUCCESS!", tx.token_memo);
    try testing.expectEqual(@as(usize, 3), tx.custom_fees.items.len);
    try testing.expectEqualSlices(u8, &metadata, tx.metadata);
}

test "TokenCreateTransaction - NFT configuration" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.tokenCreateTransaction(allocator);
    defer tx.deinit();
    
    // Configure for NFT
    _ = try tx.setTokenName("Test NFT Collection");
    _ = try tx.setTokenSymbol("TNFT");
    _ = try tx.setTokenType(hedera.TokenType.NON_FUNGIBLE_UNIQUE);
    _ = try tx.setDecimals(0); // NFTs must have 0 decimals
    _ = try tx.setInitialSupply(0); // NFTs start with 0 supply
    _ = try tx.setSupplyType(hedera.TokenSupplyType.FINITE);
    _ = try tx.setMaxSupply(10000);
    _ = try tx.setTreasuryAccountId(hedera.AccountId.init(0, 0, 100));
    
    // NFT requires supply key for minting
    var supply_key = try hedera.generatePrivateKey(allocator);
    defer supply_key.deinit();
    _ = try tx.setSupplyKey(hedera.Key.fromPublicKey(supply_key.getPublicKey()));
    
    // Verify NFT configuration
    try testing.expectEqual(hedera.TokenType.NON_FUNGIBLE_UNIQUE, tx.token_type);
    try testing.expectEqual(@as(u32, 0), tx.decimals);
    try testing.expectEqual(@as(u64, 0), tx.initial_supply);
    try testing.expectEqual(@as(i64, 10000), tx.max_supply);
    try testing.expect(tx.supply_key != null);
}

test "TokenUpdateTransaction - comprehensive updates" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.TokenUpdateTransaction.init(allocator);
    defer tx.deinit();
    
    const token_id = hedera.TokenId.init(0, 0, 1000);
    _ = try tx.setTokenId(token_id);
    
    // Update name and symbol
    _ = try tx.setTokenName("Updated Token Name");
    _ = try tx.setTokenSymbol("UPDT");
    
    // Update treasury
    _ = try tx.setTreasuryAccountId(hedera.AccountId.init(0, 0, 500));
    
    // Update keys
    var new_admin_key = try hedera.generatePrivateKey(allocator);
    defer new_admin_key.deinit();
    var new_kyc_key = try hedera.generatePrivateKey(allocator);
    defer new_kyc_key.deinit();
    var new_freeze_key = try hedera.generatePrivateKey(allocator);
    defer new_freeze_key.deinit();
    var new_wipe_key = try hedera.generatePrivateKey(allocator);
    defer new_wipe_key.deinit();
    var new_supply_key = try hedera.generatePrivateKey(allocator);
    defer new_supply_key.deinit();
    var new_fee_schedule_key = try hedera.generatePrivateKey(allocator);
    defer new_fee_schedule_key.deinit();
    var new_pause_key = try hedera.generatePrivateKey(allocator);
    defer new_pause_key.deinit();
    var new_metadata_key = try hedera.generatePrivateKey(allocator);
    defer new_metadata_key.deinit();
    
    _ = try tx.setAdminKey(hedera.Key.fromPublicKey(new_admin_key.getPublicKey()));
    _ = try tx.setKycKey(hedera.Key.fromPublicKey(new_kyc_key.getPublicKey()));
    _ = try tx.setFreezeKey(hedera.Key.fromPublicKey(new_freeze_key.getPublicKey()));
    _ = try tx.setWipeKey(hedera.Key.fromPublicKey(new_wipe_key.getPublicKey()));
    _ = try tx.setSupplyKey(hedera.Key.fromPublicKey(new_supply_key.getPublicKey()));
    _ = try tx.setFeeScheduleKey(hedera.Key.fromPublicKey(new_fee_schedule_key.getPublicKey()));
    _ = try tx.setPauseKey(hedera.Key.fromPublicKey(new_pause_key.getPublicKey()));
    _ = try tx.setMetadataKey(hedera.Key.fromPublicKey(new_metadata_key.getPublicKey()));
    
    // Update auto renew
    _ = try tx.setAutoRenewAccount(hedera.AccountId.init(0, 0, 600));
    _ = try tx.setAutoRenewPeriod(hedera.Duration.fromDays(120));
    
    // Update expiry
    _ = try tx.setExpirationTime(hedera.Timestamp.fromSeconds(9999999999));
    
    // Update memo
    _ = try tx.setTokenMemo("Updated memo NOTE:");
    
    // Update key verification mode
    _ = try tx.setKeyVerificationMode(hedera.TokenKeyValidation.FULL_VALIDATION);
    
    // Update metadata
    const new_metadata = [_]u8{0xAA, 0xBB, 0xCC, 0xDD};
    _ = try tx.setMetadata(&new_metadata);
    
    // Verify all updates
    try testing.expectEqual(@as(u64, 1000), tx.token_id.?.num());
    try testing.expectEqualStrings("Updated Token Name", tx.token_name.?);
    try testing.expectEqualStrings("UPDT", tx.token_symbol.?);
    try testing.expectEqual(@as(u64, 500), tx.treasury.?.account);
    try testing.expect(tx.admin_key != null);
    try testing.expect(tx.kyc_key != null);
    try testing.expect(tx.freeze_key != null);
    try testing.expect(tx.wipe_key != null);
    try testing.expect(tx.supply_key != null);
    try testing.expect(tx.fee_schedule_key != null);
    try testing.expect(tx.pause_key != null);
    try testing.expect(tx.metadata_key != null);
    try testing.expectEqual(@as(u64, 600), tx.auto_renew_account.?.account);
    try testing.expectEqual(@as(i64, 10368000), tx.auto_renew_period.?.seconds);
    try testing.expectEqual(@as(i64, 9999999999), tx.expiry.?.seconds);
    try testing.expectEqualStrings("Updated memo NOTE:", tx.token_memo.?);
    try testing.expectEqual(hedera.TokenKeyValidation.FULL_VALIDATION, tx.key_verification_mode);
    try testing.expectEqualSlices(u8, &new_metadata, tx.metadata.?);
}

test "TokenDeleteTransaction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.TokenDeleteTransaction.init(allocator);
    defer tx.deinit();
    
    const token_id = hedera.TokenId.init(0, 0, 5000);
    _ = try tx.setTokenId(token_id);
    
    try testing.expectEqual(@as(u64, 5000), tx.token_id.?.num());
}

test "TokenMintTransaction - fungible and NFT" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Fungible token mint
    var fungible_mint = hedera.TokenMintTransaction.init(allocator);
    defer fungible_mint.deinit();
    
    const fungible_token = hedera.TokenId.init(0, 0, 2000);
    _ = try fungible_mint.setTokenId(fungible_token);
    _ = try fungible_mint.setAmount(1000000);
    
    try testing.expectEqual(@as(u64, 2000), fungible_mint.token_id.?.num());
    try testing.expectEqual(@as(u64, 1000000), fungible_mint.amount);
    
    // NFT mint
    var nft_mint = hedera.TokenMintTransaction.init(allocator);
    defer nft_mint.deinit();
    
    const nft_token = hedera.TokenId.init(0, 0, 3000);
    _ = try nft_mint.setTokenId(nft_token);
    
    // Add metadata for NFTs
    const metadata1 = [_]u8{0x01, 0x02, 0x03};
    const metadata2 = [_]u8{0x04, 0x05, 0x06};
    const metadata3 = [_]u8{0x07, 0x08, 0x09};
    
    try nft_mint.addMetadata(&metadata1);
    try nft_mint.addMetadata(&metadata2);
    try nft_mint.addMetadata(&metadata3);
    
    try testing.expectEqual(@as(u64, 3000), nft_mint.token_id.?.num());
    try testing.expectEqual(@as(usize, 3), nft_mint.metadata.items.len);
    try testing.expectEqualSlices(u8, &metadata1, nft_mint.metadata.items[0]);
    try testing.expectEqualSlices(u8, &metadata2, nft_mint.metadata.items[1]);
    try testing.expectEqualSlices(u8, &metadata3, nft_mint.metadata.items[2]);
}

test "TokenBurnTransaction - fungible and NFT" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Fungible token burn
    var fungible_burn = hedera.TokenBurnTransaction.init(allocator);
    defer fungible_burn.deinit();
    
    const fungible_token = hedera.TokenId.init(0, 0, 2000);
    _ = try fungible_burn.setTokenId(fungible_token);
    _ = try fungible_burn.setAmount(500000);
    
    try testing.expectEqual(@as(u64, 2000), fungible_burn.token_id.?.num());
    try testing.expectEqual(@as(u64, 500000), fungible_burn.amount);
    
    // NFT burn
    var nft_burn = hedera.TokenBurnTransaction.init(allocator);
    defer nft_burn.deinit();
    
    const nft_token = hedera.TokenId.init(0, 0, 3000);
    _ = try nft_burn.setTokenId(nft_token);
    
    // Add serial numbers to burn
    const serials = [_]i64{1, 5, 10, 15, 20};
    try nft_burn.setSerialNumbers(&serials);
    
    try testing.expectEqual(@as(u64, 3000), nft_burn.token_id.?.num());
    try testing.expectEqual(@as(usize, 5), nft_burn.serials.items.len);
    try testing.expectEqual(@as(i64, 1), nft_burn.serials.items[0]);
    try testing.expectEqual(@as(i64, 20), nft_burn.serials.items[4]);
}

test "TokenWipeTransaction - wipe tokens from account" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.TokenWipeTransaction.init(allocator);
    defer tx.deinit();
    
    const token_id = hedera.TokenId.init(0, 0, 4000);
    const account_id = hedera.AccountId.init(0, 0, 100);
    
    _ = try tx.setTokenId(token_id);
    _ = try tx.setAccountId(account_id);
    _ = try tx.setAmount(100000);
    
    // For NFTs, set serial numbers
    const serials = [_]i64{1, 2, 3};
    try tx.setSerialNumbers(&serials);
    
    try testing.expectEqual(@as(u64, 4000), tx.token_id.?.num());
    try testing.expectEqual(@as(u64, 100), tx.account_id.?.account);
    try testing.expectEqual(@as(u64, 100000), tx.amount);
    try testing.expectEqual(@as(usize, 3), tx.serials.items.len);
}

test "TokenFreezeTransaction and TokenUnfreezeTransaction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Freeze
    var freeze_tx = hedera.TokenFreezeTransaction.init(allocator);
    defer freeze_tx.deinit();
    
    const token_id = hedera.TokenId.init(0, 0, 5000);
    const account_id = hedera.AccountId.init(0, 0, 200);
    
    _ = try freeze_tx.setTokenId(token_id);
    _ = try freeze_tx.setAccountId(account_id);
    
    try testing.expectEqual(@as(u64, 5000), freeze_tx.token_id.?.num());
    try testing.expectEqual(@as(u64, 200), freeze_tx.account_id.?.account);
    
    // Unfreeze
    var unfreeze_tx = hedera.TokenUnfreezeTransaction.init(allocator);
    defer unfreeze_tx.deinit();
    
    _ = try unfreeze_tx.setTokenId(token_id);
    _ = try unfreeze_tx.setAccountId(account_id);
    
    try testing.expectEqual(@as(u64, 5000), unfreeze_tx.token_id.?.num());
    try testing.expectEqual(@as(u64, 200), unfreeze_tx.account_id.?.account);
}

test "TokenGrantKycTransaction and TokenRevokeKycTransaction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Grant KYC
    var grant_tx = hedera.TokenGrantKycTransaction.init(allocator);
    defer grant_tx.deinit();
    
    const token_id = hedera.TokenId.init(0, 0, 6000);
    const account_id = hedera.AccountId.init(0, 0, 300);
    
    _ = try grant_tx.setTokenId(token_id);
    _ = try grant_tx.setAccountId(account_id);
    
    try testing.expectEqual(@as(u64, 6000), grant_tx.token_id.?.num());
    try testing.expectEqual(@as(u64, 300), grant_tx.account_id.?.account);
    
    // Revoke KYC
    var revoke_tx = hedera.TokenRevokeKycTransaction.init(allocator);
    defer revoke_tx.deinit();
    
    _ = try revoke_tx.setTokenId(token_id);
    _ = try revoke_tx.setAccountId(account_id);
    
    try testing.expectEqual(@as(u64, 6000), revoke_tx.token_id.?.num());
    try testing.expectEqual(@as(u64, 300), revoke_tx.account_id.?.account);
}

test "TokenAssociateTransaction and TokenDissociateTransaction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Associate
    var associate_tx = hedera.TokenAssociateTransaction.init(allocator);
    defer associate_tx.deinit();
    
    const account_id = hedera.AccountId.init(0, 0, 400);
    _ = try associate_tx.setAccountId(account_id);
    
    // Add multiple tokens
    const tokens = [_]hedera.TokenId{
        hedera.TokenId.init(0, 0, 1000),
        hedera.TokenId.init(0, 0, 2000),
        hedera.TokenId.init(0, 0, 3000),
    };
    
    for (tokens) |token| {
        try associate_tx.addTokenId(token);
    }
    
    try testing.expectEqual(@as(u64, 400), associate_tx.account_id.?.account);
    try testing.expectEqual(@as(usize, 3), associate_tx.token_ids.items.len);
    
    // Dissociate
    var dissociate_tx = hedera.TokenDissociateTransaction.init(allocator);
    defer dissociate_tx.deinit();
    
    _ = try dissociate_tx.setAccountId(account_id);
    
    for (tokens) |token| {
        try dissociate_tx.addTokenId(token);
    }
    
    try testing.expectEqual(@as(u64, 400), dissociate_tx.account_id.?.account);
    try testing.expectEqual(@as(usize, 3), dissociate_tx.token_ids.items.len);
}

test "TokenPauseTransaction and TokenUnpauseTransaction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Pause
    var pause_tx = hedera.TokenPauseTransaction.init(allocator);
    defer pause_tx.deinit();
    
    const token_id = hedera.TokenId.init(0, 0, 7000);
    _ = try pause_tx.setTokenId(token_id);
    
    try testing.expectEqual(@as(u64, 7000), pause_tx.token_id.?.num());
    
    // Unpause
    var unpause_tx = hedera.TokenUnpauseTransaction.init(allocator);
    defer unpause_tx.deinit();
    
    _ = try unpause_tx.setTokenId(token_id);
    
    try testing.expectEqual(@as(u64, 7000), unpause_tx.token_id.?.num());
}

test "TokenFeeScheduleUpdateTransaction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = hedera.TokenFeeScheduleUpdateTransaction.init(allocator);
    defer tx.deinit();
    
    const token_id = hedera.TokenId.init(0, 0, 8000);
    _ = try tx.setTokenId(token_id);
    
    // Add custom fees
    var fixed_fee = hedera.CustomFee.initFixed();
    _ = try fixed_fee.setFeeCollectorAccountId(hedera.AccountId.init(0, 0, 500));
    switch (fixed_fee) {
        .fixed => |*fee| {
            fee.amount = 50;
            fee.denomination_token_id = token_id;
        },
        else => {},
    }
    try tx.addCustomFee(fixed_fee);
    
    var fractional_fee = hedera.CustomFee.initFractional();
    _ = try fractional_fee.setFeeCollectorAccountId(hedera.AccountId.init(0, 0, 501));
    switch (fractional_fee) {
        .fractional => |*fee| {
            fee.numerator = 1;
            fee.denominator = 20;
            fee.minimum_amount = 1;
            fee.maximum_amount = 100;
            fee.assessment_method = .exclusive;
        },
        else => {},
    }
    try tx.addCustomFee(fractional_fee);
    
    try testing.expectEqual(@as(u64, 8000), tx.token_id.?.num());
    try testing.expectEqual(@as(usize, 2), tx.custom_fees.items.len);
}

test "TokenInfo structure - comprehensive" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var info = hedera.TokenInfo.init(allocator);
    defer info.deinit();
    
    // Set all fields
    info.token_id = hedera.TokenId.init(0, 0, 9000);
    info.name = "Test Token Info";
    info.symbol = "TTI";
    info.decimals = 6;
    info.total_supply = 1000000000;
    info.treasury_account_id = hedera.AccountId.init(0, 0, 100);
    
    // Set keys
    var admin_key = try hedera.generatePrivateKey(allocator);
    defer admin_key.deinit();
    info.admin_key = admin_key.getPublicKey();
    
    var kyc_key = try hedera.generatePrivateKey(allocator);
    defer kyc_key.deinit();
    info.kyc_key = kyc_key.getPublicKey();
    
    var freeze_key = try hedera.generatePrivateKey(allocator);
    defer freeze_key.deinit();
    info.freeze_key = freeze_key.getPublicKey();
    
    var wipe_key = try hedera.generatePrivateKey(allocator);
    defer wipe_key.deinit();
    info.wipe_key = wipe_key.getPublicKey();
    
    var supply_key = try hedera.generatePrivateKey(allocator);
    defer supply_key.deinit();
    info.supply_key = supply_key.getPublicKey();
    
    var fee_schedule_key = try hedera.generatePrivateKey(allocator);
    defer fee_schedule_key.deinit();
    info.fee_schedule_key = fee_schedule_key.getPublicKey();
    
    var pause_key = try hedera.generatePrivateKey(allocator);
    defer pause_key.deinit();
    info.pause_key = pause_key.getPublicKey();
    
    var metadata_key = try hedera.generatePrivateKey(allocator);
    defer metadata_key.deinit();
    info.metadata_key = metadata_key.getPublicKey();
    
    info.default_freeze_status = false;
    info.default_kyc_status = true;
    info.deleted = false;
    info.auto_renew_account = hedera.AccountId.init(0, 0, 200);
    info.auto_renew_period = hedera.Duration.fromDays(90);
    info.expiration_time = hedera.Timestamp.fromSeconds(1234567890);
    info.token_memo = "Test token info memo";
    info.token_type = hedera.TokenType.FUNGIBLE_COMMON;
    info.supply_type = hedera.TokenSupplyType.FINITE;
    info.max_supply = 10000000000;
    info.metadata = &[_]u8{0x01, 0x02, 0x03, 0x04};
    info.metadata_key = metadata_key.getPublicKey();
    info.ledger_id = "mainnet";
    info.pause_status = false;
    
    // Add custom fees
    var fixed_fee = hedera.CustomFee.initFixed();
    _ = try fixed_fee.setFeeCollectorAccountId(hedera.AccountId.init(0, 0, 600));
    switch (fixed_fee) {
        .fixed => |*fee| {
            fee.amount = 25;
            fee.denomination_token_id = null;
        },
        else => {},
    }
    try info.custom_fees.append(fixed_fee);
    
    // Verify all fields
    try testing.expectEqual(@as(u64, 9000), info.token_id.num());
    try testing.expectEqualStrings("Test Token Info", info.name);
    try testing.expectEqualStrings("TTI", info.symbol);
    try testing.expectEqual(@as(u32, 6), info.decimals);
    try testing.expectEqual(@as(u64, 1000000000), info.total_supply);
    try testing.expectEqual(@as(u64, 100), info.treasury_account_id.account);
    try testing.expect(info.admin_key != null);
    try testing.expect(info.kyc_key != null);
    try testing.expect(info.freeze_key != null);
    try testing.expect(info.wipe_key != null);
    try testing.expect(info.supply_key != null);
    try testing.expect(info.fee_schedule_key != null);
    try testing.expect(info.pause_key != null);
    try testing.expect(info.metadata_key != null);
    try testing.expect(!info.default_freeze_status);
    try testing.expect(info.default_kyc_status);
    try testing.expect(!info.deleted);
    try testing.expectEqual(@as(u64, 200), info.auto_renew_account.?.account);
    try testing.expectEqual(@as(i64, 7776000), info.auto_renew_period.seconds);
    try testing.expectEqualStrings("Test token info memo", info.token_memo);
    try testing.expectEqual(hedera.TokenType.FUNGIBLE_COMMON, info.token_type);
    try testing.expectEqual(hedera.TokenSupplyType.FINITE, info.supply_type);
    try testing.expectEqual(@as(i64, 10000000000), info.max_supply);
    try testing.expectEqualSlices(u8, &[_]u8{0x01, 0x02, 0x03, 0x04}, info.metadata);
    try testing.expectEqualStrings("mainnet", info.ledger_id);
    try testing.expect(!info.pause_status);
    try testing.expectEqual(@as(usize, 1), info.custom_fees.items.len);
}

test "NftId structure" {
    const nft1 = hedera.NftId{
        .token_id = hedera.TokenId.init(0, 0, 1000),
        .serial_number = 1,
    };
    
    const nft2 = hedera.NftId{
        .token_id = hedera.TokenId.init(0, 0, 1000),
        .serial_number = 2,
    };
    
    const nft3 = hedera.NftId{
        .token_id = hedera.TokenId.init(0, 0, 2000),
        .serial_number = 1,
    };
    
    try testing.expectEqual(@as(u64, 1000), nft1.token_id.num());
    try testing.expectEqual(@as(i64, 1), nft1.serial_number);
    
    // Test equality
    try testing.expect(!std.meta.eql(nft1, nft2)); // Different serial
    try testing.expect(!std.meta.eql(nft1, nft3)); // Different token
}

test "TokenRelationship structure" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const rel = hedera.TokenRelationship{
        .token_id = hedera.TokenId.init(0, 0, 5000),
        .symbol = "REL",
        .balance = 100000,
        .kyc_status = .granted,
        .freeze_status = .unfrozen,
        .decimals = 8,
        .automatic_association = true,
        .allocator = allocator,
    };
    
    try testing.expectEqual(@as(u64, 5000), rel.token_id.num());
    try testing.expectEqualStrings("REL", rel.symbol);
    try testing.expectEqual(@as(u64, 100000), rel.balance);
    try testing.expectEqual(hedera.KycStatus.granted, rel.kyc_status);
    try testing.expectEqual(hedera.FreezeStatus.unfrozen, rel.freeze_status);
    try testing.expectEqual(@as(u32, 8), rel.decimals);
    try testing.expect(rel.automatic_association);
}

test "CustomFee - all types comprehensive" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Fixed fee in HBAR
    var fixed_hbar = hedera.CustomFee.initFixed();
    _ = try fixed_hbar.setFeeCollectorAccountId(hedera.AccountId.init(0, 0, 700));
    _ = try fixed_hbar.setAllCollectorsAreExempt(true);
    switch (fixed_hbar) {
        .fixed => |*fee| {
            fee.amount = 100;
            fee.denomination_token_id = null; // HBAR
        },
        else => unreachable,
    }
    
    // Fixed fee in custom token
    var fixed_token = hedera.CustomFee.initFixed();
    _ = try fixed_token.setFeeCollectorAccountId(hedera.AccountId.init(0, 0, 701));
    switch (fixed_token) {
        .fixed => |*fee| {
            fee.amount = 50;
            fee.denomination_token_id = hedera.TokenId.init(0, 0, 9000);
        },
        else => unreachable,
    }
    
    // Fractional fee
    var fractional = hedera.CustomFee.initFractional();
    _ = try fractional.setFeeCollectorAccountId(hedera.AccountId.init(0, 0, 702));
    switch (fractional) {
        .fractional => |*fee| {
            fee.numerator = 1;
            fee.denominator = 100;
            fee.minimum_amount = 10;
            fee.maximum_amount = 1000;
            fee.assessment_method = .inclusive;
        },
        else => unreachable,
    }
    
    // Royalty fee with fallback
    var royalty = hedera.CustomFee.initRoyalty();
    _ = try royalty.setFeeCollectorAccountId(hedera.AccountId.init(0, 0, 703));
    switch (royalty) {
        .royalty => |*fee| {
            fee.numerator = 5;
            fee.denominator = 100;
            
            // Create fallback fee
            var fallback = try allocator.create(hedera.FixedFee);
            fallback.* = hedera.FixedFee{
                .fee_collector_account_id = hedera.AccountId.init(0, 0, 703),
                .amount = 10,
                .denomination_token_id = null,
                .all_collectors_are_exempt = false,
            };
            fee.fallback_fee = fallback;
        },
        else => unreachable,
    }
    
    // Verify fee properties
    try testing.expectEqual(@as(u64, 700), fixed_hbar.getFeeCollectorAccountId().?.account);
    try testing.expect(fixed_hbar.getAllCollectorsAreExempt());
    
    switch (fixed_hbar) {
        .fixed => |fee| {
            try testing.expectEqual(@as(i64, 100), fee.amount);
            try testing.expectEqual(@as(?hedera.TokenId, null), fee.denomination_token_id);
        },
        else => unreachable,
    }
    
    switch (fixed_token) {
        .fixed => |fee| {
            try testing.expectEqual(@as(i64, 50), fee.amount);
            try testing.expectEqual(@as(u64, 9000), fee.denomination_token_id.?.num());
        },
        else => unreachable,
    }
    
    switch (fractional) {
        .fractional => |fee| {
            try testing.expectEqual(@as(i64, 1), fee.numerator);
            try testing.expectEqual(@as(i64, 100), fee.denominator);
            try testing.expectEqual(@as(i64, 10), fee.minimum_amount);
            try testing.expectEqual(@as(i64, 1000), fee.maximum_amount);
            try testing.expectEqual(hedera.FeeAssessmentMethod.inclusive, fee.assessment_method);
        },
        else => unreachable,
    }
    
    switch (royalty) {
        .royalty => |fee| {
            try testing.expectEqual(@as(i64, 5), fee.numerator);
            try testing.expectEqual(@as(i64, 100), fee.denominator);
            try testing.expect(fee.fallback_fee != null);
            try testing.expectEqual(@as(i64, 10), fee.fallback_fee.?.amount);
        },
        else => unreachable,
    }
}

test "Token transfer edge cases" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Test zero amount transfers
    var zero_transfer = hedera.TokenTransfer{
        .token_id = hedera.TokenId.init(0, 0, 1000),
        .account_id = hedera.AccountId.init(0, 0, 100),
        .amount = 0,
        .transfers = std.ArrayList(hedera.AccountAmount).init(allocator),
        .expected_decimals = null,
        .is_approved = false,
    };
    defer zero_transfer.transfers.deinit();
    
    try testing.expectEqual(@as(i64, 0), zero_transfer.amount);
    
    // Test maximum values
    var max_transfer = hedera.TokenTransfer{
        .token_id = hedera.TokenId.init(std.math.maxInt(u64), std.math.maxInt(u64), std.math.maxInt(u64)),
        .account_id = hedera.AccountId.init(std.math.maxInt(u64), std.math.maxInt(u64), std.math.maxInt(u64)),
        .amount = std.math.maxInt(i64),
        .transfers = std.ArrayList(hedera.AccountAmount).init(allocator),
        .expected_decimals = 18,
        .is_approved = true,
    };
    defer max_transfer.transfers.deinit();
    
    try testing.expectEqual(std.math.maxInt(i64), max_transfer.amount);
    try testing.expectEqual(@as(?u32, 18), max_transfer.expected_decimals);
    
    // Test negative amounts
    var negative_transfer = hedera.TokenTransfer{
        .token_id = hedera.TokenId.init(0, 0, 2000),
        .account_id = hedera.AccountId.init(0, 0, 200),
        .amount = -999999999,
        .transfers = std.ArrayList(hedera.AccountAmount).init(allocator),
        .expected_decimals = null,
        .is_approved = false,
    };
    defer negative_transfer.transfers.deinit();
    
    try testing.expectEqual(@as(i64, -999999999), negative_transfer.amount);
}
const std = @import("std");
const testing = std.testing;
const hedera = @import("hedera");

test "TokenBurnTransaction factory creates valid instance" {
    const allocator = testing.allocator;
    
    // Create transaction using factory
    const tx = hedera.newTokenBurnTransaction(allocator);
    defer tx.deinit();
    
    // Verify it's properly initialized
    try testing.expect(tx.token_id == null);
    try testing.expectEqual(tx.amount, 0);
    try testing.expectEqual(tx.serials.items.len, 0);
    try testing.expectEqual(tx.serial_numbers.items.len, 0);
}

test "TokenBurnTransaction fungible token burning" {
    const allocator = testing.allocator;
    
    const tx = hedera.newTokenBurnTransaction(allocator);
    defer tx.deinit();
    
    // Set token ID
    const token_id = hedera.TokenId.init(0, 0, 1000);
    _ = try tx.setTokenId(token_id);
    try testing.expect(tx.token_id.?.equals(token_id));
    
    // Set amount for fungible tokens
    _ = try tx.setAmount(1000000);
    try testing.expectEqual(tx.amount, 1000000);
    
    // Verify serial numbers list is empty for fungible tokens
    try testing.expectEqual(tx.serial_numbers.items.len, 0);
}

test "TokenBurnTransaction NFT burning with serial numbers" {
    const allocator = testing.allocator;
    
    const tx = hedera.newTokenBurnTransaction(allocator);
    defer tx.deinit();
    
    // Set token ID
    const token_id = hedera.TokenId.init(0, 0, 2000);
    _ = try tx.setTokenId(token_id);
    
    // Add NFT serial numbers
    _ = try tx.addSerialNumber(1);
    _ = try tx.addSerialNumber(2);
    _ = try tx.addSerialNumber(3);
    
    // Verify serial numbers were added
    try testing.expectEqual(tx.serial_numbers.items.len, 3);
    try testing.expectEqual(tx.serial_numbers.items[0], 1);
    try testing.expectEqual(tx.serial_numbers.items[1], 2);
    try testing.expectEqual(tx.serial_numbers.items[2], 3);
    
    // Verify amount is 0 for NFTs
    try testing.expectEqual(tx.amount, 0);
}

test "TokenBurnTransaction batch NFT burning" {
    const allocator = testing.allocator;
    
    const tx = hedera.newTokenBurnTransaction(allocator);
    defer tx.deinit();
    
    // Set token ID
    const token_id = hedera.TokenId.init(0, 0, 3000);
    _ = try tx.setTokenId(token_id);
    
    // Create serial numbers list
    const serial_numbers = [_]i64{ 10, 20, 30, 40, 50 };
    
    // Set serial numbers
    _ = try tx.setSerialNumbers(&serial_numbers);
    
    // Verify all serial numbers were set
    try testing.expectEqual(tx.serial_numbers.items.len, 5);
    for (serial_numbers, 0..) |expected, i| {
        try testing.expectEqual(tx.serial_numbers.items[i], expected);
    }
}

test "TokenBurnTransaction validation tests" {
    const allocator = testing.allocator;
    
    const tx = hedera.newTokenBurnTransaction(allocator);
    defer tx.deinit();
    
    // Test burning without token ID
    const result = tx.execute(null);
    try testing.expectError(error.TokenIdRequired, result);
    
    // Set token ID
    const token_id = hedera.TokenId.init(0, 0, 4000);
    _ = try tx.setTokenId(token_id);
    
    // Test burning with neither amount nor serial numbers
    const empty_result = tx.execute(null);
    try testing.expectError(error.NothingToBurn, empty_result);
    
    // Test setting both amount and serial numbers (invalid)
    _ = try tx.setAmount(1000);
    const serial_result = tx.addSerialNumber(1);
    try testing.expectError(hedera.errors.HederaError.InvalidTokenBurnAmount, serial_result);
}

test "TokenBurnTransaction amount validation" {
    const allocator = testing.allocator;
    
    const tx = hedera.newTokenBurnTransaction(allocator);
    defer tx.deinit();
    
    // Test setting zero amount
    const zero_result = tx.setAmount(0);
    try testing.expectError(hedera.errors.HederaError.InvalidTokenBurnAmount, zero_result);
    
    // Test setting amount that exceeds max int64
    const max_result = tx.setAmount(std.math.maxInt(u64));
    try testing.expectError(hedera.errors.HederaError.InvalidTokenBurnAmount, max_result);
    
    // Test valid amount
    _ = try tx.setAmount(1000);
    try testing.expectEqual(tx.amount, 1000);
}

test "TokenBurnTransaction serial number validation" {
    const allocator = testing.allocator;
    
    const tx = hedera.newTokenBurnTransaction(allocator);
    defer tx.deinit();
    
    // Test negative serial number
    const negative_result = tx.addSerialNumber(-1);
    try testing.expectError(hedera.errors.HederaError.InvalidParameter, negative_result);
    
    // Test zero serial number
    const zero_result = tx.addSerialNumber(0);
    try testing.expectError(hedera.errors.HederaError.InvalidParameter, zero_result);
    
    // Test duplicate serial numbers
    _ = try tx.addSerialNumber(100);
    const duplicate_result = tx.addSerialNumber(100);
    try testing.expectError(hedera.errors.HederaError.RepeatedSerialNumbersInNftAllowance, duplicate_result);
    
    // Test valid serial number
    _ = try tx.addSerialNumber(200);
    try testing.expectEqual(tx.serial_numbers.items.len, 2);
}

test "TokenBurnTransaction NFT batch size limits" {
    const allocator = testing.allocator;
    
    const tx = hedera.newTokenBurnTransaction(allocator);
    defer tx.deinit();
    
    // Add maximum allowed NFTs
    var i: i64 = 1;
    while (i <= hedera.MAX_NFT_BURN_BATCH_SIZE) : (i += 1) {
        _ = try tx.addSerialNumber(i);
    }
    
    try testing.expectEqual(tx.serial_numbers.items.len, hedera.MAX_NFT_BURN_BATCH_SIZE);
    
    // Try to add one more (should fail)
    const extra_result = tx.addSerialNumber(hedera.MAX_NFT_BURN_BATCH_SIZE + 1);
    try testing.expectError(hedera.errors.HederaError.MaxNftsInPriceRegimeHaveBeenMinted, extra_result);
}

test "TokenBurnTransaction batch serial number validation" {
    const allocator = testing.allocator;
    
    const tx = hedera.newTokenBurnTransaction(allocator);
    defer tx.deinit();
    
    // Test batch with too many serial numbers
    var large_batch: [hedera.MAX_NFT_BURN_BATCH_SIZE + 1]i64 = undefined;
    for (large_batch, 0..) |_, i| {
        large_batch[i] = @intCast(i + 1);
    }
    
    const result = tx.setSerialNumbers(&large_batch);
    try testing.expectError(hedera.errors.HederaError.MaxNftsInPriceRegimeHaveBeenMinted, result);
    
    // Test batch with invalid serial number
    const invalid_batch = [_]i64{ 1, 2, -3, 4 };
    const invalid_result = tx.setSerialNumbers(&invalid_batch);
    try testing.expectError(hedera.errors.HederaError.InvalidParameter, invalid_result);
    
    // Test batch with duplicate serial numbers
    const duplicate_batch = [_]i64{ 1, 2, 2, 4 };
    const duplicate_result = tx.setSerialNumbers(&duplicate_batch);
    try testing.expectError(hedera.errors.HederaError.RepeatedSerialNumbersInNftAllowance, duplicate_result);
    
    // Test valid batch
    const valid_batch = [_]i64{ 10, 20, 30 };
    _ = try tx.setSerialNumbers(&valid_batch);
    try testing.expectEqual(tx.serial_numbers.items.len, 3);
}

test "TokenBurnTransaction addSerial alias method" {
    const allocator = testing.allocator;
    
    const tx = hedera.newTokenBurnTransaction(allocator);
    defer tx.deinit();
    
    // Test addSerial method (alias for addSerialNumber)
    _ = try tx.addSerial(100);
    _ = try tx.addSerial(200);
    
    try testing.expectEqual(tx.serial_numbers.items.len, 2);
    try testing.expectEqual(tx.serial_numbers.items[0], 100);
    try testing.expectEqual(tx.serial_numbers.items[1], 200);
}

test "TokenBurnTransaction freezeWith" {
    const allocator = testing.allocator;
    
    const tx = hedera.newTokenBurnTransaction(allocator);
    defer tx.deinit();
    
    // Set required fields
    const token_id = hedera.TokenId.init(0, 0, 5000);
    _ = try tx.setTokenId(token_id);
    _ = try tx.setAmount(100000);
    
    // Freeze without client (should use defaults)
    try tx.freezeWith(null);
    
    // Verify transaction is frozen
    try testing.expect(tx.base.frozen);
    try testing.expect(tx.base.transaction_id != null);
}

test "TokenBurnTransaction builds transaction body for fungible tokens" {
    const allocator = testing.allocator;
    
    const tx = hedera.newTokenBurnTransaction(allocator);
    defer tx.deinit();
    
    // Configure for fungible token burn
    const token_id = hedera.TokenId.init(0, 0, 6000);
    _ = try tx.setTokenId(token_id);
    _ = try tx.setAmount(500000);
    
    // Set transaction ID
    tx.base.transaction_id = hedera.TransactionId.generate(hedera.AccountId.init(0, 0, 2));
    
    // Build transaction body
    const body_bytes = try tx.buildTransactionBody();
    defer allocator.free(body_bytes);
    
    // Verify body was built
    try testing.expect(body_bytes.len > 0);
    
    // Parse to verify structure
    var reader = hedera.ProtoReader.init(body_bytes);
    var found_token_burn = false;
    
    while (reader.hasMore()) {
        const tag = try reader.readTag();
        if (tag.field_number == 36) { // tokenBurn field
            found_token_burn = true;
            break;
        }
        try reader.skipField(tag.wire_type);
    }
    
    try testing.expect(found_token_burn);
}

test "TokenBurnTransaction builds transaction body for NFTs" {
    const allocator = testing.allocator;
    
    const tx = hedera.newTokenBurnTransaction(allocator);
    defer tx.deinit();
    
    // Configure for NFT burn
    const token_id = hedera.TokenId.init(0, 0, 7000);
    _ = try tx.setTokenId(token_id);
    
    const serial_numbers = [_]i64{ 1, 2, 3 };
    _ = try tx.setSerialNumbers(&serial_numbers);
    
    // Set transaction ID
    tx.base.transaction_id = hedera.TransactionId.generate(hedera.AccountId.init(0, 0, 2));
    
    // Build transaction body
    const body_bytes = try tx.buildTransactionBody();
    defer allocator.free(body_bytes);
    
    // Verify body was built
    try testing.expect(body_bytes.len > 0);
    
    // Parse to verify structure
    var reader = hedera.ProtoReader.init(body_bytes);
    var found_token_burn = false;
    
    while (reader.hasMore()) {
        const tag = try reader.readTag();
        if (tag.field_number == 36) { // tokenBurn field
            found_token_burn = true;
            break;
        }
        try reader.skipField(tag.wire_type);
    }
    
    try testing.expect(found_token_burn);
}

test "TokenBurnTransaction getters" {
    const allocator = testing.allocator;
    
    const tx = hedera.newTokenBurnTransaction(allocator);
    defer tx.deinit();
    
    // Set values
    const token_id = hedera.TokenId.init(0, 0, 8000);
    _ = try tx.setTokenId(token_id);
    _ = try tx.setAmount(999999);
    
    const serial_numbers = [_]i64{ 10, 20, 30 };
    _ = try tx.setSerialNumbers(&serial_numbers);
    
    // Test getters
    try testing.expect(tx.getTokenId().?.equals(token_id));
    try testing.expectEqual(tx.getAmount(), 999999);
    try testing.expectEqual(tx.getSerialNumbers().len, 3);
    try testing.expectEqual(tx.getSerialNumbers()[0], 10);
    try testing.expectEqual(tx.getSerialNumbers()[1], 20);
    try testing.expectEqual(tx.getSerialNumbers()[2], 30);
}

test "TokenBurnTransaction frozen state protection" {
    const allocator = testing.allocator;
    
    const tx = hedera.newTokenBurnTransaction(allocator);
    defer tx.deinit();
    
    // Manually freeze the transaction
    tx.base.frozen = true;
    
    // Verify all setters fail when frozen
    const token_id = hedera.TokenId.init(0, 0, 9000);
    const token_result = tx.setTokenId(token_id);
    try testing.expectError(hedera.errors.HederaError.TransactionIsFrozen, token_result);
    
    const amount_result = tx.setAmount(1000);
    try testing.expectError(hedera.errors.HederaError.TransactionIsFrozen, amount_result);
    
    const serial_result = tx.addSerialNumber(1);
    try testing.expectError(hedera.errors.HederaError.TransactionIsFrozen, serial_result);
    
    const batch_serials = [_]i64{ 1, 2, 3 };
    const batch_result = tx.setSerialNumbers(&batch_serials);
    try testing.expectError(hedera.errors.HederaError.TransactionIsFrozen, batch_result);
}

test "TokenBurnTransaction edge cases" {
    const allocator = testing.allocator;
    
    const tx = hedera.newTokenBurnTransaction(allocator);
    defer tx.deinit();
    
    // Test clearing serial numbers and setting new ones
    _ = try tx.addSerialNumber(1);
    _ = try tx.addSerialNumber(2);
    try testing.expectEqual(tx.serial_numbers.items.len, 2);
    
    const new_serials = [_]i64{ 10, 20, 30 };
    _ = try tx.setSerialNumbers(&new_serials);
    try testing.expectEqual(tx.serial_numbers.items.len, 3);
    try testing.expectEqual(tx.serial_numbers.items[0], 10);
    
    // Test setting amount after having serial numbers (should clear serials first)
    tx.serial_numbers.clearRetainingCapacity();
    _ = try tx.setAmount(5000);
    try testing.expectEqual(tx.amount, 5000);
    try testing.expectEqual(tx.serial_numbers.items.len, 0);
}

test "TokenBurnTransaction limits constants" {
    // Verify the constant is accessible and reasonable
    try testing.expect(hedera.MAX_NFT_BURN_BATCH_SIZE > 0);
    try testing.expect(hedera.MAX_NFT_BURN_BATCH_SIZE <= 100); // Reasonable upper bound
}
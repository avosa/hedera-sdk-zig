const std = @import("std");
const testing = std.testing;
const hedera = @import("hedera");

test "TokenMintTransaction factory creates valid instance" {
    const allocator = testing.allocator;
    
    // Create transaction using factory
    const tx = hedera.newTokenMintTransaction(allocator);
    defer tx.deinit();
    
    // Verify it's properly initialized
    try testing.expect(tx.token_id == null);
    try testing.expectEqual(tx.amount, 0);
    try testing.expectEqual(tx.metadata.items.len, 0);
    try testing.expectEqual(tx.metadata_list.items.len, 0);
}

test "TokenMintTransaction fungible token minting" {
    const allocator = testing.allocator;
    
    const tx = hedera.newTokenMintTransaction(allocator);
    defer tx.deinit();
    
    // Set token ID
    const token_id = hedera.TokenId.init(0, 0, 1000);
    _ = try tx.setTokenId(token_id);
    try testing.expect(tx.token_id.?.equals(token_id));
    
    // Set amount for fungible tokens
    _ = try tx.setAmount(1000000);
    try testing.expectEqual(tx.amount, 1000000);
    
    // Verify metadata list is empty for fungible tokens
    try testing.expectEqual(tx.metadata_list.items.len, 0);
}

test "TokenMintTransaction NFT minting with metadata" {
    const allocator = testing.allocator;
    
    const tx = hedera.newTokenMintTransaction(allocator);
    defer tx.deinit();
    
    // Set token ID
    const token_id = hedera.TokenId.init(0, 0, 2000);
    _ = try tx.setTokenId(token_id);
    
    // Add NFT metadata
    const metadata1 = "NFT metadata 1";
    const metadata2 = "NFT metadata 2";
    const metadata3 = "NFT metadata 3";
    
    _ = try tx.addMetadata(metadata1);
    _ = try tx.addMetadata(metadata2);
    _ = try tx.addMetadata(metadata3);
    
    // Verify metadata was added
    try testing.expectEqual(tx.metadata_list.items.len, 3);
    try testing.expectEqualStrings(tx.metadata_list.items[0], metadata1);
    try testing.expectEqualStrings(tx.metadata_list.items[1], metadata2);
    try testing.expectEqualStrings(tx.metadata_list.items[2], metadata3);
    
    // Verify amount is 0 for NFTs
    try testing.expectEqual(tx.amount, 0);
}

test "TokenMintTransaction batch NFT minting" {
    const allocator = testing.allocator;
    
    const tx = hedera.newTokenMintTransaction(allocator);
    defer tx.deinit();
    
    // Set token ID
    const token_id = hedera.TokenId.init(0, 0, 3000);
    _ = try tx.setTokenId(token_id);
    
    // Create metadata list
    const metadata_list = [_][]const u8{
        "Batch NFT 1",
        "Batch NFT 2",
        "Batch NFT 3",
        "Batch NFT 4",
        "Batch NFT 5",
    };
    
    // Set metadata list
    _ = try tx.setMetadata(&metadata_list);
    
    // Verify all metadata was set
    try testing.expectEqual(tx.metadata_list.items.len, 5);
    for (metadata_list, 0..) |expected, i| {
        try testing.expectEqualStrings(tx.metadata_list.items[i], expected);
    }
}

test "TokenMintTransaction validation" {
    const allocator = testing.allocator;
    
    const tx = hedera.newTokenMintTransaction(allocator);
    defer tx.deinit();
    
    // Test minting without token ID
    const result = tx.execute(null);
    try testing.expectError(error.TokenIdRequired, result);
    
    // Set token ID
    const token_id = hedera.TokenId.init(0, 0, 4000);
    _ = try tx.setTokenId(token_id);
    
    // Test minting with neither amount nor metadata
    const empty_result = tx.execute(null);
    try testing.expectError(error.NothingToMint, empty_result);
    
    // Test setting both amount and metadata (invalid)
    _ = try tx.setAmount(1000);
    const metadata_result = tx.addMetadata("test");
    try testing.expectError(hedera.errors.HederaError.InvalidTokenMintMetadata, metadata_result);
}

test "TokenMintTransaction metadata size limits" {
    const allocator = testing.allocator;
    
    const tx = hedera.newTokenMintTransaction(allocator);
    defer tx.deinit();
    
    // Create metadata that's too large
    const large_metadata = try allocator.alloc(u8, hedera.MAX_METADATA_SIZE + 1);
    defer allocator.free(large_metadata);
    @memset(large_metadata, 'A');
    
    // Test adding oversized metadata
    const result = tx.addMetadata(large_metadata);
    try testing.expectError(hedera.errors.HederaError.InvalidTokenMintMetadata, result);
    
    // Test valid metadata at max size
    const max_metadata = large_metadata[0..hedera.MAX_METADATA_SIZE];
    _ = try tx.addMetadata(max_metadata);
    try testing.expectEqual(tx.metadata_list.items.len, 1);
}

test "TokenMintTransaction NFT batch size limits" {
    const allocator = testing.allocator;
    
    const tx = hedera.newTokenMintTransaction(allocator);
    defer tx.deinit();
    
    // Add maximum allowed NFTs
    var i: usize = 0;
    while (i < hedera.MAX_NFT_MINT_BATCH_SIZE) : (i += 1) {
        const metadata = try std.fmt.allocPrint(allocator, "NFT {d}", .{i});
        defer allocator.free(metadata);
        _ = try tx.addMetadata(metadata);
    }
    
    try testing.expectEqual(tx.metadata_list.items.len, hedera.MAX_NFT_MINT_BATCH_SIZE);
    
    // Try to add one more (should fail)
    const extra_result = tx.addMetadata("Extra NFT");
    try testing.expectError(hedera.errors.HederaError.MaxNftsInPriceRegimeHaveBeenMinted, extra_result);
}

test "TokenMintTransaction freezeWith" {
    const allocator = testing.allocator;
    
    const tx = hedera.newTokenMintTransaction(allocator);
    defer tx.deinit();
    
    // Set required fields
    const token_id = hedera.TokenId.init(0, 0, 5000);
    _ = try tx.setTokenId(token_id);
    _ = try tx.setAmount(100000);
    
    // Freeze without client
    try tx.freezeWith(null);
    
    // Verify transaction is frozen
    try testing.expect(tx.base.frozen);
    try testing.expect(tx.base.transaction_id != null);
}

test "TokenMintTransaction builds transaction body" {
    const allocator = testing.allocator;
    
    const tx = hedera.newTokenMintTransaction(allocator);
    defer tx.deinit();
    
    // Configure for fungible token mint
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
    var found_token_mint = false;
    
    while (reader.hasMore()) {
        const tag = try reader.readTag();
        if (tag.field_number == 35) { // tokenMint field
            found_token_mint = true;
            break;
        }
        try reader.skipField(tag.wire_type);
    }
    
    try testing.expect(found_token_mint);
}

test "TokenMintTransaction getters" {
    const allocator = testing.allocator;
    
    const tx = hedera.newTokenMintTransaction(allocator);
    defer tx.deinit();
    
    // Set values
    const token_id = hedera.TokenId.init(0, 0, 7000);
    _ = try tx.setTokenId(token_id);
    _ = try tx.setAmount(999999);
    
    const metadata = [_][]const u8{ "meta1", "meta2" };
    _ = try tx.setMetadata(&metadata);
    
    // Test getters
    try testing.expect(tx.getTokenId().?.equals(token_id));
    try testing.expectEqual(tx.getAmount(), 999999);
    try testing.expectEqual(tx.getMetadata().len, 2);
}
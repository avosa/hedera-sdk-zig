const std = @import("std");
const hedera = @import("hedera");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Initialize client for testnet
    var client = try hedera.Client.forTestnet();
    defer client.deinit();

    // Set operator account from environment variables
    const operator_id_str = std.posix.getenv("HEDERA_OPERATOR_ID") orelse {
        std.log.err("HEDERA_OPERATOR_ID environment variable not set", .{});
        return;
    };
    const operator_key_str = std.posix.getenv("HEDERA_OPERATOR_KEY") orelse {
        std.log.err("HEDERA_OPERATOR_KEY environment variable not set", .{});
        return;
    };

    const operator_id = try hedera.AccountId.fromString(allocator, operator_id_str);
    const operator_key = try hedera.PrivateKey.fromString(allocator, operator_key_str);

    const operator_key_converted = try operator_key.toOperatorKey();
    _ = try client.setOperator(operator_id, operator_key_converted);

    std.log.info("Token Operations Example", .{});
    std.log.info("=======================", .{});

    // Example 1: Create a fungible token
    std.log.info("\n1. Creating fungible token...", .{});
    
    var token_create_tx = hedera.TokenCreateTransaction.init(allocator);
    defer token_create_tx.deinit();

    _ = try token_create_tx.setTokenName("Example Token");
    _ = try token_create_tx.setTokenSymbol("EXT");
    _ = try token_create_tx.setDecimals(2);
    _ = try token_create_tx.setInitialSupply(1000000);
    _ = try token_create_tx.setTreasuryAccountId(operator_id);
    _ = try token_create_tx.setAdminKey(hedera.Key.fromPublicKey(operator_key.getPublicKey()));
    _ = try token_create_tx.setSupplyKey(hedera.Key.fromPublicKey(operator_key.getPublicKey()));
    _ = try token_create_tx.setTokenMemo("Created by Hedera Zig SDK example");

    var create_response = try token_create_tx.execute(&client);
    const create_receipt = try create_response.getReceipt(&client);
    
    if (create_receipt.token_id) |token_id| {
        std.log.info("✓ Fungible token created: {}", .{token_id});
        
        // Example 2: Query token info
        std.log.info("\n2. Querying token info...", .{});
        
        var token_info_query = hedera.TokenInfoQuery.init(allocator);
        defer token_info_query.deinit();
        
        _ = try token_info_query.setTokenId(token_id);
        const token_info = try token_info_query.execute(&client);
        
        std.log.info("✓ Token name: {s}", .{token_info.name});
        std.log.info("✓ Token symbol: {s}", .{token_info.symbol});
        std.log.info("✓ Total supply: {}", .{token_info.total_supply});
        std.log.info("✓ Decimals: {}", .{token_info.decimals});
        
        // Example 3: Create another account for token operations
        std.log.info("\n3. Creating recipient account...", .{});
        
        var recipient_key = try hedera.PrivateKey.generateEd25519(allocator);
        defer recipient_key.deinit();
        
        var account_create_tx = hedera.AccountCreateTransaction.init(allocator);
        defer account_create_tx.deinit();
        
        _ = try account_create_tx.setKey(hedera.Key.fromPublicKey(recipient_key.getPublicKey()));
        _ = try account_create_tx.setInitialBalance(try hedera.Hbar.from(10));
        
        var account_response = try account_create_tx.execute(&client);
        const account_receipt = try account_response.getReceipt(&client);
        
        if (account_receipt.account_id) |recipient_id| {
            std.log.info("✓ Recipient account created: {}", .{recipient_id});
            
            // Example 4: Associate token with recipient account
            std.log.info("\n4. Associating token with recipient...", .{});
            
            var associate_tx = hedera.TokenAssociateTransaction.init(allocator);
            defer associate_tx.deinit();
            
            _ = try associate_tx.setAccountId(recipient_id);
            _ = try associate_tx.addTokenId(token_id);
            
            _ = try associate_tx.base.freezeWith(&client);
            _ = try associate_tx.base.sign(recipient_key);
            
            var associate_response = try associate_tx.execute(&client);
            const associate_receipt = try associate_response.getReceipt(&client);
            
            std.log.info("✓ Token associated with status: {}", .{associate_receipt.status});
            
            // Example 5: Transfer tokens
            std.log.info("\n5. Transferring tokens...", .{});
            
            var transfer_tx = hedera.TransferTransaction.init(allocator);
            defer transfer_tx.deinit();
            
            _ = try transfer_tx.addTokenTransfer(token_id, operator_id, -1000);
            _ = try transfer_tx.addTokenTransfer(token_id, recipient_id, 1000);
            _ = try transfer_tx.setTransactionMemo("Token transfer via Hedera Zig SDK");
            
            var transfer_response = try transfer_tx.execute(&client);
            const transfer_receipt = try transfer_response.getReceipt(&client);
            
            std.log.info("✓ Tokens transferred with status: {}", .{transfer_receipt.status});
            
            // Example 6: Query account balance for tokens
            std.log.info("\n6. Querying token balances...", .{});
            
            var balance_query = hedera.AccountBalanceQuery.init(allocator);
            defer balance_query.deinit();
            
            _ = try balance_query.setAccountId(recipient_id);
            const balance = try balance_query.execute(&client);
            
            std.log.info("✓ Recipient HBAR balance: {} hbars", .{balance.hbars.toHbar()});
            if (balance.tokens.get(token_id)) |token_balance| {
                std.log.info("✓ Recipient token balance: {}", .{token_balance});
            }
            
            // Example 7: Mint more tokens
            std.log.info("\n7. Minting additional tokens...", .{});
            
            var mint_tx = hedera.TokenMintTransaction.init(allocator);
            defer mint_tx.deinit();
            
            _ = try mint_tx.setTokenId(token_id);
            _ = try mint_tx.setAmount(50000);
            
            var mint_response = try mint_tx.execute(&client);
            const mint_receipt = try mint_response.getReceipt(&client);
            
            std.log.info("✓ Tokens minted with status: {}", .{mint_receipt.status});
            std.log.info("✓ New total supply: {}", .{mint_receipt.total_supply});
            
            // Example 8: Burn tokens
            std.log.info("\n8. Burning tokens...", .{});
            
            var burn_tx = hedera.TokenBurnTransaction.init(allocator);
            defer burn_tx.deinit();
            
            _ = try burn_tx.setTokenId(token_id);
            _ = try burn_tx.setAmount(25000);
            
            var burn_response = try burn_tx.execute(&client);
            const burn_receipt = try burn_response.getReceipt(&client);
            
            std.log.info("✓ Tokens burned with status: {}", .{burn_receipt.status});
            std.log.info("✓ New total supply: {}", .{burn_receipt.total_supply});
            
            // Example 9: Freeze token for account
            std.log.info("\n9. Freezing token for recipient...", .{});
            
            var freeze_tx = hedera.TokenFreezeTransaction.init(allocator);
            defer freeze_tx.deinit();
            
            _ = try freeze_tx.setTokenId(token_id);
            _ = try freeze_tx.setAccountId(recipient_id);
            
            var freeze_response = try freeze_tx.execute(&client);
            const freeze_receipt = try freeze_response.getReceipt(&client);
            
            std.log.info("✓ Token frozen with status: {}", .{freeze_receipt.status});
            
            // Example 10: Unfreeze token for account
            std.log.info("\n10. Unfreezing token for recipient...", .{});
            
            var unfreeze_tx = hedera.TokenUnfreezeTransaction.init(allocator);
            defer unfreeze_tx.deinit();
            
            _ = try unfreeze_tx.setTokenId(token_id);
            _ = try unfreeze_tx.setAccountId(recipient_id);
            
            var unfreeze_response = try unfreeze_tx.execute(&client);
            const unfreeze_receipt = try unfreeze_response.getReceipt(&client);
            
            std.log.info("✓ Token unfrozen with status: {}", .{unfreeze_receipt.status});
            
            // Example 11: Update token
            std.log.info("\n11. Updating token...", .{});
            
            var update_tx = hedera.TokenUpdateTransaction.init(allocator);
            defer update_tx.deinit();
            
            _ = try update_tx.setTokenId(token_id);
            _ = try update_tx.setTokenName("Updated Example Token");
            _ = try update_tx.setTokenMemo("Updated by Hedera Zig SDK");
            
            var update_response = try update_tx.execute(&client);
            const update_receipt = try update_response.getReceipt(&client);
            
            std.log.info("✓ Token updated with status: {}", .{update_receipt.status});
            
            // Clean up: Dissociate token from recipient
            std.log.info("\n12. Cleaning up - dissociating token...", .{});
            
            var dissociate_tx = hedera.TokenDissociateTransaction.init(allocator);
            defer dissociate_tx.deinit();
            
            _ = try dissociate_tx.setAccountId(recipient_id);
            _ = try dissociate_tx.addTokenId(token_id);

            _ = try dissociate_tx.base.freezeWith(&client);
            _ = try dissociate_tx.base.sign(recipient_key);
            
            var dissociate_response = try dissociate_tx.execute(&client);
            const dissociate_receipt = try dissociate_response.getReceipt(&client);
            
            std.log.info("✓ Token dissociated with status: {}", .{dissociate_receipt.status});
            
            // Delete recipient account
            var delete_tx = hedera.AccountDeleteTransaction.init(allocator);
            defer delete_tx.deinit();
            
            _ = try delete_tx.setAccountId(recipient_id);
            _ = try delete_tx.setTransferAccountId(operator_id);

            _ = try delete_tx.base.freezeWith(&client);
            _ = try delete_tx.base.sign(recipient_key);
            
            var delete_response = try delete_tx.execute(&client);
            const delete_receipt = try delete_response.getReceipt(&client);
            
            std.log.info("✓ Recipient account deleted with status: {}", .{delete_receipt.status});
        }
        
        // Example 12: Delete token
        std.log.info("\n13. Deleting token...", .{});
        
        var token_delete_tx = hedera.TokenDeleteTransaction.init(allocator);
        defer token_delete_tx.deinit();
        
        _ = try token_delete_tx.setTokenId(token_id);
        
        var token_delete_response = try token_delete_tx.execute(&client);
        const token_delete_receipt = try token_delete_response.getReceipt(&client);
        
        std.log.info("✓ Token deleted with status: {}", .{token_delete_receipt.status});
        
    } else {
        std.log.err("Failed to get token ID from receipt", .{});
    }
    
    std.log.info("\nToken operations example completed successfully!", .{});
}
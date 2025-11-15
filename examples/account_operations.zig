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

    std.log.info("Account Operations Example", .{});
    std.log.info("========================", .{});

    // Example 1: Create a new account
    std.log.info("\n1. Creating new account...", .{});

    var new_account_key = try hedera.PrivateKey.generateEd25519(allocator);
    defer new_account_key.deinit();

    var account_create_tx = hedera.AccountCreateTransaction.init(allocator);
    defer account_create_tx.deinit();

    _ = try account_create_tx.setKey(hedera.Key.fromPublicKey(new_account_key.getPublicKey()));
    _ = try account_create_tx.setInitialBalance(try hedera.Hbar.from(10));
    _ = try account_create_tx.setAccountMemo("Created by Hedera Zig SDK example");

    var create_response = try account_create_tx.execute(&client);
    const create_receipt = try create_response.getReceipt(&client);
    
    if (create_receipt.account_id) |new_account_id| {
        std.log.info("✓ New account created: {}", .{new_account_id});
        
        // Example 2: Query account balance
        std.log.info("\n2. Querying account balance...", .{});
        
        var balance_query = hedera.AccountBalanceQuery.init(allocator);
        defer balance_query.deinit();
        
        _ = try balance_query.setAccountId(new_account_id);
        const balance = try balance_query.execute(&client);
        
        std.log.info("✓ Account balance: {} hbars", .{balance.hbars.toHbar()});
        
        // Example 3: Query account info
        std.log.info("\n3. Querying account info...", .{});
        
        var info_query = hedera.AccountInfoQuery.init(allocator);
        defer info_query.deinit();
        
        _ = try info_query.setAccountId(new_account_id);
        const account_info = try info_query.execute(&client);
        
        std.log.info("✓ Account ID: {}", .{account_info.account_id});
        std.log.info("✓ Balance: {} hbars", .{account_info.balance.toHbar()});
        std.log.info("✓ Auto renew period: {} seconds", .{account_info.auto_renew_period.seconds});
        
        // Example 4: Transfer HBAR
        std.log.info("\n4. Transferring HBAR...", .{});
        
        var transfer_tx = hedera.TransferTransaction.init(allocator);
        defer transfer_tx.deinit();
        
        _ = try transfer_tx.addHbarTransfer(operator_id, try hedera.Hbar.from(-5));
        _ = try transfer_tx.addHbarTransfer(new_account_id, try hedera.Hbar.from(5));
        _ = try transfer_tx.setTransactionMemo("Transfer from Hedera Zig SDK example");
        
        var transfer_response = try transfer_tx.execute(&client);
        const transfer_receipt = try transfer_response.getReceipt(&client);
        
        std.log.info("✓ Transfer completed with status: {}", .{transfer_receipt.status});
        
        // Example 5: Update account
        std.log.info("\n5. Updating account...", .{});
        
        var account_update_tx = hedera.AccountUpdateTransaction.init(allocator);
        defer account_update_tx.deinit();
        
        _ = try account_update_tx.setAccountId(new_account_id);
        _ = try account_update_tx.setAccountMemo("Updated by Hedera Zig SDK example");
        
        var update_response = try account_update_tx.execute(&client);
        const update_receipt = try update_response.getReceipt(&client);
        
        std.log.info("✓ Account updated with status: {}", .{update_receipt.status});
        
        // Example 6: Query account records
        std.log.info("\n6. Querying account records...", .{});
        
        var records_query = hedera.AccountRecordsQuery.init(allocator);
        defer records_query.deinit();
        
        _ = try records_query.setAccountId(new_account_id);
        const records = try records_query.execute(&client);
        
        std.log.info("✓ Found {} transaction records", .{records.len});
        
        // Example 7: Delete account (send remaining balance back to operator)
        std.log.info("\n7. Deleting account...", .{});
        
        var account_delete_tx = hedera.AccountDeleteTransaction.init(allocator);
        defer account_delete_tx.deinit();
        
        _ = try account_delete_tx.setAccountId(new_account_id);
        _ = try account_delete_tx.setTransferAccountId(operator_id);
        
        _ = try account_delete_tx.base.freezeWith(&client);
        _ = try account_delete_tx.base.sign(new_account_key);
        
        var delete_response = try account_delete_tx.execute(&client);
        const delete_receipt = try delete_response.getReceipt(&client);
        
        std.log.info("✓ Account deleted with status: {}", .{delete_receipt.status});
        
    } else {
        std.log.err("Failed to get new account ID from receipt", .{});
    }
    
    std.log.info("\nAccount operations example completed successfully!", .{});
}
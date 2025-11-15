const std = @import("std");
const hedera = @import("hedera");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Match Go SDK pattern: ClientForName
    var client = try hedera.clientForName(std.posix.getenv("HEDERA_NETWORK") orelse "testnet");
    defer client.deinit();

    // Match Go SDK pattern: AccountIDFromString and PrivateKeyFromString
    const operator_id_str = std.posix.getenv("OPERATOR_ID") orelse {
        std.log.err("OPERATOR_ID environment variable not set", .{});
        return;
    };
    const operator_key_str = std.posix.getenv("OPERATOR_KEY") orelse {
        std.log.err("OPERATOR_KEY environment variable not set", .{});
        return;
    };

    const operator_id = try hedera.accountIdFromString(allocator, operator_id_str);
    var operator_key = try hedera.privateKeyFromString(allocator, operator_key_str);
    defer operator_key.deinit();

    // Match Go SDK pattern: SetOperator
    const operator_key_converted = try operator_key.toOperatorKey();
    _ = try client.setOperator(operator_id, operator_key_converted);

    std.log.info("Transfer Crypto Example", .{});
    std.log.info("======================", .{});

    // Create a new account to transfer to
    var new_key = try hedera.generatePrivateKey(allocator);
    defer new_key.deinit();

    var create_tx = hedera.AccountCreateTransaction.init(allocator);
    defer create_tx.deinit();

    _ = try create_tx.setKeyWithoutAlias(hedera.Key.fromPublicKey(new_key.getPublicKey()));
    _ = try create_tx.setInitialBalance(try hedera.Hbar.from(10));

    var create_response = try create_tx.execute(&client);
    const create_receipt = try create_response.getReceipt(&client);
    
    const new_account_id = create_receipt.account_id orelse {
        std.log.err("Failed to get new account ID", .{});
        return;
    };
    
    std.log.info("Created account: {s}", .{try new_account_id.toString(allocator)});
    
    // Transfer HBAR
    var transfer = hedera.TransferTransaction.init(allocator);
    defer transfer.deinit();

    _ = try transfer.addHbarTransfer(operator_id, try hedera.Hbar.from(-5));
    _ = try transfer.addHbarTransfer(new_account_id, try hedera.Hbar.from(5));
    _ = try transfer.setTransactionMemo("Transfer from Zig SDK");

    var transfer_response = try transfer.execute(&client);
    const transfer_receipt = try transfer_response.getReceipt(&client);
    
    std.log.info("Transfer completed with status: {}", .{transfer_receipt.status});
    
    // Check balance
    var balance_query = hedera.AccountBalanceQuery.init(allocator);
    defer balance_query.deinit();
    
    _ = try balance_query.setAccountId(new_account_id);
    const balance = try balance_query.execute(&client);
    
    std.log.info("New account balance: {} hbars", .{balance.hbars.toHbar()});
}
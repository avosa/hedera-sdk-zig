const std = @import("std");
const hedera = @import("hedera");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Match Go SDK pattern: ClientForName
    var client = try hedera.client_for_name(std.posix.getenv("HEDERA_NETWORK") orelse "testnet");
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
    
    const operator_id = try hedera.account_id_from_string(allocator, operator_id_str);
    var operator_key = try hedera.private_key_from_string(allocator, operator_key_str);
    defer operator_key.deinit();
    
    // Match Go SDK pattern: SetOperator
    try client.set_operator(operator_id, operator_key);
    
    std.log.info("Transfer Crypto Example", .{});
    std.log.info("======================", .{});
    
    // Create a new account to transfer to
    var new_key = try hedera.generate_private_key(allocator);
    defer new_key.deinit();
    
    var create_tx = hedera.new_account_create_transaction(allocator);
    defer create_tx.deinit();
    
    _ = try create_tx.set_key_without_alias(hedera.Key.fromPublicKey(new_key.getPublicKey()));
    _ = try create_tx.set_initial_balance(hedera.Hbar.from(10));
    
    const create_response = try create_tx.execute(&client);
    const create_receipt = try create_response.get_receipt(&client);
    
    const new_account_id = create_receipt.account_id orelse {
        std.log.err("Failed to get new account ID", .{});
        return;
    };
    
    std.log.info("Created account: {s}", .{try new_account_id.toString(allocator)});
    
    // Transfer HBAR
    var transfer = hedera.TransferTransaction.init(allocator);
    defer transfer.deinit();
    
    try transfer.addHbarTransfer(operator_id, hedera.Hbar.from(-5));
    try transfer.addHbarTransfer(new_account_id, hedera.Hbar.from(5));
    try transfer.setTransactionMemo("Transfer from Zig SDK");
    
    const transfer_response = try transfer.execute(&client);
    const transfer_receipt = try transfer_response.get_receipt(&client);
    
    std.log.info("Transfer completed with status: {}", .{transfer_receipt.status});
    
    // Check balance
    var balance_query = hedera.AccountBalanceQuery.init(allocator);
    defer balance_query.deinit();
    
    try balance_query.setAccountId(new_account_id);
    const balance = try balance_query.execute(&client);
    
    std.log.info("New account balance: {} hbars", .{balance.hbars.toHbars()});
}
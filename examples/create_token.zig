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
    
    std.log.info("Create Token Example", .{});
    std.log.info("===================", .{});
    
    // Generate keys for token
    var admin_key = try hedera.generate_private_key(allocator);
    defer admin_key.deinit();
    
    var supply_key = try hedera.generate_private_key(allocator);
    defer supply_key.deinit();
    
    // Create token
    var token_create = hedera.TokenCreateTransaction.init(allocator);
    defer token_create.deinit();
    
    try token_create.setTokenName("Zig SDK Token");
    try token_create.setTokenSymbol("ZST");
    try token_create.setDecimals(2);
    try token_create.setInitialSupply(1000000);
    try token_create.setTreasuryAccountId(operator_id);
    try token_create.setAdminKey(hedera.Key.fromPublicKey(admin_key.getPublicKey()));
    try token_create.setSupplyKey(hedera.Key.fromPublicKey(supply_key.getPublicKey()));
    try token_create.setTokenMemo("Created with Hedera Zig SDK");
    
    const create_response = try token_create.execute(&client);
    const create_receipt = try create_response.get_receipt(&client);
    
    const token_id = create_receipt.token_id orelse {
        std.log.err("Failed to get token ID", .{});
        return;
    };
    
    std.log.info("Created token: {s}", .{try token_id.toString(allocator)});
    
    // Create new account and associate token
    var new_account_key = try hedera.generate_private_key(allocator);
    defer new_account_key.deinit();
    
    var account_create = hedera.new_account_create_transaction(allocator);
    defer account_create.deinit();
    
    _ = try account_create.set_key_without_alias(hedera.Key.fromPublicKey(new_account_key.getPublicKey()));
    
    const account_response = try account_create.execute(&client);
    const account_receipt = try account_response.get_receipt(&client);
    
    const new_account_id = account_receipt.account_id orelse {
        std.log.err("Failed to get new account ID", .{});
        return;
    };
    
    std.log.info("Created account: {s}", .{try new_account_id.toString(allocator)});
    
    // Associate token with account
    var token_associate = hedera.TokenAssociateTransaction.init(allocator);
    defer token_associate.deinit();
    
    try token_associate.setAccountId(new_account_id);
    try token_associate.addTokenId(token_id);
    
    // Freeze and sign with new account's key
    try token_associate.freezeWith(&client);
    try token_associate.sign(new_account_key);
    
    const associate_response = try token_associate.execute(&client);
    const associate_receipt = try associate_response.get_receipt(&client);
    
    std.log.info("Token association status: {}", .{associate_receipt.status});
    
    // Transfer tokens
    var transfer = hedera.TransferTransaction.init(allocator);
    defer transfer.deinit();
    
    try transfer.addTokenTransfer(token_id, operator_id, -100);
    try transfer.addTokenTransfer(token_id, new_account_id, 100);
    
    const transfer_response = try transfer.execute(&client);
    const transfer_receipt = try transfer_response.get_receipt(&client);
    
    std.log.info("Token transfer status: {}", .{transfer_receipt.status});
}
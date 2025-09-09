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
    
    std.log.info("Account Create Example", .{});
    std.log.info("=====================", .{});
    
    // Match Go SDK pattern: GeneratePrivateKey
    var new_key = try hedera.generate_private_key(allocator);
    defer new_key.deinit();
    
    std.log.info("Private key: {s}", .{try new_key.toString(allocator)});
    std.log.info("Public key: {s}", .{try new_key.getPublicKey().toString(allocator)});
    
    // Match Go SDK pattern: NewAccountCreateTransaction with chaining
    var tx = hedera.new_account_create_transaction(allocator);
    defer tx.deinit();
    
    _ = try tx.set_key_without_alias(hedera.Key.fromPublicKey(new_key.getPublicKey()));
    _ = try tx.set_receiver_signature_required(false);
    _ = try tx.set_max_automatic_token_associations(1);
    _ = try tx.set_transaction_memo("zig sdk example create_account.zig");
    
    // Execute transaction
    const tx_response = try tx.execute(&client);
    
    // Get receipt
    const receipt = try tx_response.get_receipt(&client);
    
    // Get new account ID from receipt
    if (receipt.account_id) |new_account_id| {
        std.log.info("Account created: {s}", .{try new_account_id.toString(allocator)});
    } else {
        std.log.err("Failed to get new account ID from receipt", .{});
    }
}
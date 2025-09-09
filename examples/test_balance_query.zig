const std = @import("std");
const hedera = @import("hedera");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize testnet client
    var client = try hedera.Client.forTestnet();
    defer client.deinit();

    // Set operator credentials
    const operator_id_str = std.posix.getenv("HEDERA_OPERATOR_ID") orelse {
        std.debug.print("Error: HEDERA_OPERATOR_ID environment variable not set\n", .{});
        return;
    };
    
    const operator_key_str = std.posix.getenv("HEDERA_OPERATOR_KEY") orelse {
        std.debug.print("Error: HEDERA_OPERATOR_KEY environment variable not set\n", .{});
        return;
    };

    const operator_id = try hedera.AccountId.fromString(allocator, operator_id_str);
    const operator_key = try hedera.PrivateKey.fromString(allocator, operator_key_str);
    
    const operator_key_converted = try operator_key.toOperatorKey();
    _ = try client.setOperator(operator_id, operator_key_converted);

    std.debug.print("Testing account balance query...\n", .{});

    // Query the operator account balance
    var balance_query = hedera.AccountBalanceQuery.init(allocator);
    defer balance_query.deinit();

    _ = try balance_query.setAccountId(operator_id);
    const balance = try balance_query.execute(&client);
    defer balance.deinit();

    std.debug.print("Account balance: {} hbar\n", .{balance.hbars});
    std.debug.print("SUCCESS: Balance query completed!\n", .{});
}
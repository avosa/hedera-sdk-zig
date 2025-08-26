const std = @import("std");
const Client = @import("../network/client.zig").Client;
const AccountId = @import("../core/id.zig").AccountId;
const AccountInfoQuery = @import("../account/account_info_query.zig").AccountInfoQuery;
const AccountInfo = @import("../account/account_info_query.zig").AccountInfo;
const PublicKey = @import("../crypto/key.zig").PublicKey;
const Key = @import("../crypto/key.zig").Key;
const Transaction = @import("../transaction/transaction.zig").Transaction;

// AccountInfoFlow provides utility functions to verify signatures and transactions
// using account information from the network
pub const AccountInfoFlow = struct {
    
    // Verify a signature using the account's key from the network
    pub fn verifySignature(client: *Client, account_id: AccountId, message: []const u8, signature: []const u8) !bool {
        var info_query = AccountInfoQuery.init(client.allocator);
        defer info_query.deinit();
        _ = info_query.setAccountId(account_id);
        
        const info = try info_query.execute(client);
        defer info.deinit(client.allocator);
        
        if (info.key) |key| {
            switch (key) {
                .ed25519 => |public_key| return public_key.verify(message, signature),
                .ecdsa_secp256k1 => |public_key| return public_key.verify(message, signature),
                else => return false, // Complex key types not supported for direct verification
            }
        }
        
        return false;
    }
    
    // Verify a transaction using the account's key from the network
    pub fn verifyTransaction(client: *Client, account_id: AccountId, transaction: Transaction) !bool {
        var info_query = AccountInfoQuery.init(client.allocator);
        defer info_query.deinit();
        _ = info_query.setAccountId(account_id);
        
        const info = try info_query.execute(client);
        defer info.deinit(client.allocator);
        
        if (info.key) |key| {
            switch (key) {
                .ed25519 => |public_key| return public_key.verifyTransaction(transaction),
                .ecdsa_secp256k1 => |public_key| return public_key.verifyTransaction(transaction),
                else => return false, // Complex key types not supported for direct verification
            }
        }
        
        return false;
    }
};

// Creates a new account information flow
pub fn accountInfoFlow() AccountInfoFlow {
    return AccountInfoFlow{};
}
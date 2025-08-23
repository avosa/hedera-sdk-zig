const std = @import("std");
const AccountId = @import("../core/id.zig").AccountId;
const TokenId = @import("../core/id.zig").TokenId;
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const errors = @import("../core/errors.zig");

// TokenUnfreezeTransaction unfreezes an account's ability to transfer a token
pub const TokenUnfreezeTransaction = struct {
    base: Transaction,
    token_id: ?TokenId,
    account_id: ?AccountId,
    
    pub fn init(allocator: std.mem.Allocator) TokenUnfreezeTransaction {
        return TokenUnfreezeTransaction{
            .base = Transaction.init(allocator),
            .token_id = null,
            .account_id = null,
        };
    }
    
    pub fn deinit(self: *TokenUnfreezeTransaction) void {
        self.base.deinit();
    }
    
    // Set the token to unfreeze
    pub fn setTokenId(self: *TokenUnfreezeTransaction, token_id: TokenId) errors.HederaError!*TokenUnfreezeTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        self.token_id = token_id;
        return self;
    }
    
    // Set the account to unfreeze
    pub fn setAccountId(self: *TokenUnfreezeTransaction, account_id: AccountId) errors.HederaError!*TokenUnfreezeTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        self.account_id = account_id;
        return self;
    }
    
    // Getter methods for uniformity with Go SDK
    pub fn getTokenId(self: *const TokenUnfreezeTransaction) ?TokenId {
        return self.token_id;
    }
    
    pub fn getAccountId(self: *const TokenUnfreezeTransaction) ?AccountId {
        return self.account_id;
    }
    
    // Execute the transaction
    pub fn execute(self: *TokenUnfreezeTransaction, client: *Client) !TransactionResponse {
        if (self.token_id == null) {
            return error.TokenIdRequired;
        }
        
        if (self.account_id == null) {
            return error.AccountIdRequired;
        }
        
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *TokenUnfreezeTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Common transaction fields
        try self.writeCommonFields(&writer);
        
        // tokenUnfreeze = 32 (oneof data)
        var unfreeze_writer = ProtoWriter.init(self.base.allocator);
        defer unfreeze_writer.deinit();
        
        // token = 1
        if (self.token_id) |token| {
            var token_writer = ProtoWriter.init(self.base.allocator);
            defer token_writer.deinit();
            try token_writer.writeInt64(1, @intCast(token.shard));
            try token_writer.writeInt64(2, @intCast(token.realm));
            try token_writer.writeInt64(3, @intCast(token.num));
            const token_bytes = try token_writer.toOwnedSlice();
            defer self.base.allocator.free(token_bytes);
            try unfreeze_writer.writeMessage(1, token_bytes);
        }
        
        // account = 2
        if (self.account_id) |account| {
            var account_writer = ProtoWriter.init(self.base.allocator);
            defer account_writer.deinit();
            try account_writer.writeInt64(1, @intCast(account.shard));
            try account_writer.writeInt64(2, @intCast(account.realm));
            try account_writer.writeInt64(3, @intCast(account.account));
            const account_bytes = try account_writer.toOwnedSlice();
            defer self.base.allocator.free(account_bytes);
            try unfreeze_writer.writeMessage(2, account_bytes);
        }
        
        const unfreeze_bytes = try unfreeze_writer.toOwnedSlice();
        defer self.base.allocator.free(unfreeze_bytes);
        try writer.writeMessage(32, unfreeze_bytes);
        
        return writer.toOwnedSlice();
    }
    
    fn writeCommonFields(self: *TokenUnfreezeTransaction, writer: *ProtoWriter) !void {
        // transactionID = 1
        if (self.base.transaction_id) |tx_id| {
            var tx_id_writer = ProtoWriter.init(self.base.allocator);
            defer tx_id_writer.deinit();
            
            var timestamp_writer = ProtoWriter.init(self.base.allocator);
            defer timestamp_writer.deinit();
            try timestamp_writer.writeInt64(1, tx_id.valid_start.seconds);
            try timestamp_writer.writeInt32(2, tx_id.valid_start.nanos);
            const timestamp_bytes = try timestamp_writer.toOwnedSlice();
            defer self.base.allocator.free(timestamp_bytes);
            try tx_id_writer.writeMessage(1, timestamp_bytes);
            
            var account_writer = ProtoWriter.init(self.base.allocator);
            defer account_writer.deinit();
            try account_writer.writeInt64(1, @intCast(tx_id.account_id.shard));
            try account_writer.writeInt64(2, @intCast(tx_id.account_id.realm));
            try account_writer.writeInt64(3, @intCast(tx_id.account_id.account));
            const account_bytes = try account_writer.toOwnedSlice();
            defer self.base.allocator.free(account_bytes);
            try tx_id_writer.writeMessage(2, account_bytes);
            
            if (tx_id.nonce) |n| {
                try tx_id_writer.writeInt32(4, @intCast(n));
            }
            
            const tx_id_bytes = try tx_id_writer.toOwnedSlice();
            defer self.base.allocator.free(tx_id_bytes);
            try writer.writeMessage(1, tx_id_bytes);
        }
        
        // nodeAccountID = 2
        if (self.base.node_account_ids.items.len > 0) {
            var node_writer = ProtoWriter.init(self.base.allocator);
            defer node_writer.deinit();
            const node = self.base.node_account_ids.items[0];
            try node_writer.writeInt64(1, @intCast(node.shard));
            try node_writer.writeInt64(2, @intCast(node.realm));
            try node_writer.writeInt64(3, @intCast(node.account));
            const node_bytes = try node_writer.toOwnedSlice();
            defer self.base.allocator.free(node_bytes);
            try writer.writeMessage(2, node_bytes);
        }
        
        // transactionFee = 3
        if (self.base.max_transaction_fee) |fee| {
            try writer.writeUint64(3, @intCast(fee.toTinybars()));
        }
        
        // transactionValidDuration = 4
        var duration_writer = ProtoWriter.init(self.base.allocator);
        defer duration_writer.deinit();
        try duration_writer.writeInt64(1, self.base.transaction_valid_duration.seconds);
        const duration_bytes = try duration_writer.toOwnedSlice();
        defer self.base.allocator.free(duration_bytes);
        try writer.writeMessage(4, duration_bytes);
        
        // memo = 5
        if (self.base.transaction_memo.len > 0) {
            try writer.writeString(5, self.base.transaction_memo);
        }
    }
};

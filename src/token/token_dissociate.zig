const std = @import("std");
const AccountId = @import("../core/id.zig").AccountId;
const TokenId = @import("../core/id.zig").TokenId;
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;

// Maximum number of tokens that can be dissociated in a single transaction
pub const MAX_TOKEN_DISSOCIATIONS: usize = 100;

// TokenDissociateTransaction dissociates tokens from an account
pub const TokenDissociateTransaction = struct {
    base: Transaction,
    account_id: ?AccountId,
    token_ids: std.ArrayList(TokenId),
    
    pub fn init(allocator: std.mem.Allocator) TokenDissociateTransaction {
        return TokenDissociateTransaction{
            .base = Transaction.init(allocator),
            .account_id = null,
            .token_ids = std.ArrayList(TokenId).init(allocator),
        };
    }
    
    pub fn deinit(self: *TokenDissociateTransaction) void {
        self.base.deinit();
        self.token_ids.deinit();
    }
    
    // Set the account to dissociate tokens from
    pub fn setAccountId(self: *TokenDissociateTransaction, account_id: AccountId) *TokenDissociateTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        self.account_id = account_id;
        return self;
    }
    
    // Includes a token for dissociation
    pub fn addTokenId(self: *TokenDissociateTransaction, token_id: TokenId) *TokenDissociateTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        
        if (self.token_ids.items.len >= MAX_TOKEN_DISSOCIATIONS) {
            @panic("Too many token dissociations");
        }
        
        // Check for duplicates
        for (self.token_ids.items) |existing| {
            if (existing.equals(token_id)) {
                @panic("Duplicate token ID");
            }
        }
        
        self.token_ids.append(token_id) catch @panic("Failed to append token ID");
        return self;
    }
    
    // Set the list of tokens to dissociate
    pub fn setTokenIds(self: *TokenDissociateTransaction, token_ids: []const TokenId) *TokenDissociateTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        
        if (token_ids.len > MAX_TOKEN_DISSOCIATIONS) {
            @panic("Too many token dissociations");
        }
        
        // Clear existing tokens
        self.token_ids.clearRetainingCapacity();
        
        // Include new tokens, checking for duplicates
        for (token_ids) |token_id| {
            for (self.token_ids.items) |existing| {
                if (existing.equals(token_id)) {
                    @panic("Duplicate token ID");
                }
            }
            self.token_ids.append(token_id) catch @panic("Failed to append token ID");
        }
        return self;
    }
    
    // Getter methods for uniformity with Go SDK
    pub fn getAccountId(self: *const TokenDissociateTransaction) ?AccountId {
        return self.account_id;
    }
    
    pub fn getTokenIDs(self: *const TokenDissociateTransaction) []const TokenId {
        return self.token_ids.items;
    }
    
    // Execute the transaction
    pub fn execute(self: *TokenDissociateTransaction, client: *Client) !TransactionResponse {
        if (self.account_id == null) {
            return error.AccountIdRequired;
        }
        
        if (self.token_ids.items.len == 0) {
            return error.NoTokensToDissociate;
        }
        
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *TokenDissociateTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Common transaction fields
        try self.writeCommonFields(&writer);
        
        // tokenDissociate = 41 (oneof data)
        var dissociate_writer = ProtoWriter.init(self.base.allocator);
        defer dissociate_writer.deinit();
        
        // account = 1
        if (self.account_id) |account| {
            var account_writer = ProtoWriter.init(self.base.allocator);
            defer account_writer.deinit();
            try account_writer.writeInt64(1, @intCast(account.shard));
            try account_writer.writeInt64(2, @intCast(account.realm));
            try account_writer.writeInt64(3, @intCast(account.account));
            const account_bytes = try account_writer.toOwnedSlice();
            defer self.base.allocator.free(account_bytes);
            try dissociate_writer.writeMessage(1, account_bytes);
        }
        
        // tokens = 2 (repeated)
        for (self.token_ids.items) |token| {
            var token_writer = ProtoWriter.init(self.base.allocator);
            defer token_writer.deinit();
            try token_writer.writeInt64(1, @intCast(token.shard));
            try token_writer.writeInt64(2, @intCast(token.realm));
            try token_writer.writeInt64(3, @intCast(token.num));
            const token_bytes = try token_writer.toOwnedSlice();
            defer self.base.allocator.free(token_bytes);
            try dissociate_writer.writeMessage(2, token_bytes);
        }
        
        const dissociate_bytes = try dissociate_writer.toOwnedSlice();
        defer self.base.allocator.free(dissociate_bytes);
        try writer.writeMessage(41, dissociate_bytes);
        
        return writer.toOwnedSlice();
    }
    
    fn writeCommonFields(self: *TokenDissociateTransaction, writer: *ProtoWriter) !void {
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

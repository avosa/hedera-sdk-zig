const std = @import("std");
const TokenId = @import("../core/id.zig").TokenId;
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const errors = @import("../core/errors.zig");

// Maximum metadata size for NFTs
pub const MAX_METADATA_SIZE: usize = 100;
pub const MAX_NFT_MINT_BATCH_SIZE: usize = 10;

// TokenMintTransaction mints new fungible tokens or NFTs
pub const TokenMintTransaction = struct {
    base: Transaction,
    token_id: ?TokenId,
    amount: u64,
    metadata: std.ArrayList([]const u8),
    metadata_list: std.ArrayList([]const u8),
    
    pub fn init(allocator: std.mem.Allocator) TokenMintTransaction {
        return TokenMintTransaction{
            .base = Transaction.init(allocator),
            .token_id = null,
            .amount = 0,
            .metadata = std.ArrayList([]const u8).init(allocator),
            .metadata_list = std.ArrayList([]const u8).init(allocator),
        };
    }
    
    pub fn deinit(self: *TokenMintTransaction) void {
        self.base.deinit();
        self.metadata.deinit();
        self.metadata_list.deinit();
    }
    
    // Set the token to mint
    pub fn setTokenId(self: *TokenMintTransaction, token_id: TokenId) errors.HederaError!*TokenMintTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        self.token_id = token_id;
        return self;
    }
    
    // Set amount to mint (for fungible tokens)
    pub fn setAmount(self: *TokenMintTransaction, amount: u64) errors.HederaError!*TokenMintTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        
        if (self.metadata_list.items.len > 0) {
            return errors.HederaError.InvalidTokenMintAmount;
        }
        
        if (amount == 0) {
            return errors.HederaError.InvalidTokenMintAmount;
        }
        
        if (amount > std.math.maxInt(i64)) {
            return errors.HederaError.InvalidTokenMintAmount;
        }
        
        self.amount = amount;
        return self;
    }
    
    // Includes metadata for NFT minting
    pub fn addMetadata(self: *TokenMintTransaction, metadata: []const u8) errors.HederaError!*TokenMintTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        
        if (self.amount > 0) {
            return errors.HederaError.InvalidTokenMintMetadata;
        }
        
        if (metadata.len > MAX_METADATA_SIZE) {
            return errors.HederaError.InvalidTokenMintMetadata;
        }
        
        if (self.metadata_list.items.len >= MAX_NFT_MINT_BATCH_SIZE) {
            return errors.HederaError.MaxNftsInPriceRegimeHaveBeenMinted;
        }
        
        try errors.handleAppendError(&self.metadata_list, metadata);
        return self;
    }
    
    // Set metadata list for batch NFT minting
    pub fn setMetadata(self: *TokenMintTransaction, metadata_list: []const []const u8) errors.HederaError!*TokenMintTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        
        if (self.amount > 0) {
            return errors.HederaError.InvalidTokenMintMetadata;
        }
        
        if (metadata_list.len > MAX_NFT_MINT_BATCH_SIZE) {
            return errors.HederaError.MaxNftsInPriceRegimeHaveBeenMinted;
        }
        
        self.metadata_list.clearRetainingCapacity();
        
        for (metadata_list) |metadata| {
            if (metadata.len > MAX_METADATA_SIZE) {
                return errors.HederaError.InvalidTokenMintMetadata;
            }
            try errors.handleAppendError(&self.metadata_list, metadata);
        }
        return self;
    }
    
    // Getter methods for uniformity with Go SDK
    pub fn getTokenId(self: *const TokenMintTransaction) ?TokenId {
        return self.token_id;
    }
    
    pub fn getAmount(self: *const TokenMintTransaction) u64 {
        return self.amount;
    }
    
    pub fn getMetadata(self: *const TokenMintTransaction) []const []const u8 {
        return self.metadata_list.items;
    }
    
    // Execute the transaction
    pub fn execute(self: *TokenMintTransaction, client: *Client) !TransactionResponse {
        if (self.token_id == null) {
            return error.TokenIdRequired;
        }
        
        if (self.amount == 0 and self.metadata_list.items.len == 0) {
            return error.NothingToMint;
        }
        
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *TokenMintTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Common transaction fields
        try self.writeCommonFields(&writer);
        
        // tokenMint = 35 (oneof data)
        var mint_writer = ProtoWriter.init(self.base.allocator);
        defer mint_writer.deinit();
        
        // token = 1
        if (self.token_id) |token| {
            var token_writer = ProtoWriter.init(self.base.allocator);
            defer token_writer.deinit();
            try token_writer.writeInt64(1, @intCast(token.shard));
            try token_writer.writeInt64(2, @intCast(token.realm));
            try token_writer.writeInt64(3, @intCast(token.num));
            const token_bytes = try token_writer.toOwnedSlice();
            defer self.base.allocator.free(token_bytes);
            try mint_writer.writeMessage(1, token_bytes);
        }
        
        // amount = 2 (for fungible tokens)
        if (self.amount > 0) {
            try mint_writer.writeUint64(2, self.amount);
        }
        
        // metadata = 3 (repeated, for NFTs)
        for (self.metadata_list.items) |metadata| {
            try mint_writer.writeBytes(3, metadata);
        }
        
        const mint_bytes = try mint_writer.toOwnedSlice();
        defer self.base.allocator.free(mint_bytes);
        try writer.writeMessage(35, mint_bytes);
        
        return writer.toOwnedSlice();
    }
    
    fn writeCommonFields(self: *TokenMintTransaction, writer: *ProtoWriter) !void {
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

const std = @import("std");
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const AccountId = @import("../core/id.zig").AccountId;
const TokenId = @import("../core/id.zig").TokenId;
const NftId = @import("../core/id.zig").NftId;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const errors = @import("../core/errors.zig");

// TokenReference represents a token reference for rejection
pub const TokenReference = struct {
    token_id: ?TokenId = null,
    nft_id: ?NftId = null,
};

// TokenRejectTransaction rejects unwanted tokens
pub const TokenRejectTransaction = struct {
    base: Transaction,
    owner: ?AccountId = null,
    token_references: std.ArrayList(TokenReference),
    
    pub fn init(allocator: std.mem.Allocator) TokenRejectTransaction {
        return TokenRejectTransaction{
            .base = Transaction.init(allocator),
            .token_references = std.ArrayList(TokenReference).init(allocator),
        };
    }
    
    pub fn deinit(self: *TokenRejectTransaction) void {
        self.base.deinit();
        self.token_references.deinit();
    }
    
    // Set the owner account
    pub fn setOwner(self: *TokenRejectTransaction, owner: AccountId) !*TokenRejectTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        self.owner = owner;
        return self;
    }
    
    // Alias for setOwner to match example usage
    pub fn setOwnerId(self: *TokenRejectTransaction, owner: AccountId) !*TokenRejectTransaction {
        return self.setOwner(owner);
    }
    
    // Add a fungible token to reject
    pub fn addTokenId(self: *TokenRejectTransaction, token_id: TokenId) !void {
        try self.token_references.append(TokenReference{
            .token_id = token_id,
        });
    }
    
    // Set multiple token IDs to reject
    pub fn setTokenIds(self: *TokenRejectTransaction, token_ids: []const TokenId) !*TokenRejectTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        
        // Clear existing references and add new ones
        self.token_references.clearRetainingCapacity();
        for (token_ids) |token_id| {
            try self.token_references.append(TokenReference{
                .token_id = token_id,
            });
        }
        return self;
    }
    
    // Add an NFT to reject
    pub fn addNftId(self: *TokenRejectTransaction, nft_id: NftId) !void {
        try self.token_references.append(TokenReference{
            .nft_id = nft_id,
        });
    }
    
    // Set multiple NFT IDs to reject
    pub fn setNftIds(self: *TokenRejectTransaction, nft_ids: []const NftId) !*TokenRejectTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        
        // Clear existing references and add NFT references
        self.token_references.clearRetainingCapacity();
        for (nft_ids) |nft_id| {
            try self.token_references.append(TokenReference{
                .nft_id = nft_id,
            });
        }
        return self;
    }
    
    // Set all token references to reject
    pub fn setTokenReferences(self: *TokenRejectTransaction, references: []const TokenReference) !*TokenRejectTransaction {
        self.token_references.clearAndFree();
        try self.token_references.appendSlice(references);
        return self;
    }
    
    // Freeze the transaction
    pub fn freezeWith(self: *TokenRejectTransaction, client: *Client) !void {
        try self.base.freezeWith(client);
    }
    
    // Execute the transaction
    pub fn execute(self: *TokenRejectTransaction, client: *Client) !TransactionResponse {
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *TokenRejectTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Write common transaction fields
        try self.writeCommonFields(&writer);
        
        // tokenReject = 59 (oneof data)
        var reject_writer = ProtoWriter.init(self.base.allocator);
        defer reject_writer.deinit();
        
        // owner = 1
        if (self.owner) |owner| {
            var owner_writer = ProtoWriter.init(self.base.allocator);
            defer owner_writer.deinit();
            try owner_writer.writeInt64(1, @intCast(owner.shard));
            try owner_writer.writeInt64(2, @intCast(owner.realm));
            try owner_writer.writeInt64(3, @intCast(owner.account));
            const owner_bytes = try owner_writer.toOwnedSlice();
            defer self.base.allocator.free(owner_bytes);
            try reject_writer.writeMessage(1, owner_bytes);
        }
        
        // rejections = 2 (repeated)
        for (self.token_references.items) |reference| {
            var ref_writer = ProtoWriter.init(self.base.allocator);
            defer ref_writer.deinit();
            
            // fungibleToken = 1 (oneof)
            if (reference.token_id) |token_id| {
                var token_writer = ProtoWriter.init(self.base.allocator);
                defer token_writer.deinit();
                try token_writer.writeInt64(1, @intCast(token_id.shard));
                try token_writer.writeInt64(2, @intCast(token_id.realm));
                try token_writer.writeInt64(3, @intCast(token_id.num));
                const token_bytes = try token_writer.toOwnedSlice();
                defer self.base.allocator.free(token_bytes);
                try ref_writer.writeMessage(1, token_bytes);
            }
            
            // nft = 2 (oneof)
            if (reference.nft_id) |nft_id| {
                var nft_writer = ProtoWriter.init(self.base.allocator);
                defer nft_writer.deinit();
                
                // tokenId = 1
                var token_writer = ProtoWriter.init(self.base.allocator);
                defer token_writer.deinit();
                try token_writer.writeInt64(1, @intCast(nft_id.token_id.shard));
                try token_writer.writeInt64(2, @intCast(nft_id.token_id.realm));
                try token_writer.writeInt64(3, @intCast(nft_id.token_id.num));
                const token_bytes = try token_writer.toOwnedSlice();
                defer self.base.allocator.free(token_bytes);
                try nft_writer.writeMessage(1, token_bytes);
                
                // serialNumber = 2
                try nft_writer.writeInt64(2, nft_id.serial_number);
                
                const nft_bytes = try nft_writer.toOwnedSlice();
                defer self.base.allocator.free(nft_bytes);
                try ref_writer.writeMessage(2, nft_bytes);
            }
            
            const ref_bytes = try ref_writer.toOwnedSlice();
            defer self.base.allocator.free(ref_bytes);
            try reject_writer.writeMessage(2, ref_bytes);
        }
        
        const reject_bytes = try reject_writer.toOwnedSlice();
        defer self.base.allocator.free(reject_bytes);
        try writer.writeMessage(59, reject_bytes);
        
        return writer.toOwnedSlice();
    }
    
    fn writeCommonFields(self: *TokenRejectTransaction, writer: *ProtoWriter) !void {
        // Write standard transaction fields
        try self.base.writeCommonFields(writer);
    }
};

// Constructor function matching the pattern used by other transactions

const std = @import("std");
const AccountId = @import("../core/id.zig").AccountId;
const TokenId = @import("../core/id.zig").TokenId;
const NftId = @import("../core/id.zig").NftId;
const Client = @import("../network/client.zig").Client;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const TokenRejectTransaction = @import("../token/token_reject_transaction.zig").TokenRejectTransaction;
const TokenDissociateTransaction = @import("../token/token_dissociate.zig").TokenDissociateTransaction;
const PrivateKey = @import("../crypto/key.zig").PrivateKey;
const PublicKey = @import("../crypto/key.zig").PublicKey;

// TokenRejectFlow rejects tokens and then dissociates them from the account
pub const TokenRejectFlow = struct {
    owner_id: ?AccountId = null,
    token_ids: std.ArrayList(TokenId),
    nft_ids: std.ArrayList(NftId),
    freeze_with_client: ?*Client = null,
    sign_private_key: ?PrivateKey = null,
    sign_public_key: ?PublicKey = null,
    transaction_signer: ?TransactionSigner = null,
    allocator: std.mem.Allocator,
    
    pub const TransactionSigner = fn (message: []const u8) []const u8;
    
    pub fn init(allocator: std.mem.Allocator) TokenRejectFlow {
        return TokenRejectFlow{
            .token_ids = std.ArrayList(TokenId).init(allocator),
            .nft_ids = std.ArrayList(NftId).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *TokenRejectFlow) void {
        self.token_ids.deinit();
        self.nft_ids.deinit();
    }
    
    // Set owner ID
    pub fn setOwnerId(self: *TokenRejectFlow, owner_id: AccountId) !*TokenRejectFlow {
        self.owner_id = owner_id;
        return self;
    }
    
    // Set token IDs
    pub fn setTokenIds(self: *TokenRejectFlow, ids: []const TokenId) !*TokenRejectFlow {
        self.token_ids.clearRetainingCapacity();
        try self.token_ids.appendSlice(ids);
        return self;
    }
    
    // Add token ID
    pub fn addTokenId(self: *TokenRejectFlow, id: TokenId) !*TokenRejectFlow {
        try self.token_ids.append(id);
        return self;
    }
    
    // Set NFT IDs
    pub fn setNftIds(self: *TokenRejectFlow, ids: []const NftId) !*TokenRejectFlow {
        self.nft_ids.clearRetainingCapacity();
        try self.nft_ids.appendSlice(ids);
        return self;
    }
    
    // Add NFT ID
    pub fn addNftId(self: *TokenRejectFlow, id: NftId) !*TokenRejectFlow {
        try self.nft_ids.append(id);
        return self;
    }
    
    // Sign with private key
    pub fn sign(self: *TokenRejectFlow, private_key: PrivateKey) *TokenRejectFlow {
        self.sign_private_key = private_key;
        return self;
    }
    
    // Sign with public key and signer
    pub fn signWith(self: *TokenRejectFlow, public_key: PublicKey, signer: TransactionSigner) *TokenRejectFlow {
        self.sign_public_key = public_key;
        self.transaction_signer = signer;
        return self;
    }
    
    // Freeze with client
    pub fn freezeWith(self: *TokenRejectFlow, client: *Client) !*TokenRejectFlow {
        self.freeze_with_client = client;
        return self;
    }
    
    // Create token dissociate transaction
    fn createTokenDissociateTransaction(self: *TokenRejectFlow, _: *Client) !TokenDissociateTransaction {
        var token_dissociate = TokenDissociateTransaction.init(self.allocator);
        
        if (self.owner_id) |owner_id| {
            try token_dissociate.setAccountId(owner_id);
        }
        
        // Collect all unique token IDs from both token_ids and nft_ids
        var token_ids_set = std.AutoHashMap(TokenId, void).init(self.allocator);
        defer token_ids_set.deinit();
        
        // Add regular token IDs
        for (self.token_ids.items) |token_id| {
            try token_ids_set.put(token_id, {});
        }
        
        // Add token IDs from NFT IDs
        for (self.nft_ids.items) |nft_id| {
            try token_ids_set.put(nft_id.token_id, {});
        }
        
        // Convert set to array
        var unique_token_ids = std.ArrayList(TokenId).init(self.allocator);
        defer unique_token_ids.deinit();
        
        var iter = token_ids_set.iterator();
        while (iter.next()) |entry| {
            try unique_token_ids.append(entry.key_ptr.*);
        }
        
        if (unique_token_ids.items.len > 0) {
            try token_dissociate.setTokenIds(unique_token_ids.items);
        }
        
        // Freeze if client provided
        if (self.freeze_with_client) |freeze_client| {
            try token_dissociate.base.freezeWith(freeze_client);
        }
        
        // Sign if keys provided
        if (self.sign_private_key) |private_key| {
            try token_dissociate.base.sign(private_key);
        }
        
        if (self.sign_public_key) |public_key| {
            if (self.transaction_signer) |signer| {
                try token_dissociate.base.signWith(public_key, signer);
            }
        }
        
        return token_dissociate;
    }
    
    // Create token reject transaction
    fn createTokenRejectTransaction(self: *TokenRejectFlow, _: *Client) !TokenRejectTransaction {
        var token_reject = TokenRejectTransaction.init(self.allocator);
        
        if (self.owner_id) |owner_id| {
            try token_reject.setOwnerId(owner_id);
        }
        
        if (self.token_ids.items.len > 0) {
            try token_reject.setTokenIds(self.token_ids.items);
        }
        
        if (self.nft_ids.items.len > 0) {
            try token_reject.setNftIds(self.nft_ids.items);
        }
        
        // Freeze if client provided
        if (self.freeze_with_client) |freeze_client| {
            try token_reject.base.freezeWith(freeze_client);
        }
        
        // Sign if keys provided
        if (self.sign_private_key) |private_key| {
            try token_reject.base.sign(private_key);
        }
        
        if (self.sign_public_key) |public_key| {
            if (self.transaction_signer) |signer| {
                try token_reject.base.signWith(public_key, signer);
            }
        }
        
        return token_reject;
    }
    
    // Execute the flow
    pub fn execute(self: *TokenRejectFlow, client: *Client) !TransactionResponse {
        // First reject the tokens
        var token_reject = try self.createTokenRejectTransaction(client);
        defer token_reject.deinit();
        
        const token_reject_response = try token_reject.execute(client);
        _ = try token_reject_response.getReceipt(client);
        
        // Then dissociate the tokens
        var token_dissociate = try self.createTokenDissociateTransaction(client);
        defer token_dissociate.deinit();
        
        const token_dissociate_response = try token_dissociate.execute(client);
        _ = try token_dissociate_response.getReceipt(client);
        
        // Return the reject response as the primary response
        return token_reject_response;
    }
};

// Creates a new token rejection flow
pub fn tokenRejectFlow(allocator: std.mem.Allocator) TokenRejectFlow {
    return TokenRejectFlow.init(allocator);
}
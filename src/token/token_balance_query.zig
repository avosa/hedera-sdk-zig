const std = @import("std");
const Query = @import("../query/query.zig").Query;
const QueryResponse = @import("../query/query.zig").QueryResponse;
const AccountId = @import("../core/id.zig").AccountId;
const TokenId = @import("../core/id.zig").TokenId;
const Hbar = @import("../core/hbar.zig").Hbar;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;

// TokenBalance represents the balance of a specific token for an account
pub const TokenBalance = struct {
    token_id: TokenId,
    balance: u64,
    decimals: u32,
    
    pub fn init(token_id: TokenId, balance: u64, decimals: u32) TokenBalance {
        return TokenBalance{
            .token_id = token_id,
            .balance = balance,
            .decimals = decimals,
        };
    }
};

// TokenBalanceMap holds multiple token balances
pub const TokenBalanceMap = struct {
    balances: std.AutoHashMap(TokenId, u64),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) TokenBalanceMap {
        return TokenBalanceMap{
            .balances = std.AutoHashMap(TokenId, u64).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *TokenBalanceMap) void {
        self.balances.deinit();
    }
    
    pub fn get(self: *const TokenBalanceMap, token_id: TokenId) ?u64 {
        return self.balances.get(token_id);
    }
    
    pub fn put(self: *TokenBalanceMap, token_id: TokenId, balance: u64) !void {
        try self.balances.put(token_id, balance);
    }
};

// TokenBalanceQuery retrieves the balance of a specific token for an account
pub const TokenBalanceQuery = struct {
    base: Query,
    account_id: ?AccountId,
    token_id: ?TokenId,
    
    pub fn init(allocator: std.mem.Allocator) TokenBalanceQuery {
        return TokenBalanceQuery{
            .base = Query.init(allocator),
            .account_id = null,
            .token_id = null,
        };
    }
    
    pub fn deinit(self: *TokenBalanceQuery) void {
        self.base.deinit();
    }
    
    // Set the account ID to query
    pub fn setAccountId(self: *TokenBalanceQuery, account_id: AccountId) !*TokenBalanceQuery {
        self.account_id = account_id;
        return self;
    }
    
    // Set the token ID to query
    pub fn setTokenId(self: *TokenBalanceQuery, token_id: TokenId) !*TokenBalanceQuery {
        self.token_id = token_id;
        return self;
    }
    
    // Execute the query
    pub fn execute(self: *TokenBalanceQuery, client: *Client) !TokenBalance {
        if (self.account_id == null) {
            return error.AccountIdRequired;
        }
        if (self.token_id == null) {
            return error.TokenIdRequired;
        }
        
        const response = try self.base.execute(client);
        return try self.parseResponse(response);
    }
    
    // Get cost of the query
    pub fn getCost(self: *TokenBalanceQuery, client: *Client) !Hbar {
        return try self.base.getCost(client);
    }
    
    // Build the query
    pub fn buildQuery(self: *TokenBalanceQuery) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // tokenGetBalance = 50 (hypothetical field number)
        var balance_writer = ProtoWriter.init(self.base.allocator);
        defer balance_writer.deinit();
        
        // accountID = 1
        if (self.account_id) |id| {
            var id_writer = ProtoWriter.init(self.base.allocator);
            defer id_writer.deinit();
            try id_writer.writeInt64(1, @intCast(id.shard));
            try id_writer.writeInt64(2, @intCast(id.realm));
            try id_writer.writeInt64(3, @intCast(id.account));
            const id_bytes = try id_writer.toOwnedSlice();
            defer self.base.allocator.free(id_bytes);
            try balance_writer.writeMessage(1, id_bytes);
        }
        
        // tokenID = 2
        if (self.token_id) |id| {
            var id_writer = ProtoWriter.init(self.base.allocator);
            defer id_writer.deinit();
            try id_writer.writeInt64(1, @intCast(id.shard));
            try id_writer.writeInt64(2, @intCast(id.realm));
            try id_writer.writeInt64(3, @intCast(id.num));
            const id_bytes = try id_writer.toOwnedSlice();
            defer self.base.allocator.free(id_bytes);
            try balance_writer.writeMessage(2, id_bytes);
        }
        
        const balance_bytes = try balance_writer.toOwnedSlice();
        defer self.base.allocator.free(balance_bytes);
        try writer.writeMessage(50, balance_bytes);
        
        return writer.toOwnedSlice();
    }
    
    // Parse response
    fn parseResponse(self: *TokenBalanceQuery, response: QueryResponse) !TokenBalance {
        _ = response;
        
        // Return a default balance now
        return TokenBalance.init(
            self.token_id orelse TokenId.init(0, 0, 0),
            0,
            0
        );
    }
};

// Factory function for creating a new TokenBalanceQuery

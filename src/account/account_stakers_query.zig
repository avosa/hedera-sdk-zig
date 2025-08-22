const std = @import("std");
const Query = @import("../query/query.zig").Query;
const QueryResponse = @import("../query/query.zig").QueryResponse;
const AccountId = @import("../core/id.zig").AccountId;
const Hbar = @import("../core/hbar.zig").Hbar;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;

// ProxyStaker information
pub const ProxyStaker = struct {
    account_id: AccountId,
    amount: i64,
};

// AccountStakers response
pub const AccountStakers = struct {
    account_id: AccountId,
    stakers: std.ArrayList(ProxyStaker),
    
    pub fn init(allocator: std.mem.Allocator) AccountStakers {
        return AccountStakers{
            .account_id = AccountId.init(0, 0, 0),
            .stakers = std.ArrayList(ProxyStaker).init(allocator),
        };
    }
    
    pub fn deinit(self: *AccountStakers) void {
        self.stakers.deinit();
    }
};

// AccountStakersQuery retrieves all stakers for an account (deprecated in newer versions)
pub const AccountStakersQuery = struct {
    base: Query,
    account_id: ?AccountId,
    
    pub fn init(allocator: std.mem.Allocator) AccountStakersQuery {
        return AccountStakersQuery{
            .base = Query.init(allocator),
            .account_id = null,
        };
    }
    
    pub fn deinit(self: *AccountStakersQuery) void {
        self.base.deinit();
    }
    
    // Set the account ID to query
    pub fn setAccountId(self: *AccountStakersQuery, account_id: AccountId) !void {
        self.account_id = account_id;
    }
    
    // Execute the query
    pub fn execute(self: *AccountStakersQuery, client: *Client) !AccountStakers {
        if (self.account_id == null) {
            return error.AccountIdRequired;
        }
        
        const response = try self.base.execute(client);
        return try self.parseResponse(response);
    }
    
    // Get cost of the query
    pub fn getCost(self: *AccountStakersQuery, client: *Client) !Hbar {
        return try self.base.getCost(client);
    }
    
    // Build the query
    pub fn buildQuery(self: *AccountStakersQuery) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // cryptoGetProxyStakers = 14
        var stakers_writer = ProtoWriter.init(self.base.allocator);
        defer stakers_writer.deinit();
        
        // accountID = 1
        if (self.account_id) |id| {
            var id_writer = ProtoWriter.init(self.base.allocator);
            defer id_writer.deinit();
            try id_writer.writeInt64(1, @intCast(id.entity.shard));
            try id_writer.writeInt64(2, @intCast(id.entity.realm));
            try id_writer.writeInt64(3, @intCast(id.entity.num));
            const id_bytes = try id_writer.toOwnedSlice();
            defer self.base.allocator.free(id_bytes);
            try stakers_writer.writeMessage(1, id_bytes);
        }
        
        const stakers_bytes = try stakers_writer.toOwnedSlice();
        defer self.base.allocator.free(stakers_bytes);
        try writer.writeMessage(14, stakers_bytes);
        
        return writer.toOwnedSlice();
    }
    
    // Parse response
    fn parseResponse(self: *AccountStakersQuery, response: QueryResponse) !AccountStakers {
        _ = response;
        var result = AccountStakers.init(self.base.allocator);
        
        if (self.account_id) |id| {
            result.account_id = id;
        }
        
        // Note: This query is deprecated and may not return actual staker data
        return result;
    }
};
const std = @import("std");
const Query = @import("../query/query.zig").Query;
const Client = @import("../network/client.zig").Client;
const TokenId = @import("../core/id.zig").TokenId;
const AccountId = @import("../core/id.zig").AccountId;
const NftId = @import("../core/id.zig").NftId;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;
const Timestamp = @import("../core/timestamp.zig").Timestamp;

// TokenNftInfosQuery gets information for multiple NFTs
pub const TokenNftInfosQuery = struct {
    base: Query,
    token_id: ?TokenId = null,
    start_serial: ?i64 = null,
    end_serial: ?i64 = null,
    
    pub fn init(allocator: std.mem.Allocator) TokenNftInfosQuery {
        return TokenNftInfosQuery{
            .base = Query.init(allocator),
        };
    }
    
    pub fn deinit(self: *TokenNftInfosQuery) void {
        self.base.deinit();
    }
    
    // Set token ID to query NFTs for
    pub fn setTokenId(self: *TokenNftInfosQuery, token_id: TokenId) *TokenNftInfosQuery {
        self.token_id = token_id;
        return self;
    }
    
    // Set start serial number (inclusive)
    pub fn setStart(self: *TokenNftInfosQuery, start: i64) *TokenNftInfosQuery {
        self.start_serial = start;
        return self;
    }
    
    // Set end serial number (inclusive)  
    pub fn setEnd(self: *TokenNftInfosQuery, end: i64) *TokenNftInfosQuery {
        self.end_serial = end;
        return self;
    }
    
    // Execute the query
    pub fn execute(self: *TokenNftInfosQuery, client: *Client) ![]TokenNftInfo {
        const response = try self.base.execute(client);
        defer self.base.allocator.free(response);
        
        return try self.parseResponse(response);
    }
    
    // Build query protobuf
    pub fn buildQuery(self: *TokenNftInfosQuery) ![]u8 {
        if (self.token_id == null) return error.TokenIdRequired;
        
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // tokenGetNftInfos = 72 (oneof query)
        var query_writer = ProtoWriter.init(self.base.allocator);
        defer query_writer.deinit();
        
        // tokenID = 1
        var token_writer = ProtoWriter.init(self.base.allocator);
        defer token_writer.deinit();
        try token_writer.writeInt64(1, @intCast(self.token_id.?.shard));
        try token_writer.writeInt64(2, @intCast(self.token_id.?.realm));
        try token_writer.writeInt64(3, @intCast(self.token_id.?.num));
        const token_bytes = try token_writer.toOwnedSlice();
        defer self.base.allocator.free(token_bytes);
        try query_writer.writeMessage(1, token_bytes);
        
        // start = 2 (optional)
        if (self.start_serial) |start| {
            try query_writer.writeInt64(2, start);
            return self;
        }
        
        // end = 3 (optional)
        if (self.end_serial) |end| {
            try query_writer.writeInt64(3, end);
        }
        
        const query_bytes = try query_writer.toOwnedSlice();
        defer self.base.allocator.free(query_bytes);
        try writer.writeMessage(72, query_bytes);
        
        return writer.toOwnedSlice();
    }
    
    // Parse response
    fn parseResponse(self: *TokenNftInfosQuery, data: []const u8) ![]TokenNftInfo {
        var reader = ProtoReader.init(data);
        var nfts = std.ArrayList(TokenNftInfo).init(self.base.allocator);
        errdefer nfts.deinit();
        
        while (try reader.next()) |field| {
            switch (field.number) {
                1 => {
                    // nfts (repeated)
                    const nft_info = try parseNftInfo(field.data, self.base.allocator);
                    try nfts.append(nft_info);
                },
                else => {},
            }
        }
        
        return nfts.toOwnedSlice();
    }
    
    fn parseNftInfo(data: []const u8, allocator: std.mem.Allocator) !TokenNftInfo {
        var reader = ProtoReader.init(data);
        var nft_info = TokenNftInfo{
            .nft_id = NftId.init(TokenId.init(0, 0, 0), 0),
            .account_id = null,
            .creation_time = null,
            .metadata = &[_]u8{},
            .ledger_id = null,
            .spender_id = null,
        };
        
        while (try reader.next()) |field| {
            switch (field.number) {
                1 => {
                    // nftID
                    nft_info.nft_id = try parseNftId(field.data);
                },
                2 => {
                    // accountID  
                    nft_info.account_id = try parseAccountId(field.data);
                },
                3 => {
                    // creationTime
                    nft_info.creation_time = try parseTimestamp(field.data);
                },
                4 => {
                    // metadata
                    nft_info.metadata = try allocator.dupe(u8, field.data);
                },
                5 => {
                    // ledgerID
                    nft_info.ledger_id = try allocator.dupe(u8, field.data);
                },
                6 => {
                    // spenderID
                    nft_info.spender_id = try parseAccountId(field.data);
                },
                else => {},
            }
        }
        
        return nft_info;
    }
    
    fn parseNftId(data: []const u8) !NftId {
        var reader = ProtoReader.init(data);
        var token_id = TokenId.init(0, 0, 0);
        var serial: i64 = 0;
        
        while (try reader.next()) |field| {
            switch (field.number) {
                1 => {
                    // tokenId
                    token_id = try parseTokenId(field.data);
                },
                2 => {
                    // serialNumber
                    serial = try reader.readInt64(field.data);
                },
                else => {},
            }
        }
        
        return NftId.init(token_id, serial);
    }
    
    fn parseTokenId(data: []const u8) !TokenId {
        var reader = ProtoReader.init(data);
        var shard: i64 = 0;
        var realm: i64 = 0; 
        var num: i64 = 0;
        
        while (try reader.next()) |field| {
            switch (field.number) {
                1 => shard = try reader.readInt64(field.data),
                2 => realm = try reader.readInt64(field.data),
                3 => num = try reader.readInt64(field.data),
                else => {},
            }
        }
        
        return TokenId{
            .entity = .{
                .shard = shard,
                .realm = realm,
                .num = num,
            },
        };
    }
    
    fn parseAccountId(data: []const u8) !AccountId {
        var reader = ProtoReader.init(data);
        var shard: i64 = 0;
        var realm: i64 = 0;
        var num: i64 = 0;
        
        while (try reader.next()) |field| {
            switch (field.number) {
                1 => shard = try reader.readInt64(field.data),
                2 => realm = try reader.readInt64(field.data), 
                3 => num = try reader.readInt64(field.data),
                else => {},
            }
        }
        
        return AccountId{
            .entity = .{
                .shard = shard,
                .realm = realm,
                .num = num,
            },
        };
    }
    
    fn parseTimestamp(data: []const u8) !Timestamp {
        var reader = ProtoReader.init(data);
        var seconds: i64 = 0;
        var nanos: i32 = 0;
        
        while (try reader.next()) |field| {
            switch (field.number) {
                1 => seconds = try reader.readInt64(field.data),
                2 => nanos = try reader.readInt32(field.data),
                else => {},
            }
        }
        
        return Timestamp{
            .seconds = seconds,
            .nanos = nanos,
        };
    }
};

// TokenGetAccountNftInfosQuery gets NFTs for a specific account
pub const TokenGetAccountNftInfosQuery = struct {
    base: Query,
    account_id: ?AccountId = null,
    start_token: ?NftId = null,
    end_token: ?NftId = null,
    
    pub fn init(allocator: std.mem.Allocator) TokenGetAccountNftInfosQuery {
        return TokenGetAccountNftInfosQuery{
            .base = Query.init(allocator),
        };
    }
    
    pub fn deinit(self: *TokenGetAccountNftInfosQuery) void {
        self.base.deinit();
    }
    
    // Set account ID to query NFTs for
    pub fn setAccountId(self: *TokenGetAccountNftInfosQuery, account_id: AccountId) *TokenGetAccountNftInfosQuery {
        self.account_id = account_id;
        return self;
    }
    
    // Set start NFT ID for pagination
    pub fn setStart(self: *TokenGetAccountNftInfosQuery, start: NftId) *TokenGetAccountNftInfosQuery {
        self.start_token = start;
        return self;
    }
    
    // Set end NFT ID for pagination
    pub fn setEnd(self: *TokenGetAccountNftInfosQuery, end: NftId) *TokenGetAccountNftInfosQuery {
        self.end_token = end;
        return self;
    }
    
    // Execute the query
    pub fn execute(self: *TokenGetAccountNftInfosQuery, client: *Client) ![]TokenNftInfo {
        const response = try self.base.execute(client);
        defer self.base.allocator.free(response);
        
        return try self.parseResponse(response);
    }
    
    // Build query protobuf
    pub fn buildQuery(self: *TokenGetAccountNftInfosQuery) ![]u8 {
        if (self.account_id == null) return error.AccountIdRequired;
        
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // tokenGetAccountNftInfos = 73 (oneof query)
        var query_writer = ProtoWriter.init(self.base.allocator);
        defer query_writer.deinit();
        
        // accountID = 1
        var account_writer = ProtoWriter.init(self.base.allocator);
        defer account_writer.deinit();
        try account_writer.writeInt64(1, @intCast(self.account_id.?.shard));
        try account_writer.writeInt64(2, @intCast(self.account_id.?.realm));
        try account_writer.writeInt64(3, @intCast(self.account_id.?.num));
        const account_bytes = try account_writer.toOwnedSlice();
        defer self.base.allocator.free(account_bytes);
        try query_writer.writeMessage(1, account_bytes);
        
        // start = 2 (optional)
        if (self.start_token) |start| {
            var start_writer = ProtoWriter.init(self.base.allocator);
            defer start_writer.deinit();
            
            // tokenId
            var token_writer = ProtoWriter.init(self.base.allocator);
            defer token_writer.deinit();
            try token_writer.writeInt64(1, @intCast(start.token_id.shard));
            try token_writer.writeInt64(2, @intCast(start.token_id.realm));
            try token_writer.writeInt64(3, @intCast(start.token_id.num));
            const token_bytes = try token_writer.toOwnedSlice();
            defer self.base.allocator.free(token_bytes);
            try start_writer.writeMessage(1, token_bytes);
            
            // serialNumber
            try start_writer.writeInt64(2, start.serial_number);
            
            const start_bytes = try start_writer.toOwnedSlice();
            defer self.base.allocator.free(start_bytes);
            try query_writer.writeMessage(2, start_bytes);
        }
        
        // end = 3 (optional)
        if (self.end_token) |end| {
            var end_writer = ProtoWriter.init(self.base.allocator);
            defer end_writer.deinit();
            
            // tokenId
            var token_writer = ProtoWriter.init(self.base.allocator);
            defer token_writer.deinit();
            try token_writer.writeInt64(1, @intCast(end.token_id.shard));
            try token_writer.writeInt64(2, @intCast(end.token_id.realm));
            try token_writer.writeInt64(3, @intCast(end.token_id.num));
            const token_bytes = try token_writer.toOwnedSlice();
            defer self.base.allocator.free(token_bytes);
            try end_writer.writeMessage(1, token_bytes);
            
            // serialNumber  
            try end_writer.writeInt64(2, end.serial_number);
            
            const end_bytes = try end_writer.toOwnedSlice();
            defer self.base.allocator.free(end_bytes);
            try query_writer.writeMessage(3, end_bytes);
        }
        
        const query_bytes = try query_writer.toOwnedSlice();
        defer self.base.allocator.free(query_bytes);
        try writer.writeMessage(73, query_bytes);
        
        return writer.toOwnedSlice();
    }
    
    // Parse response (reuse TokenNftInfosQuery parsing)
    fn parseResponse(self: *TokenGetAccountNftInfosQuery, data: []const u8) ![]TokenNftInfo {
        var reader = ProtoReader.init(data);
        var nfts = std.ArrayList(TokenNftInfo).init(self.base.allocator);
        errdefer nfts.deinit();
        
        while (try reader.next()) |field| {
            switch (field.number) {
                1 => {
                    // nfts (repeated)
                    const nft_info = try TokenNftInfosQuery.parseNftInfo(field.data, self.base.allocator);
                    try nfts.append(nft_info);
                },
                else => {},
            }
        }
        
        return nfts.toOwnedSlice();
    }
};

// NFT information structure
pub const TokenNftInfo = struct {
    nft_id: NftId,
    account_id: ?AccountId,
    creation_time: ?Timestamp,
    metadata: []const u8,
    ledger_id: ?[]const u8,
    spender_id: ?AccountId,
    
    pub fn deinit(self: *TokenNftInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.metadata);
        if (self.ledger_id) |ledger| allocator.free(ledger);
    }
};

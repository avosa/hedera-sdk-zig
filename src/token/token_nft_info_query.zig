const std = @import("std");
const NftId = @import("../core/id.zig").NftId;
const TokenId = @import("../core/id.zig").TokenId;
const AccountId = @import("../core/id.zig").AccountId;
const Timestamp = @import("../core/timestamp.zig").Timestamp;
const Query = @import("../query/query.zig").Query;
const QueryResponse = @import("../query/query.zig").QueryResponse;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;
const Hbar = @import("../core/hbar.zig").Hbar;

// TokenNftInfo contains information about a specific NFT
pub const TokenNftInfo = struct {
    nft_id: NftId,
    account_id: AccountId,
    creation_time: Timestamp,
    metadata: []const u8,
    ledger_id: []const u8,
    spender: ?AccountId,
    spender_id: ?AccountId,
    
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) TokenNftInfo {
        return TokenNftInfo{
            .nft_id = NftId.init(TokenId.init(0, 0, 0), 0),
            .account_id = AccountId.init(0, 0, 0),
            .creation_time = Timestamp{ .seconds = 0, .nanos = 0 },
            .metadata = "",
            .ledger_id = "",
            .spender = null,
            .spender_id = null,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *TokenNftInfo) void {
        if (self.metadata.len > 0) {
            self.allocator.free(self.metadata);
        }
        if (self.ledger_id.len > 0) {
            self.allocator.free(self.ledger_id);
        }
    }
};

// TokenNftInfoQuery retrieves information about a specific NFT
pub const TokenNftInfoQuery = struct {
    base: Query,
    nft_id: ?NftId,
    
    pub fn init(allocator: std.mem.Allocator) TokenNftInfoQuery {
        return TokenNftInfoQuery{
            .base = Query.init(allocator),
            .nft_id = null,
        };
    }
    
    pub fn deinit(self: *TokenNftInfoQuery) void {
        self.base.deinit();
    }
    
    // Set the NFT ID to query
    pub fn setNftId(self: *TokenNftInfoQuery, nft_id: NftId) *TokenNftInfoQuery {
        self.nft_id = nft_id;
        return self;
    }
    
    // Set the query payment amount
    pub fn setQueryPayment(self: *TokenNftInfoQuery, payment: Hbar) *TokenNftInfoQuery {
        self.base.payment_amount = payment;
        return self;
    }
    
    // Execute the query
    pub fn execute(self: *TokenNftInfoQuery, client: *Client) !TokenNftInfo {
        if (self.nft_id == null) {
            return error.NftIdRequired;
        }
        
        const response = try self.base.execute(client);
        return try self.parseResponse(response);
    }
    
    // Get cost of the query
    pub fn getCost(self: *TokenNftInfoQuery, client: *Client) !Hbar {
        self.base.response_type = .CostAnswer;
        const response = try self.base.execute(client);
        
        var reader = ProtoReader.init(response.response_bytes);
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                2 => {
                    const cost = try reader.readUint64();
                    return try Hbar.fromTinybars(@intCast(cost));
                },
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return error.CostNotFound;
    }
    
    // Build the query
    pub fn buildQuery(self: *TokenNftInfoQuery) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Query message structure
        // header = 1
        var header_writer = ProtoWriter.init(self.base.allocator);
        defer header_writer.deinit();
        
        // payment = 1
        if (self.base.payment_transaction) |payment| {
            try header_writer.writeMessage(1, payment);
        }
        
        // responseType = 2
        try header_writer.writeInt32(2, @intFromEnum(self.base.response_type));
        
        const header_bytes = try header_writer.toOwnedSlice();
        defer self.base.allocator.free(header_bytes);
        try writer.writeMessage(1, header_bytes);
        
        // tokenGetNftInfo = 19 (oneof query)
        var info_query_writer = ProtoWriter.init(self.base.allocator);
        defer info_query_writer.deinit();
        
        // nftID = 1
        if (self.nft_id) |nft| {
            var nft_writer = ProtoWriter.init(self.base.allocator);
            defer nft_writer.deinit();
            
            // tokenID = 1
            var token_writer = ProtoWriter.init(self.base.allocator);
            defer token_writer.deinit();
            try token_writer.writeInt64(1, @intCast(nft.token_id.shard));
            try token_writer.writeInt64(2, @intCast(nft.token_id.realm));
            try token_writer.writeInt64(3, @intCast(nft.token_id.num));
            const token_bytes = try token_writer.toOwnedSlice();
            defer self.base.allocator.free(token_bytes);
            try nft_writer.writeMessage(1, token_bytes);
            
            // serialNumber = 2
            try nft_writer.writeInt64(2, nft.serial_number);
            
            const nft_bytes = try nft_writer.toOwnedSlice();
            defer self.base.allocator.free(nft_bytes);
            try info_query_writer.writeMessage(1, nft_bytes);
        }
        
        const info_query_bytes = try info_query_writer.toOwnedSlice();
        defer self.base.allocator.free(info_query_bytes);
        try writer.writeMessage(19, info_query_bytes);
        
        return writer.toOwnedSlice();
    }
    
    // Parse the response
    fn parseResponse(self: *TokenNftInfoQuery, response: QueryResponse) !TokenNftInfo {
        try response.validateStatus();
        
        var reader = ProtoReader.init(response.response_bytes);
        
        var info = TokenNftInfo{
            .nft_id = NftId.init(TokenId.init(0, 0, 0), 0),
            .account_id = AccountId.init(0, 0, 0),
            .creation_time = Timestamp{ .seconds = 0, .nanos = 0 },
            .metadata = "",
            .ledger_id = "",
            .spender_id = null,
            .allocator = self.base.allocator,
        };
        
        // Parse TokenGetNftInfoResponse
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => {
                    // header
                    _ = try reader.readMessage();
                },
                2 => {
                    // nft
                    const nft_bytes = try reader.readMessage();
                    var nft_reader = ProtoReader.init(nft_bytes);
                    
                    while (nft_reader.hasMore()) {
                        const n_tag = try nft_reader.readTag();
                        
                        switch (n_tag.field_number) {
                            1 => {
                                // nftID
                                const nft_id_bytes = try nft_reader.readMessage();
                                var nft_id_reader = ProtoReader.init(nft_id_bytes);
                                
                                var token_shard: i64 = 0;
                                var token_realm: i64 = 0;
                                var token_num: i64 = 0;
                                var serial_number: i64 = 0;
                                
                                while (nft_id_reader.hasMore()) {
                                    const id_tag = try nft_id_reader.readTag();
                                    
                                    switch (id_tag.field_number) {
                                        1 => {
                                            // tokenID
                                            const token_bytes = try nft_id_reader.readMessage();
                                            var token_reader = ProtoReader.init(token_bytes);
                                            
                                            while (token_reader.hasMore()) {
                                                const t = try token_reader.readTag();
                                                switch (t.field_number) {
                                                    1 => token_shard = try token_reader.readInt64(),
                                                    2 => token_realm = try token_reader.readInt64(),
                                                    3 => token_num = try token_reader.readInt64(),
                                                    else => try token_reader.skipField(t.wire_type),
                                                }
                                            }
                                        },
                                        2 => serial_number = try nft_id_reader.readInt64(),
                                        else => try nft_id_reader.skipField(id_tag.wire_type),
                                    }
                                }
                                
                                const token_id = TokenId.init(@intCast(token_shard), @intCast(token_realm), @intCast(token_num));
                                info.nft_id = NftId.init(token_id, serial_number);
                            },
                            2 => {
                                // accountID
                                const account_bytes = try nft_reader.readMessage();
                                var account_reader = ProtoReader.init(account_bytes);
                                
                                var shard: i64 = 0;
                                var realm: i64 = 0;
                                var num: i64 = 0;
                                
                                while (account_reader.hasMore()) {
                                    const a = try account_reader.readTag();
                                    switch (a.field_number) {
                                        1 => shard = try account_reader.readInt64(),
                                        2 => realm = try account_reader.readInt64(),
                                        3 => num = try account_reader.readInt64(),
                                        else => try account_reader.skipField(a.wire_type),
                                    }
                                }
                                
                                info.account_id = AccountId.init(@intCast(shard), @intCast(realm), @intCast(num));
                            },
                            3 => {
                                // creationTime
                                const time_bytes = try nft_reader.readMessage();
                                var time_reader = ProtoReader.init(time_bytes);
                                
                                while (time_reader.hasMore()) {
                                    const t = try time_reader.readTag();
                                    switch (t.field_number) {
                                        1 => info.creation_time.seconds = try time_reader.readInt64(),
                                        2 => info.creation_time.nanos = try time_reader.readInt32(),
                                        else => try time_reader.skipField(t.wire_type),
                                    }
                                }
                            },
                            4 => {
                                // metadata
                                const metadata_bytes = try nft_reader.readBytes();
                                info.metadata = try self.base.allocator.dupe(u8, metadata_bytes);
                            },
                            5 => {
                                // ledgerId
                                const ledger_bytes = try nft_reader.readBytes();
                                info.ledger_id = try self.base.allocator.dupe(u8, ledger_bytes);
                            },
                            6 => {
                                // spenderId
                                const spender_bytes = try nft_reader.readMessage();
                                var spender_reader = ProtoReader.init(spender_bytes);
                                
                                var shard: i64 = 0;
                                var realm: i64 = 0;
                                var num: i64 = 0;
                                
                                while (spender_reader.hasMore()) {
                                    const s = try spender_reader.readTag();
                                    switch (s.field_number) {
                                        1 => shard = try spender_reader.readInt64(),
                                        2 => realm = try spender_reader.readInt64(),
                                        3 => num = try spender_reader.readInt64(),
                                        else => try spender_reader.skipField(s.wire_type),
                                    }
                                }
                                
                                if (num != 0) {
                                    info.spender_id = AccountId.init(@intCast(shard), @intCast(realm), @intCast(num));
                                }
                            },
                            else => try nft_reader.skipField(n_tag.wire_type),
                        }
                    }
                },
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return info;
    }
};

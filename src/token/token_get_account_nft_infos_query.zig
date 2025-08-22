const std = @import("std");
const Query = @import("../query/query.zig").Query;
const AccountId = @import("../core/id.zig").AccountId;
const TokenId = @import("../core/id.zig").TokenId;
const NftId = @import("../core/id.zig").NftId;
const Client = @import("../network/client.zig").Client;
const Status = @import("../core/status.zig").Status;
const Timestamp = @import("../core/timestamp.zig").Timestamp;
const ProtoWriter = @import("../protobuf/writer.zig").ProtoWriter;
const ProtoReader = @import("../protobuf/reader.zig").ProtoReader;

/// Information about an NFT
pub const NftInfo = struct {
    nft_id: NftId,
    account_id: AccountId,
    creation_time: Timestamp,
    metadata: []const u8,
    ledger_id: []const u8,
    spender_id: ?AccountId,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *NftInfo) void {
        if (self.metadata.len > 0) {
            self.allocator.free(self.metadata);
        }
        if (self.ledger_id.len > 0) {
            self.allocator.free(self.ledger_id);
        }
    }
};

/// Query for all NFTs owned by an account
pub const TokenGetAccountNftInfosQuery = struct {
    query: Query,
    account_id: ?AccountId,
    start: i64,
    end: i64,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .query = Query.init(allocator, .TokenGetAccountNftInfos),
            .account_id = null,
            .start = 0,
            .end = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.query.deinit();
    }

    /// Set the account to query NFTs for
    pub fn setAccountId(self: *Self, account_id: AccountId) *Self {
        self.account_id = account_id;
        return self;
    }

    /// Get the account ID
    pub fn getAccountId(self: *const Self) ?AccountId {
        return self.account_id;
    }

    /// Set the start serial number (inclusive)
    pub fn setStart(self: *Self, start: i64) *Self {
        self.start = start;
        return self;
    }

    /// Get the start serial number
    pub fn getStart(self: *const Self) i64 {
        return self.start;
    }

    /// Set the end serial number (inclusive)
    pub fn setEnd(self: *Self, end: i64) *Self {
        self.end = end;
        return self;
    }

    /// Get the end serial number
    pub fn getEnd(self: *const Self) i64 {
        return self.end;
    }

    /// Set the maximum number of NFTs to return
    pub fn setMaxQueryPayment(self: *Self, max_payment: i64) *Self {
        self.query.setMaxQueryPayment(max_payment);
        return self;
    }

    /// Set the query payment
    pub fn setQueryPayment(self: *Self, payment: i64) *Self {
        self.query.setQueryPayment(payment);
        return self;
    }

    /// Set node account IDs
    pub fn setNodeAccountIds(self: *Self, node_account_ids: []const AccountId) !*Self {
        try self.query.setNodeAccountIds(node_account_ids);
        return self;
    }

    /// Execute the query
    pub fn execute(self: *Self, client: *Client) ![]NftInfo {
        try self.validate();
        
        const response = try self.query.execute(client);
        defer self.query.allocator.free(response);
        
        return self.parseResponse(response);
    }

    /// Execute with specific payment
    pub fn executeWithPayment(self: *Self, client: *Client, payment: i64) ![]NftInfo {
        self.setQueryPayment(payment);
        return self.execute(client);
    }

    /// Get the cost of this query
    pub fn getCost(self: *Self, client: *Client) !i64 {
        try self.validate();
        return self.query.getCost(client);
    }

    fn validate(self: *const Self) !void {
        if (self.account_id == null) {
            return error.AccountIdRequired;
        }
        if (self.end < self.start and self.end != 0) {
            return error.InvalidRange;
        }
    }

    fn buildQuery(self: *const Self) ![]u8 {
        var writer = ProtoWriter.init(self.query.allocator);
        defer writer.deinit();

        // header
        const header = try self.query.buildHeader();
        defer self.query.allocator.free(header);
        try writer.writeBytes(1, header);

        // account_id
        if (self.account_id) |account| {
            try writer.writeMessage(2, struct {
                pub fn write(w: *ProtoWriter) !void {
                    try account.toProtobuf(w);
                }
            });
        }

        // start
        if (self.start > 0) {
            try writer.writeInt64(3, self.start);
        }

        // end
        if (self.end > 0) {
            try writer.writeInt64(4, self.end);
        }

        return writer.finalize();
    }

    fn parseResponse(self: *Self, response: []const u8) ![]NftInfo {
        var reader = ProtoReader.init(response);
        var nfts = std.ArrayList(NftInfo).init(self.query.allocator);
        defer nfts.deinit();

        while (try reader.next()) |field| {
            switch (field.number) {
                1 => {
                    // header
                    _ = try reader.skip();
                },
                2 => {
                    // nfts
                    const nft_bytes = try reader.getBytes(self.query.allocator);
                    defer self.query.allocator.free(nft_bytes);
                    
                    const nft_info = try self.parseNftInfo(nft_bytes);
                    try nfts.append(nft_info);
                },
                else => try reader.skip(),
            }
        }

        return nfts.toOwnedSlice();
    }

    fn parseNftInfo(self: *Self, bytes: []const u8) !NftInfo {
        var reader = ProtoReader.init(bytes);
        var info = NftInfo{
            .nft_id = NftId{
                .token_id = TokenId.init(0, 0, 0),
                .serial_number = 0,
            },
            .account_id = AccountId.init(0, 0, 0),
            .creation_time = Timestamp.fromSeconds(0),
            .metadata = &[_]u8{},
            .ledger_id = &[_]u8{},
            .spender_id = null,
            .allocator = self.query.allocator,
        };

        while (try reader.next()) |field| {
            switch (field.number) {
                1 => {
                    // nft_id
                    const nft_id_bytes = try reader.getBytes(self.query.allocator);
                    defer self.query.allocator.free(nft_id_bytes);
                    info.nft_id = try NftId.fromProtobuf(nft_id_bytes);
                },
                2 => {
                    // account_id
                    const account_bytes = try reader.getBytes(self.query.allocator);
                    defer self.query.allocator.free(account_bytes);
                    info.account_id = try AccountId.fromProtobuf(account_bytes);
                },
                3 => {
                    // creation_time
                    const time_bytes = try reader.getBytes(self.query.allocator);
                    defer self.query.allocator.free(time_bytes);
                    info.creation_time = try Timestamp.fromProtobuf(time_bytes);
                },
                4 => {
                    // metadata
                    info.metadata = try reader.getBytes(self.query.allocator);
                },
                5 => {
                    // ledger_id
                    info.ledger_id = try reader.getString(self.query.allocator);
                },
                6 => {
                    // spender_id
                    const spender_bytes = try reader.getBytes(self.query.allocator);
                    defer self.query.allocator.free(spender_bytes);
                    info.spender_id = try AccountId.fromProtobuf(spender_bytes);
                },
                else => try reader.skip(),
            }
        }

        return info;
    }

    /// Get string representation
    pub fn toString(self: *const Self, allocator: std.mem.Allocator) ![]u8 {
        var list = std.ArrayList(u8).init(allocator);
        errdefer list.deinit();

        try list.appendSlice("TokenGetAccountNftInfosQuery{");
        
        if (self.account_id) |account| {
            try list.appendSlice("accountId=");
            const account_str = try account.toString(allocator);
            defer allocator.free(account_str);
            try list.appendSlice(account_str);
        }
        
        if (self.start > 0) {
            try std.fmt.format(list.writer(), ", start={}", .{self.start});
        }
        
        if (self.end > 0) {
            try std.fmt.format(list.writer(), ", end={}", .{self.end});
        }
        
        try list.append('}');
        
        return list.toOwnedSlice();
    }
};

test "TokenGetAccountNftInfosQuery initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var query = TokenGetAccountNftInfosQuery.init(allocator);
    defer query.deinit();

    try testing.expect(query.account_id == null);
    try testing.expectEqual(@as(i64, 0), query.start);
    try testing.expectEqual(@as(i64, 0), query.end);
}

test "TokenGetAccountNftInfosQuery setters" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var query = TokenGetAccountNftInfosQuery.init(allocator);
    defer query.deinit();

    const account = AccountId.init(0, 0, 100);
    _ = query.setAccountId(account);
    _ = query.setStart(1);
    _ = query.setEnd(100);

    try testing.expect(query.getAccountId().?.equals(account));
    try testing.expectEqual(@as(i64, 1), query.getStart());
    try testing.expectEqual(@as(i64, 100), query.getEnd());
}

test "TokenGetAccountNftInfosQuery validation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var query = TokenGetAccountNftInfosQuery.init(allocator);
    defer query.deinit();

    // Should fail without account ID
    try testing.expectError(error.AccountIdRequired, query.validate());

    _ = query.setAccountId(AccountId.init(0, 0, 100));
    try query.validate();

    // Invalid range
    _ = query.setStart(100);
    _ = query.setEnd(50);
    try testing.expectError(error.InvalidRange, query.validate());
}
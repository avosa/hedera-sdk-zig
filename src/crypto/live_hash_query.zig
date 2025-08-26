const std = @import("std");
const errors = @import("../core/errors.zig");
const HederaError = errors.HederaError;
const Query = @import("../query/query.zig").Query;
const Client = @import("../network/client.zig").Client;
const AccountId = @import("../core/id.zig").AccountId;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;
const LiveHash = @import("live_hash.zig").LiveHash;

// LiveHashQuery gets a live hash from the network
pub const LiveHashQuery = struct {
    base: Query,
    account_id: ?AccountId = null,
    hash: ?[]const u8 = null,
    
    pub fn init(allocator: std.mem.Allocator) LiveHashQuery {
        return LiveHashQuery{
            .base = Query.init(allocator),
        };
    }
    
    pub fn deinit(self: *LiveHashQuery) void {
        if (self.hash) |hash| {
            self.base.allocator.free(hash);
        }
        self.base.deinit();
    }
    
    // Set the account ID that owns the live hash
    pub fn setAccountId(self: *LiveHashQuery, account_id: AccountId) !*LiveHashQuery {
        self.account_id = account_id;
        return self;
    }
    
    // Set the hash to query for
    pub fn setHash(self: *LiveHashQuery, hash: []const u8) !*LiveHashQuery {
        if (self.hash) |old_hash| {
            self.base.allocator.free(old_hash);
            return self;
        }
        self.hash = try self.base.allocator.dupe(u8, hash);
        return self;
    }
    
    // Execute the query
    pub fn execute(self: *LiveHashQuery, client: *Client) !LiveHash {
        const response = try self.base.execute(client);
        defer self.base.allocator.free(response);
        
        return try self.parseResponse(response);
    }
    
    // Build the query protobuf
    pub fn buildQuery(self: *LiveHashQuery) ![]u8 {
        if (self.account_id == null) return error.AccountIdRequired;
        if (self.hash == null) return error.HashRequired;
        
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // cryptoGetLiveHash = 51 (oneof query)
        var query_writer = ProtoWriter.init(self.base.allocator);
        defer query_writer.deinit();
        
        // accountID = 1
        var account_writer = ProtoWriter.init(self.base.allocator);
        defer account_writer.deinit();
        try account_writer.writeInt64(1, @intCast(self.account_id.?.shard));
        try account_writer.writeInt64(2, @intCast(self.account_id.?.realm));
        try account_writer.writeInt64(3, @intCast(self.account_id.?.account));
        const account_bytes = try account_writer.toOwnedSlice();
        defer self.base.allocator.free(account_bytes);
        try query_writer.writeMessage(1, account_bytes);
        
        // hash = 2
        try query_writer.writeBytes(2, self.hash.?);
        
        const query_bytes = try query_writer.toOwnedSlice();
        defer self.base.allocator.free(query_bytes);
        try writer.writeMessage(51, query_bytes);
        
        return writer.toOwnedSlice();
    }
    
    // Parse the response
    fn parseResponse(self: *LiveHashQuery, data: []const u8) !LiveHash {
        var reader = ProtoReader.init(data);
        
        while (try reader.next()) |field| {
            switch (field.number) {
                1 => {
                    // liveHash
                    return try parseLiveHashFromBytes(field.data, self.base.allocator);
                },
                else => {},
            }
        }
        
        return HederaError.InvalidProtobuf;
    }
    
    fn parseLiveHashFromBytes(data: []const u8, allocator: std.mem.Allocator) !LiveHash {
        var reader = ProtoReader.init(data);
        var live_hash = LiveHash{
            .account_id = AccountId.init(0, 0, 0),
            .hash = &[_]u8{},
            .keys = std.ArrayList(@import("key.zig").Key).init(allocator),
            .duration = null,
        };
        
        while (try reader.next()) |field| {
            switch (field.number) {
                1 => {
                    // accountId
                    live_hash.account_id = try parseAccountId(field.data);
                },
                2 => {
                    // hash
                    live_hash.hash = try allocator.dupe(u8, field.data);
                },
                3 => {
                    // keys - KeyList
                    const key_list = try parseKeyList(field.data, allocator);
                    live_hash.keys = key_list;
                },
                4 => {
                    // duration
                    var duration_reader = ProtoReader.init(field.data);
                    while (try duration_reader.next()) |duration_field| {
                        if (duration_field.number == 1) {
                            live_hash.duration = @import("../core/duration.zig").Duration{
                                .seconds = try duration_reader.readInt64(duration_field.data),
                            };
                        }
                    }
                },
                else => {},
            }
        }
        
        return live_hash;
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
            .shard = shard,
            .realm = realm,
            .account = num,
        };
    }
    
    fn parseKeyList(data: []const u8, allocator: std.mem.Allocator) !std.ArrayList(@import("key.zig").Key) {
        var reader = ProtoReader.init(data);
        var keys = std.ArrayList(@import("key.zig").Key).init(allocator);
        
        while (try reader.next()) |field| {
            switch (field.number) {
                1 => {
                    // keys (repeated)
                    const key = try parseKey(field.data, allocator);
                    try keys.append(key);
                },
                else => {},
            }
        }
        
        return keys;
    }
    
    fn parseKey(data: []const u8, allocator: std.mem.Allocator) !@import("key.zig").Key {
        const Key = @import("key.zig").Key;
        
        // Simple parsing - in full implementation would handle all key types
        if (data.len >= 32) {
            // Assume Ed25519 key
            const Ed25519PublicKey = @import("key.zig").Ed25519PublicKey;
            var key_bytes: [32]u8 = undefined;
            @memcpy(&key_bytes, data[0..32]);
            return Key{ .ed25519 = Ed25519PublicKey{ .bytes = key_bytes } };
        }
        
        _ = allocator; // Key parsing doesn't need allocator for basic types
        return error.InvalidKeyFormat;
    }
};

// Factory function for creating a new LiveHashQuery

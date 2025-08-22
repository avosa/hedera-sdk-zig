const std = @import("std");
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const AccountId = @import("../core/id.zig").AccountId;
const Duration = @import("../core/duration.zig").Duration;
const Key = @import("key.zig").Key;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;

// LiveHash represents a hash of some content with associated metadata
pub const LiveHash = struct {
    account_id: AccountId,
    hash: []const u8,
    keys: ?Key = null,
    duration: ?Duration = null,
};

// LiveHashAddTransaction adds a live hash to an account
pub const LiveHashAddTransaction = struct {
    base: Transaction,
    live_hash: ?LiveHash = null,
    account_id: ?AccountId = null,
    hash: []const u8, // Direct access to hash for Go SDK compatibility
    duration: Duration, // Direct access to duration for Go SDK compatibility
    keys: std.ArrayList(Key), // Direct access to keys list
    
    pub fn init(allocator: std.mem.Allocator) LiveHashAddTransaction {
        return LiveHashAddTransaction{
            .base = Transaction.init(allocator),
            .account_id = null,
            .hash = "",
            .duration = Duration.fromDays(30), // Default 30 days
            .keys = std.ArrayList(Key).init(allocator),
        };
    }
    
    pub fn deinit(self: *LiveHashAddTransaction) void {
        self.base.deinit();
        self.keys.deinit();
        if (self.live_hash) |hash| {
            self.base.allocator.free(hash.hash);
        }
    }
    
    // Set the account ID
    pub fn setAccountId(self: *LiveHashAddTransaction, account_id: AccountId) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.account_id = account_id;
        if (self.live_hash) |*hash| {
            hash.account_id = account_id;
        }
    }
    
    // Set the live hash
    pub fn setLiveHash(self: *LiveHashAddTransaction, live_hash: LiveHash) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        
        // Copy the hash data
        const hash_copy = try self.base.allocator.dupe(u8, live_hash.hash);
        
        // Free old hash if exists
        if (self.live_hash) |old| {
            self.base.allocator.free(old.hash);
        }
        
        self.live_hash = LiveHash{
            .account_id = live_hash.account_id,
            .hash = hash_copy,
            .keys = live_hash.keys,
            .duration = live_hash.duration,
        };
        self.account_id = live_hash.account_id;
        self.hash = hash_copy; // Update direct hash field
    }
    
    
    // Set the hash
    pub fn setHash(self: *LiveHashAddTransaction, hash: []const u8) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        
        const hash_copy = try self.base.allocator.dupe(u8, hash);
        
        // Update direct hash field
        self.hash = hash_copy;
        
        if (self.live_hash) |*live| {
            if (live.hash.len > 0) {
                self.base.allocator.free(live.hash);
            }
            live.hash = hash_copy;
        } else {
            self.live_hash = LiveHash{
                .account_id = try AccountId.fromString(self.base.allocator, "0.0.0"),
                .hash = hash_copy,
            };
        }
    }
    
    // Set the keys
    pub fn setKeys(self: *LiveHashAddTransaction, keys: Key) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        if (self.live_hash) |*live| {
            live.keys = keys;
        } else {
            self.live_hash = LiveHash{
                .account_id = try AccountId.fromString(self.base.allocator, "0.0.0"),
                .hash = &[_]u8{},
                .keys = keys,
            };
        }
    }
    
    // Add a key to the keys list
    pub fn addKey(self: *LiveHashAddTransaction, key: Key) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        try self.keys.append(key);
    }
    
    // Set the duration
    pub fn setDuration(self: *LiveHashAddTransaction, duration: Duration) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        if (self.live_hash) |*live| {
            live.duration = duration;
        } else {
            self.live_hash = LiveHash{
                .account_id = try AccountId.fromString(self.base.allocator, "0.0.0"),
                .hash = &[_]u8{},
                .duration = duration,
            };
        }
    }
    
    // Execute the transaction
    pub fn execute(self: *LiveHashAddTransaction, client: *Client) !TransactionResponse {
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *LiveHashAddTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Write common transaction fields
        try self.writeCommonFields(&writer);
        
        // cryptoAddLiveHash = 25 (oneof data)
        var hash_writer = ProtoWriter.init(self.base.allocator);
        defer hash_writer.deinit();
        
        if (self.live_hash) |live_hash| {
            // liveHash = 1
            var live_writer = ProtoWriter.init(self.base.allocator);
            defer live_writer.deinit();
            
            // accountId = 1
            var account_writer = ProtoWriter.init(self.base.allocator);
            defer account_writer.deinit();
            try account_writer.writeInt64(1, @intCast(live_hash.account_id.entity.shard));
            try account_writer.writeInt64(2, @intCast(live_hash.account_id.entity.realm));
            try account_writer.writeInt64(3, @intCast(live_hash.account_id.entity.num));
            const account_bytes = try account_writer.toOwnedSlice();
            defer self.base.allocator.free(account_bytes);
            try live_writer.writeMessage(1, account_bytes);
            
            // hash = 2
            try live_writer.writeBytes(2, live_hash.hash);
            
            // keys = 3
            if (live_hash.keys) |keys| {
                const keys_bytes = try keys.toProtobuf(self.base.allocator);
                defer self.base.allocator.free(keys_bytes);
                try live_writer.writeMessage(3, keys_bytes);
            }
            
            // duration = 4
            if (live_hash.duration) |duration| {
                var duration_writer = ProtoWriter.init(self.base.allocator);
                defer duration_writer.deinit();
                try duration_writer.writeInt64(1, duration.seconds);
                const duration_bytes = try duration_writer.toOwnedSlice();
                defer self.base.allocator.free(duration_bytes);
                try live_writer.writeMessage(4, duration_bytes);
            }
            
            const live_bytes = try live_writer.toOwnedSlice();
            defer self.base.allocator.free(live_bytes);
            try hash_writer.writeMessage(1, live_bytes);
        }
        
        const hash_bytes = try hash_writer.toOwnedSlice();
        defer self.base.allocator.free(hash_bytes);
        try writer.writeMessage(25, hash_bytes);
        
        return writer.toOwnedSlice();
    }
    
    fn writeCommonFields(self: *LiveHashAddTransaction, writer: *ProtoWriter) !void {
        // Write standard transaction fields
        try self.base.writeCommonFields(writer);
    }
};
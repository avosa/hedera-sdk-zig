const std = @import("std");
const AccountId = @import("../core/id.zig").AccountId;
const Key = @import("key.zig").Key;
const Duration = @import("../core/duration.zig").Duration;
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;

// LiveHash represents a hash that can be used to verify data integrity
pub const LiveHash = struct {
    account_id: AccountId,
    hash: []const u8,
    keys: std.ArrayList(Key),
    duration: Duration,
    
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, account_id: AccountId, hash: []const u8, duration: Duration) !LiveHash {
        if (hash.len != 48) return error.InvalidHashLength; // SHA-384 hash
        
        return LiveHash{
            .account_id = account_id,
            .hash = try allocator.dupe(u8, hash),
            .keys = std.ArrayList(Key).init(allocator),
            .duration = duration,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *LiveHash) void {
        if (self.hash.len > 0) {
            self.allocator.free(self.hash);
        }
        // Keys don't need individual deinit
        self.keys.deinit();
    }
    
    pub fn addKey(self: *LiveHash, key: Key) !void {
        try self.keys.append(try key.clone(self.allocator));
    }
};

// LiveHashAddTransaction adds a live hash to an account
pub const LiveHashAddTransaction = struct {
    base: Transaction,
    account_id: ?AccountId,
    hash: []const u8,
    keys: std.ArrayList(Key),
    duration: ?Duration,
    
    pub fn init(allocator: std.mem.Allocator) LiveHashAddTransaction {
        return LiveHashAddTransaction{
            .base = Transaction.init(allocator),
            .account_id = null,
            .hash = "",
            .keys = std.ArrayList(Key).init(allocator),
            .duration = null,
        };
    }
    
    pub fn deinit(self: *LiveHashAddTransaction) void {
        self.base.deinit();
        if (self.hash.len > 0) {
            self.base.allocator.free(self.hash);
        }
        // Keys don't need individual deinit
        self.keys.deinit();
    }
    
    // Set the account ID for the live hash
    pub fn setAccountId(self: *LiveHashAddTransaction, account_id: AccountId) *LiveHashAddTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        self.account_id = account_id;
        return self;
    }
    
    // Set the hash value (must be SHA-384)
    pub fn setHash(self: *LiveHashAddTransaction, hash: []const u8) !*LiveHashAddTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        if (hash.len != 48) @panic("Invalid hash length - must be SHA-384");
        
        if (self.hash.len > 0) {
            self.base.allocator.free(self.hash);
        }
        self.hash = try self.base.allocator.dupe(u8, hash);
        return self;
    }
    
    // Includes a key that can query the live hash
    pub fn addKey(self: *LiveHashAddTransaction, key: Key) !void {
        if (self.base.frozen) @panic("Transaction is frozen");
        try self.keys.append(key);
    }
    
    // Set the duration the live hash will remain valid
    pub fn setDuration(self: *LiveHashAddTransaction, duration: Duration) *LiveHashAddTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        if (duration.seconds > 120 * 24 * 60 * 60) @panic("Duration exceeds maximum of 120 days");
        self.duration = duration;
        return self;
    }
    
    // Execute the transaction
    pub fn execute(self: *LiveHashAddTransaction, client: *Client) !TransactionResponse {
        if (self.account_id == null) {
            return error.AccountIdRequired;
        }
        if (self.hash.len == 0) {
            return error.HashRequired;
        }
        if (self.keys.items.len == 0) {
            return error.KeysRequired;
        }
        if (self.duration == null) {
            return error.DurationRequired;
        }
        
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *LiveHashAddTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Common transaction fields
        try self.writeCommonFields(&writer);
        
        // cryptoAddLiveHash = 17 (oneof data)
        var add_writer = ProtoWriter.init(self.base.allocator);
        defer add_writer.deinit();
        
        // liveHash = 1
        var live_hash_writer = ProtoWriter.init(self.base.allocator);
        defer live_hash_writer.deinit();
        
        // accountId = 1
        if (self.account_id) |account| {
            var account_writer = ProtoWriter.init(self.base.allocator);
            defer account_writer.deinit();
            try account_writer.writeInt64(1, @intCast(account.shard));
            try account_writer.writeInt64(2, @intCast(account.realm));
            try account_writer.writeInt64(3, @intCast(account.account));
            const account_bytes = try account_writer.toOwnedSlice();
            defer self.base.allocator.free(account_bytes);
            try live_hash_writer.writeMessage(1, account_bytes);
        }
        
        // hash = 2
        if (self.hash.len > 0) {
            try live_hash_writer.writeBytes(2, self.hash);
        }
        
        // keys = 3
        if (self.keys.items.len > 0) {
            var key_list_writer = ProtoWriter.init(self.base.allocator);
            defer key_list_writer.deinit();
            
            for (self.keys.items) |key| {
                const key_bytes = try key.toProtobuf(self.base.allocator);
                defer self.base.allocator.free(key_bytes);
                try key_list_writer.writeMessage(1, key_bytes);
            }
            
            const key_list_bytes = try key_list_writer.toOwnedSlice();
            defer self.base.allocator.free(key_list_bytes);
            try live_hash_writer.writeMessage(3, key_list_bytes);
        }
        
        // duration = 4
        if (self.duration) |duration| {
            var duration_writer = ProtoWriter.init(self.base.allocator);
            defer duration_writer.deinit();
            try duration_writer.writeInt64(1, duration.seconds);
            const duration_bytes = try duration_writer.toOwnedSlice();
            defer self.base.allocator.free(duration_bytes);
            try live_hash_writer.writeMessage(4, duration_bytes);
        }
        
        const live_hash_bytes = try live_hash_writer.toOwnedSlice();
        defer self.base.allocator.free(live_hash_bytes);
        try add_writer.writeMessage(1, live_hash_bytes);
        
        const add_bytes = try add_writer.toOwnedSlice();
        defer self.base.allocator.free(add_bytes);
        try writer.writeMessage(17, add_bytes);
        
        return writer.toOwnedSlice();
    }
    
    fn writeCommonFields(self: *LiveHashAddTransaction, writer: *ProtoWriter) !void {
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

// LiveHashDeleteTransaction removes a live hash from an account
pub const LiveHashDeleteTransaction = struct {
    base: Transaction,
    account_id: ?AccountId,
    hash: []const u8,
    
    pub fn init(allocator: std.mem.Allocator) LiveHashDeleteTransaction {
        return LiveHashDeleteTransaction{
            .base = Transaction.init(allocator),
            .account_id = null,
            .hash = "",
        };
    }
    
    pub fn deinit(self: *LiveHashDeleteTransaction) void {
        self.base.deinit();
        if (self.hash.len > 0) {
            self.base.allocator.free(self.hash);
        }
    }
    
    // Set the account ID for the live hash
    pub fn setAccountId(self: *LiveHashDeleteTransaction, account_id: AccountId) *LiveHashDeleteTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        self.account_id = account_id;
        return self;
    }
    
    // Set the hash value to delete
    pub fn setHash(self: *LiveHashDeleteTransaction, hash: []const u8) !*LiveHashDeleteTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        if (hash.len != 48) @panic("Invalid hash length - must be SHA-384");
        
        if (self.hash.len > 0) {
            self.base.allocator.free(self.hash);
        }
        self.hash = try self.base.allocator.dupe(u8, hash);
        return self;
    }
    
    // Execute the transaction
    pub fn execute(self: *LiveHashDeleteTransaction, client: *Client) !TransactionResponse {
        if (self.account_id == null) {
            return error.AccountIdRequired;
        }
        if (self.hash.len == 0) {
            return error.HashRequired;
        }
        
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *LiveHashDeleteTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Common transaction fields
        try self.writeCommonFields(&writer);
        
        // cryptoDeleteLiveHash = 18 (oneof data)
        var delete_writer = ProtoWriter.init(self.base.allocator);
        defer delete_writer.deinit();
        
        // accountOfLiveHash = 1
        if (self.account_id) |account| {
            var account_writer = ProtoWriter.init(self.base.allocator);
            defer account_writer.deinit();
            try account_writer.writeInt64(1, @intCast(account.shard));
            try account_writer.writeInt64(2, @intCast(account.realm));
            try account_writer.writeInt64(3, @intCast(account.account));
            const account_bytes = try account_writer.toOwnedSlice();
            defer self.base.allocator.free(account_bytes);
            try delete_writer.writeMessage(1, account_bytes);
        }
        
        // liveHashToDelete = 2
        if (self.hash.len > 0) {
            try delete_writer.writeBytes(2, self.hash);
        }
        
        const delete_bytes = try delete_writer.toOwnedSlice();
        defer self.base.allocator.free(delete_bytes);
        try writer.writeMessage(18, delete_bytes);
        
        return writer.toOwnedSlice();
    }
    
    fn writeCommonFields(self: *LiveHashDeleteTransaction, writer: *ProtoWriter) !void {
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
const std = @import("std");
const FileId = @import("../core/id.zig").FileId;
const PublicKey = @import("../crypto/key.zig").PublicKey;
const KeyList = @import("../crypto/key.zig").KeyList;
const Key = @import("../crypto/key.zig").Key;
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const Timestamp = @import("../core/timestamp.zig").Timestamp;

// Maximum file size in bytes
pub const MAX_FILE_SIZE: usize = 1024 * 1024; // 1MB
pub const MAX_CHUNK_SIZE: usize = 4096; // 4KB per chunk

// FileCreateTransaction creates a new file in the Hedera network
pub const FileCreateTransaction = struct {
    base: Transaction,
    expiration_time: ?Timestamp,
    keys: std.ArrayList(Key),
    contents: []const u8,
    memo: ?[]const u8,
    
    pub fn init(allocator: std.mem.Allocator) FileCreateTransaction {
        return FileCreateTransaction{
            .base = Transaction.init(allocator),
            .expiration_time = null,
            .keys = std.ArrayList(Key).init(allocator),
            .contents = "",
            .memo = null,
        };
    }
    
    pub fn deinit(self: *FileCreateTransaction) void {
        self.base.deinit();
        self.keys.deinit();
    }
    
    // Set the expiration time for the file
    pub fn setExpirationTime(self: *FileCreateTransaction, time: Timestamp) *FileCreateTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        self.expiration_time = time;
        return self;
    }
    
    // Includes a key that must sign for modifications
    pub fn addKey(self: *FileCreateTransaction, key: Key) !void {
        if (self.base.frozen) @panic("Transaction is frozen");
        try self.keys.append(key);
    }
    
    // Set the keys that must sign for modifications (accepts Key)
    pub fn setKeys(self: *FileCreateTransaction, key: Key) !*FileCreateTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        
        self.keys.clearRetainingCapacity();
        
        // Add Key to the keys list
        try self.keys.append(key);
        return self;
    }
    
    // Set the keys that must sign for modifications (accepts Key array)
    pub fn setKeysArray(self: *FileCreateTransaction, keys: []const Key) *FileCreateTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        
        self.keys.clearRetainingCapacity();
        for (keys) |key| {
            try self.keys.append(key);
            return self;
        }
    }
    
    // Set the file contents
    pub fn setContents(self: *FileCreateTransaction, contents: []const u8) *FileCreateTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        
        if (contents.len > MAX_FILE_SIZE) {
            @panic("File too large");
        }
        
        self.contents = contents;
        return self;
    }
    
    // Set the file memo
    pub fn setMemo(self: *FileCreateTransaction, memo: []const u8) *FileCreateTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        
        if (memo.len > 100) {
            @panic("Memo too long");
        }
        
        self.memo = memo;
        return self;
    }
    
    // Set file memo (alias)
    pub fn setFileMemo(self: *FileCreateTransaction, memo: []const u8) *FileCreateTransaction {
        return self.setMemo(memo);
    }
    
    // Execute the transaction
    pub fn execute(self: *FileCreateTransaction, client: *Client) !TransactionResponse {
        // Files require at least one key
        if (self.keys.items.len == 0) {
            return error.KeyRequired;
        }
        
        // Set default expiration if not provided
        if (self.expiration_time == null) {
            const now = Timestamp.now();
            // Default to 90 days from now
            self.expiration_time = Timestamp{
                .seconds = now.seconds + (90 * 24 * 60 * 60),
                .nanos = now.nanos,
            };
        }
        
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *FileCreateTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Common transaction fields
        try self.writeCommonFields(&writer);
        
        // fileCreate = 19 (oneof data)
        var create_writer = ProtoWriter.init(self.base.allocator);
        defer create_writer.deinit();
        
        // expirationTime = 2
        if (self.expiration_time) |time| {
            var timestamp_writer = ProtoWriter.init(self.base.allocator);
            defer timestamp_writer.deinit();
            try timestamp_writer.writeInt64(1, time.seconds);
            try timestamp_writer.writeInt32(2, time.nanos);
            const timestamp_bytes = try timestamp_writer.toOwnedSlice();
            defer self.base.allocator.free(timestamp_bytes);
            try create_writer.writeMessage(2, timestamp_bytes);
        }
        
        // keys = 3
        if (self.keys.items.len > 0) {
            var keys_writer = ProtoWriter.init(self.base.allocator);
            defer keys_writer.deinit();
            
            // Create KeyList
            var key_list_writer = ProtoWriter.init(self.base.allocator);
            defer key_list_writer.deinit();
            
            for (self.keys.items) |key| {
                const key_bytes = try key.toProtobuf(self.base.allocator);
                defer self.base.allocator.free(key_bytes);
                try key_list_writer.writeMessage(1, key_bytes);
            }
            
            const key_list_bytes = try key_list_writer.toOwnedSlice();
            defer self.base.allocator.free(key_list_bytes);
            
            // Wrap in Key message with keyList = 2
            try keys_writer.writeMessage(2, key_list_bytes);
            
            const keys_bytes = try keys_writer.toOwnedSlice();
            defer self.base.allocator.free(keys_bytes);
            try create_writer.writeMessage(3, keys_bytes);
        }
        
        // contents = 4
        if (self.contents.len > 0) {
            try create_writer.writeBytes(4, self.contents);
        }
        
        // memo = 5
        if (self.memo) |memo| {
            try create_writer.writeString(5, memo);
        }
        
        const create_bytes = try create_writer.toOwnedSlice();
        defer self.base.allocator.free(create_bytes);
        try writer.writeMessage(19, create_bytes);
        
        return writer.toOwnedSlice();
    }
    
    fn writeCommonFields(self: *FileCreateTransaction, writer: *ProtoWriter) !void {
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
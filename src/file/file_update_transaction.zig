const std = @import("std");
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const FileId = @import("../core/id.zig").FileId;
const Key = @import("../crypto/key.zig").Key;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const Timestamp = @import("../core/timestamp.zig").Timestamp;

// FileUpdateTransaction updates a file's properties
pub const FileUpdateTransaction = struct {
    base: Transaction,
    file_id: ?FileId = null,
    keys: ?std.ArrayList(Key) = null,
    contents: ?[]const u8 = null,
    expiration_time: ?Timestamp = null,
    memo: ?[]const u8 = null,
    
    pub fn init(allocator: std.mem.Allocator) FileUpdateTransaction {
        return FileUpdateTransaction{
            .base = Transaction.init(allocator),
        };
    }
    
    pub fn deinit(self: *FileUpdateTransaction) void {
        self.base.deinit();
        if (self.keys) |*keys| {
            keys.deinit();
        }
        if (self.contents) |contents| {
            self.base.allocator.free(contents);
        }
        if (self.memo) |memo| {
            self.base.allocator.free(memo);
        }
    }
    
    // Set the file ID to update
    pub fn setFileId(self: *FileUpdateTransaction, file_id: FileId) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.file_id = file_id;
    }
    
    // Set the keys for the file (accepts ArrayList)
    pub fn setKeysList(self: *FileUpdateTransaction, keys: std.ArrayList(Key)) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        
        if (self.keys) |*old_keys| {
            old_keys.deinit();
        }
        
        self.keys = keys;
    }
    
    // Set the keys for the file (accepts single Key)
    pub fn setKeys(self: *FileUpdateTransaction, key: Key) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        
        if (self.keys) |*old_keys| {
            old_keys.deinit();
        }
        
        var keys = std.ArrayList(Key).init(self.base.allocator);
        try keys.append(key);
        self.keys = keys;
    }
    
    // Set the contents of the file
    pub fn setContents(self: *FileUpdateTransaction, contents: []const u8) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        
        if (self.contents) |old_contents| {
            self.base.allocator.free(old_contents);
        }
        
        self.contents = try self.base.allocator.dupe(u8, contents);
    }
    
    // Set the expiration time
    pub fn setExpirationTime(self: *FileUpdateTransaction, expiration_time: Timestamp) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.expiration_time = expiration_time;
    }
    
    // Set the memo
    pub fn setMemo(self: *FileUpdateTransaction, memo: []const u8) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        
        if (self.memo) |old_memo| {
            self.base.allocator.free(old_memo);
        }
        
        self.memo = try self.base.allocator.dupe(u8, memo);
    }
    
    // Set the file memo (alias for setMemo for Go SDK compatibility)
    pub fn setFileMemo(self: *FileUpdateTransaction, memo: []const u8) !void {
        return self.setMemo(memo);
    }
    
    // Execute the transaction
    pub fn execute(self: *FileUpdateTransaction, client: *Client) !TransactionResponse {
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *FileUpdateTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Write common transaction fields
        try self.base.writeCommonFields(&writer);
        
        // fileUpdate = 16 (oneof data)
        var file_writer = ProtoWriter.init(self.base.allocator);
        defer file_writer.deinit();
        
        // fileID = 1
        if (self.file_id) |file_id| {
            var id_writer = ProtoWriter.init(self.base.allocator);
            defer id_writer.deinit();
            try id_writer.writeInt64(1, @intCast(file_id.entity.shard));
            try id_writer.writeInt64(2, @intCast(file_id.entity.realm));
            try id_writer.writeInt64(3, @intCast(file_id.entity.num));
            const id_bytes = try id_writer.toOwnedSlice();
            defer self.base.allocator.free(id_bytes);
            try file_writer.writeMessage(1, id_bytes);
        }
        
        // expirationTime = 2
        if (self.expiration_time) |expiration| {
            var timestamp_writer = ProtoWriter.init(self.base.allocator);
            defer timestamp_writer.deinit();
            try timestamp_writer.writeInt64(1, expiration.seconds);
            try timestamp_writer.writeInt32(2, expiration.nanos);
            const timestamp_bytes = try timestamp_writer.toOwnedSlice();
            defer self.base.allocator.free(timestamp_bytes);
            try file_writer.writeMessage(2, timestamp_bytes);
        }
        
        // keys = 3
        if (self.keys) |keys| {
            var key_list_writer = ProtoWriter.init(self.base.allocator);
            defer key_list_writer.deinit();
            
            for (keys.items) |key| {
                const key_bytes = try key.toProtobuf(self.base.allocator);
                defer self.base.allocator.free(key_bytes);
                try key_list_writer.writeMessage(1, key_bytes);
            }
            
            const key_list_bytes = try key_list_writer.toOwnedSlice();
            defer self.base.allocator.free(key_list_bytes);
            try file_writer.writeMessage(3, key_list_bytes);
        }
        
        // contents = 4
        if (self.contents) |contents| {
            try file_writer.writeBytes(4, contents);
        }
        
        // memo = 5
        if (self.memo) |memo| {
            // Wrap in StringValue
            var memo_writer = ProtoWriter.init(self.base.allocator);
            defer memo_writer.deinit();
            try memo_writer.writeString(1, memo);
            const memo_bytes = try memo_writer.toOwnedSlice();
            defer self.base.allocator.free(memo_bytes);
            try file_writer.writeMessage(5, memo_bytes);
        }
        
        const file_bytes = try file_writer.toOwnedSlice();
        defer self.base.allocator.free(file_bytes);
        try writer.writeMessage(16, file_bytes);
        
        return writer.toOwnedSlice();
    }
};
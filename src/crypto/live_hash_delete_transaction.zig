const std = @import("std");
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const AccountId = @import("../core/id.zig").AccountId;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;

// LiveHashDeleteTransaction deletes a live hash from an account
pub const LiveHashDeleteTransaction = struct {
    base: Transaction,
    account_id: ?AccountId = null,
    hash: ?[]const u8 = null,
    
    pub fn init(allocator: std.mem.Allocator) LiveHashDeleteTransaction {
        return LiveHashDeleteTransaction{
            .base = Transaction.init(allocator),
        };
    }
    
    pub fn deinit(self: *LiveHashDeleteTransaction) void {
        self.base.deinit();
        if (self.hash) |hash| {
            self.base.allocator.free(hash);
        }
    }
    
    // Set the account ID
    pub fn setAccountId(self: *LiveHashDeleteTransaction, account_id: AccountId) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.account_id = account_id;
    }
    
    // Set the hash to delete
    pub fn setHash(self: *LiveHashDeleteTransaction, hash: []const u8) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        
        if (self.hash) |old_hash| {
            self.base.allocator.free(old_hash);
        }
        
        self.hash = try self.base.allocator.dupe(u8, hash);
    }
    
    // Execute the transaction
    pub fn execute(self: *LiveHashDeleteTransaction, client: *Client) !TransactionResponse {
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *LiveHashDeleteTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Write common transaction fields
        try self.writeCommonFields(&writer);
        
        // cryptoDeleteLiveHash = 26 (oneof data)
        var delete_writer = ProtoWriter.init(self.base.allocator);
        defer delete_writer.deinit();
        
        // accountOfLiveHash = 1
        if (self.account_id) |account_id| {
            var account_writer = ProtoWriter.init(self.base.allocator);
            defer account_writer.deinit();
            try account_writer.writeInt64(1, @intCast(account_id.entity.shard));
            try account_writer.writeInt64(2, @intCast(account_id.entity.realm));
            try account_writer.writeInt64(3, @intCast(account_id.entity.num));
            const account_bytes = try account_writer.toOwnedSlice();
            defer self.base.allocator.free(account_bytes);
            try delete_writer.writeMessage(1, account_bytes);
        }
        
        // liveHashToDelete = 2
        if (self.hash) |hash| {
            try delete_writer.writeBytes(2, hash);
        }
        
        const delete_bytes = try delete_writer.toOwnedSlice();
        defer self.base.allocator.free(delete_bytes);
        try writer.writeMessage(26, delete_bytes);
        
        return writer.toOwnedSlice();
    }
    
    fn writeCommonFields(self: *LiveHashDeleteTransaction, writer: *ProtoWriter) !void {
        // Write standard transaction fields
        try self.base.writeCommonFields(writer);
    }
};
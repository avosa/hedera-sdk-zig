const std = @import("std");
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const AccountId = @import("../core/id.zig").AccountId;
const TokenId = @import("../core/id.zig").TokenId;
const Timestamp = @import("../core/timestamp.zig").Timestamp;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;

// TokenUpdateNftsTransaction updates metadata for NFTs
pub const TokenUpdateNftsTransaction = struct {
    base: Transaction,
    token_id: ?TokenId = null,
    serials: std.ArrayList(i64),
    metadata: ?[]const u8 = null,
    
    pub fn init(allocator: std.mem.Allocator) TokenUpdateNftsTransaction {
        return TokenUpdateNftsTransaction{
            .base = Transaction.init(allocator),
            .serials = std.ArrayList(i64).init(allocator),
        };
    }
    
    pub fn deinit(self: *TokenUpdateNftsTransaction) void {
        self.base.deinit();
        self.serials.deinit();
        if (self.metadata) |metadata| {
            self.base.allocator.free(metadata);
        }
    }
    
    // Set the token ID
    pub fn setTokenId(self: *TokenUpdateNftsTransaction, token_id: TokenId) *TokenUpdateNftsTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        self.token_id = token_id;
    }
    
    // Add a serial number to update
    pub fn addSerial(self: *TokenUpdateNftsTransaction, serial: i64) !void {
        try self.serials.append(serial);
    }
    
    // Set all serials to update
    pub fn setSerials(self: *TokenUpdateNftsTransaction, serials: []const i64) *TokenUpdateNftsTransaction {
        self.serials.clearAndFree();
        try self.serials.appendSlice(serials);
    }
    
    // Set the metadata for the NFTs
    pub fn setMetadata(self: *TokenUpdateNftsTransaction, metadata: []const u8) *TokenUpdateNftsTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        if (metadata.len > 100) return error.MetadataTooLong;
        
        if (self.metadata) |old| {
            self.base.allocator.free(old);
            return self;
        }
        self.metadata = try self.base.allocator.dupe(u8, metadata);
    }
    
    // Execute the transaction
    pub fn execute(self: *TokenUpdateNftsTransaction, client: *Client) !TransactionResponse {
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *TokenUpdateNftsTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Write common transaction fields
        try self.writeCommonFields(&writer);
        
        // tokenUpdateNfts = 60 (oneof data)
        var update_writer = ProtoWriter.init(self.base.allocator);
        defer update_writer.deinit();
        
        // token = 1
        if (self.token_id) |token_id| {
            var token_writer = ProtoWriter.init(self.base.allocator);
            defer token_writer.deinit();
            try token_writer.writeInt64(1, @intCast(token_id.shard));
            try token_writer.writeInt64(2, @intCast(token_id.realm));
            try token_writer.writeInt64(3, @intCast(token_id.num));
            const token_bytes = try token_writer.toOwnedSlice();
            defer self.base.allocator.free(token_bytes);
            try update_writer.writeMessage(1, token_bytes);
        }
        
        // serials = 2 (repeated)
        for (self.serials.items) |serial| {
            try update_writer.writeInt64(2, serial);
        }
        
        // metadata = 3
        if (self.metadata) |metadata| {
            // Wrap metadata in google.protobuf.BytesValue
            var metadata_writer = ProtoWriter.init(self.base.allocator);
            defer metadata_writer.deinit();
            try metadata_writer.writeBytes(1, metadata);
            const metadata_bytes = try metadata_writer.toOwnedSlice();
            defer self.base.allocator.free(metadata_bytes);
            try update_writer.writeMessage(3, metadata_bytes);
        }
        
        const update_bytes = try update_writer.toOwnedSlice();
        defer self.base.allocator.free(update_bytes);
        try writer.writeMessage(60, update_bytes);
        
        return writer.toOwnedSlice();
    }
    
    fn writeCommonFields(self: *TokenUpdateNftsTransaction, writer: *ProtoWriter) !void {
        // Write standard transaction fields
        try self.base.writeCommonFields(writer);
    }
};

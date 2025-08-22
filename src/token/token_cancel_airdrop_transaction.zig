const std = @import("std");
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const AccountId = @import("../core/id.zig").AccountId;
const TokenId = @import("../core/id.zig").TokenId;
const NftId = @import("../core/id.zig").NftId;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;

// PendingAirdropId identifies a pending airdrop
pub const PendingAirdropId = struct {
    sender: AccountId,
    receiver: AccountId,
    token_id: ?TokenId = null,
    nft_id: ?NftId = null,
};

// TokenCancelAirdropTransaction cancels pending airdrops
pub const TokenCancelAirdropTransaction = struct {
    base: Transaction,
    pending_airdrops: std.ArrayList(PendingAirdropId),
    
    pub fn init(allocator: std.mem.Allocator) TokenCancelAirdropTransaction {
        return TokenCancelAirdropTransaction{
            .base = Transaction.init(allocator),
            .pending_airdrops = std.ArrayList(PendingAirdropId).init(allocator),
        };
    }
    
    pub fn deinit(self: *TokenCancelAirdropTransaction) void {
        self.base.deinit();
        self.pending_airdrops.deinit();
    }
    
    // Add a pending airdrop to cancel
    pub fn addPendingAirdrop(self: *TokenCancelAirdropTransaction, pending_airdrop: PendingAirdropId) !void {
        try self.pending_airdrops.append(pending_airdrop);
    }
    
    // Set all pending airdrops to cancel
    pub fn setPendingAirdrops(self: *TokenCancelAirdropTransaction, pending_airdrops: []const PendingAirdropId) !void {
        self.pending_airdrops.clearAndFree();
        try self.pending_airdrops.appendSlice(pending_airdrops);
    }
    
    // Execute the transaction
    pub fn execute(self: *TokenCancelAirdropTransaction, client: *Client) !TransactionResponse {
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *TokenCancelAirdropTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Write common transaction fields
        try self.writeCommonFields(&writer);
        
        // tokenCancelAirdrop = 57 (oneof data)
        var cancel_writer = ProtoWriter.init(self.base.allocator);
        defer cancel_writer.deinit();
        
        // pendingAirdrops = 1 (repeated)
        for (self.pending_airdrops.items) |pending| {
            var pending_writer = ProtoWriter.init(self.base.allocator);
            defer pending_writer.deinit();
            
            // senderId = 1
            var sender_writer = ProtoWriter.init(self.base.allocator);
            defer sender_writer.deinit();
            try sender_writer.writeInt64(1, @intCast(pending.sender.entity.shard));
            try sender_writer.writeInt64(2, @intCast(pending.sender.entity.realm));
            try sender_writer.writeInt64(3, @intCast(pending.sender.entity.num));
            const sender_bytes = try sender_writer.toOwnedSlice();
            defer self.base.allocator.free(sender_bytes);
            try pending_writer.writeMessage(1, sender_bytes);
            
            // receiverId = 2
            var receiver_writer = ProtoWriter.init(self.base.allocator);
            defer receiver_writer.deinit();
            try receiver_writer.writeInt64(1, @intCast(pending.receiver.entity.shard));
            try receiver_writer.writeInt64(2, @intCast(pending.receiver.entity.realm));
            try receiver_writer.writeInt64(3, @intCast(pending.receiver.entity.num));
            const receiver_bytes = try receiver_writer.toOwnedSlice();
            defer self.base.allocator.free(receiver_bytes);
            try pending_writer.writeMessage(2, receiver_bytes);
            
            // token = 3 (oneof)
            if (pending.token_id) |token_id| {
                var token_writer = ProtoWriter.init(self.base.allocator);
                defer token_writer.deinit();
                try token_writer.writeInt64(1, @intCast(token_id.entity.shard));
                try token_writer.writeInt64(2, @intCast(token_id.entity.realm));
                try token_writer.writeInt64(3, @intCast(token_id.entity.num));
                const token_bytes = try token_writer.toOwnedSlice();
                defer self.base.allocator.free(token_bytes);
                try pending_writer.writeMessage(3, token_bytes);
            }
            
            // nft = 4 (oneof)
            if (pending.nft_id) |nft_id| {
                var nft_writer = ProtoWriter.init(self.base.allocator);
                defer nft_writer.deinit();
                
                // tokenId = 1
                var token_writer = ProtoWriter.init(self.base.allocator);
                defer token_writer.deinit();
                try token_writer.writeInt64(1, @intCast(nft_id.token_id.entity.shard));
                try token_writer.writeInt64(2, @intCast(nft_id.token_id.entity.realm));
                try token_writer.writeInt64(3, @intCast(nft_id.token_id.entity.num));
                const token_bytes = try token_writer.toOwnedSlice();
                defer self.base.allocator.free(token_bytes);
                try nft_writer.writeMessage(1, token_bytes);
                
                // serialNumber = 2
                try nft_writer.writeInt64(2, nft_id.serial_number);
                
                const nft_bytes = try nft_writer.toOwnedSlice();
                defer self.base.allocator.free(nft_bytes);
                try pending_writer.writeMessage(4, nft_bytes);
            }
            
            const pending_bytes = try pending_writer.toOwnedSlice();
            defer self.base.allocator.free(pending_bytes);
            try cancel_writer.writeMessage(1, pending_bytes);
        }
        
        const cancel_bytes = try cancel_writer.toOwnedSlice();
        defer self.base.allocator.free(cancel_bytes);
        try writer.writeMessage(57, cancel_bytes);
        
        return writer.toOwnedSlice();
    }
    
    fn writeCommonFields(self: *TokenCancelAirdropTransaction, writer: *ProtoWriter) !void {
        // Write standard transaction fields
        try self.base.writeCommonFields(writer);
    }
};
// Identifier for a pending airdrop in the Hedera network
// Tracks pending token or NFT airdrops with sender, receiver, and token information

const std = @import("std");
const AccountId = @import("../core/id.zig").AccountId;
const TokenId = @import("../core/id.zig").TokenId;
const NftId = @import("../core/id.zig").NftId;
const ProtoWriter = @import("../protobuf/writer.zig").ProtoWriter;
const ProtoReader = @import("../protobuf/reader.zig").ProtoReader;
const HederaError = @import("../core/errors.zig").HederaError;

// Represents an identifier for a pending airdrop
pub const PendingAirdropId = struct {
    sender_id: ?AccountId = null,
    receiver_id: ?AccountId = null,
    token_id: ?TokenId = null,
    nft_id: ?NftId = null,
    
    const Self = @This();
    
    pub fn init() Self {
        return Self{};
    }
    
    // Set the sender account ID
    pub fn setSenderId(self: *Self, sender_id: AccountId) *Self {
        self.sender_id = sender_id;
        return self;
    }
    
    // Get the sender account ID
    pub fn getSenderId(self: *const Self) ?AccountId {
        return self.sender_id;
    }
    
    // Set the receiver account ID
    pub fn setReceiverId(self: *Self, receiver_id: AccountId) *Self {
        self.receiver_id = receiver_id;
        return self;
    }
    
    // Get the receiver account ID
    pub fn getReceiverId(self: *const Self) ?AccountId {
        return self.receiver_id;
    }
    
    // Set the fungible token ID
    pub fn setTokenId(self: *Self, token_id: TokenId) *Self {
        self.token_id = token_id;
        self.nft_id = null; // Clear NFT ID when setting token ID
        return self;
    }
    
    // Get the fungible token ID
    pub fn getTokenId(self: *const Self) ?TokenId {
        return self.token_id;
    }
    
    // Set the NFT ID
    pub fn setNftId(self: *Self, nft_id: NftId) *Self {
        self.nft_id = nft_id;
        self.token_id = null; // Clear token ID when setting NFT ID
        return self;
    }
    
    // Get the NFT ID
    pub fn getNftId(self: *const Self) ?NftId {
        return self.nft_id;
    }
    
    // Validate that the pending airdrop ID has required fields
    pub fn validate(self: *const Self) HederaError!void {
        if (self.sender_id == null) {
            return HederaError.InvalidParameter;
        }
        if (self.receiver_id == null) {
            return HederaError.InvalidParameter;
        }
        if (self.token_id == null and self.nft_id == null) {
            return HederaError.InvalidParameter;
        }
        if (self.token_id != null and self.nft_id != null) {
            return HederaError.InvalidParameter;
        }
    }
    
    // Convert to protobuf bytes
    pub fn toProtobuf(self: *const Self, allocator: std.mem.Allocator) ![]u8 {
        var writer = ProtoWriter.init(allocator);
        defer writer.deinit();
        
        // senderId = 1
        if (self.sender_id) |sender| {
            const sender_bytes = try sender.toProtobuf(allocator);
            defer allocator.free(sender_bytes);
            try writer.writeMessage(1, sender_bytes);
        }
        
        // receiverId = 2
        if (self.receiver_id) |receiver| {
            const receiver_bytes = try receiver.toProtobuf(allocator);
            defer allocator.free(receiver_bytes);
            try writer.writeMessage(2, receiver_bytes);
        }
        
        // fungibleTokenType = 3 or nonFungibleToken = 4
        if (self.token_id) |token| {
            const token_bytes = try token.toProtobuf(allocator);
            defer allocator.free(token_bytes);
            try writer.writeMessage(3, token_bytes);
        } else if (self.nft_id) |nft| {
            var nft_writer = ProtoWriter.init(allocator);
            defer nft_writer.deinit();
            
            // tokenId
            const token_bytes = try nft.token_id.toProtobuf(allocator);
            defer allocator.free(token_bytes);
            try nft_writer.writeMessage(1, token_bytes);
            
            // serialNumber
            try nft_writer.writeInt64(2, @intCast(nft.serial_number));
            
            const nft_bytes = try nft_writer.toOwnedSlice();
            defer allocator.free(nft_bytes);
            try writer.writeMessage(4, nft_bytes);
        }
        
        return writer.toOwnedSlice();
    }
    
    // Parse from protobuf bytes
    pub fn fromProtobuf(allocator: std.mem.Allocator, bytes: []const u8) !Self {
        var result = Self{};
        
        if (bytes.len == 0) {
            return result;
        }
        
        var reader = ProtoReader.init(bytes);
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => {
                    // senderId
                    const sender_bytes = try reader.readBytes();
                    result.sender_id = try AccountId.fromProtobuf(allocator, sender_bytes);
                },
                2 => {
                    // receiverId
                    const receiver_bytes = try reader.readBytes();
                    result.receiver_id = try AccountId.fromProtobuf(allocator, receiver_bytes);
                },
                3 => {
                    // fungibleTokenType
                    const token_bytes = try reader.readBytes();
                    result.token_id = try TokenId.fromProtobuf(allocator, token_bytes);
                },
                4 => {
                    // nonFungibleToken
                    const nft_bytes = try reader.readBytes();
                    var nft_reader = ProtoReader.init(nft_bytes);
                    
                    var token_id: ?TokenId = null;
                    var serial: u64 = 0;
                    
                    while (nft_reader.hasMore()) {
                        const nft_tag = try nft_reader.readTag();
                        
                        switch (nft_tag.field_number) {
                            1 => {
                                const token_bytes_inner = try nft_reader.readBytes();
                                token_id = try TokenId.fromProtobuf(allocator, token_bytes_inner);
                            },
                            2 => {
                                serial = @intCast(try nft_reader.readInt64());
                            },
                            else => try nft_reader.skipField(nft_tag.wire_type),
                        }
                    }
                    
                    if (token_id) |tid| {
                        result.nft_id = NftId.init(tid, serial);
                    }
                },
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return result;
    }
    
    // Check equality
    pub fn equals(self: Self, other: Self) bool {
        const sender_match = if (self.sender_id != null and other.sender_id != null)
            self.sender_id.?.equals(other.sender_id.?)
        else
            self.sender_id == null and other.sender_id == null;
            
        const receiver_match = if (self.receiver_id != null and other.receiver_id != null)
            self.receiver_id.?.equals(other.receiver_id.?)
        else
            self.receiver_id == null and other.receiver_id == null;
            
        const token_match = if (self.token_id != null and other.token_id != null)
            self.token_id.?.equals(other.token_id.?)
        else
            self.token_id == null and other.token_id == null;
            
        const nft_match = if (self.nft_id != null and other.nft_id != null)
            self.nft_id.?.equals(other.nft_id.?)
        else
            self.nft_id == null and other.nft_id == null;
            
        return sender_match and receiver_match and token_match and nft_match;
    }
};
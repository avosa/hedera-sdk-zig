const std = @import("std");
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const AccountId = @import("../core/id.zig").AccountId;
const TokenId = @import("../core/id.zig").TokenId;
const NftId = @import("../core/id.zig").NftId;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;

// AccountAllowanceDeleteTransaction deletes allowances for accounts
pub const AccountAllowanceDeleteTransaction = struct {
    base: Transaction,
    nft_allowances: std.ArrayList(NftRemoveAllowance),
    nft_allowance_deletions: std.ArrayList(NftRemoveAllowance),  // Alias for compatibility
    
    const NftRemoveAllowance = struct {
        token_id: TokenId,
        owner: AccountId,
        serials: std.ArrayList(i64),
    };
    
    pub fn init(allocator: std.mem.Allocator) AccountAllowanceDeleteTransaction {
        return AccountAllowanceDeleteTransaction{
            .base = Transaction.init(allocator),
            .nft_allowances = std.ArrayList(NftRemoveAllowance).init(allocator),
            .nft_allowance_deletions = std.ArrayList(NftRemoveAllowance).init(allocator),
        };
    }
    
    pub fn deinit(self: *AccountAllowanceDeleteTransaction) void {
        self.base.deinit();
        for (self.nft_allowances.items) |*nft| {
            nft.serials.deinit();
        }
        self.nft_allowances.deinit();
        
        for (self.nft_allowance_deletions.items) |*nft| {
            nft.serials.deinit();
        }
        self.nft_allowance_deletions.deinit();
    }
    
    // Delete NFT allowance
    pub fn deleteNftAllowance(self: *AccountAllowanceDeleteTransaction, nft_id: NftId, owner: AccountId) !void {
        // Check if we already have an entry for this token and owner
        for (self.nft_allowances.items) |*nft| {
            if (nft.token_id.num == nft_id.token_id.num and
                nft.owner.account == owner.account) {
                try nft.serials.append(nft_id.serial_number);
                return;
            }
        }
        
        // Create new entry
        var serials = std.ArrayList(i64).init(self.base.allocator);
        try serials.append(nft_id.serial_number);
        
        try self.nft_allowances.append(NftRemoveAllowance{
            .token_id = nft_id.token_id,
            .owner = owner,
            .serials = serials,
        });
    }
    
    // Delete all NFT allowances for a token
    pub fn deleteAllTokenNftAllowances(self: *AccountAllowanceDeleteTransaction, token_id: TokenId, owner: AccountId) !void {
        try self.nft_allowance_deletions.append(NftRemoveAllowance{
            .token_id = token_id,
            .owner = owner,
            .serials = std.ArrayList(i64).init(self.base.allocator), // Empty means all
        });
    }
    
    // Execute the transaction
    pub fn execute(self: *AccountAllowanceDeleteTransaction, client: *Client) !TransactionResponse {
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *AccountAllowanceDeleteTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Write common transaction fields
        try self.writeCommonFields(&writer);
        
        // cryptoDeleteAllowance = 49 (oneof data)
        var delete_writer = ProtoWriter.init(self.base.allocator);
        defer delete_writer.deinit();
        
        // nftAllowances = 1 (repeated)
        for (self.nft_allowances.items) |nft| {
            var nft_writer = ProtoWriter.init(self.base.allocator);
            defer nft_writer.deinit();
            
            // tokenId = 1
            var token_writer = ProtoWriter.init(self.base.allocator);
            defer token_writer.deinit();
            try token_writer.writeInt64(1, @intCast(nft.token_id.shard));
            try token_writer.writeInt64(2, @intCast(nft.token_id.realm));
            try token_writer.writeInt64(3, @intCast(nft.token_id.num));
            const token_bytes = try token_writer.toOwnedSlice();
            defer self.base.allocator.free(token_bytes);
            try nft_writer.writeMessage(1, token_bytes);
            
            // owner = 2
            var owner_writer = ProtoWriter.init(self.base.allocator);
            defer owner_writer.deinit();
            try owner_writer.writeInt64(1, @intCast(nft.owner.shard));
            try owner_writer.writeInt64(2, @intCast(nft.owner.realm));
            try owner_writer.writeInt64(3, @intCast(nft.owner.account));
            const owner_bytes = try owner_writer.toOwnedSlice();
            defer self.base.allocator.free(owner_bytes);
            try nft_writer.writeMessage(2, owner_bytes);
            
            // serialNumbers = 3 (repeated)
            for (nft.serials.items) |serial| {
                try nft_writer.writeInt64(3, serial);
            }
            
            const nft_bytes = try nft_writer.toOwnedSlice();
            defer self.base.allocator.free(nft_bytes);
            try delete_writer.writeMessage(1, nft_bytes);
        }
        
        const delete_bytes = try delete_writer.toOwnedSlice();
        defer self.base.allocator.free(delete_bytes);
        try writer.writeMessage(49, delete_bytes);
        
        return writer.toOwnedSlice();
    }
    
    fn writeCommonFields(self: *AccountAllowanceDeleteTransaction, writer: *ProtoWriter) !void {
        // Write standard transaction fields
        try self.base.writeCommonFields(writer);
    }
};
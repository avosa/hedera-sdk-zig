const std = @import("std");
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const AccountId = @import("../core/id.zig").AccountId;
const TokenId = @import("../core/id.zig").TokenId;
const NftId = @import("../core/id.zig").NftId;
const Hbar = @import("../core/hbar.zig").Hbar;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;

// TokenAirdropTransaction airdrops tokens to multiple accounts
pub const TokenAirdropTransaction = struct {
    base: Transaction,
    token_transfers: std.ArrayList(TokenTransfer),
    nft_transfers: std.ArrayList(NftTransfer),
    
    const TokenTransfer = struct {
        token_id: TokenId,
        account_id: AccountId,
        amount: i64,
        is_approval: bool = false,
    };
    
    const NftTransfer = struct {
        token_id: TokenId,
        sender: AccountId,
        receiver: AccountId,
        serial: i64,
        is_approval: bool = false,
    };
    
    pub fn init(allocator: std.mem.Allocator) TokenAirdropTransaction {
        return TokenAirdropTransaction{
            .base = Transaction.init(allocator),
            .token_transfers = std.ArrayList(TokenTransfer).init(allocator),
            .nft_transfers = std.ArrayList(NftTransfer).init(allocator),
        };
    }
    
    pub fn deinit(self: *TokenAirdropTransaction) void {
        self.base.deinit();
        self.token_transfers.deinit();
        self.nft_transfers.deinit();
    }
    
    // Add a token transfer to the airdrop
    pub fn addTokenTransfer(self: *TokenAirdropTransaction, token_id: TokenId, account_id: AccountId, amount: i64) !void {
        try self.token_transfers.append(TokenTransfer{
            .token_id = token_id,
            .account_id = account_id,
            .amount = amount,
        });
    }
    
    // Add an approved token transfer
    pub fn addApprovedTokenTransfer(self: *TokenAirdropTransaction, token_id: TokenId, account_id: AccountId, amount: i64) !void {
        try self.token_transfers.append(TokenTransfer{
            .token_id = token_id,
            .account_id = account_id,
            .amount = amount,
            .is_approval = true,
        });
    }
    
    // Add an NFT transfer to the airdrop
    pub fn addNftTransfer(self: *TokenAirdropTransaction, nft_id: NftId, receiver: AccountId) !void {
        try self.nft_transfers.append(NftTransfer{
            .token_id = nft_id.token_id,
            .sender = try AccountId.fromString(self.base.allocator, "0.0.0"), // Treasury
            .receiver = receiver,
            .serial = nft_id.serial_number,
        });
    }
    
    // Add an approved NFT transfer
    pub fn addApprovedNftTransfer(self: *TokenAirdropTransaction, token_id: TokenId, sender: AccountId, receiver: AccountId, serial: i64) !void {
        try self.nft_transfers.append(NftTransfer{
            .token_id = token_id,
            .sender = sender,
            .receiver = receiver,
            .serial = serial,
            .is_approval = true,
        });
    }
    
    // Freeze the transaction
    pub fn freezeWith(self: *TokenAirdropTransaction, client: *Client) !void {
        try self.base.freezeWith(client);
    }
    
    // Execute the transaction
    pub fn execute(self: *TokenAirdropTransaction, client: *Client) !TransactionResponse {
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *TokenAirdropTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Write common transaction fields
        try self.writeCommonFields(&writer);
        
        // tokenAirdrop = 56 (oneof data)
        var airdrop_writer = ProtoWriter.init(self.base.allocator);
        defer airdrop_writer.deinit();
        
        // tokenTransfers = 1 (repeated)
        for (self.token_transfers.items) |transfer| {
            var transfer_writer = ProtoWriter.init(self.base.allocator);
            defer transfer_writer.deinit();
            
            // token = 1
            var token_writer = ProtoWriter.init(self.base.allocator);
            defer token_writer.deinit();
            try token_writer.writeInt64(1, @intCast(transfer.token_id.shard));
            try token_writer.writeInt64(2, @intCast(transfer.token_id.realm));
            try token_writer.writeInt64(3, @intCast(transfer.token_id.num));
            const token_bytes = try token_writer.toOwnedSlice();
            defer self.base.allocator.free(token_bytes);
            try transfer_writer.writeMessage(1, token_bytes);
            
            // transfers = 2
            var account_writer = ProtoWriter.init(self.base.allocator);
            defer account_writer.deinit();
            
            // accountID = 1
            var acc_id_writer = ProtoWriter.init(self.base.allocator);
            defer acc_id_writer.deinit();
            try acc_id_writer.writeInt64(1, @intCast(transfer.account_id.shard));
            try acc_id_writer.writeInt64(2, @intCast(transfer.account_id.realm));
            try acc_id_writer.writeInt64(3, @intCast(transfer.account_id.account));
            const acc_bytes = try acc_id_writer.toOwnedSlice();
            defer self.base.allocator.free(acc_bytes);
            try account_writer.writeMessage(1, acc_bytes);
            
            // amount = 2
            try account_writer.writeInt64(2, transfer.amount);
            
            // is_approval = 3
            if (transfer.is_approval) {
                try account_writer.writeBool(3, true);
            }
            
            const account_transfer_bytes = try account_writer.toOwnedSlice();
            defer self.base.allocator.free(account_transfer_bytes);
            try transfer_writer.writeMessage(2, account_transfer_bytes);
            
            const transfer_bytes = try transfer_writer.toOwnedSlice();
            defer self.base.allocator.free(transfer_bytes);
            try airdrop_writer.writeMessage(1, transfer_bytes);
        }
        
        // nftTransfers = 2 (repeated)
        for (self.nft_transfers.items) |nft| {
            var nft_writer = ProtoWriter.init(self.base.allocator);
            defer nft_writer.deinit();
            
            // token = 1
            var token_writer = ProtoWriter.init(self.base.allocator);
            defer token_writer.deinit();
            try token_writer.writeInt64(1, @intCast(nft.token_id.shard));
            try token_writer.writeInt64(2, @intCast(nft.token_id.realm));
            try token_writer.writeInt64(3, @intCast(nft.token_id.num));
            const token_bytes = try token_writer.toOwnedSlice();
            defer self.base.allocator.free(token_bytes);
            try nft_writer.writeMessage(1, token_bytes);
            
            // sender = 2
            var sender_writer = ProtoWriter.init(self.base.allocator);
            defer sender_writer.deinit();
            try sender_writer.writeInt64(1, @intCast(nft.sender.shard));
            try sender_writer.writeInt64(2, @intCast(nft.sender.realm));
            try sender_writer.writeInt64(3, @intCast(nft.sender.account));
            const sender_bytes = try sender_writer.toOwnedSlice();
            defer self.base.allocator.free(sender_bytes);
            try nft_writer.writeMessage(2, sender_bytes);
            
            // receiver = 3
            var receiver_writer = ProtoWriter.init(self.base.allocator);
            defer receiver_writer.deinit();
            try receiver_writer.writeInt64(1, @intCast(nft.receiver.shard));
            try receiver_writer.writeInt64(2, @intCast(nft.receiver.realm));
            try receiver_writer.writeInt64(3, @intCast(nft.receiver.account));
            const receiver_bytes = try receiver_writer.toOwnedSlice();
            defer self.base.allocator.free(receiver_bytes);
            try nft_writer.writeMessage(3, receiver_bytes);
            
            // serialNumber = 4
            try nft_writer.writeInt64(4, nft.serial);
            
            // is_approval = 5
            if (nft.is_approval) {
                try nft_writer.writeBool(5, true);
            }
            
            const nft_bytes = try nft_writer.toOwnedSlice();
            defer self.base.allocator.free(nft_bytes);
            try airdrop_writer.writeMessage(2, nft_bytes);
        }
        
        const airdrop_bytes = try airdrop_writer.toOwnedSlice();
        defer self.base.allocator.free(airdrop_bytes);
        try writer.writeMessage(56, airdrop_bytes);
        
        return writer.toOwnedSlice();
    }
    
    fn writeCommonFields(self: *TokenAirdropTransaction, writer: *ProtoWriter) !void {
        // Write standard transaction fields
        try self.base.writeCommonFields(writer);
    }
};

// Constructor function matching the pattern used by other transactions

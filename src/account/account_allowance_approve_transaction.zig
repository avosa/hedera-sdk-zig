const std = @import("std");
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const AccountId = @import("../core/id.zig").AccountId;
const TokenId = @import("../core/id.zig").TokenId;
const NftId = @import("../core/id.zig").NftId;
const Hbar = @import("../core/hbar.zig").Hbar;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;

// HbarAllowance represents an HBAR allowance
pub const HbarAllowance = struct {
    owner: ?AccountId = null,
    spender: AccountId,
    amount: Hbar,
};

// TokenAllowance represents a token allowance
pub const TokenAllowance = struct {
    token_id: TokenId,
    owner: ?AccountId = null,
    spender: AccountId,
    amount: i64,
};

// NftAllowance represents an NFT allowance
pub const NftAllowance = struct {
    token_id: TokenId,
    owner: ?AccountId = null,
    spender: ?AccountId = null,
    serials: std.ArrayList(i64),
    approved_for_all: ?AccountId = null,
    delegating_spender: ?AccountId = null,
};

pub const TokenNftAllowance = struct {
    token_id: TokenId,
    owner: AccountId,
    spender: AccountId,
    serial_numbers: std.ArrayList(i64),
    approved_for_all: bool,
    
    pub fn deinit(self: *TokenNftAllowance) void {
        self.serial_numbers.deinit();
    }
};

// AccountAllowanceApproveTransaction approves allowances for accounts
pub const AccountAllowanceApproveTransaction = struct {
    base: Transaction,
    hbar_allowances: std.ArrayList(HbarAllowance),
    token_allowances: std.ArrayList(TokenAllowance),
    nft_allowances: std.ArrayList(NftAllowance),
    token_nft_allowances: std.ArrayList(TokenNftAllowance),
    
    pub fn init(allocator: std.mem.Allocator) AccountAllowanceApproveTransaction {
        return AccountAllowanceApproveTransaction{
            .base = Transaction.init(allocator),
            .hbar_allowances = std.ArrayList(HbarAllowance).init(allocator),
            .token_allowances = std.ArrayList(TokenAllowance).init(allocator),
            .nft_allowances = std.ArrayList(NftAllowance).init(allocator),
            .token_nft_allowances = std.ArrayList(TokenNftAllowance).init(allocator),
        };
    }
    
    pub fn deinit(self: *AccountAllowanceApproveTransaction) void {
        self.base.deinit();
        self.hbar_allowances.deinit();
        self.token_allowances.deinit();
        for (self.nft_allowances.items) |*nft| {
            nft.serials.deinit();
        }
        self.nft_allowances.deinit();
        for (self.token_nft_allowances.items) |*token_nft| {
            token_nft.deinit();
        }
        self.token_nft_allowances.deinit();
    }
    
    // Approve HBAR allowance
    pub fn approveHbarAllowance(self: *AccountAllowanceApproveTransaction, owner: ?AccountId, spender: AccountId, amount: Hbar) !void {
        try self.hbar_allowances.append(HbarAllowance{
            .owner = owner,
            .spender = spender,
            .amount = amount,
        });
    }
    
    // Add HBAR allowance (alias for approveHbarAllowance)
    pub fn addHbarAllowance(self: *AccountAllowanceApproveTransaction, owner: ?AccountId, spender: AccountId, amount: Hbar) !void {
        return self.approveHbarAllowance(owner, spender, amount);
    }
    
    // Approve token allowance
    pub fn approveTokenAllowance(self: *AccountAllowanceApproveTransaction, token_id: TokenId, owner: ?AccountId, spender: AccountId, amount: i64) !void {
        try self.token_allowances.append(TokenAllowance{
            .token_id = token_id,
            .owner = owner,
            .spender = spender,
            .amount = amount,
        });
    }
    
    // Add token allowance (alias for approveTokenAllowance)
    pub fn addTokenAllowance(self: *AccountAllowanceApproveTransaction, token_id: TokenId, owner: ?AccountId, spender: AccountId, amount: i64) !void {
        return self.approveTokenAllowance(token_id, owner, spender, amount);
    }
    
    // Approve NFT allowance
    pub fn approveNftAllowance(self: *AccountAllowanceApproveTransaction, token_id: TokenId, owner: ?AccountId, spender: AccountId, serials: []const i64) !void {
        var serial_list = std.ArrayList(i64).init(self.base.allocator);
        try serial_list.appendSlice(serials);
        
        try self.nft_allowances.append(NftAllowance{
            .token_id = token_id,
            .owner = owner,
            .spender = spender,
            .serials = serial_list,
        });
    }
    
    // Add NFT allowance (simplified version for tests)
    pub fn addNftAllowance(self: *AccountAllowanceApproveTransaction, nft_id: NftId, owner: ?AccountId, spender: AccountId) !void {
        var serials = std.ArrayList(i64).init(self.base.allocator);
        try serials.append(@intCast(nft_id.serial_number));
        
        try self.nft_allowances.append(NftAllowance{
            .token_id = nft_id.token_id,
            .owner = owner,
            .spender = spender,
            .serials = serials,
        });
    }
    
    // Approve NFT allowance for all serials
    pub fn approveNftAllowanceAllSerials(self: *AccountAllowanceApproveTransaction, token_id: TokenId, owner: ?AccountId, spender: AccountId) !void {
        try self.token_nft_allowances.append(TokenNftAllowance{
            .token_id = token_id,
            .owner = owner orelse AccountId.init(0, 0, 0),
            .spender = spender,
            .serial_numbers = std.ArrayList(i64).init(self.base.allocator),
            .approved_for_all = true,
        });
    }
    
    // Add all NFT allowance (alias for approveNftAllowanceAllSerials for Go SDK compatibility)  
    pub fn addAllNftAllowance(self: *AccountAllowanceApproveTransaction, token_id: TokenId, owner: ?AccountId, spender: AccountId) !void {
        return self.approveNftAllowanceAllSerials(token_id, owner, spender);
    }
    
    // Execute the transaction
    pub fn execute(self: *AccountAllowanceApproveTransaction, client: *Client) !TransactionResponse {
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *AccountAllowanceApproveTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Write common transaction fields
        try self.writeCommonFields(&writer);
        
        // cryptoApproveAllowance = 48 (oneof data)
        var approve_writer = ProtoWriter.init(self.base.allocator);
        defer approve_writer.deinit();
        
        // cryptoAllowances = 1 (repeated)
        for (self.hbar_allowances.items) |hbar| {
            var hbar_writer = ProtoWriter.init(self.base.allocator);
            defer hbar_writer.deinit();
            
            // owner = 1
            if (hbar.owner) |owner| {
                var owner_writer = ProtoWriter.init(self.base.allocator);
                defer owner_writer.deinit();
                try owner_writer.writeInt64(1, @intCast(owner.entity.shard));
                try owner_writer.writeInt64(2, @intCast(owner.entity.realm));
                try owner_writer.writeInt64(3, @intCast(owner.entity.num));
                const owner_bytes = try owner_writer.toOwnedSlice();
                defer self.base.allocator.free(owner_bytes);
                try hbar_writer.writeMessage(1, owner_bytes);
            }
            
            // spender = 2
            var spender_writer = ProtoWriter.init(self.base.allocator);
            defer spender_writer.deinit();
            try spender_writer.writeInt64(1, @intCast(hbar.spender.entity.shard));
            try spender_writer.writeInt64(2, @intCast(hbar.spender.entity.realm));
            try spender_writer.writeInt64(3, @intCast(hbar.spender.entity.num));
            const spender_bytes = try spender_writer.toOwnedSlice();
            defer self.base.allocator.free(spender_bytes);
            try hbar_writer.writeMessage(2, spender_bytes);
            
            // amount = 3
            try hbar_writer.writeInt64(3, hbar.amount.toTinybars());
            
            const hbar_bytes = try hbar_writer.toOwnedSlice();
            defer self.base.allocator.free(hbar_bytes);
            try approve_writer.writeMessage(1, hbar_bytes);
        }
        
        // tokenAllowances = 2 (repeated)
        for (self.token_allowances.items) |token| {
            var token_writer = ProtoWriter.init(self.base.allocator);
            defer token_writer.deinit();
            
            // tokenId = 1
            var token_id_writer = ProtoWriter.init(self.base.allocator);
            defer token_id_writer.deinit();
            try token_id_writer.writeInt64(1, @intCast(token.token_id.entity.shard));
            try token_id_writer.writeInt64(2, @intCast(token.token_id.entity.realm));
            try token_id_writer.writeInt64(3, @intCast(token.token_id.entity.num));
            const token_id_bytes = try token_id_writer.toOwnedSlice();
            defer self.base.allocator.free(token_id_bytes);
            try token_writer.writeMessage(1, token_id_bytes);
            
            // owner = 2
            if (token.owner) |owner| {
                var owner_writer = ProtoWriter.init(self.base.allocator);
                defer owner_writer.deinit();
                try owner_writer.writeInt64(1, @intCast(owner.entity.shard));
                try owner_writer.writeInt64(2, @intCast(owner.entity.realm));
                try owner_writer.writeInt64(3, @intCast(owner.entity.num));
                const owner_bytes = try owner_writer.toOwnedSlice();
                defer self.base.allocator.free(owner_bytes);
                try token_writer.writeMessage(2, owner_bytes);
            }
            
            // spender = 3
            var spender_writer = ProtoWriter.init(self.base.allocator);
            defer spender_writer.deinit();
            try spender_writer.writeInt64(1, @intCast(token.spender.entity.shard));
            try spender_writer.writeInt64(2, @intCast(token.spender.entity.realm));
            try spender_writer.writeInt64(3, @intCast(token.spender.entity.num));
            const spender_bytes = try spender_writer.toOwnedSlice();
            defer self.base.allocator.free(spender_bytes);
            try token_writer.writeMessage(3, spender_bytes);
            
            // amount = 4
            try token_writer.writeInt64(4, token.amount);
            
            const token_bytes = try token_writer.toOwnedSlice();
            defer self.base.allocator.free(token_bytes);
            try approve_writer.writeMessage(2, token_bytes);
        }
        
        // nftAllowances = 3 (repeated)
        for (self.nft_allowances.items) |nft| {
            var nft_writer = ProtoWriter.init(self.base.allocator);
            defer nft_writer.deinit();
            
            // tokenId = 1
            var token_id_writer = ProtoWriter.init(self.base.allocator);
            defer token_id_writer.deinit();
            try token_id_writer.writeInt64(1, @intCast(nft.token_id.entity.shard));
            try token_id_writer.writeInt64(2, @intCast(nft.token_id.entity.realm));
            try token_id_writer.writeInt64(3, @intCast(nft.token_id.entity.num));
            const token_id_bytes = try token_id_writer.toOwnedSlice();
            defer self.base.allocator.free(token_id_bytes);
            try nft_writer.writeMessage(1, token_id_bytes);
            
            // owner = 2
            if (nft.owner) |owner| {
                var owner_writer = ProtoWriter.init(self.base.allocator);
                defer owner_writer.deinit();
                try owner_writer.writeInt64(1, @intCast(owner.entity.shard));
                try owner_writer.writeInt64(2, @intCast(owner.entity.realm));
                try owner_writer.writeInt64(3, @intCast(owner.entity.num));
                const owner_bytes = try owner_writer.toOwnedSlice();
                defer self.base.allocator.free(owner_bytes);
                try nft_writer.writeMessage(2, owner_bytes);
            }
            
            // spender = 3
            if (nft.spender) |spender| {
                var spender_writer = ProtoWriter.init(self.base.allocator);
                defer spender_writer.deinit();
                try spender_writer.writeInt64(1, @intCast(spender.entity.shard));
                try spender_writer.writeInt64(2, @intCast(spender.entity.realm));
                try spender_writer.writeInt64(3, @intCast(spender.entity.num));
                const spender_bytes = try spender_writer.toOwnedSlice();
                defer self.base.allocator.free(spender_bytes);
                try nft_writer.writeMessage(3, spender_bytes);
            }
            
            // serialNumbers = 4 (repeated)
            for (nft.serials.items) |serial| {
                try nft_writer.writeInt64(4, serial);
            }
            
            // approvedForAll = 5
            if (nft.approved_for_all) |approved| {
                var approved_writer = ProtoWriter.init(self.base.allocator);
                defer approved_writer.deinit();
                try approved_writer.writeInt64(1, @intCast(approved.entity.shard));
                try approved_writer.writeInt64(2, @intCast(approved.entity.realm));
                try approved_writer.writeInt64(3, @intCast(approved.entity.num));
                const approved_bytes = try approved_writer.toOwnedSlice();
                defer self.base.allocator.free(approved_bytes);
                try nft_writer.writeMessage(5, approved_bytes);
            }
            
            // delegatingSpender = 6
            if (nft.delegating_spender) |delegating| {
                var delegating_writer = ProtoWriter.init(self.base.allocator);
                defer delegating_writer.deinit();
                try delegating_writer.writeInt64(1, @intCast(delegating.entity.shard));
                try delegating_writer.writeInt64(2, @intCast(delegating.entity.realm));
                try delegating_writer.writeInt64(3, @intCast(delegating.entity.num));
                const delegating_bytes = try delegating_writer.toOwnedSlice();
                defer self.base.allocator.free(delegating_bytes);
                try nft_writer.writeMessage(6, delegating_bytes);
            }
            
            const nft_bytes = try nft_writer.toOwnedSlice();
            defer self.base.allocator.free(nft_bytes);
            try approve_writer.writeMessage(3, nft_bytes);
        }
        
        const approve_bytes = try approve_writer.toOwnedSlice();
        defer self.base.allocator.free(approve_bytes);
        try writer.writeMessage(48, approve_bytes);
        
        return writer.toOwnedSlice();
    }
    
    fn writeCommonFields(self: *AccountAllowanceApproveTransaction, writer: *ProtoWriter) !void {
        // Write standard transaction fields
        try self.base.writeCommonFields(writer);
    }
};
// Base transaction class for token transfer operations
// Provides common functionality for token and NFT transfers

const std = @import("std");
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TokenId = @import("../core/id.zig").TokenId;
const AccountId = @import("../core/id.zig").AccountId;
const NftId = @import("../core/id.zig").NftId;
const HederaError = @import("../core/errors.zig").HederaError;
const ProtoWriter = @import("../protobuf/writer.zig").ProtoWriter;
const requireNotFrozen = @import("../core/errors.zig").requireNotFrozen;

// Use existing TokenTransfer and NftTransfer from transfer module - NO REDUNDANCY
const TokenTransfer = @import("../transfer/transfer_transaction.zig").TokenTransfer;
const NftTransfer = @import("../transfer/transfer_transaction.zig").NftTransfer;

// Token transfer list structure
pub const TokenTransferList = struct {
    token_id: TokenId,
    expected_decimals: ?u32 = null,
    transfers: std.ArrayList(TokenTransfer),
    nft_transfers: std.ArrayList(NftTransfer),
    
    pub fn init(allocator: std.mem.Allocator, token_id: TokenId) TokenTransferList {
        return .{
            .token_id = token_id,
            .expected_decimals = null,
            .transfers = std.ArrayList(TokenTransfer).init(allocator),
            .nft_transfers = std.ArrayList(NftTransfer).init(allocator),
        };
    }
    
    pub fn deinit(self: *TokenTransferList) void {
        self.transfers.deinit();
        self.nft_transfers.deinit();
    }
    
    pub fn toProtobuf(self: *const TokenTransferList, allocator: std.mem.Allocator) ![]u8 {
        var writer = ProtoWriter.init(allocator);
        defer writer.deinit();
        
        // token = 1
        const token_bytes = try self.token_id.toProtobuf(allocator);
        defer allocator.free(token_bytes);
        try writer.writeMessage(1, token_bytes);
        
        // expectedDecimals = 2
        if (self.expected_decimals) |decimals| {
            var decimals_writer = ProtoWriter.init(allocator);
            defer decimals_writer.deinit();
            try decimals_writer.writeUint32(1, decimals);
            const decimals_bytes = try decimals_writer.toOwnedSlice();
            defer allocator.free(decimals_bytes);
            try writer.writeMessage(2, decimals_bytes);
        }
        
        // transfers = 3 (repeated)
        for (self.transfers.items) |transfer| {
            const transfer_bytes = try transfer.toProtobuf(allocator);
            defer allocator.free(transfer_bytes);
            try writer.writeMessage(3, transfer_bytes);
        }
        
        // nftTransfers = 4 (repeated)
        for (self.nft_transfers.items) |nft| {
            const nft_bytes = try nft.toProtobuf(allocator);
            defer allocator.free(nft_bytes);
            try writer.writeMessage(4, nft_bytes);
        }
        
        return writer.toOwnedSlice();
    }
};

// Base class for token transfer transactions
pub const AbstractTokenTransferTransaction = struct {
    base: Transaction,
    token_transfers: std.ArrayList(TokenTransfer),
    nft_transfers: std.ArrayList(NftTransfer),
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .base = Transaction.init(allocator),
            .token_transfers = std.ArrayList(TokenTransfer).init(allocator),
            .nft_transfers = std.ArrayList(NftTransfer).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.token_transfers.deinit();
        self.nft_transfers.deinit();
        self.base.deinit();
    }
    
    // Add a token transfer
    pub fn addTokenTransfer(self: *Self, token_id: TokenId, account_id: AccountId, amount: i64) HederaError!*Self {
        try requireNotFrozen(self.base.frozen);
        
        // Check if transfer already exists and merge amounts
        for (self.token_transfers.items) |*transfer| {
            if (transfer.token_id.equals(token_id) and transfer.account_id.equals(account_id)) {
                transfer.amount += amount;
                return self;
            }
        }
        
        // Add new transfer
        try self.token_transfers.append(.{
            .token_id = token_id,
            .account_id = account_id,
            .amount = amount,
            .is_approved = false,
            .expected_decimals = null,
        });
        
        return self;
    }
    
    // Add an approved token transfer
    pub fn addApprovedTokenTransfer(self: *Self, token_id: TokenId, account_id: AccountId, amount: i64) HederaError!*Self {
        try requireNotFrozen(self.base.frozen);
        
        // Check if transfer already exists and merge amounts
        for (self.token_transfers.items) |*transfer| {
            if (transfer.token_id.equals(token_id) and transfer.account_id.equals(account_id)) {
                transfer.amount += amount;
                transfer.is_approved = true;
                return self;
            }
        }
        
        // Add new approved transfer
        try self.token_transfers.append(.{
            .token_id = token_id,
            .account_id = account_id,
            .amount = amount,
            .is_approved = true,
            .expected_decimals = null,
        });
        
        return self;
    }
    
    // Add a token transfer with expected decimals
    pub fn addTokenTransferWithDecimals(self: *Self, token_id: TokenId, account_id: AccountId, amount: i64, decimals: u32) HederaError!*Self {
        try requireNotFrozen(self.base.frozen);
        
        // Check if transfer already exists
        for (self.token_transfers.items) |*transfer| {
            if (transfer.token_id.equals(token_id)) {
                // Verify decimals match
                if (transfer.expected_decimals) |existing_decimals| {
                    if (existing_decimals != decimals) {
                        return HederaError.InvalidParameter;
                    }
                } else {
                    transfer.expected_decimals = decimals;
                }
                
                if (transfer.account_id.equals(account_id)) {
                    transfer.amount += amount;
                    return self;
                }
            }
        }
        
        // Add new transfer with decimals
        try self.token_transfers.append(.{
            .token_id = token_id,
            .account_id = account_id,
            .amount = amount,
            .is_approved = false,
            .expected_decimals = decimals,
        });
        
        return self;
    }
    
    // Add an NFT transfer
    pub fn addNftTransfer(self: *Self, nft_id: NftId, sender: AccountId, receiver: AccountId) HederaError!*Self {
        try requireNotFrozen(self.base.frozen);
        
        // Check if NFT transfer already exists and update
        for (self.nft_transfers.items) |*transfer| {
            if (transfer.nft_id.equals(nft_id)) {
                transfer.sender_account_id = sender;
                transfer.receiver_account_id = receiver;
                return self;
            }
        }
        
        // Add new NFT transfer  
        try self.nft_transfers.append(NftTransfer.init(nft_id, sender, receiver));
        
        return self;
    }
    
    // Add an approved NFT transfer
    pub fn addApprovedNftTransfer(self: *Self, nft_id: NftId, sender: AccountId, receiver: AccountId) HederaError!*Self {
        try requireNotFrozen(self.base.frozen);
        
        // Check if NFT transfer already exists and update
        for (self.nft_transfers.items) |*transfer| {
            if (transfer.nft_id.equals(nft_id)) {
                transfer.sender_account_id = sender;
                transfer.receiver_account_id = receiver;
                transfer.is_approved = true;
                return self;
            }
        }
        
        // Add new approved NFT transfer
        try self.nft_transfers.append(NftTransfer.initApproved(nft_id, sender, receiver));
        
        return self;
    }
    
    // Get token transfers
    pub fn getTokenTransfers(self: *const Self) []const TokenTransfer {
        return self.token_transfers.items;
    }
    
    // Get NFT transfers
    pub fn getNftTransfers(self: *const Self) []const NftTransfer {
        return self.nft_transfers.items;
    }
    
    // Clear all token transfers
    pub fn clearTokenTransfers(self: *Self) HederaError!*Self {
        try requireNotFrozen(self.base.frozen);
        self.token_transfers.clearRetainingCapacity();
        return self;
    }
    
    // Clear all NFT transfers
    pub fn clearNftTransfers(self: *Self) HederaError!*Self {
        try requireNotFrozen(self.base.frozen);
        self.nft_transfers.clearRetainingCapacity();
        return self;
    }
    
    // Build token transfer lists for protobuf
    pub fn buildTokenTransferLists(self: *Self, allocator: std.mem.Allocator) !std.ArrayList(TokenTransferList) {
        var lists = std.ArrayList(TokenTransferList).init(allocator);
        errdefer {
            for (lists.items) |*list| {
                list.deinit();
            }
            lists.deinit();
        }
        
        // Sort token transfers by token ID and account ID
        std.mem.sort(TokenTransfer, self.token_transfers.items, {}, compareTokenTransfers);
        
        // Sort NFT transfers
        std.mem.sort(NftTransfer, self.nft_transfers.items, {}, compareNftTransfers);
        
        // Build transfer lists grouped by token ID
        var i: usize = 0;
        var j: usize = 0;
        
        while (i < self.token_transfers.items.len or j < self.nft_transfers.items.len) {
            if (i < self.token_transfers.items.len and j < self.nft_transfers.items.len) {
                const token_transfer = self.token_transfers.items[i];
                const nft_transfer = self.nft_transfers.items[j];
                
                // Check if we can add to existing list
                if (lists.items.len > 0) {
                    var last = &lists.items[lists.items.len - 1];
                    
                    if (last.token_id.equals(token_transfer.token_id)) {
                        try last.transfers.append(token_transfer);
                        i += 1;
                        continue;
                    }
                    
                    if (last.token_id.equals(nft_transfer.nft_id.token_id)) {
                        try last.nft_transfers.append(nft_transfer);
                        j += 1;
                        continue;
                    }
                }
                
                // Create new list
                const cmp = compareTokenIds(token_transfer.token_id, nft_transfer.nft_id.token_id);
                if (cmp == 0) {
                    var list = TokenTransferList.init(allocator, token_transfer.token_id);
                    list.expected_decimals = token_transfer.expected_decimals;
                    try list.transfers.append(token_transfer);
                    try list.nft_transfers.append(nft_transfer);
                    try lists.append(list);
                    i += 1;
                    j += 1;
                } else if (cmp < 0) {
                    var list = TokenTransferList.init(allocator, token_transfer.token_id);
                    list.expected_decimals = token_transfer.expected_decimals;
                    try list.transfers.append(token_transfer);
                    try lists.append(list);
                    i += 1;
                } else {
                    var list = TokenTransferList.init(allocator, nft_transfer.nft_id.token_id);
                    try list.nft_transfers.append(nft_transfer);
                    try lists.append(list);
                    j += 1;
                }
            } else if (i < self.token_transfers.items.len) {
                const token_transfer = self.token_transfers.items[i];
                
                // Check if we can add to existing list
                var found = false;
                for (lists.items) |*list| {
                    if (list.token_id.equals(token_transfer.token_id)) {
                        try list.transfers.append(token_transfer);
                        found = true;
                        break;
                    }
                }
                
                if (!found) {
                    var list = TokenTransferList.init(allocator, token_transfer.token_id);
                    list.expected_decimals = token_transfer.expected_decimals;
                    try list.transfers.append(token_transfer);
                    try lists.append(list);
                }
                
                i += 1;
            } else if (j < self.nft_transfers.items.len) {
                const nft_transfer = self.nft_transfers.items[j];
                
                // Check if we can add to existing list
                var found = false;
                for (lists.items) |*list| {
                    if (list.token_id.equals(nft_transfer.nft_id.token_id)) {
                        try list.nft_transfers.append(nft_transfer);
                        found = true;
                        break;
                    }
                }
                
                if (!found) {
                    var list = TokenTransferList.init(allocator, nft_transfer.nft_id.token_id);
                    try list.nft_transfers.append(nft_transfer);
                    try lists.append(list);
                }
                
                j += 1;
            }
        }
        
        return lists;
    }
    
    // Comparison functions for sorting
    fn compareTokenTransfers(context: void, a: TokenTransfer, b: TokenTransfer) bool {
        _ = context;
        const token_cmp = compareTokenIds(a.token_id, b.token_id);
        if (token_cmp != 0) {
            return token_cmp < 0;
        }
        return compareAccountIds(a.account_id, b.account_id) < 0;
    }
    
    fn compareNftTransfers(context: void, a: NftTransfer, b: NftTransfer) bool {
        _ = context;
        const sender_cmp = compareAccountIds(a.sender_account_id, b.sender_account_id);
        if (sender_cmp != 0) {
            return sender_cmp < 0;
        }
        
        const receiver_cmp = compareAccountIds(a.receiver_account_id, b.receiver_account_id);
        if (receiver_cmp != 0) {
            return receiver_cmp < 0;
        }
        
        return a.nft_id.serial_number < b.nft_id.serial_number;
    }
    
    fn compareTokenIds(a: TokenId, b: TokenId) i32 {
        if (a.shard != b.shard) {
            return if (a.shard < b.shard) -1 else 1;
        }
        if (a.realm != b.realm) {
            return if (a.realm < b.realm) -1 else 1;
        }
        if (a.token != b.token) {
            return if (a.token < b.token) -1 else 1;
        }
        return 0;
    }
    
    fn compareAccountIds(a: AccountId, b: AccountId) i32 {
        if (a.shard != b.shard) {
            return if (a.shard < b.shard) -1 else 1;
        }
        if (a.realm != b.realm) {
            return if (a.realm < b.realm) -1 else 1;
        }
        if (a.account != b.account) {
            return if (a.account < b.account) -1 else 1;
        }
        return 0;
    }
};
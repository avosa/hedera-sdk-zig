const std = @import("std");
const AccountId = @import("../core/id.zig").AccountId;
const TokenId = @import("../core/id.zig").TokenId;
const Hbar = @import("../core/hbar.zig").Hbar;
const NftTransfer = @import("transfer_transaction.zig").NftTransfer;

// AccountAmount represents an account and amount pair
pub const AccountAmount = struct {
    account_id: AccountId,
    amount: i64,
    is_approved: bool = false,
};

// Transfer represents an HBAR transfer
pub const Transfer = struct {
    account_id: AccountId,
    amount: Hbar,
    is_approved: bool,
    
    pub fn init(account_id: AccountId, amount: Hbar) Transfer {
        return Transfer{
            .account_id = account_id,
            .amount = amount,
            .is_approved = false,
        };
    }
};

// TokenTransfer represents a token transfer
pub const TokenTransfer = struct {
    token_id: TokenId,
    account_id: AccountId,
    amount: i64,
    expected_decimals: ?u32 = null,  // For Go SDK compatibility
    transfers: std.ArrayList(AccountAmount),
    nft_transfers: std.ArrayList(NftTransfer),  // For compatibility
    
    pub fn init(token_id: TokenId, account_id: AccountId, amount: i64) TokenTransfer {
        return TokenTransfer{
            .token_id = token_id,
            .account_id = account_id,
            .amount = amount,
            .expected_decimals = null,
            .transfers = std.ArrayList(AccountAmount).init(std.heap.page_allocator),
            .nft_transfers = std.ArrayList(NftTransfer).init(std.heap.page_allocator),
        };
    }
    
    pub fn deinit(self: *TokenTransfer) void {
        self.transfers.deinit();
        self.nft_transfers.deinit();
    }
    
    pub fn initWithAllocator(allocator: std.mem.Allocator, token_id: TokenId, account_id: AccountId, amount: i64) TokenTransfer {
        return TokenTransfer{
            .token_id = token_id,
            .account_id = account_id,
            .amount = amount,
            .transfers = std.ArrayList(AccountAmount).init(allocator),
            .nft_transfers = std.ArrayList(NftTransfer).init(allocator),
        };
    }
};
const std = @import("std");
const AccountId = @import("../core/id.zig").AccountId;
const TokenId = @import("../core/id.zig").TokenId;
const NftId = @import("../core/id.zig").NftId;
const Hbar = @import("../core/hbar.zig").Hbar;
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;

// Transfer alias for Go SDK compatibility  
pub const Transfer = HbarTransfer;

// HbarTransfer represents a transfer of HBAR between accounts
pub const HbarTransfer = struct {
    account_id: AccountId,
    amount: Hbar,
    is_approved: bool = false,
    
    pub fn init(account_id: AccountId, amount: Hbar) HbarTransfer {
        return HbarTransfer{
            .account_id = account_id,
            .amount = amount,
            .is_approved = false,
        };
    }
    
    pub fn initApproved(account_id: AccountId, amount: Hbar) HbarTransfer {
        return HbarTransfer{
            .account_id = account_id,
            .amount = amount,
            .is_approved = true,
        };
    }
};

// Import AccountAmount from transfer.zig to eliminate redundancy
pub const AccountAmount = @import("transfer.zig").AccountAmount;

// TokenTransfer represents a fungible token transfer
pub const TokenTransfer = struct {
    token_id: TokenId,
    account_id: AccountId,
    amount: i64,
    is_approved: bool = false,
    expected_decimals: ?u32 = null,
    transfers: std.ArrayList(AccountAmount),  // For compatibility
    
    pub fn init(token_id: TokenId, account_id: AccountId, amount: i64, allocator: std.mem.Allocator) TokenTransfer {
        return TokenTransfer{
            .token_id = token_id,
            .account_id = account_id,
            .amount = amount,
            .is_approved = false,
            .expected_decimals = null,
            .transfers = std.ArrayList(AccountAmount).init(allocator),
        };
    }
    
    pub fn deinit(self: *TokenTransfer) void {
        self.transfers.deinit();
    }
    
    pub fn initWithDecimals(token_id: TokenId, account_id: AccountId, amount: i64, decimals: u32, allocator: std.mem.Allocator) TokenTransfer {
        return TokenTransfer{
            .token_id = token_id,
            .account_id = account_id,
            .amount = amount,
            .is_approved = false,
            .expected_decimals = decimals,
            .transfers = std.ArrayList(AccountAmount).init(allocator),
        };
    }
    
    pub fn initApproved(token_id: TokenId, account_id: AccountId, amount: i64, allocator: std.mem.Allocator) TokenTransfer {
        return TokenTransfer{
            .token_id = token_id,
            .account_id = account_id,
            .amount = amount,
            .is_approved = true,
            .expected_decimals = null,
            .transfers = std.ArrayList(AccountAmount).init(allocator),
        };
    }
};

// NftTransfer represents an NFT transfer
pub const NftTransfer = struct {
    nft_id: NftId,
    sender_account_id: AccountId,
    receiver_account_id: AccountId,
    is_approved: bool = false,
    
    pub fn init(nft_id: NftId, sender: AccountId, receiver: AccountId) NftTransfer {
        return NftTransfer{
            .nft_id = nft_id,
            .sender_account_id = sender,
            .receiver_account_id = receiver,
            .is_approved = false,
        };
    }
    
    pub fn initApproved(nft_id: NftId, sender: AccountId, receiver: AccountId) NftTransfer {
        return NftTransfer{
            .nft_id = nft_id,
            .sender_account_id = sender,
            .receiver_account_id = receiver,
            .is_approved = true,
        };
    }
};

// TransferTransaction transfers HBAR and tokens between accounts
pub const TransferTransaction = struct {
    base: Transaction,
    hbar_transfers: std.ArrayList(HbarTransfer),
    token_transfers: std.ArrayList(TokenTransfer),
    nft_transfers: std.ArrayList(NftTransfer),
    token_decimals: std.AutoHashMap(TokenId, u32),
    
    pub fn init(allocator: std.mem.Allocator) TransferTransaction {
        return TransferTransaction{
            .base = Transaction.init(allocator),
            .hbar_transfers = std.ArrayList(HbarTransfer).init(allocator),
            .token_transfers = std.ArrayList(TokenTransfer).init(allocator),
            .nft_transfers = std.ArrayList(NftTransfer).init(allocator),
            .token_decimals = std.AutoHashMap(TokenId, u32).init(allocator),
        };
    }
    
    pub fn deinit(self: *TransferTransaction) void {
        self.base.deinit();
        self.hbar_transfers.deinit();
        self.token_transfers.deinit();
        self.nft_transfers.deinit();
        self.token_decimals.deinit();
    }
    
    // Includes an HBAR transfer in the transaction
    pub fn addHbarTransfer(self: *TransferTransaction, account_id: AccountId, amount: Hbar) !void {
        if (self.base.frozen) @panic("Transaction is frozen");
        
        // Check if account already has a transfer
        for (self.hbar_transfers.items) |*transfer| {
            if (transfer.account_id.equals(account_id)) {
                // Combine amounts
                transfer.amount = try transfer.amount.add(amount);
                return;
            }
        }
        
        // Create new transfer entry
        try self.hbar_transfers.append(HbarTransfer.init(account_id, amount));
    }
    
    // Includes an approved HBAR transfer in the transaction
    pub fn addApprovedHbarTransfer(self: *TransferTransaction, account_id: AccountId, amount: Hbar) !void {
        if (self.base.frozen) @panic("Transaction is frozen");
        
        // Check if account already has a transfer
        for (self.hbar_transfers.items) |*transfer| {
            if (transfer.account_id.equals(account_id)) {
                transfer.amount = try transfer.amount.add(amount);
                transfer.is_approved = true;
                return;
            }
        }
        
        // Create new approved transfer entry
        try self.hbar_transfers.append(HbarTransfer.initApproved(account_id, amount));
    }
    
    // Includes a token transfer in the transaction
    pub fn addTokenTransfer(self: *TransferTransaction, token_id: TokenId, account_id: AccountId, amount: i64) !void {
        if (self.base.frozen) @panic("Transaction is frozen");
        
        // Check if this token-account pair already has a transfer
        for (self.token_transfers.items) |*transfer| {
            if (transfer.token_id.equals(token_id) and transfer.account_id.equals(account_id)) {
                transfer.amount += amount;
                return;
            }
        }
        
        // Create new transfer entry
        try self.token_transfers.append(TokenTransfer.init(token_id, account_id, amount, self.base.allocator));
    }
    
    // Includes a token transfer in the transaction with decimals
    pub fn addTokenTransferWithDecimals(self: *TransferTransaction, token_id: TokenId, account_id: AccountId, amount: i64, decimals: u32) !void {
        if (self.base.frozen) @panic("Transaction is frozen");
        
        // Store expected decimals
        try self.token_decimals.put(token_id, decimals);
        
        // Check if this token-account pair already has a transfer
        for (self.token_transfers.items) |*transfer| {
            if (transfer.token_id.equals(token_id) and transfer.account_id.equals(account_id)) {
                transfer.amount += amount;
                transfer.expected_decimals = decimals;
                return;
            }
        }
        
        // Create new transfer entry
        try self.token_transfers.append(TokenTransfer.initWithDecimals(token_id, account_id, amount, decimals, self.base.allocator));
    }
    
    // Includes an approved token transfer in the transaction
    pub fn addApprovedTokenTransfer(self: *TransferTransaction, token_id: TokenId, account_id: AccountId, amount: i64) !void {
        if (self.base.frozen) @panic("Transaction is frozen");
        
        // Check if this token-account pair already has a transfer
        for (self.token_transfers.items) |*transfer| {
            if (transfer.token_id.equals(token_id) and transfer.account_id.equals(account_id)) {
                transfer.amount += amount;
                transfer.is_approved = true;
                return;
            }
        }
        
        // Create new approved transfer entry
        try self.token_transfers.append(TokenTransfer.initApproved(token_id, account_id, amount, self.base.allocator));
    }
    
    // Includes an NFT transfer in the transaction
    pub fn addNftTransfer(self: *TransferTransaction, nft_id: NftId, sender: AccountId, receiver: AccountId) !void {
        if (self.base.frozen) @panic("Transaction is frozen");
        
        // Check for duplicate (same NFT with same sender/receiver)
        for (self.nft_transfers.items) |transfer| {
            if (transfer.nft_id.equals(nft_id) and 
                transfer.sender_account_id.equals(sender) and 
                transfer.receiver_account_id.equals(receiver)) {
                return error.DuplicateNftTransfer;
            }
        }
        
        try self.nft_transfers.append(NftTransfer.init(nft_id, sender, receiver));
    }
    
    // Includes an approved NFT transfer in the transaction
    pub fn addApprovedNftTransfer(self: *TransferTransaction, nft_id: NftId, sender: AccountId, receiver: AccountId) !void {
        if (self.base.frozen) @panic("Transaction is frozen");
        
        // Check for duplicate (same NFT with same sender/receiver)
        for (self.nft_transfers.items) |transfer| {
            if (transfer.nft_id.equals(nft_id) and 
                transfer.sender_account_id.equals(sender) and 
                transfer.receiver_account_id.equals(receiver)) {
                return error.DuplicateNftTransfer;
            }
        }
        
        try self.nft_transfers.append(NftTransfer.initApproved(nft_id, sender, receiver));
    }
    
    // Validate transfers sum to zero
    fn validateTransfers(self: *TransferTransaction) !void {
        // Validate HBAR transfers
        var hbar_sum = Hbar.zero();
        for (self.hbar_transfers.items) |transfer| {
            hbar_sum = try hbar_sum.add(transfer.amount);
        }
        if (!hbar_sum.isZero()) {
            return error.UnbalancedHbarTransfers;
        }
        
        // Validate token transfers per token
        var token_sums = std.AutoHashMap(TokenId, i64).init(self.base.allocator);
        defer token_sums.deinit();
        
        for (self.token_transfers.items) |transfer| {
            const current = token_sums.get(transfer.token_id) orelse 0;
            try token_sums.put(transfer.token_id, current + transfer.amount);
        }
        
        var iter = token_sums.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.* != 0) {
                return error.UnbalancedTokenTransfers;
            }
        }
    }
    
    // Freeze the transaction
    pub fn freeze(self: *TransferTransaction) !void {
        try self.validateTransfers();
        try self.base.freeze();
    }
    
    // Freeze with client
    pub fn freezeWith(self: *TransferTransaction, client: *Client) !void {
        try self.validateTransfers();
        try self.base.freezeWith(client);
    }
    
    // Sign the transaction
    pub fn sign(self: *TransferTransaction, private_key: anytype) !void {
        try self.base.sign(private_key);
    }
    
    // Sign with operator
    pub fn signWithOperator(self: *TransferTransaction, client: *Client) !void {
        try self.base.signWithOperator(client);
    }
    
    // Execute the transaction
    pub fn execute(self: *TransferTransaction, client: *Client) !TransactionResponse {
        if (self.hbar_transfers.items.len == 0 and 
            self.token_transfers.items.len == 0 and 
            self.nft_transfers.items.len == 0) {
            return error.NoTransfersSpecified;
        }
        
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *TransferTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // TransactionBody message
        
        // Common transaction fields (1-5)
        try self.writeCommonFields(&writer);
        
        // cryptoTransfer = 14 (oneof data)
        var transfer_writer = ProtoWriter.init(self.base.allocator);
        defer transfer_writer.deinit();
        
        // transfers = 1 (TransferList)
        if (self.hbar_transfers.items.len > 0) {
            var transfer_list_writer = ProtoWriter.init(self.base.allocator);
            defer transfer_list_writer.deinit();
            
            // accountAmounts = 1 (repeated)
            for (self.hbar_transfers.items) |transfer| {
                var amount_writer = ProtoWriter.init(self.base.allocator);
                defer amount_writer.deinit();
                
                // accountID = 1
                var account_writer = ProtoWriter.init(self.base.allocator);
                defer account_writer.deinit();
                try account_writer.writeInt64(1, @intCast(transfer.account_id.shard));
                try account_writer.writeInt64(2, @intCast(transfer.account_id.realm));
                try account_writer.writeInt64(3, @intCast(transfer.account_id.account));
                const account_bytes = try account_writer.toOwnedSlice();
                defer self.base.allocator.free(account_bytes);
                try amount_writer.writeMessage(1, account_bytes);
                
                // amount = 2 (in tinybars, signed)
                try amount_writer.writeInt64(2, transfer.amount.toTinybars());
                
                // isApproval = 3
                if (transfer.is_approved) {
                    try amount_writer.writeBool(3, true);
                }
                
                const amount_bytes = try amount_writer.toOwnedSlice();
                defer self.base.allocator.free(amount_bytes);
                try transfer_list_writer.writeMessage(1, amount_bytes);
            }
            
            const transfer_list_bytes = try transfer_list_writer.toOwnedSlice();
            defer self.base.allocator.free(transfer_list_bytes);
            try transfer_writer.writeMessage(1, transfer_list_bytes);
        }
        
        // tokenTransfers = 2 (repeated TokenTransferList)
        if (self.token_transfers.items.len > 0) {
            // Group transfers by token
            var token_groups = std.AutoHashMap(TokenId, std.ArrayList(TokenTransfer)).init(self.base.allocator);
            defer {
                var iter = token_groups.iterator();
                while (iter.next()) |entry| {
                    entry.value_ptr.*.deinit();
                }
                token_groups.deinit();
            }
            
            for (self.token_transfers.items) |transfer| {
                var list = token_groups.get(transfer.token_id) orelse blk: {
                    const new_list = std.ArrayList(TokenTransfer).init(self.base.allocator);
                    try token_groups.put(transfer.token_id, new_list);
                    break :blk token_groups.get(transfer.token_id).?;
                };
                try list.append(transfer);
            }
            
            var token_iter = token_groups.iterator();
            while (token_iter.next()) |entry| {
                var token_list_writer = ProtoWriter.init(self.base.allocator);
                defer token_list_writer.deinit();
                
                // token = 1
                var token_writer = ProtoWriter.init(self.base.allocator);
                defer token_writer.deinit();
                try token_writer.writeInt64(1, @intCast(entry.key_ptr.*.shard));
                try token_writer.writeInt64(2, @intCast(entry.key_ptr.*.realm));
                try token_writer.writeInt64(3, @intCast(entry.key_ptr.*.account));
                const token_bytes = try token_writer.toOwnedSlice();
                defer self.base.allocator.free(token_bytes);
                try token_list_writer.writeMessage(1, token_bytes);
                
                // transfers = 2 (repeated)
                for (entry.value_ptr.*.items) |transfer| {
                    var amount_writer = ProtoWriter.init(self.base.allocator);
                    defer amount_writer.deinit();
                    
                    // accountID = 1
                    var account_writer = ProtoWriter.init(self.base.allocator);
                    defer account_writer.deinit();
                    try account_writer.writeInt64(1, @intCast(transfer.account_id.shard));
                    try account_writer.writeInt64(2, @intCast(transfer.account_id.realm));
                    try account_writer.writeInt64(3, @intCast(transfer.account_id.account));
                    const account_bytes = try account_writer.toOwnedSlice();
                    defer self.base.allocator.free(account_bytes);
                    try amount_writer.writeMessage(1, account_bytes);
                    
                    // amount = 2
                    try amount_writer.writeInt64(2, transfer.amount);
                    
                    // isApproval = 3
                    if (transfer.is_approved) {
                        try amount_writer.writeBool(3, true);
                    }
                    
                    const amount_bytes = try amount_writer.toOwnedSlice();
                    defer self.base.allocator.free(amount_bytes);
                    try token_list_writer.writeMessage(2, amount_bytes);
                }
                
                // expected_decimals = 3
                if (self.token_decimals.get(entry.key_ptr.*)) |decimals| {
                    try token_list_writer.writeUint32(3, decimals);
                }
                
                const token_list_bytes = try token_list_writer.toOwnedSlice();
                defer self.base.allocator.free(token_list_bytes);
                try transfer_writer.writeMessage(2, token_list_bytes);
            }
        }
        
        // tokenTransferLists = 3 (repeated NftTransfer)
        if (self.nft_transfers.items.len > 0) {
            // Group NFT transfers by token
            var nft_groups = std.AutoHashMap(TokenId, std.ArrayList(NftTransfer)).init(self.base.allocator);
            defer {
                var iter = nft_groups.iterator();
                while (iter.next()) |entry| {
                    entry.value_ptr.*.deinit();
                }
                nft_groups.deinit();
            }
            
            for (self.nft_transfers.items) |transfer| {
                const token_id = transfer.nft_id.token_id;
                var list = nft_groups.get(token_id) orelse blk: {
                    const new_list = std.ArrayList(NftTransfer).init(self.base.allocator);
                    try nft_groups.put(token_id, new_list);
                    break :blk nft_groups.get(token_id).?;
                };
                try list.append(transfer);
            }
            
            var nft_iter = nft_groups.iterator();
            while (nft_iter.next()) |entry| {
                var nft_list_writer = ProtoWriter.init(self.base.allocator);
                defer nft_list_writer.deinit();
                
                // token = 1
                var token_writer = ProtoWriter.init(self.base.allocator);
                defer token_writer.deinit();
                try token_writer.writeInt64(1, @intCast(entry.key_ptr.*.shard));
                try token_writer.writeInt64(2, @intCast(entry.key_ptr.*.realm));
                try token_writer.writeInt64(3, @intCast(entry.key_ptr.*.account));
                const token_bytes = try token_writer.toOwnedSlice();
                defer self.base.allocator.free(token_bytes);
                try nft_list_writer.writeMessage(1, token_bytes);
                
                // nftTransfers = 4 (repeated)
                for (entry.value_ptr.*.items) |transfer| {
                    var nft_transfer_writer = ProtoWriter.init(self.base.allocator);
                    defer nft_transfer_writer.deinit();
                    
                    // senderAccountID = 1
                    var sender_writer = ProtoWriter.init(self.base.allocator);
                    defer sender_writer.deinit();
                    try sender_writer.writeInt64(1, @intCast(transfer.sender_account_id.shard));
                    try sender_writer.writeInt64(2, @intCast(transfer.sender_account_id.realm));
                    try sender_writer.writeInt64(3, @intCast(transfer.sender_account_id.account));
                    const sender_bytes = try sender_writer.toOwnedSlice();
                    defer self.base.allocator.free(sender_bytes);
                    try nft_transfer_writer.writeMessage(1, sender_bytes);
                    
                    // receiverAccountID = 2
                    var receiver_writer = ProtoWriter.init(self.base.allocator);
                    defer receiver_writer.deinit();
                    try receiver_writer.writeInt64(1, @intCast(transfer.receiver_account_id.shard));
                    try receiver_writer.writeInt64(2, @intCast(transfer.receiver_account_id.realm));
                    try receiver_writer.writeInt64(3, @intCast(transfer.receiver_account_id.account));
                    const receiver_bytes = try receiver_writer.toOwnedSlice();
                    defer self.base.allocator.free(receiver_bytes);
                    try nft_transfer_writer.writeMessage(2, receiver_bytes);
                    
                    // serialNumber = 3
                    try nft_transfer_writer.writeInt64(3, transfer.nft_id.serial_number);
                    
                    // isApproval = 4
                    if (transfer.is_approved) {
                        try nft_transfer_writer.writeBool(4, true);
                    }
                    
                    const nft_transfer_bytes = try nft_transfer_writer.toOwnedSlice();
                    defer self.base.allocator.free(nft_transfer_bytes);
                    try nft_list_writer.writeMessage(4, nft_transfer_bytes);
                }
                
                const nft_list_bytes = try nft_list_writer.toOwnedSlice();
                defer self.base.allocator.free(nft_list_bytes);
                try transfer_writer.writeMessage(3, nft_list_bytes);
            }
        }
        
        const transfer_bytes = try transfer_writer.toOwnedSlice();
        defer self.base.allocator.free(transfer_bytes);
        try writer.writeMessage(14, transfer_bytes);
        
        return writer.toOwnedSlice();
    }
    
    fn writeCommonFields(self: *TransferTransaction, writer: *ProtoWriter) !void {
        // transactionID = 1
        if (self.base.transaction_id) |tx_id| {
            var tx_id_writer = ProtoWriter.init(self.base.allocator);
            defer tx_id_writer.deinit();
            
            var timestamp_writer = ProtoWriter.init(self.base.allocator);
            defer timestamp_writer.deinit();
            try timestamp_writer.writeInt64(1, tx_id.valid_start.seconds);
            try timestamp_writer.writeInt32(2, tx_id.valid_start.nanos);
            const timestamp_bytes = try timestamp_writer.toOwnedSlice();
            defer self.base.allocator.free(timestamp_bytes);
            try tx_id_writer.writeMessage(1, timestamp_bytes);
            
            var account_writer = ProtoWriter.init(self.base.allocator);
            defer account_writer.deinit();
            try account_writer.writeInt64(1, @intCast(tx_id.account_id.shard));
            try account_writer.writeInt64(2, @intCast(tx_id.account_id.realm));
            try account_writer.writeInt64(3, @intCast(tx_id.account_id.account));
            const account_bytes = try account_writer.toOwnedSlice();
            defer self.base.allocator.free(account_bytes);
            try tx_id_writer.writeMessage(2, account_bytes);
            
            const tx_id_bytes = try tx_id_writer.toOwnedSlice();
            defer self.base.allocator.free(tx_id_bytes);
            try writer.writeMessage(1, tx_id_bytes);
        }
        
        // nodeAccountID = 2
        if (self.base.node_account_ids.items.len > 0) {
            var node_writer = ProtoWriter.init(self.base.allocator);
            defer node_writer.deinit();
            const node = self.base.node_account_ids.items[0];
            try node_writer.writeInt64(1, @intCast(node.shard));
            try node_writer.writeInt64(2, @intCast(node.realm));
            try node_writer.writeInt64(3, @intCast(node.account));
            const node_bytes = try node_writer.toOwnedSlice();
            defer self.base.allocator.free(node_bytes);
            try writer.writeMessage(2, node_bytes);
        }
        
        // transactionFee = 3
        if (self.base.max_transaction_fee) |fee| {
            try writer.writeUint64(3, @intCast(fee.toTinybars()));
        }
        
        // transactionValidDuration = 4
        var duration_writer = ProtoWriter.init(self.base.allocator);
        defer duration_writer.deinit();
        try duration_writer.writeInt64(1, self.base.transaction_valid_duration.seconds);
        const duration_bytes = try duration_writer.toOwnedSlice();
        defer self.base.allocator.free(duration_bytes);
        try writer.writeMessage(4, duration_bytes);
        
        // memo = 5
        if (self.base.transaction_memo.len > 0) {
            try writer.writeString(5, self.base.transaction_memo);
        }
    }
};
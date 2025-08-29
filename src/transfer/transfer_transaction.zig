const std = @import("std");
const AccountId = @import("../core/id.zig").AccountId;
const TokenId = @import("../core/id.zig").TokenId;
const NftId = @import("../core/id.zig").NftId;
const Hbar = @import("../core/hbar.zig").Hbar;
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction_response.zig").TransactionResponse;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/writer.zig").ProtoWriter;
const Duration = @import("../core/duration.zig").Duration;
const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;
const errors = @import("../core/errors.zig");
const HederaError = errors.HederaError;
  
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
    
    // Parse HbarTransfer from protobuf bytes
    pub fn fromProtobuf(allocator: std.mem.Allocator, bytes: []const u8) !HbarTransfer {
        var reader = @import("../protobuf/encoding.zig").ProtoReader.init(bytes);
        
        var result = HbarTransfer{
            .account_id = AccountId{ .shard = 0, .realm = 0, .account = 0 },
            .amount = Hbar{ .tinybars = 0 },
            .is_approved = false,
        };
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            switch (tag.field_number) {
                1 => {
                    // accountID
                    const account_bytes = try reader.readMessage();
                    result.account_id = try AccountId.fromProtobufBytes(allocator, account_bytes);
                },
                2 => {
                    // amount
                    const amount = try reader.readInt64();
                    result.amount = try Hbar.fromTinybars(amount);
                },
                3 => {
                    // is_approval
                    result.is_approved = try reader.readBool();
                },
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return result;
    }
};

// AccountAmount represents an account and amount pair
pub const AccountAmount = struct {
    account_id: AccountId,
    amount: i64,
    is_approved: bool = false,
};

// TokenTransfer represents a fungible token transfer
pub const TokenTransfer = struct {
    token_id: TokenId,
    account_id: AccountId,
    amount: i64,
    is_approved: bool = false,
    expected_decimals: ?u32 = null,
    transfers: std.ArrayList(AccountAmount),  
    
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
    
    pub fn fromProtobuf(allocator: std.mem.Allocator, data: []const u8) !TokenTransfer {
        var reader = ProtoReader.init(data);
        var token_id: ?TokenId = null;
        var transfers = std.ArrayList(AccountAmount).init(allocator);
        var expected_decimals: ?u32 = null;
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            switch (tag.field_number) {
                1 => {
                    const token_bytes = try reader.readBytes();
                    var token_reader = ProtoReader.init(token_bytes);
                    var shard: u64 = 0;
                    var realm: u64 = 0;
                    var num: u64 = 0;
                    
                    while (token_reader.hasMore()) {
                        const token_tag = try token_reader.readTag();
                        switch (token_tag.field_number) {
                            1 => shard = @intCast(try token_reader.readInt64()),
                            2 => realm = @intCast(try token_reader.readInt64()),
                            3 => num = @intCast(try token_reader.readInt64()),
                            else => try token_reader.skipField(token_tag.wire_type),
                        }
                    }
                    
                    token_id = TokenId{
                        .entity = .{
                            .shard = shard,
                            .realm = realm,
                            .num = num,
                        },
                    };
                },
                2 => {
                    const transfer_bytes = try reader.readBytes();
                    var transfer_reader = ProtoReader.init(transfer_bytes);
                    
                    while (transfer_reader.hasMore()) {
                        const transfer_tag = try transfer_reader.readTag();
                        switch (transfer_tag.field_number) {
                            1 => {
                                const account_bytes = try transfer_reader.readBytes();
                                var account_reader = ProtoReader.init(account_bytes);
                                var account_shard: u64 = 0;
                                var account_realm: u64 = 0;
                                var account_num: u64 = 0;
                                
                                while (account_reader.hasMore()) {
                                    const account_tag = try account_reader.readTag();
                                    switch (account_tag.field_number) {
                                        1 => account_shard = @intCast(try account_reader.readInt64()),
                                        2 => account_realm = @intCast(try account_reader.readInt64()),
                                        3 => account_num = @intCast(try account_reader.readInt64()),
                                        else => try account_reader.skipField(account_tag.wire_type),
                                    }
                                }
                                
                                const amount = try transfer_reader.readInt64();
                                try transfers.append(AccountAmount{
                                    .account_id = AccountId{
                                        .shard = account_shard,
                                        .realm = account_realm,
                                        .account = account_num,
                                        .alias_key = null,
                                        .alias_evm_address = null,
                                        .checksum = null,
                                    },
                                    .amount = amount,
                                    .is_approved = false,
                                });
                            },
                            2 => {
                                const amount = try transfer_reader.readInt64();
                                if (transfers.items.len > 0) {
                                    transfers.items[transfers.items.len - 1].amount = amount;
                                }
                            },
                            else => try transfer_reader.skipField(transfer_tag.wire_type),
                        }
                    }
                },
                3 => expected_decimals = @intCast(try reader.readUint32()),
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        const first_transfer = if (transfers.items.len > 0) transfers.items[0] else AccountAmount{
            .account_id = AccountId.init(0, 0, 0),
            .amount = 0,
            .is_approved = false,
        };
        
        return TokenTransfer{
            .token_id = token_id orelse TokenId.init(0, 0, 0),
            .account_id = first_transfer.account_id,
            .amount = first_transfer.amount,
            .is_approved = false,
            .expected_decimals = expected_decimals,
            .transfers = transfers,
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
    
    pub fn toProtobuf(self: *const TokenTransfer, allocator: std.mem.Allocator) ![]u8 {
        var writer = ProtoWriter.init(allocator);
        defer writer.deinit();
        
        // accountID = 1
        const account_bytes = try self.account_id.toProtobuf(allocator);
        defer allocator.free(account_bytes);
        try writer.writeMessage(1, account_bytes);
        
        // amount = 2
        try writer.writeInt64(2, self.amount);
        
        // isApproval = 3
        if (self.is_approved) {
            try writer.writeBool(3, self.is_approved);
        }
        
        return writer.toOwnedSlice();
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
    
    pub fn fromProtobuf(allocator: std.mem.Allocator, data: []const u8) !NftTransfer {
        var reader = ProtoReader.init(data);
        var transfer = NftTransfer{
            .nft_id = NftId.init(TokenId.init(0, 0, 0), 0),
            .sender_account_id = AccountId.init(0, 0, 0),
            .receiver_account_id = AccountId.init(0, 0, 0),
            .is_approved = false,
        };
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            switch (tag.field_number) {
                1 => {
                    const sender_bytes = try reader.readBytes();
                    transfer.sender_account_id = try AccountId.fromProtobuf(allocator, sender_bytes);
                },
                2 => {
                    const receiver_bytes = try reader.readBytes();
                    transfer.receiver_account_id = try AccountId.fromProtobuf(allocator, receiver_bytes);
                },
                3 => {
                    const token_bytes = try reader.readBytes();
                    const token_id = try TokenId.fromProtobuf(allocator, token_bytes);
                    transfer.nft_id.token_id = token_id;
                },
                4 => transfer.nft_id.serial_number = @intCast(try reader.readInt64()),
                5 => transfer.is_approved = try reader.readBool(),
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return transfer;
    }
    
    pub fn toProtobuf(self: *const NftTransfer, allocator: std.mem.Allocator) ![]u8 {
        var writer = ProtoWriter.init(allocator);
        defer writer.deinit();
        
        // senderAccountID = 1
        const sender_bytes = try self.sender_account_id.toProtobuf(allocator);
        defer allocator.free(sender_bytes);
        try writer.writeMessage(1, sender_bytes);
        
        // receiverAccountID = 2
        const receiver_bytes = try self.receiver_account_id.toProtobuf(allocator);
        defer allocator.free(receiver_bytes);
        try writer.writeMessage(2, receiver_bytes);
        
        // serialNumber = 3
        try writer.writeInt64(3, @intCast(self.nft_id.serial_number));
        
        // isApproval = 4
        if (self.is_approved) {
            try writer.writeBool(4, self.is_approved);
        }
        
        return writer.toOwnedSlice();
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
        var transfer = TransferTransaction{
            .base = Transaction.init(allocator),
            .hbar_transfers = std.ArrayList(HbarTransfer).init(allocator),
            .token_transfers = std.ArrayList(TokenTransfer).init(allocator),
            .nft_transfers = std.ArrayList(NftTransfer).init(allocator),
            .token_decimals = std.AutoHashMap(TokenId, u32).init(allocator),
        };
        // Set the function pointer for building transaction body
        transfer.base.buildTransactionBodyForNode = buildTransactionBodyForNode;
        return transfer;
    }
    
    pub fn deinit(self: *TransferTransaction) void {
        self.base.deinit();
        self.hbar_transfers.deinit();
        self.token_transfers.deinit();
        self.nft_transfers.deinit();
        self.token_decimals.deinit();
    }
    
    // Add HBAR transfer to the transaction
    pub fn addHbarTransfer(self: *TransferTransaction, account_id: AccountId, amount: Hbar) HederaError!*TransferTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        
        // Check if account already has a transfer
        for (self.hbar_transfers.items) |*transfer| {
            if (transfer.account_id.equals(account_id)) {
                // Combine amounts
                transfer.amount = try transfer.amount.add(amount);
                return self;
            }
        }
        
        // Create new transfer entry
        try errors.handleAppendError(&self.hbar_transfers, HbarTransfer.init(account_id, amount));
        return self;
    }
    
    // Add approved HBAR transfer to the transaction
    pub fn addApprovedHbarTransfer(self: *TransferTransaction, account_id: AccountId, amount: Hbar) HederaError!*TransferTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        
        // Check if account already has a transfer
        for (self.hbar_transfers.items) |*transfer| {
            if (transfer.account_id.equals(account_id)) {
                transfer.amount = try transfer.amount.add(amount);
                transfer.is_approved = true;
                return self;
            }
        }
        
        // Create new approved transfer entry
        try errors.handleAppendError(&self.hbar_transfers, HbarTransfer.initApproved(account_id, amount));
        return self;
    }
    
    // Add token transfer to the transaction
    pub fn addTokenTransfer(self: *TransferTransaction, token_id: TokenId, account_id: AccountId, amount: i64) HederaError!*TransferTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        
        // Check if this token-account pair already has a transfer
        for (self.token_transfers.items) |*transfer| {
            if (transfer.token_id.equals(token_id) and transfer.account_id.equals(account_id)) {
                transfer.amount += amount;
                return self;
            }
        }
        
        // Create new transfer entry
        try errors.handleAppendError(&self.token_transfers, TokenTransfer.init(token_id, account_id, amount, self.base.allocator));
        return self;
    }
    
    // Add token transfer with decimals to the transaction
    pub fn addTokenTransferWithDecimals(self: *TransferTransaction, token_id: TokenId, account_id: AccountId, amount: i64, decimals: u32) HederaError!*TransferTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        
        // Store expected decimals
        self.token_decimals.put(token_id, decimals) catch return error.InvalidParameter;
        
        // Check if this token-account pair already has a transfer
        for (self.token_transfers.items) |*transfer| {
            if (transfer.token_id.equals(token_id) and transfer.account_id.equals(account_id)) {
                transfer.amount += amount;
                transfer.expected_decimals = decimals;
                return self;
            }
        }
        
        // Create new transfer entry
        try errors.handleAppendError(&self.token_transfers, TokenTransfer.initWithDecimals(token_id, account_id, amount, decimals, self.base.allocator));
        return self;
    }
    
    // Add approved token transfer to the transaction
    pub fn addApprovedTokenTransfer(self: *TransferTransaction, token_id: TokenId, account_id: AccountId, amount: i64) HederaError!*TransferTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        
        // Check if this token-account pair already has a transfer
        for (self.token_transfers.items) |*transfer| {
            if (transfer.token_id.equals(token_id) and transfer.account_id.equals(account_id)) {
                transfer.amount += amount;
                transfer.is_approved = true;
                return self;
            }
        }
        
        // Create new approved transfer entry
        try errors.handleAppendError(&self.token_transfers, TokenTransfer.initApproved(token_id, account_id, amount, self.base.allocator));
        return self;
    }
    
    // Add NFT transfer to the transaction
    pub fn addNftTransfer(self: *TransferTransaction, nft_id: NftId, sender: AccountId, receiver: AccountId) HederaError!*TransferTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        
        // Check for duplicate (same NFT with same sender/receiver)
        for (self.nft_transfers.items) |transfer| {
            if (transfer.nft_id.equals(nft_id) and 
                transfer.sender_account_id.equals(sender) and 
                transfer.receiver_account_id.equals(receiver)) {
                return error.InvalidParameter;
            }
        }
        
        try errors.handleAppendError(&self.nft_transfers, NftTransfer.init(nft_id, sender, receiver));
        return self;
    }
    
    // Add approved NFT transfer to the transaction
    pub fn addApprovedNftTransfer(self: *TransferTransaction, nft_id: NftId, sender: AccountId, receiver: AccountId) HederaError!*TransferTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        
        // Check for duplicate (same NFT with same sender/receiver)
        for (self.nft_transfers.items) |transfer| {
            if (transfer.nft_id.equals(nft_id) and 
                transfer.sender_account_id.equals(sender) and 
                transfer.receiver_account_id.equals(receiver)) {
                return error.InvalidParameter;
            }
        }
        
        try errors.handleAppendError(&self.nft_transfers, NftTransfer.initApproved(nft_id, sender, receiver));
        return self;
    }
    
    // Validate transfers sum to zero
    fn validateTransfers(self: *TransferTransaction) HederaError!void {
        // Validate HBAR transfers
        var hbar_sum = Hbar.zero();
        for (self.hbar_transfers.items) |transfer| {
            hbar_sum = try hbar_sum.add(transfer.amount);
        }
        if (!hbar_sum.isZero()) {
            return error.InvalidParameter;
        }
        
        // Validate token transfers per token
        var token_sums = std.AutoHashMap(TokenId, i64).init(self.base.allocator);
        defer token_sums.deinit();
        
        for (self.token_transfers.items) |transfer| {
            const current = token_sums.get(transfer.token_id) orelse 0;
            token_sums.put(transfer.token_id, current + transfer.amount) catch return error.InvalidParameter;
        }
        
        var iter = token_sums.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.* != 0) {
                return error.InvalidParameter;
            }
        }
    }
    
    // Freeze the transaction
    pub fn freeze(self: *TransferTransaction) HederaError!*TransferTransaction {
        try self.validateTransfers();
        self.base.freeze() catch return error.InvalidParameter;
        return self;
    }
    
    // Set transaction ID
    pub fn setTransactionId(self: *TransferTransaction, transaction_id: TransactionId) !*TransferTransaction {
        _ = try self.base.setTransactionId(transaction_id);
        return self;
    }
    
    pub fn setTransactionMemo(self: *TransferTransaction, memo: []const u8) !*TransferTransaction {
        _ = try self.base.setTransactionMemo(memo);
        return self;
    }
    
    pub fn setMaxTransactionFee(self: *TransferTransaction, fee: Hbar) !*TransferTransaction {
        _ = try self.base.setMaxTransactionFee(fee);
        return self;
    }
    
    pub fn setTransactionValidDuration(self: *TransferTransaction, duration: Duration) !*TransferTransaction {
        _ = try self.base.setTransactionValidDuration(duration);
        return self;
    }
    
    pub fn setNodeAccountIds(self: *TransferTransaction, nodes: []const AccountId) !*TransferTransaction {
        _ = try self.base.setNodeAccountIds(nodes);
        return self;
    }
    
    pub fn setGrpcDeadline(self: *TransferTransaction, deadline: Duration) !*TransferTransaction {
        _ = try self.base.setGrpcDeadline(deadline);
        return self;
    }
    
    pub fn setRegenerateTransactionId(self: *TransferTransaction, regenerate: bool) !*TransferTransaction {
        _ = try self.base.setRegenerateTransactionId(regenerate);
        return self;
    }
    
    pub fn freezeWith(self: *TransferTransaction, client: *Client) HederaError!*TransferTransaction {
        try self.validateTransfers();
        _ = self.base.freezeWith(client) catch return error.InvalidParameter;
        return self;
    }
    
    // Sign the transaction
    pub fn sign(self: *TransferTransaction, private_key: anytype) !*TransferTransaction {
        _ = self.base.sign(private_key) catch return error.InvalidParameter;
        return self;
    }
    
    // Sign with operator
    pub fn signWithOperator(self: *TransferTransaction, client: *Client) HederaError!*TransferTransaction {
        self.base.signWithOperator(client) catch return error.InvalidParameter;
        return self;
    }
    
    // Execute the transaction
    pub fn execute(self: *TransferTransaction, client: *Client) HederaError!TransactionResponse {
        if (self.hbar_transfers.items.len == 0 and 
            self.token_transfers.items.len == 0 and 
            self.nft_transfers.items.len == 0) {
            return error.InvalidParameter;
        }
        
        // Check if any transfer involves an EVM address (hollow account creation)
        var has_evm_address = false;
        for (self.hbar_transfers.items) |transfer| {
            if (transfer.account_id.alias_evm_address != null) {
                has_evm_address = true;
                break;
            }
        }
        
        // Execute the base transaction
        const base_response = self.base.execute(client) catch return error.InvalidParameter;
        
        // Create a proper TransactionResponse with all fields
        var response = try TransactionResponse.init(
            self.base.allocator, 
            base_response.transaction_id,
            base_response.node_account_id,
            base_response.hash orelse &[_]u8{},
        );
        
        // Enable child receipts for EVM address transfers (hollow account creation)
        if (has_evm_address) {
            _ = try response.setIncludeChildReceipts(true);
        }
        
        return response;
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
                try token_writer.writeInt64(1, @intCast(entry.key_ptr.*.entity.shard));
                try token_writer.writeInt64(2, @intCast(entry.key_ptr.*.entity.realm));
                try token_writer.writeInt64(3, @intCast(entry.key_ptr.*.entity.num));
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
                    try token_list_writer.writeUint32Field(3, decimals);
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
                try token_writer.writeInt64(1, @intCast(entry.key_ptr.*.entity.shard));
                try token_writer.writeInt64(2, @intCast(entry.key_ptr.*.entity.realm));
                try token_writer.writeInt64(3, @intCast(entry.key_ptr.*.entity.num));
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
                    try nft_transfer_writer.writeInt64(3, @intCast(transfer.nft_id.serial_number));
                    
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
        try duration_writer.writeInt64(1, self.base.transaction_valid_duration.toSeconds());
        const duration_bytes = try duration_writer.toOwnedSlice();
        defer self.base.allocator.free(duration_bytes);
        try writer.writeMessage(4, duration_bytes);
        
        // memo = 5
        if (self.base.transaction_memo.len > 0) {
            try writer.writeStringField(5, self.base.transaction_memo);
        }
    }
    
    // Wrapper function for Transaction base class function pointer
    pub fn buildTransactionBodyForNode(transaction: *Transaction, node: AccountId) anyerror![]u8 {
        const self = @as(*TransferTransaction, @fieldParentPtr("base", transaction));
        _ = node; // Node parameter not needed for transfer transactions
        return self.buildTransactionBody();
    }
};



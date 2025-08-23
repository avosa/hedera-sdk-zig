const std = @import("std");
const errors = @import("../core/errors.zig");
const AccountId = @import("../core/id.zig").AccountId;
const TokenId = @import("../core/id.zig").TokenId;
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;

// Maximum number of NFT serial numbers that can be wiped in a single transaction
pub const MAX_NFT_WIPE_BATCH_SIZE: usize = 10;

// TokenWipeTransaction wipes tokens from an account's balance
pub const TokenWipeTransaction = struct {
    base: Transaction,
    token_id: ?TokenId,
    account_id: ?AccountId,
    amount: u64,
    serials: std.ArrayList(i64),
    serial_numbers: std.ArrayList(i64),
    
    pub fn init(allocator: std.mem.Allocator) TokenWipeTransaction {
        return TokenWipeTransaction{
            .base = Transaction.init(allocator),
            .token_id = null,
            .account_id = null,
            .amount = 0,
            .serials = std.ArrayList(i64).init(allocator),
            .serial_numbers = std.ArrayList(i64).init(allocator),
        };
    }
    
    pub fn deinit(self: *TokenWipeTransaction) void {
        self.base.deinit();
        self.serials.deinit();
        self.serial_numbers.deinit();
    }
    
    // Set the token to wipe
    pub fn setTokenId(self: *TokenWipeTransaction, token_id: TokenId) errors.HederaError!*TokenWipeTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        self.token_id = token_id;
        return self;
    }
    
    // Set the account to wipe from
    pub fn setAccountId(self: *TokenWipeTransaction, account_id: AccountId) errors.HederaError!*TokenWipeTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        self.account_id = account_id;
        return self;
    }
    
    // Set amount to wipe (for fungible tokens)
    pub fn setAmount(self: *TokenWipeTransaction, amount: u64) errors.HederaError!*TokenWipeTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        
        if (self.serial_numbers.items.len > 0) {
            return errors.HederaError.InvalidParameter;
        }
        
        if (amount == 0) {
            return errors.HederaError.InvalidParameter;
        }
        
        if (amount > std.math.maxInt(i64)) {
            return errors.HederaError.InvalidParameter;
        }
        
        self.amount = amount;
        return self;
    }
    
    // Includes a serial number for NFT wiping
    pub fn addSerialNumber(self: *TokenWipeTransaction, serial_number: i64) errors.HederaError!*TokenWipeTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        
        if (self.amount > 0) {
            return errors.HederaError.InvalidParameter;
        }
        
        if (serial_number <= 0) {
            return errors.HederaError.InvalidParameter;
        }
        
        if (self.serial_numbers.items.len >= MAX_NFT_WIPE_BATCH_SIZE) {
            return errors.HederaError.InvalidParameter;
        }
        
        // Check for duplicates
        for (self.serial_numbers.items) |existing| {
            if (existing == serial_number) {
                return errors.HederaError.InvalidParameter;
            }
        }
        
        try errors.handleAppendError(&self.serial_numbers, serial_number);
        return self;
    }
    
    // Set serial numbers for batch NFT wiping
    pub fn setSerialNumbers(self: *TokenWipeTransaction, serial_numbers: []const i64) errors.HederaError!*TokenWipeTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        
        if (self.amount > 0) {
            return errors.HederaError.InvalidParameter;
        }
        
        if (serial_numbers.len > MAX_NFT_WIPE_BATCH_SIZE) {
            return errors.HederaError.InvalidParameter;
        }
        
        self.serial_numbers.clearRetainingCapacity();
        
        for (serial_numbers) |serial_number| {
            if (serial_number <= 0) {
                return errors.HederaError.InvalidParameter;
            }
            
            // Check for duplicates
            for (self.serial_numbers.items) |existing| {
                if (existing == serial_number) {
                    return errors.HederaError.InvalidParameter;
                }
            }
            
            try errors.handleAppendError(&self.serial_numbers, serial_number);
        }
        return self;
    }
    
    // Add serial (alias for AddSerialNumber)
    pub fn addSerial(self: *TokenWipeTransaction, serial: i64) errors.HederaError!*TokenWipeTransaction {
        return try self.addSerialNumber(serial);
    }
    
    // Getter methods for uniformity with Go SDK
    pub fn getTokenId(self: *const TokenWipeTransaction) ?TokenId {
        return self.token_id;
    }
    
    pub fn getAccountId(self: *const TokenWipeTransaction) ?AccountId {
        return self.account_id;
    }
    
    pub fn getAmount(self: *const TokenWipeTransaction) u64 {
        return self.amount;
    }
    
    pub fn getSerialNumbers(self: *const TokenWipeTransaction) []const i64 {
        return self.serial_numbers.items;
    }
    
    // Execute the transaction
    pub fn execute(self: *TokenWipeTransaction, client: *Client) !TransactionResponse {
        if (self.token_id == null) {
            return error.TokenIdRequired;
        }
        
        if (self.account_id == null) {
            return error.AccountIdRequired;
        }
        
        if (self.amount == 0 and self.serial_numbers.items.len == 0) {
            return error.NothingToWipe;
        }
        
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *TokenWipeTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Common transaction fields
        try self.writeCommonFields(&writer);
        
        // tokenWipe = 39 (oneof data)
        var wipe_writer = ProtoWriter.init(self.base.allocator);
        defer wipe_writer.deinit();
        
        // token = 1
        if (self.token_id) |token| {
            var token_writer = ProtoWriter.init(self.base.allocator);
            defer token_writer.deinit();
            try token_writer.writeInt64(1, @intCast(token.shard));
            try token_writer.writeInt64(2, @intCast(token.realm));
            try token_writer.writeInt64(3, @intCast(token.num));
            const token_bytes = try token_writer.toOwnedSlice();
            defer self.base.allocator.free(token_bytes);
            try wipe_writer.writeMessage(1, token_bytes);
        }
        
        // account = 2
        if (self.account_id) |account| {
            var account_writer = ProtoWriter.init(self.base.allocator);
            defer account_writer.deinit();
            try account_writer.writeInt64(1, @intCast(account.shard));
            try account_writer.writeInt64(2, @intCast(account.realm));
            try account_writer.writeInt64(3, @intCast(account.account));
            const account_bytes = try account_writer.toOwnedSlice();
            defer self.base.allocator.free(account_bytes);
            try wipe_writer.writeMessage(2, account_bytes);
        }
        
        // amount = 3 (for fungible tokens)
        if (self.amount > 0) {
            try wipe_writer.writeUint64(3, self.amount);
        }
        
        // serialNumbers = 4 (repeated, for NFTs)
        for (self.serial_numbers.items) |serial_number| {
            try wipe_writer.writeInt64(4, serial_number);
        }
        
        const wipe_bytes = try wipe_writer.toOwnedSlice();
        defer self.base.allocator.free(wipe_bytes);
        try writer.writeMessage(39, wipe_bytes);
        
        return writer.toOwnedSlice();
    }
    
    fn writeCommonFields(self: *TokenWipeTransaction, writer: *ProtoWriter) !void {
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
            
            if (tx_id.nonce) |n| {
                try tx_id_writer.writeInt32(4, @intCast(n));
            }
            
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

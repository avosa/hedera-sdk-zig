const std = @import("std");
const TokenId = @import("../core/id.zig").TokenId;
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;

// Maximum number of NFT serial numbers that can be burned in a single transaction
pub const MAX_NFT_BURN_BATCH_SIZE: usize = 10;

// TokenBurnTransaction burns fungible tokens or NFTs
pub const TokenBurnTransaction = struct {
    base: Transaction,
    token_id: ?TokenId,
    amount: u64,
    serials: std.ArrayList(i64),
    serial_numbers: std.ArrayList(i64),
    
    pub fn init(allocator: std.mem.Allocator) TokenBurnTransaction {
        return TokenBurnTransaction{
            .base = Transaction.init(allocator),
            .token_id = null,
            .amount = 0,
            .serials = std.ArrayList(i64).init(allocator),
            .serial_numbers = std.ArrayList(i64).init(allocator),
        };
    }
    
    pub fn deinit(self: *TokenBurnTransaction) void {
        self.base.deinit();
        self.serials.deinit();
        self.serial_numbers.deinit();
    }
    
    // Set the token to burn
    pub fn setTokenId(self: *TokenBurnTransaction, token_id: TokenId) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.token_id = token_id;
    }
    
    // Set amount to burn (for fungible tokens)
    pub fn setAmount(self: *TokenBurnTransaction, amount: u64) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        
        if (self.serial_numbers.items.len > 0) {
            return error.CannotSetBothAmountAndSerialNumbers;
        }
        
        if (amount == 0) {
            return error.InvalidBurnAmount;
        }
        
        if (amount > std.math.maxInt(i64)) {
            return error.BurnAmountTooLarge;
        }
        
        self.amount = amount;
    }
    
    // Includes a serial number for NFT burning
    pub fn addSerialNumber(self: *TokenBurnTransaction, serial_number: i64) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        
        if (self.amount > 0) {
            return error.CannotSetBothAmountAndSerialNumbers;
        }
        
        if (serial_number <= 0) {
            return error.InvalidSerialNumber;
        }
        
        if (self.serial_numbers.items.len >= MAX_NFT_BURN_BATCH_SIZE) {
            return error.TooManySerialNumbers;
        }
        
        // Check for duplicates
        for (self.serial_numbers.items) |existing| {
            if (existing == serial_number) {
                return error.DuplicateSerialNumber;
            }
        }
        
        try self.serial_numbers.append(serial_number);
    }
    
    // Set serial numbers for batch NFT burning
    pub fn setSerialNumbers(self: *TokenBurnTransaction, serial_numbers: []const i64) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        
        if (self.amount > 0) {
            return error.CannotSetBothAmountAndSerialNumbers;
        }
        
        if (serial_numbers.len > MAX_NFT_BURN_BATCH_SIZE) {
            return error.TooManySerialNumbers;
        }
        
        self.serial_numbers.clearRetainingCapacity();
        
        for (serial_numbers) |serial_number| {
            if (serial_number <= 0) {
                return error.InvalidSerialNumber;
            }
            
            // Check for duplicates
            for (self.serial_numbers.items) |existing| {
                if (existing == serial_number) {
                    return error.DuplicateSerialNumber;
                }
            }
            
            try self.serial_numbers.append(serial_number);
        }
    }
    
    // Add serial (alias for addSerialNumber)
    pub fn addSerial(self: *TokenBurnTransaction, serial: i64) !void {
        return self.addSerialNumber(serial);
    }
    
    // Execute the transaction
    pub fn execute(self: *TokenBurnTransaction, client: *Client) !TransactionResponse {
        if (self.token_id == null) {
            return error.TokenIdRequired;
        }
        
        if (self.amount == 0 and self.serial_numbers.items.len == 0) {
            return error.NothingToBurn;
        }
        
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *TokenBurnTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Common transaction fields
        try self.writeCommonFields(&writer);
        
        // tokenBurn = 36 (oneof data)
        var burn_writer = ProtoWriter.init(self.base.allocator);
        defer burn_writer.deinit();
        
        // token = 1
        if (self.token_id) |token| {
            var token_writer = ProtoWriter.init(self.base.allocator);
            defer token_writer.deinit();
            try token_writer.writeInt64(1, @intCast(token.entity.shard));
            try token_writer.writeInt64(2, @intCast(token.entity.realm));
            try token_writer.writeInt64(3, @intCast(token.entity.num));
            const token_bytes = try token_writer.toOwnedSlice();
            defer self.base.allocator.free(token_bytes);
            try burn_writer.writeMessage(1, token_bytes);
        }
        
        // amount = 2 (for fungible tokens)
        if (self.amount > 0) {
            try burn_writer.writeUint64(2, self.amount);
        }
        
        // serialNumbers = 3 (repeated, for NFTs)
        for (self.serial_numbers.items) |serial_number| {
            try burn_writer.writeInt64(3, serial_number);
        }
        
        const burn_bytes = try burn_writer.toOwnedSlice();
        defer self.base.allocator.free(burn_bytes);
        try writer.writeMessage(36, burn_bytes);
        
        return writer.toOwnedSlice();
    }
    
    fn writeCommonFields(self: *TokenBurnTransaction, writer: *ProtoWriter) !void {
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
            try account_writer.writeInt64(1, @intCast(tx_id.account_id.entity.shard));
            try account_writer.writeInt64(2, @intCast(tx_id.account_id.entity.realm));
            try account_writer.writeInt64(3, @intCast(tx_id.account_id.entity.num));
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
            try node_writer.writeInt64(1, @intCast(node.entity.shard));
            try node_writer.writeInt64(2, @intCast(node.entity.realm));
            try node_writer.writeInt64(3, @intCast(node.entity.num));
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
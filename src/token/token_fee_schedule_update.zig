const std = @import("std");
const TokenId = @import("../core/id.zig").TokenId;
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const CustomFee = @import("token_create.zig").CustomFee;

// TokenFeeScheduleUpdateTransaction updates the custom fee schedule for a token
pub const TokenFeeScheduleUpdateTransaction = struct {
    base: Transaction,
    token_id: ?TokenId,
    custom_fees: std.ArrayList(CustomFee),
    
    pub fn init(allocator: std.mem.Allocator) TokenFeeScheduleUpdateTransaction {
        return TokenFeeScheduleUpdateTransaction{
            .base = Transaction.init(allocator),
            .token_id = null,
            .custom_fees = std.ArrayList(CustomFee).init(allocator),
        };
    }
    
    pub fn deinit(self: *TokenFeeScheduleUpdateTransaction) void {
        for (self.custom_fees.items) |*fee| {
            fee.deinit();
        }
        self.custom_fees.deinit();
        self.base.deinit();
    }
    
    // Set the token ID for fee schedule update
    pub fn setTokenId(self: *TokenFeeScheduleUpdateTransaction, token_id: TokenId) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.token_id = token_id;
    }
    
    // Set custom fees for the token
    pub fn setCustomFees(self: *TokenFeeScheduleUpdateTransaction, fees: []const CustomFee) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        if (fees.len > 10) return error.TooManyCustomFees; // Maximum 10 custom fees per token
        
        // Clear existing fees
        for (self.custom_fees.items) |*fee| {
            fee.deinit();
        }
        self.custom_fees.clearRetainingCapacity();
        
        // Copy new fees
        for (fees) |fee| {
            try self.custom_fees.append(try fee.clone(self.base.allocator));
        }
    }
    
    // Includes a custom fee for the token
    pub fn addCustomFee(self: *TokenFeeScheduleUpdateTransaction, fee: CustomFee) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        if (self.custom_fees.items.len >= 10) return error.TooManyCustomFees;
        
        try self.custom_fees.append(try fee.clone(self.base.allocator));
    }
    
    // Execute the transaction
    pub fn execute(self: *TokenFeeScheduleUpdateTransaction, client: *Client) !TransactionResponse {
        if (self.token_id == null) {
            return error.TokenIdRequired;
        }
        
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *TokenFeeScheduleUpdateTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Common transaction fields
        try self.writeCommonFields(&writer);
        
        // tokenFeeScheduleUpdate = 45 (oneof data)
        var update_writer = ProtoWriter.init(self.base.allocator);
        defer update_writer.deinit();
        
        // tokenId = 1
        if (self.token_id) |token| {
            var token_writer = ProtoWriter.init(self.base.allocator);
            defer token_writer.deinit();
            try token_writer.writeInt64(1, @intCast(token.entity.shard));
            try token_writer.writeInt64(2, @intCast(token.entity.realm));
            try token_writer.writeInt64(3, @intCast(token.entity.num));
            const token_bytes = try token_writer.toOwnedSlice();
            defer self.base.allocator.free(token_bytes);
            try update_writer.writeMessage(1, token_bytes);
        }
        
        // customFees = 2 (repeated)
        for (self.custom_fees.items) |fee| {
            const fee_bytes = try fee.encode(self.base.allocator);
            defer self.base.allocator.free(fee_bytes);
            try update_writer.writeMessage(2, fee_bytes);
        }
        
        const update_bytes = try update_writer.toOwnedSlice();
        defer self.base.allocator.free(update_bytes);
        try writer.writeMessage(45, update_bytes);
        
        return writer.toOwnedSlice();
    }
    
    fn writeCommonFields(self: *TokenFeeScheduleUpdateTransaction, writer: *ProtoWriter) !void {
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
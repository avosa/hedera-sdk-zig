const std = @import("std");
const Transaction = @import("transaction.zig").Transaction;
const TransactionResponse = @import("transaction.zig").TransactionResponse;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;
const AccountId = @import("../core/id.zig").AccountId;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const Ed25519PrivateKey = @import("../crypto/key.zig").Ed25519PrivateKey;
const errors = @import("../core/errors.zig");

// BatchTransaction allows multiple transactions to be submitted as a batch
pub const BatchTransaction = struct {
    base: Transaction,
    transactions: std.ArrayList(*Transaction),
    signed_transactions: std.ArrayList(SignedTransaction),
    
    const SignedTransaction = struct {
        body_bytes: []const u8,
        signature_map: std.AutoHashMap(AccountId, []const u8),
    };
    
    pub fn init(allocator: std.mem.Allocator) BatchTransaction {
        return BatchTransaction{
            .base = Transaction.init(allocator),
            .transactions = std.ArrayList(*Transaction).init(allocator),
            .signed_transactions = std.ArrayList(SignedTransaction).init(allocator),
        };
    }
    
    pub fn deinit(self: *BatchTransaction) void {
        self.base.deinit();
        self.transactions.deinit();
        for (self.signed_transactions.items) |*signed| {
            self.base.allocator.free(signed.body_bytes);
            signed.signature_map.deinit();
        }
        self.signed_transactions.deinit();
    }
    
    // Add a transaction to the batch
    pub fn addTransaction(self: *BatchTransaction, transaction: *Transaction) !void {
        if (self.base.frozen) return error.TransactionFrozen;
        try self.transactions.append(transaction);
    }
    
    // Set all transactions in the batch
    pub fn setTransactions(self: *BatchTransaction, transactions: []*Transaction) !*BatchTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        self.transactions.clearAndFree();
        self.transactions.appendSlice(transactions) catch return error.InvalidParameter;
        return self;
    }
    
    // Sign all transactions in the batch
    pub fn sign(self: *BatchTransaction, private_key: Ed25519PrivateKey) !void {
        for (self.transactions.items) |tx| {
            try tx.sign(private_key);
            return self;
        }
    }
    
    // Freeze all transactions in the batch
    pub fn freeze(self: *BatchTransaction) !void {
        if (self.base.frozen) return;
        
        // Freeze base transaction
        self.base.frozen = true;
        
        // Freeze all child transactions
        for (self.transactions.items) |tx| {
            if (!tx.frozen) {
                try tx.freeze();
            }
            
            // Build and store signed transaction
            const body_bytes = try tx.buildTransactionBody();
            
            var sig_map = std.AutoHashMap(AccountId, []const u8).init(self.base.allocator);
            
            // Copy signatures from child transaction
            var iter = tx.signatures.iterator();
            while (iter.next()) |entry| {
                const account_id = entry.key_ptr.*;
                const sig_list = entry.value_ptr.*;
                
                if (sig_list.items.len > 0) {
                    const sig = sig_list.items[0].signature;
                    const sig_copy = try self.base.allocator.dupe(u8, sig);
                    try sig_map.put(account_id, sig_copy);
                }
            }
            
            try self.signed_transactions.append(SignedTransaction{
                .body_bytes = body_bytes,
                .signature_map = sig_map,
            });
        }
    }
    
    // Execute the batch transaction
    pub fn execute(self: *BatchTransaction, client: *Client) !TransactionResponse {
        if (!self.base.frozen) {
            try self.freeze();
        }
        
        // Execute each transaction in the batch
        var responses = std.ArrayList(TransactionResponse).init(self.base.allocator);
        defer responses.deinit();
        
        for (self.transactions.items) |tx| {
            const response = try tx.execute(client);
            try responses.append(response);
        }
        
        // Return the first response as representative
        if (responses.items.len > 0) {
            return responses.items[0];
        }
        
        return TransactionResponse{
            .transaction_id = self.base.transaction_id orelse TransactionId.generate(try AccountId.fromString(self.base.allocator, "0.0.0")),
            .hash = &[_]u8{0} ** 32,
        };
    }
    
    // Build transaction body for the batch
    pub fn buildTransactionBody(self: *BatchTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Write common transaction fields
        try self.writeCommonFields(&writer);
        
        // batch = 62 (oneof data)
        var batch_writer = ProtoWriter.init(self.base.allocator);
        defer batch_writer.deinit();
        
        // signedTransactions = 1 (repeated)
        for (self.signed_transactions.items) |signed| {
            var signed_writer = ProtoWriter.init(self.base.allocator);
            defer signed_writer.deinit();
            
            // bodyBytes = 1
            try signed_writer.writeBytes(1, signed.body_bytes);
            
            // sigMap = 2
            var sig_map_writer = ProtoWriter.init(self.base.allocator);
            defer sig_map_writer.deinit();
            
            var iter = signed.signature_map.iterator();
            while (iter.next()) |entry| {
                var sig_pair_writer = ProtoWriter.init(self.base.allocator);
                defer sig_pair_writer.deinit();
                
                // pubKeyPrefix = 1
                const account_id = entry.key_ptr.*;
                var prefix: [6]u8 = undefined;
                std.mem.writeInt(u16, prefix[0..2], @intCast(account_id.shard), .big);
                std.mem.writeInt(u16, prefix[2..4], @intCast(account_id.realm), .big);
                std.mem.writeInt(u16, prefix[4..6], @intCast(account_id.account), .big);
                try sig_pair_writer.writeBytes(1, &prefix);
                
                // signature = 2
                try sig_pair_writer.writeBytes(2, entry.value_ptr.*);
                
                const sig_pair_bytes = try sig_pair_writer.toOwnedSlice();
                defer self.base.allocator.free(sig_pair_bytes);
                try sig_map_writer.writeMessage(1, sig_pair_bytes);
            }
            
            const sig_map_bytes = try sig_map_writer.toOwnedSlice();
            defer self.base.allocator.free(sig_map_bytes);
            try signed_writer.writeMessage(2, sig_map_bytes);
            
            const signed_bytes = try signed_writer.toOwnedSlice();
            defer self.base.allocator.free(signed_bytes);
            try batch_writer.writeMessage(1, signed_bytes);
        }
        
        const batch_bytes = try batch_writer.toOwnedSlice();
        defer self.base.allocator.free(batch_bytes);
        try writer.writeMessage(62, batch_bytes);
        
        return writer.toOwnedSlice();
    }
    
    fn writeCommonFields(self: *BatchTransaction, writer: *ProtoWriter) !void {
        // Write standard transaction fields
        try self.base.writeCommonFields(writer);
    }
    
    // Freeze the transaction with client
    pub fn freezeWith(self: *BatchTransaction, client: *Client) !*BatchTransaction {
        try self.base.freezeWith(client);
        return self;
    }
};



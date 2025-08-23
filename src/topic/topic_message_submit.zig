const std = @import("std");
const errors = @import("../core/errors.zig");
const TopicId = @import("../core/id.zig").TopicId;
const AccountId = @import("../core/id.zig").AccountId;
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;
const Client = @import("../network/client.zig").Client;
const Hbar = @import("../core/hbar.zig").Hbar;
const ScheduleCreateTransaction = @import("../schedule/schedule_create_transaction.zig").ScheduleCreateTransaction;

// CustomFeeLimit represents a custom fee limit
pub const CustomFeeLimit = struct {
    fee_collector_account_id: AccountId,
    max_amount: u64,
    
    pub fn init(fee_collector_account_id: AccountId, max_amount: u64) CustomFeeLimit {
        return CustomFeeLimit{
            .fee_collector_account_id = fee_collector_account_id,
            .max_amount = max_amount,
        };
    }
};

// TopicMessageSubmitTransaction submits a message to a consensus topic
pub const TopicMessageSubmitTransaction = struct {
    allocator: std.mem.Allocator,
    transaction: Transaction,
    topic_id: ?TopicId,
    message: []const u8,
    max_chunks: u64,
    chunk_size: u64,
    custom_fee_limits: std.ArrayList(*CustomFeeLimit),
    
    pub fn init(allocator: std.mem.Allocator) !*TopicMessageSubmitTransaction {
        const self = try allocator.create(TopicMessageSubmitTransaction);
        self.* = TopicMessageSubmitTransaction{
            .allocator = allocator,
            .transaction = Transaction.init(allocator),
            .topic_id = null,
            .message = "",
            .max_chunks = 20,
            .chunk_size = 1024,
            .custom_fee_limits = std.ArrayList(*CustomFeeLimit).init(allocator),
        };
        return self;
    }
    
    pub fn deinit(self: *TopicMessageSubmitTransaction) void {
        for (self.custom_fee_limits.items) |fee_limit| {
            self.allocator.destroy(fee_limit);
        }
        self.custom_fee_limits.deinit();
        self.transaction.deinit();
        self.allocator.destroy(self);
    }
    
    // SetTopicID sets the topic to submit message to
    pub fn setTopicId(self: *TopicMessageSubmitTransaction, topic_id: TopicId) errors.HederaError!*TopicMessageSubmitTransaction {
        try errors.requireNotFrozen(self.transaction.frozen);
        self.topic_id = topic_id;
        return self;
    }
    
    // GetTopicID returns the TopicID for this TopicMessageSubmitTransaction
    pub fn getTopicId(self: *TopicMessageSubmitTransaction) TopicId {
        return self.topic_id orelse TopicId{};
    }
    
    // SetMessage sets the message to be submitted
    pub fn setMessage(self: *TopicMessageSubmitTransaction, message: []const u8) errors.HederaError!*TopicMessageSubmitTransaction {
        try errors.requireNotFrozen(self.transaction.frozen);
        self.message = message;
        return self;
    }
    
    // GetMessage returns the message to be submitted
    pub fn getMessage(self: *TopicMessageSubmitTransaction) []const u8 {
        return self.message;
    }
    
    // SetMaxChunks sets the maximum amount of chunks to use to send the message
    pub fn setMaxChunks(self: *TopicMessageSubmitTransaction, max_chunks: u64) errors.HederaError!*TopicMessageSubmitTransaction {
        try errors.requireNotFrozen(self.transaction.frozen);
        self.max_chunks = max_chunks;
        return self;
    }
    
    // GetMaxChunks returns the maximum amount of chunks to use to send the message
    pub fn getMaxChunks(self: *TopicMessageSubmitTransaction) u64 {
        return self.max_chunks;
    }
    
    // SetChunkSize sets the chunk size to use to send the message
    pub fn setChunkSize(self: *TopicMessageSubmitTransaction, chunk_size: u64) errors.HederaError!*TopicMessageSubmitTransaction {
        try errors.requireNotFrozen(self.transaction.frozen);
        self.chunk_size = chunk_size;
        return self;
    }
    
    // GetChunkSize returns the chunk size to use to send the message
    pub fn getChunkSize(self: *TopicMessageSubmitTransaction) u64 {
        return self.chunk_size;
    }
    
    // SetCustomFeeLimits sets the maximum custom fee that the user is willing to pay for the message
    pub fn setCustomFeeLimits(self: *TopicMessageSubmitTransaction, custom_fee_limits: []*CustomFeeLimit) errors.HederaError!*TopicMessageSubmitTransaction {
        try errors.requireNotFrozen(self.transaction.frozen);
        
        for (self.custom_fee_limits.items) |fee_limit| {
            self.allocator.destroy(fee_limit);
        }
        self.custom_fee_limits.clearRetainingCapacity();
        try errors.handleAppendSliceError(&self.custom_fee_limits, custom_fee_limits);
        
        return self;
    }
    
    // AddCustomFeeLimit adds the maximum custom fee that the user is willing to pay for the message
    pub fn addCustomFeeLimit(self: *TopicMessageSubmitTransaction, custom_fee_limit: *CustomFeeLimit) errors.HederaError!*TopicMessageSubmitTransaction {
        try errors.requireNotFrozen(self.transaction.frozen);
        try errors.handleAppendError(&self.custom_fee_limits, custom_fee_limit);
        return self;
    }
    
    // ClearCustomFeeLimits clears the maximum custom fee that the user is willing to pay for the message
    pub fn clearCustomFeeLimits(self: *TopicMessageSubmitTransaction) errors.HederaError!*TopicMessageSubmitTransaction {
        try errors.requireNotFrozen(self.transaction.frozen);
        
        for (self.custom_fee_limits.items) |fee_limit| {
            self.allocator.destroy(fee_limit);
        }
        self.custom_fee_limits.clearRetainingCapacity();
        
        return self;
    }
    
    // GetCustomFeeLimits gets the maximum custom fee that the user is willing to pay for the message
    pub fn getCustomFeeLimits(self: *TopicMessageSubmitTransaction) []*CustomFeeLimit {
        return self.custom_fee_limits.items;
    }
    
    // Freeze prepares the transaction for execution
    pub fn freeze(self: *TopicMessageSubmitTransaction) !*TopicMessageSubmitTransaction {
        return try self.freezeWith(null);
    }
    
    // FreezeWith prepares the transaction for execution with a client
    pub fn freezeWith(self: *TopicMessageSubmitTransaction, client: ?*Client) !*TopicMessageSubmitTransaction {
        // Validate chunk size
        if (self.chunk_size == 0) {
            return errors.HederaError.InvalidParameter;
        }
        
        // Calculate required chunks
        const chunks = (self.message.len + self.chunk_size - 1) / self.chunk_size;
        if (chunks > self.max_chunks) {
            return errors.HederaError.MessageSizeTooLarge;
        }
        
        try self.transaction.freezeWith(client);
        return self;
    }
    
    // Execute executes the transaction
    pub fn execute(self: *TopicMessageSubmitTransaction, client: *Client) !TransactionResponse {
        if (self.topic_id == null) {
            return errors.HederaError.InvalidTopicId;
        }
        if (self.message.len == 0) {
            return errors.HederaError.InvalidTopicMessage;
        }
        
        const responses = try self.executeAll(client);
        if (responses.len > 0) {
            return responses[0];
        }
        
        return errors.HederaError.UnknownError;
    }
    
    // ExecuteAll executes all the transactions with the provided client
    pub fn executeAll(self: *TopicMessageSubmitTransaction, client: *Client) ![]TransactionResponse {
        if (!self.transaction.frozen) {
            _ = try self.freezeWith(client);
        }
        
        // For now, treat as single transaction - chunking implementation would be more complex
        const response = try self.transaction.execute(client);
        
        var responses = try self.allocator.alloc(TransactionResponse, 1);
        responses[0] = response;
        
        return responses;
    }
    
    // Schedule creates a scheduled transaction
    pub fn schedule(self: *TopicMessageSubmitTransaction) !*ScheduleCreateTransaction {
        // Calculate required chunks
        const chunks = (self.message.len + self.chunk_size - 1) / self.chunk_size;
        if (chunks > 1) {
            return errors.HederaError.MessageSizeTooLarge;
        }
        
        return try self.transaction.schedule();
    }
    
    // Sign signs the transaction
    pub fn sign(self: *TopicMessageSubmitTransaction, private_key: anytype) !*TopicMessageSubmitTransaction {
        try self.transaction.sign(private_key);
        return self;
    }
    
    // SignWith signs the transaction with a specific key
    pub fn signWith(self: *TopicMessageSubmitTransaction, public_key: anytype, private_key: anytype) *TopicMessageSubmitTransaction {
        self.transaction.signWith(public_key, private_key);
        return self;
    }
    
    // SetMaxTransactionFee sets the maximum transaction fee
    pub fn setMaxTransactionFee(self: *TopicMessageSubmitTransaction, fee: Hbar) *TopicMessageSubmitTransaction {
        _ = self.transaction.setMaxTransactionFee(fee);
        return self;
    }
    
    // GetMaxTransactionFee returns the maximum transaction fee
    pub fn getMaxTransactionFee(self: *TopicMessageSubmitTransaction) ?Hbar {
        return self.transaction.getMaxTransactionFee();
    }
    
    // SetTransactionMemo sets the transaction memo
    pub fn setTransactionMemo(self: *TopicMessageSubmitTransaction, memo: []const u8) *TopicMessageSubmitTransaction {
        _ = self.transaction.setTransactionMemo(memo);
        return self;
    }
    
    // GetTransactionMemo returns the transaction memo
    pub fn getTransactionMemo(self: *TopicMessageSubmitTransaction) []const u8 {
        return self.transaction.getTransactionMemo();
    }
    
    // SetNodeAccountIDs sets the node account IDs for this transaction
    pub fn setNodeAccountIDs(self: *TopicMessageSubmitTransaction, node_account_ids: []const AccountId) *TopicMessageSubmitTransaction {
        _ = self.transaction.setNodeAccountIDs(node_account_ids);
        return self;
    }
    
    // GetNodeAccountIDs returns the node account IDs for this transaction
    pub fn getNodeAccountIDs(self: *TopicMessageSubmitTransaction) []const AccountId {
        return self.transaction.getNodeAccountIDs();
    }
    
    // SetTransactionID sets the transaction ID
    pub fn setTransactionId(self: *TopicMessageSubmitTransaction, transaction_id: TransactionId) *TopicMessageSubmitTransaction {
        _ = self.transaction.setTransactionId(transaction_id);
        return self;
    }
    
    // GetTransactionID returns the transaction ID
    pub fn getTransactionId(self: *TopicMessageSubmitTransaction) ?TransactionId {
        return self.transaction.getTransactionId();
    }
};

// NewTopicMessageSubmitTransaction creates a TopicMessageSubmitTransaction
pub fn newTopicMessageSubmitTransaction(allocator: std.mem.Allocator) !*TopicMessageSubmitTransaction {
    return try TopicMessageSubmitTransaction.init(allocator);
}

const std = @import("std");
const errors = @import("../core/errors.zig");
const TopicId = @import("../core/id.zig").TopicId;
const AccountId = @import("../core/id.zig").AccountId;
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const Client = @import("../network/client.zig").Client;
const Hbar = @import("../core/hbar.zig").Hbar;

// TopicDeleteTransaction deletes a consensus topic
pub const TopicDeleteTransaction = struct {
    allocator: std.mem.Allocator,
    transaction: Transaction,
    topic_id: ?TopicId,
    
    pub fn init(allocator: std.mem.Allocator) !*TopicDeleteTransaction {
        const self = try allocator.create(TopicDeleteTransaction);
        self.* = TopicDeleteTransaction{
            .allocator = allocator,
            .transaction = Transaction.init(allocator),
            .topic_id = null,
        };
        return self;
    }
    
    pub fn deinit(self: *TopicDeleteTransaction) void {
        self.transaction.deinit();
        self.allocator.destroy(self);
    }
    
    // SetTopicID sets the topic IDentifier
    pub fn setTopicId(self: *TopicDeleteTransaction, topic_id: TopicId) !*TopicDeleteTransaction {
        try errors.requireNotFrozen(self.transaction.frozen);
        self.topic_id = topic_id;
        return self;
    }
    
    // GetTopicID returns the topic IDentifier
    pub fn getTopicId(self: *TopicDeleteTransaction) TopicId {
        return self.topic_id orelse TopicId{};
    }
    
    // Execute executes the transaction
    pub fn execute(self: *TopicDeleteTransaction, client: *Client) !TransactionResponse {
        if (self.topic_id == null) {
            return error.InvalidParameter;
        }
        return try self.transaction.execute(client);
    }
    
    // Freeze prepares the transaction for execution
    pub fn freeze(self: *TopicDeleteTransaction) !*TopicDeleteTransaction {
        return try self.freezeWith(null);
    }
    
    // FreezeWith prepares the transaction for execution with a client
    pub fn freezeWith(self: *TopicDeleteTransaction, client: ?*Client) !*TopicDeleteTransaction {
        try self.transaction.freezeWith(client);
        return self;
    }
    
    // Sign signs the transaction
    pub fn sign(self: *TopicDeleteTransaction, private_key: anytype) *TopicDeleteTransaction {
        self.transaction.sign(private_key);
        return self;
    }
    
    // SignWith signs the transaction with a specific key
    pub fn signWith(self: *TopicDeleteTransaction, public_key: anytype, private_key: anytype) *TopicDeleteTransaction {
        self.transaction.signWith(public_key, private_key);
        return self;
    }
    
    // SetMaxTransactionFee sets the maximum transaction fee
    pub fn setMaxTransactionFee(self: *TopicDeleteTransaction, fee: Hbar) !*TopicDeleteTransaction {
        _ = self.transaction.setMaxTransactionFee(fee) catch {};
        return self;
    }
    
    // GetMaxTransactionFee returns the maximum transaction fee
    pub fn getMaxTransactionFee(self: *TopicDeleteTransaction) ?Hbar {
        return self.transaction.getMaxTransactionFee();
    }
    
    // SetTransactionMemo sets the transaction memo
    pub fn setTransactionMemo(self: *TopicDeleteTransaction, memo: []const u8) !*TopicDeleteTransaction {
        _ = self.transaction.setTransactionMemo(memo);
        return self;
    }
    
    // GetTransactionMemo returns the transaction memo
    pub fn getTransactionMemo(self: *TopicDeleteTransaction) []const u8 {
        return self.transaction.getTransactionMemo();
    }
    
    // SetNodeAccountIDs sets the node account IDs for this transaction
    pub fn setNodeAccountIDs(self: *TopicDeleteTransaction, node_account_ids: []const AccountId) !*TopicDeleteTransaction {
        _ = self.transaction.setNodeAccountIds(node_account_ids) catch {};
        return self;
    }
    
    // GetNodeAccountIDs returns the node account IDs for this transaction
    pub fn getNodeAccountIDs(self: *TopicDeleteTransaction) []const AccountId {
        return self.transaction.getNodeAccountIDs();
    }
};

// NewTopicDeleteTransaction creates a TopicDeleteTransaction

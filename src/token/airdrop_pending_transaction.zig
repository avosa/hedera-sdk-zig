// Transaction to manage pending airdrops
// Allows operations on airdrops that are waiting to be claimed

const std = @import("std");
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction_response.zig").TransactionResponse;
const PendingAirdropId = @import("pending_airdrop_id.zig").PendingAirdropId;
const ProtoWriter = @import("../protobuf/writer.zig").ProtoWriter;
const AccountId = @import("../core/id.zig").AccountId;
const HederaError = @import("../core/errors.zig").HederaError;
const requireNotFrozen = @import("../core/errors.zig").requireNotFrozen;

// Transaction for managing pending airdrops
pub const AirdropPendingTransaction = struct {
    base: Transaction,
    pending_airdrop_ids: std.ArrayList(PendingAirdropId),
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .base = Transaction.init(allocator),
            .pending_airdrop_ids = std.ArrayList(PendingAirdropId).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.pending_airdrop_ids.deinit();
        self.base.deinit();
    }
    
    // Add a pending airdrop ID to the transaction
    pub fn addPendingAirdropId(self: *Self, pending_airdrop_id: PendingAirdropId) HederaError!*Self {
        try requireNotFrozen(self.base.frozen);
        try pending_airdrop_id.validate();
        try self.pending_airdrop_ids.append(pending_airdrop_id);
        return self;
    }
    
    // Set multiple pending airdrop IDs
    pub fn setPendingAirdropIds(self: *Self, pending_airdrop_ids: []const PendingAirdropId) HederaError!*Self {
        try requireNotFrozen(self.base.frozen);
        
        // Clear existing
        self.pending_airdrop_ids.clearRetainingCapacity();
        
        // Validate and add all
        for (pending_airdrop_ids) |id| {
            try id.validate();
            try self.pending_airdrop_ids.append(id);
        }
        
        return self;
    }
    
    // Get the list of pending airdrop IDs
    pub fn getPendingAirdropIds(self: *const Self) []const PendingAirdropId {
        return self.pending_airdrop_ids.items;
    }
    
    // Clear all pending airdrop IDs
    pub fn clearPendingAirdropIds(self: *Self) HederaError!*Self {
        try requireNotFrozen(self.base.frozen);
        self.pending_airdrop_ids.clearRetainingCapacity();
        return self;
    }
    
    // Build transaction body for a specific node
    pub fn buildTransactionBodyForNode(self: *Self, node: AccountId) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Build TransactionBody
        
        // transactionID = 1
        if (self.base.transaction_id) |tx_id| {
            var tx_id_writer = ProtoWriter.init(self.base.allocator);
            defer tx_id_writer.deinit();
            
            // validStart
            var timestamp_writer = ProtoWriter.init(self.base.allocator);
            defer timestamp_writer.deinit();
            try timestamp_writer.writeInt64(1, tx_id.valid_start.seconds);
            try timestamp_writer.writeInt32(2, tx_id.valid_start.nanos);
            const timestamp_bytes = try timestamp_writer.toOwnedSlice();
            defer self.base.allocator.free(timestamp_bytes);
            try tx_id_writer.writeMessage(1, timestamp_bytes);
            
            // accountID
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
        var node_writer = ProtoWriter.init(self.base.allocator);
        defer node_writer.deinit();
        try node_writer.writeInt64(1, @intCast(node.shard));
        try node_writer.writeInt64(2, @intCast(node.realm));
        try node_writer.writeInt64(3, @intCast(node.account));
        const node_bytes = try node_writer.toOwnedSlice();
        defer self.base.allocator.free(node_bytes);
        try writer.writeMessage(2, node_bytes);
        
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
            try writer.writeStringField(5, self.base.transaction_memo);
        }
        
        // tokenUpdateNfts = 54 (field number for pending airdrop operations)
        const airdrop_body = try self.buildAirdropPendingBody();
        defer self.base.allocator.free(airdrop_body);
        try writer.writeMessage(54, airdrop_body);
        
        return writer.toOwnedSlice() catch HederaError.SerializationFailed;
    }
    
    // Build the airdrop pending transaction body
    fn buildAirdropPendingBody(self: *Self) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // pendingAirdropIds = 1 (repeated field)
        for (self.pending_airdrop_ids.items) |pending_id| {
            const id_bytes = try pending_id.toProtobuf(self.base.allocator);
            defer self.base.allocator.free(id_bytes);
            try writer.writeMessage(1, id_bytes);
        }
        
        return writer.toOwnedSlice() catch HederaError.SerializationFailed;
    }
    
    // Freeze the transaction
    pub fn freeze(self: *Self) HederaError!*Self {
        // Validate required fields
        if (self.pending_airdrop_ids.items.len == 0) {
            return HederaError.InvalidParameter;
        }
        
        self.base.frozen = true;
        return self;
    }
    
    // Freeze with client
    pub fn freezeWith(self: *Self, client: anytype) HederaError!*Self {
        // Validate required fields
        if (self.pending_airdrop_ids.items.len == 0) {
            return HederaError.InvalidParameter;
        }
        
        _ = self.base.freezeWith(client) catch return HederaError.TransactionFrozen;
        return self;
    }
    
    // Sign the transaction
    pub fn sign(self: *Self, private_key: anytype) HederaError!*Self {
        _ = self.base.sign(private_key) catch return HederaError.TransactionFrozen;
        return self;
    }
    
    // Execute transaction
    pub fn execute(self: *Self, client: anytype) !TransactionResponse {
        // Validate required fields
        if (self.pending_airdrop_ids.items.len == 0) {
            return HederaError.InvalidParameter;
        }
        
        // Override base buildTransactionBodyForNode
        self.base.buildTransactionBodyForNode = buildTransactionBodyForNodeWrapper;
        
        // Execute through base transaction
        return self.base.execute(client);
    }
    
    // Wrapper function for Transaction base class function pointer
    pub fn buildTransactionBodyForNodeWrapper(transaction: *Transaction, node: AccountId) anyerror![]u8 {
        const self = @as(*AirdropPendingTransaction, @fieldParentPtr("base", transaction));
        return self.buildTransactionBodyForNode(node);
    }
};
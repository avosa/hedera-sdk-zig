const std = @import("std");
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const errors = @import("../core/errors.zig");

// NodeDeleteTransaction deletes a consensus node from the network
pub const NodeDeleteTransaction = struct {
    base: Transaction,
    node_id: ?u64 = null,
    
    pub fn init(allocator: std.mem.Allocator) NodeDeleteTransaction {
        return NodeDeleteTransaction{
            .base = Transaction.init(allocator),
        };
    }
    
    pub fn deinit(self: *NodeDeleteTransaction) void {
        self.base.deinit();
    }
    
    // Set the node ID to delete
    pub fn setNodeId(self: *NodeDeleteTransaction, node_id: u64) errors.HederaError!*NodeDeleteTransaction {
        if (self.base.frozen) return errors.HederaError.InvalidTransaction;
        self.node_id = node_id;
        return self;
    }
    
    // Execute the transaction
    pub fn execute(self: *NodeDeleteTransaction, client: *Client) !TransactionResponse {
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *NodeDeleteTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Write common transaction fields
        try self.writeCommonFields(&writer);
        
        // nodeDelete = 64 (oneof data)
        var node_writer = ProtoWriter.init(self.base.allocator);
        defer node_writer.deinit();
        
        // nodeId = 1
        if (self.node_id) |node_id| {
            try node_writer.writeUint64(1, node_id);
        }
        
        const node_bytes = try node_writer.toOwnedSlice();
        defer self.base.allocator.free(node_bytes);
        try writer.writeMessage(64, node_bytes);
        
        return writer.toOwnedSlice();
    }
    
    fn writeCommonFields(self: *NodeDeleteTransaction, writer: *ProtoWriter) !void {
        // Write standard transaction fields
        try self.base.writeCommonFields(writer);
    }
};
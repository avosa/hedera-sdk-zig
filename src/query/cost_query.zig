// Query for getting the cost of another query
// Returns the estimated cost in Hbar before executing the actual query

const std = @import("std");
const Query = @import("query.zig").Query;
const Hbar = @import("../core/hbar.zig").Hbar;
const AccountId = @import("../core/id.zig").AccountId;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;
const ProtoWriter = @import("../protobuf/writer.zig").ProtoWriter;
const ProtoReader = @import("../protobuf/reader.zig").ProtoReader;
const HederaError = @import("../core/errors.zig").HederaError;
const Client = @import("../network/client.zig").Client;

// Query to get the cost of executing another query
pub const CostQuery = struct {
    base: Query,
    target_query: ?*Query = null,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .base = Query.init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.base.deinit();
    }
    
    // Set the query to get the cost for
    pub fn setQuery(self: *Self, query: *Query) HederaError!*Self {
        self.target_query = query;
        
        // Copy settings from target query
        self.base.node_account_ids = query.node_account_ids;
        self.base.payment = query.payment;
        
        return self;
    }
    
    // Get the target query
    pub fn getQuery(self: *const Self) ?*Query {
        return self.target_query;
    }
    
    // Build the query header
    fn buildQueryHeader(self: *Self, node: AccountId) ![]u8 {
        _ = node;
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // payment = 1
        if (self.base.payment) |payment| {
            const payment_bytes = try payment.toProtobuf(self.base.allocator);
            defer self.base.allocator.free(payment_bytes);
            try writer.writeMessage(1, payment_bytes);
        }
        
        // responseType = 2 (COST_ANSWER = 1)
        try writer.writeInt32(2, 1);
        
        return writer.toOwnedSlice();
    }
    
    // Build query for a specific node
    pub fn buildQueryForNode(self: *Self, node: AccountId) ![]u8 {
        if (self.target_query == null) {
            return HederaError.InvalidParameter;
        }
        
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Build the target query with COST_ANSWER response type
        const target_bytes = try self.target_query.?.buildQueryForNode(node);
        defer self.base.allocator.free(target_bytes);
        
        // Parse the target query to modify its response type
        var reader = ProtoReader.init(target_bytes);
        var modified_writer = ProtoWriter.init(self.base.allocator);
        defer modified_writer.deinit();
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            // Copy all fields but modify the query header
            if (tag.field_number == 1) {
                // This is the query header
                const header_bytes = try reader.readBytes();
                const modified_header = try self.modifyQueryHeader(header_bytes);
                defer self.base.allocator.free(modified_header);
                try modified_writer.writeMessage(1, modified_header);
            } else {
                // Copy other fields as-is
                switch (tag.wire_type) {
                    0 => {
                        const value = try reader.readVarint();
                        try modified_writer.writeVarint(tag.field_number, value);
                    },
                    1 => {
                        const value = try reader.readFixed64();
                        try modified_writer.writeFixed64(tag.field_number, value);
                    },
                    2 => {
                        const value = try reader.readBytes();
                        try modified_writer.writeBytesField(tag.field_number, value);
                    },
                    5 => {
                        const value = try reader.readFixed32();
                        try modified_writer.writeFixed32(tag.field_number, value);
                    },
                    else => return HederaError.InvalidParameter,
                }
            }
        }
        
        return modified_writer.toOwnedSlice();
    }
    
    // Modify query header to set COST_ANSWER response type
    fn modifyQueryHeader(self: *Self, header_bytes: []const u8) ![]u8 {
        var reader = ProtoReader.init(header_bytes);
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            if (tag.field_number == 2) {
                // responseType field - set to COST_ANSWER (1)
                try writer.writeInt32(2, 1);
                _ = try reader.readVarint(); // Skip the original value
            } else {
                // Copy other fields as-is
                switch (tag.wire_type) {
                    0 => {
                        const value = try reader.readVarint();
                        try writer.writeVarint(tag.field_number, value);
                    },
                    1 => {
                        const value = try reader.readFixed64();
                        try writer.writeFixed64(tag.field_number, value);
                    },
                    2 => {
                        const value = try reader.readBytes();
                        try writer.writeBytesField(tag.field_number, value);
                    },
                    5 => {
                        const value = try reader.readFixed32();
                        try writer.writeFixed32(tag.field_number, value);
                    },
                    else => return HederaError.InvalidParameter,
                }
            }
        }
        
        return writer.toOwnedSlice();
    }
    
    // Execute the query
    pub fn execute(self: *Self, client: *Client) !Hbar {
        if (self.target_query == null) {
            return HederaError.InvalidParameter;
        }
        
        // Set default payment if not set
        if (self.base.payment == null) {
            self.base.payment = try Hbar.fromTinybars(0);
        }
        
        // Execute the query
        const response_bytes = try self.base.executeWithClient(client, self);
        defer self.base.allocator.free(response_bytes);
        
        // Parse response to get cost
        return self.parseCostResponse(response_bytes);
    }
    
    // Parse the cost response
    fn parseCostResponse(self: *Self, response_bytes: []const u8) !Hbar {
        _ = self;
        var reader = ProtoReader.init(response_bytes);
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => {
                    // header
                    const header_bytes = try reader.readBytes();
                    _ = header_bytes; // Process header if needed
                },
                2 => {
                    // cost
                    const cost = try reader.readUint64();
                    return Hbar.fromTinybars(@intCast(cost));
                },
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return HederaError.InvalidResponse;
    }
    
    // Set node account IDs
    pub fn setNodeAccountIds(self: *Self, node_account_ids: []const AccountId) !*Self {
        try self.base.setNodeAccountIds(node_account_ids);
        return self;
    }
    
    // Set query payment
    pub fn setQueryPayment(self: *Self, payment: Hbar) !*Self {
        self.base.payment = payment;
        return self;
    }
    
    // Set max query payment
    pub fn setMaxQueryPayment(self: *Self, max_payment: Hbar) !*Self {
        self.base.max_query_payment = max_payment;
        return self;
    }
    
    // Get the cost without executing
    pub fn getCost(self: *Self, client: *Client) !Hbar {
        return self.execute(client);
    }
    
    // Wrapper function for Query base class function pointer
    pub fn buildQueryForNodeWrapper(query: *Query, node: AccountId) anyerror![]u8 {
        const self = @as(*CostQuery, @fieldParentPtr("base", query));
        return self.buildQueryForNode(node);
    }
};
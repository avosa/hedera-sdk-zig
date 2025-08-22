const std = @import("std");
const ContractId = @import("../core/id.zig").ContractId;
const Query = @import("../query/query.zig").Query;
const QueryResponse = @import("../query/query.zig").QueryResponse;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;
const Hbar = @import("../core/hbar.zig").Hbar;

// ContractBytecode contains the bytecode for a smart contract
pub const ContractBytecode = struct {
    contract_id: ContractId,
    bytecode: []const u8,
    
    allocator: std.mem.Allocator,
    
    pub fn deinit(self: *ContractBytecode) void {
        if (self.bytecode.len > 0) {
            self.allocator.free(self.bytecode);
        }
    }
};

// ContractBytecodeQuery retrieves the bytecode for a smart contract
pub const ContractBytecodeQuery = struct {
    base: Query,
    contract_id: ?ContractId,
    
    pub fn init(allocator: std.mem.Allocator) ContractBytecodeQuery {
        return ContractBytecodeQuery{
            .base = Query.init(allocator),
            .contract_id = null,
        };
    }
    
    pub fn deinit(self: *ContractBytecodeQuery) void {
        self.base.deinit();
    }
    
    // Set the contract ID to query bytecode for
    pub fn setContractId(self: *ContractBytecodeQuery, contract_id: ContractId) !void {
        self.contract_id = contract_id;
    }
    
    // Set the query payment amount
    pub fn setQueryPayment(self: *ContractBytecodeQuery, payment: Hbar) !void {
        self.base.payment_amount = payment;
    }
    
    // Execute the query
    pub fn execute(self: *ContractBytecodeQuery, client: *Client) !ContractBytecode {
        if (self.contract_id == null) {
            return error.ContractIdRequired;
        }
        
        const response = try self.base.execute(client);
        return try self.parseResponse(response);
    }
    
    // Get cost of the query
    pub fn getCost(self: *ContractBytecodeQuery, client: *Client) !Hbar {
        self.base.response_type = .CostAnswer;
        const response = try self.base.execute(client);
        
        var reader = ProtoReader.init(response.response_bytes);
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                2 => {
                    const cost = try reader.readUint64();
                    return try Hbar.fromTinybars(@intCast(cost));
                },
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return error.CostNotFound;
    }
    
    // Build the query
    pub fn buildQuery(self: *ContractBytecodeQuery) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Query message structure
        // header = 1
        var header_writer = ProtoWriter.init(self.base.allocator);
        defer header_writer.deinit();
        
        // payment = 1
        if (self.base.payment_transaction) |payment| {
            try header_writer.writeMessage(1, payment);
        }
        
        // responseType = 2
        try header_writer.writeInt32(2, @intFromEnum(self.base.response_type));
        
        const header_bytes = try header_writer.toOwnedSlice();
        defer self.base.allocator.free(header_bytes);
        try writer.writeMessage(1, header_bytes);
        
        // contractGetBytecode = 8 (oneof query)
        var bytecode_query_writer = ProtoWriter.init(self.base.allocator);
        defer bytecode_query_writer.deinit();
        
        // contractID = 1
        if (self.contract_id) |contract| {
            var contract_writer = ProtoWriter.init(self.base.allocator);
            defer contract_writer.deinit();
            try contract_writer.writeInt64(1, @intCast(contract.entity.shard));
            try contract_writer.writeInt64(2, @intCast(contract.entity.realm));
            try contract_writer.writeInt64(3, @intCast(contract.entity.num));
            const contract_bytes = try contract_writer.toOwnedSlice();
            defer self.base.allocator.free(contract_bytes);
            try bytecode_query_writer.writeMessage(1, contract_bytes);
        }
        
        const bytecode_query_bytes = try bytecode_query_writer.toOwnedSlice();
        defer self.base.allocator.free(bytecode_query_bytes);
        try writer.writeMessage(8, bytecode_query_bytes);
        
        return writer.toOwnedSlice();
    }
    
    // Parse the response
    fn parseResponse(self: *ContractBytecodeQuery, response: QueryResponse) !ContractBytecode {
        try response.validateStatus();
        
        var reader = ProtoReader.init(response.response_bytes);
        
        var bytecode_result = ContractBytecode{
            .contract_id = ContractId.init(0, 0, 0),
            .bytecode = "",
            .allocator = self.base.allocator,
        };
        
        // Parse ContractGetBytecodeResponse
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => {
                    // header
                    _ = try reader.readMessage();
                },
                2 => {
                    // bytecode
                    const bytecode_bytes = try reader.readBytes();
                    bytecode_result.bytecode = try self.base.allocator.dupe(u8, bytecode_bytes);
                },
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        if (self.contract_id) |contract_id| {
            bytecode_result.contract_id = contract_id;
        }
        
        return bytecode_result;
    }
};
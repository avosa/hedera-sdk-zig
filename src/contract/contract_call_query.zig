const std = @import("std");
const ContractId = @import("../core/id.zig").ContractId;
const AccountId = @import("../core/id.zig").AccountId;
const Hbar = @import("../core/hbar.zig").Hbar;
const Query = @import("../query/query.zig").Query;
const QueryResponse = @import("../query/query.zig").QueryResponse;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;
const ContractFunctionParameters = @import("contract_execute.zig").ContractFunctionParameters;
const ContractFunctionResult = @import("contract_execute.zig").ContractFunctionResult;

// ContractCallQuery executes a smart contract function and returns the result
pub const ContractCallQuery = struct {
    base: Query,
    contract_id: ?ContractId,
    gas: i64,
    function_parameters: []const u8,
    function_name: []const u8 = "",  // For Go SDK compatibility
    max_result_size: i64,
    sender_id: ?AccountId,
    
    pub fn init(allocator: std.mem.Allocator) ContractCallQuery {
        return ContractCallQuery{
            .base = Query.init(allocator),
            .contract_id = null,
            .gas = 100000,
            .function_parameters = "",
            .function_name = "",
            .max_result_size = 1024,
            .sender_id = null,
        };
    }
    
    pub fn deinit(self: *ContractCallQuery) void {
        self.base.deinit();
    }
    
    // Set the contract to call
    pub fn setContractId(self: *ContractCallQuery, contract_id: ContractId) !void {
        self.contract_id = contract_id;
    }
    
    // Set gas limit for the call
    pub fn setGas(self: *ContractCallQuery, gas: i64) !void {
        if (gas <= 0) return error.InvalidGasLimit;
        self.gas = gas;
    }
    
    // Set function parameters
    pub fn setFunctionParameters(self: *ContractCallQuery, params: []const u8) !void {
        self.function_parameters = params;
    }
    
    // Set function with parameters using builder
    pub fn setFunction(self: *ContractCallQuery, name: []const u8, params: ?ContractFunctionParameters) !void {
        var full_params = std.ArrayList(u8).init(self.base.allocator);
        defer full_params.deinit();
        
        // Calculate function selector (first 4 bytes of Keccak256 hash)
        var hasher = std.crypto.hash.sha3.Keccak256.init(.{});
        hasher.update(name);
        hasher.update("(");
        
        if (params) |p| {
            // Build parameter type string
            var type_string = std.ArrayList(u8).init(self.base.allocator);
            defer type_string.deinit();
            
            for (p.arguments.items, 0..) |arg, i| {
                if (i > 0) try type_string.append(',');
                
                switch (arg) {
                    .uint256 => try type_string.appendSlice("uint256"),
                    .int256 => try type_string.appendSlice("int256"),
                    .uint64 => try type_string.appendSlice("uint64"),
                    .int64 => try type_string.appendSlice("int64"),
                    .uint32 => try type_string.appendSlice("uint32"),
                    .int32 => try type_string.appendSlice("int32"),
                    .uint16 => try type_string.appendSlice("uint16"),
                    .int16 => try type_string.appendSlice("int16"),
                    .uint8 => try type_string.appendSlice("uint8"),
                    .int8 => try type_string.appendSlice("int8"),
                    .address => try type_string.appendSlice("address"),
                    .bool_val => try type_string.appendSlice("bool"),
                    .bytes_val => try type_string.appendSlice("bytes"),
                    .bytes32 => try type_string.appendSlice("bytes32"),
                    .string_val => try type_string.appendSlice("string"),
                    .uint_array => |arr| {
                        try type_string.appendSlice("uint256[");
                        const len_str = try std.fmt.allocPrint(self.base.allocator, "{d}", .{arr.len});
                        defer self.base.allocator.free(len_str);
                        try type_string.appendSlice(len_str);
                        try type_string.append(']');
                    },
                    .address_array => |arr| {
                        try type_string.appendSlice("address[");
                        const len_str = try std.fmt.allocPrint(self.base.allocator, "{d}", .{arr.len});
                        defer self.base.allocator.free(len_str);
                        try type_string.appendSlice(len_str);
                        try type_string.append(']');
                    },
                    .uint8_array => |arr| {
                        try type_string.appendSlice("uint8[");
                        const len_str = try std.fmt.allocPrint(self.base.allocator, "{d}", .{arr.len});
                        defer self.base.allocator.free(len_str);
                        try type_string.appendSlice(len_str);
                        try type_string.append(']');
                    },
                    .int8_array => |arr| {
                        try type_string.appendSlice("int8[");
                        const len_str = try std.fmt.allocPrint(self.base.allocator, "{d}", .{arr.len});
                        defer self.base.allocator.free(len_str);
                        try type_string.appendSlice(len_str);
                        try type_string.append(']');
                    },
                    .uint32_array => |arr| {
                        try type_string.appendSlice("uint32[");
                        const len_str = try std.fmt.allocPrint(self.base.allocator, "{d}", .{arr.len});
                        defer self.base.allocator.free(len_str);
                        try type_string.appendSlice(len_str);
                        try type_string.append(']');
                    },
                    .int32_array => |arr| {
                        try type_string.appendSlice("int32[");
                        const len_str = try std.fmt.allocPrint(self.base.allocator, "{d}", .{arr.len});
                        defer self.base.allocator.free(len_str);
                        try type_string.appendSlice(len_str);
                        try type_string.append(']');
                    },
                    .uint64_array => |arr| {
                        try type_string.appendSlice("uint64[");
                        const len_str = try std.fmt.allocPrint(self.base.allocator, "{d}", .{arr.len});
                        defer self.base.allocator.free(len_str);
                        try type_string.appendSlice(len_str);
                        try type_string.append(']');
                    },
                    .int64_array => |arr| {
                        try type_string.appendSlice("int64[");
                        const len_str = try std.fmt.allocPrint(self.base.allocator, "{d}", .{arr.len});
                        defer self.base.allocator.free(len_str);
                        try type_string.appendSlice(len_str);
                        try type_string.append(']');
                    },
                    .uint256_array => |arr| {
                        try type_string.appendSlice("uint256[");
                        const len_str = try std.fmt.allocPrint(self.base.allocator, "{d}", .{arr.len});
                        defer self.base.allocator.free(len_str);
                        try type_string.appendSlice(len_str);
                        try type_string.append(']');
                    },
                    .int256_array => |arr| {
                        try type_string.appendSlice("int256[");
                        const len_str = try std.fmt.allocPrint(self.base.allocator, "{d}", .{arr.len});
                        defer self.base.allocator.free(len_str);
                        try type_string.appendSlice(len_str);
                        try type_string.append(']');
                    },
                    .bool_array => |arr| {
                        try type_string.appendSlice("bool[");
                        const len_str = try std.fmt.allocPrint(self.base.allocator, "{d}", .{arr.len});
                        defer self.base.allocator.free(len_str);
                        try type_string.appendSlice(len_str);
                        try type_string.append(']');
                    },
                    .bytes32_array => |arr| {
                        try type_string.appendSlice("bytes32[");
                        const len_str = try std.fmt.allocPrint(self.base.allocator, "{d}", .{arr.len});
                        defer self.base.allocator.free(len_str);
                        try type_string.appendSlice(len_str);
                        try type_string.append(']');
                    },
                    .string_array => |arr| {
                        try type_string.appendSlice("string[");
                        const len_str = try std.fmt.allocPrint(self.base.allocator, "{d}", .{arr.len});
                        defer self.base.allocator.free(len_str);
                        try type_string.appendSlice(len_str);
                        try type_string.append(']');
                    },
                }
            }
            
            hasher.update(type_string.items);
            
            // Encode parameters
            const encoded_params = try p.encode(self.base.allocator);
            defer self.base.allocator.free(encoded_params);
            try full_params.appendSlice(encoded_params);
        }
        
        hasher.update(")");
        
        var hash: [32]u8 = undefined;
        hasher.final(&hash);
        
        // Function selector is first 4 bytes
        try full_params.insertSlice(0, hash[0..4]);
        
        self.function_parameters = try self.base.allocator.dupe(u8, full_params.items);
        self.function_name = name;
    }
    
    // Set maximum result size
    pub fn setMaxResultSize(self: *ContractCallQuery, size: i64) !void {
        if (size <= 0) return error.InvalidMaxResultSize;
        self.max_result_size = size;
    }
    
    // Set sender account ID
    pub fn setSenderId(self: *ContractCallQuery, sender_id: AccountId) !void {
        self.sender_id = sender_id;
    }
    
    // Set query payment
    pub fn setQueryPayment(self: *ContractCallQuery, payment: Hbar) !void {
        self.base.payment_amount = payment;
    }
    
    // Execute the query
    pub fn execute(self: *ContractCallQuery, client: *Client) !ContractFunctionResult {
        if (self.contract_id == null) {
            return error.ContractIdRequired;
        }
        
        const response = try self.base.execute(client);
        return try self.parseResponse(response);
    }
    
    // Get cost of the query
    pub fn getCost(self: *ContractCallQuery, client: *Client) !Hbar {
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
    pub fn buildQuery(self: *ContractCallQuery) ![]u8 {
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
        
        // contractCallLocal = 7 (oneof query)
        var call_query_writer = ProtoWriter.init(self.base.allocator);
        defer call_query_writer.deinit();
        
        // header = 1 (ContractCallLocalQuery has its own header)
        var call_header_writer = ProtoWriter.init(self.base.allocator);
        defer call_header_writer.deinit();
        
        // contractID = 2
        if (self.contract_id) |contract| {
            var contract_writer = ProtoWriter.init(self.base.allocator);
            defer contract_writer.deinit();
            try contract_writer.writeInt64(1, @intCast(contract.entity.shard));
            try contract_writer.writeInt64(2, @intCast(contract.entity.realm));
            try contract_writer.writeInt64(3, @intCast(contract.entity.num));
            const contract_bytes = try contract_writer.toOwnedSlice();
            defer self.base.allocator.free(contract_bytes);
            try call_query_writer.writeMessage(2, contract_bytes);
        }
        
        // gas = 3
        try call_query_writer.writeInt64(3, self.gas);
        
        // functionParameters = 4
        if (self.function_parameters.len > 0) {
            try call_query_writer.writeBytes(4, self.function_parameters);
        }
        
        // maxResultSize = 5
        try call_query_writer.writeInt64(5, self.max_result_size);
        
        // senderId = 6
        if (self.sender_id) |sender| {
            var sender_writer = ProtoWriter.init(self.base.allocator);
            defer sender_writer.deinit();
            try sender_writer.writeInt64(1, @intCast(sender.entity.shard));
            try sender_writer.writeInt64(2, @intCast(sender.entity.realm));
            try sender_writer.writeInt64(3, @intCast(sender.entity.num));
            const sender_bytes = try sender_writer.toOwnedSlice();
            defer self.base.allocator.free(sender_bytes);
            try call_query_writer.writeMessage(6, sender_bytes);
        }
        
        const call_query_bytes = try call_query_writer.toOwnedSlice();
        defer self.base.allocator.free(call_query_bytes);
        try writer.writeMessage(7, call_query_bytes);
        
        return writer.toOwnedSlice();
    }
    
    // Parse the response
    fn parseResponse(self: *ContractCallQuery, response: QueryResponse) !ContractFunctionResult {
        try response.validateStatus();
        
        var reader = ProtoReader.init(response.response_bytes);
        var result = ContractFunctionResult.init(self.base.allocator);
        
        // Parse ContractCallLocalResponse
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => {
                    // header
                    _ = try reader.readMessage();
                },
                2 => {
                    // functionResult
                    const function_result_bytes = try reader.readMessage();
                    var function_reader = ProtoReader.init(function_result_bytes);
                    
                    while (function_reader.hasMore()) {
                        const f_tag = try function_reader.readTag();
                        
                        switch (f_tag.field_number) {
                            1 => {
                                // contractID
                                const contract_bytes = try function_reader.readMessage();
                                var contract_reader = ProtoReader.init(contract_bytes);
                                
                                var shard: i64 = 0;
                                var realm: i64 = 0;
                                var num: i64 = 0;
                                
                                while (contract_reader.hasMore()) {
                                    const c = try contract_reader.readTag();
                                    switch (c.field_number) {
                                        1 => shard = try contract_reader.readInt64(),
                                        2 => realm = try contract_reader.readInt64(),
                                        3 => num = try contract_reader.readInt64(),
                                        else => try contract_reader.skipField(c.wire_type),
                                    }
                                }
                                
                                result.contract_id = ContractId.init(@intCast(shard), @intCast(realm), @intCast(num));
                            },
                            2 => {
                                // contractCallResult
                                result.contract_call_result = try self.base.allocator.dupe(u8, try function_reader.readBytes());
                            },
                            3 => {
                                // errorMessage
                                result.error_message = try self.base.allocator.dupe(u8, try function_reader.readString());
                            },
                            4 => {
                                // bloom
                                result.bloom = try self.base.allocator.dupe(u8, try function_reader.readBytes());
                            },
                            5 => result.gas_used = try function_reader.readUint64(),
                            6 => {
                                // logInfo (repeated)
                                const log_bytes = try function_reader.readMessage();
                                var log_reader = ProtoReader.init(log_bytes);
                                
                                var log_info = ContractFunctionResult.ContractLogInfo{
                                    .contract_id = undefined,
                                    .bloom = "",
                                    .topics = std.ArrayList([]const u8).init(self.base.allocator),
                                    .data = "",
                                };
                                
                                while (log_reader.hasMore()) {
                                    const l = try log_reader.readTag();
                                    switch (l.field_number) {
                                        1 => {
                                            // contractID
                                            const contract_bytes = try log_reader.readMessage();
                                            var contract_reader = ProtoReader.init(contract_bytes);
                                            
                                            var shard: i64 = 0;
                                            var realm: i64 = 0;
                                            var num: i64 = 0;
                                            
                                            while (contract_reader.hasMore()) {
                                                const c = try contract_reader.readTag();
                                                switch (c.field_number) {
                                                    1 => shard = try contract_reader.readInt64(),
                                                    2 => realm = try contract_reader.readInt64(),
                                                    3 => num = try contract_reader.readInt64(),
                                                    else => try contract_reader.skipField(c.wire_type),
                                                }
                                            }
                                            
                                            log_info.contract_id = ContractId.init(@intCast(shard), @intCast(realm), @intCast(num));
                                        },
                                        2 => log_info.bloom = try self.base.allocator.dupe(u8, try log_reader.readBytes()),
                                        3 => try log_info.topics.append(try self.base.allocator.dupe(u8, try log_reader.readBytes())),
                                        4 => log_info.data = try self.base.allocator.dupe(u8, try log_reader.readBytes()),
                                        else => try log_reader.skipField(l.wire_type),
                                    }
                                }
                                
                                try result.logs.append(log_info);
                            },
                            7 => {
                                // createdContractIDs (repeated)
                                const created_bytes = try function_reader.readMessage();
                                var created_reader = ProtoReader.init(created_bytes);
                                
                                var shard: i64 = 0;
                                var realm: i64 = 0;
                                var num: i64 = 0;
                                
                                while (created_reader.hasMore()) {
                                    const c = try created_reader.readTag();
                                    switch (c.field_number) {
                                        1 => shard = try created_reader.readInt64(),
                                        2 => realm = try created_reader.readInt64(),
                                        3 => num = try created_reader.readInt64(),
                                        else => try created_reader.skipField(c.wire_type),
                                    }
                                }
                                
                                try result.created_contract_ids.append(ContractId.init(@intCast(shard), @intCast(realm), @intCast(num)));
                            },
                            8 => {
                                // evmAddress
                                result.evm_address = try self.base.allocator.dupe(u8, try function_reader.readBytes());
                            },
                            9 => result.gas_consumed = try function_reader.readInt64(),
                            10 => {
                                // contractNonces (repeated)
                                const nonce_bytes = try function_reader.readMessage();
                                var nonce_reader = ProtoReader.init(nonce_bytes);
                                
                                var nonce_info = ContractFunctionResult.ContractNonceInfo{
                                    .contract_id = undefined,
                                    .nonce = 0,
                                };
                                
                                while (nonce_reader.hasMore()) {
                                    const n = try nonce_reader.readTag();
                                    switch (n.field_number) {
                                        1 => {
                                            // contractId
                                            const contract_bytes = try nonce_reader.readMessage();
                                            var contract_reader = ProtoReader.init(contract_bytes);
                                            
                                            var shard: i64 = 0;
                                            var realm: i64 = 0;
                                            var num: i64 = 0;
                                            
                                            while (contract_reader.hasMore()) {
                                                const c = try contract_reader.readTag();
                                                switch (c.field_number) {
                                                    1 => shard = try contract_reader.readInt64(),
                                                    2 => realm = try contract_reader.readInt64(),
                                                    3 => num = try contract_reader.readInt64(),
                                                    else => try contract_reader.skipField(c.wire_type),
                                                }
                                            }
                                            
                                            nonce_info.contract_id = ContractId.init(@intCast(shard), @intCast(realm), @intCast(num));
                                        },
                                        2 => nonce_info.nonce = try nonce_reader.readInt64(),
                                        else => try nonce_reader.skipField(n.wire_type),
                                    }
                                }
                                
                                try result.contract_nonces.append(nonce_info);
                            },
                            11 => {
                                // signerNonce
                                result.signer_nonce = try self.base.allocator.dupe(u8, try function_reader.readBytes());
                            },
                            else => try function_reader.skipField(f_tag.wire_type),
                        }
                    }
                },
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return result;
    }
};
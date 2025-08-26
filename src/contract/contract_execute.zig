const std = @import("std");
const errors = @import("../core/errors.zig");
const HederaError = errors.HederaError;const ContractId = @import("../core/id.zig").ContractId;
const AccountId = @import("../core/id.zig").AccountId;
const Hbar = @import("../core/hbar.zig").Hbar;
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;

// Maximum gas for contract execution
pub const MAX_GAS: i64 = 15_000_000;
pub const DEFAULT_GAS: i64 = 100_000;

// Contract function parameters
pub const ContractFunctionParameters = struct {
    allocator: std.mem.Allocator,
    arguments: std.ArrayList(Argument),
    function_selector: [4]u8,
    
    const Argument = union(enum) {
        uint8: u8,
        int8: i8,
        uint16: u16,
        int16: i16,
        uint32: u32,
        int32: i32,
        uint64: u64,
        int64: i64,
        uint256: [32]u8,
        int256: [32]u8,
        address: [20]u8,
        bool_val: bool,
        bytes_val: []const u8,
        bytes32: [32]u8,
        string_val: []const u8,
        uint_array: []u256,  // Generic uint array
        uint8_array: []u8,
        int8_array: []i8,
        uint32_array: []u32,
        int32_array: []i32,
        uint64_array: []u64,
        int64_array: []i64,
        uint256_array: [][32]u8,
        int256_array: [][32]u8,
        address_array: [][20]u8,
        bool_array: []bool,
        bytes32_array: [][32]u8,
        string_array: [][]const u8,
    };
    
    pub fn init(allocator: std.mem.Allocator) ContractFunctionParameters {
        return ContractFunctionParameters{
            .allocator = allocator,
            .arguments = std.ArrayList(Argument).init(allocator),
            .function_selector = .{ 0, 0, 0, 0 },
        };
    }
    
    pub fn deinit(self: *ContractFunctionParameters) void {
        self.arguments.deinit();
    }
    
    // Sets the function selector for the contract call
    pub fn setFunction(self: *ContractFunctionParameters, function_name: []const u8) !*ContractFunctionParameters {
        // Calculate function selector using Keccak256
        var hasher = std.crypto.hash.sha3.Keccak256.init(.{});
        hasher.update(function_name);
        var hash: [32]u8 = undefined;
        hasher.final(&hash);
        
        // Take first 4 bytes as selector
        @memcpy(&self.function_selector, hash[0..4]);
    }
    
    // Appends a uint256 parameter to the contract call (as bytes)
    pub fn addUint256Bytes(self: *ContractFunctionParameters, value: [32]u8) !void {
        try self.arguments.append(.{ .uint256 = value });
    }
    
    // Appends a uint256 parameter to the contract call (as integer)
    pub fn addUint256(self: *ContractFunctionParameters, value: u256) !void {
        var bytes: [32]u8 = [_]u8{0} ** 32;
        std.mem.writeInt(u256, &bytes, value, .big);
        try self.arguments.append(.{ .uint256 = bytes });
    }
    
    // Appends an int256 parameter to the contract call
    pub fn addInt256(self: *ContractFunctionParameters, value: [32]u8) !void {
        try self.arguments.append(.{ .int256 = value });
    }
    
    // Appends a uint64 parameter to the contract call
    pub fn addUint64(self: *ContractFunctionParameters, value: u64) !void {
        try self.arguments.append(.{ .uint64 = value });
    }
    
    // Appends an int64 parameter to the contract call
    pub fn addInt64(self: *ContractFunctionParameters, value: i64) !void {
        try self.arguments.append(.{ .int64 = value });
    }
    
    // Appends a uint32 parameter to the contract call
    pub fn addUint32(self: *ContractFunctionParameters, value: u32) !void {
        try self.arguments.append(.{ .uint32 = value });
    }
    
    // Appends an int32 parameter to the contract call
    pub fn addInt32(self: *ContractFunctionParameters, value: i32) !void {
        try self.arguments.append(.{ .int32 = value });
    }
    
    // Appends a uint8 parameter to the contract call
    pub fn addUint8(self: *ContractFunctionParameters, value: u8) !void {
        try self.arguments.append(.{ .uint8 = value });
    }
    
    // Appends an int8 parameter to the contract call
    pub fn addInt8(self: *ContractFunctionParameters, value: i8) !void {
        try self.arguments.append(.{ .int8 = value });
    }
    
    // Appends an address parameter to the contract call
    pub fn addAddress(self: *ContractFunctionParameters, address: []const u8) !void {
        var addr: [20]u8 = undefined;
        
        if (address.len == 20) {
            // Raw 20-byte address
            @memcpy(&addr, address);
        } else if (address.len == 42 and std.mem.startsWith(u8, address, "0x")) {
            // Hex string with 0x prefix (42 chars total)
            const hex_part = address[2..];
            for (0..20) |i| {
                const hex_byte = hex_part[i * 2..(i + 1) * 2];
                addr[i] = std.fmt.parseInt(u8, hex_byte, 16) catch return error.InvalidAddressFormat;
            }
        } else if (address.len == 40) {
            // Hex string without 0x prefix (40 chars)
            for (0..20) |i| {
                const hex_byte = address[i * 2..(i + 1) * 2];
                addr[i] = std.fmt.parseInt(u8, hex_byte, 16) catch return error.InvalidAddressFormat;
            }
        } else {
            return error.InvalidAddressLength;
        }
        
        try self.arguments.append(.{ .address = addr });
    }
    
    // Appends a boolean parameter to the contract call
    pub fn addBool(self: *ContractFunctionParameters, value: bool) !void {
        try self.arguments.append(.{ .bool_val = value });
    }
    
    // Appends a bytes parameter to the contract call
    pub fn addBytes(self: *ContractFunctionParameters, value: []const u8) !void {
        try self.arguments.append(.{ .bytes_val = value });
    }
    
    // Appends a bytes32 parameter to the contract call
    pub fn addBytes32(self: *ContractFunctionParameters, value: [32]u8) !void {
        try self.arguments.append(.{ .bytes32 = value });
    }
    
    // Appends a string parameter to the contract call
    pub fn addString(self: *ContractFunctionParameters, value: []const u8) !void {
        try self.arguments.append(.{ .string_val = value });
    }
    
    // Build function call data as bytes
    pub fn toBytes(self: ContractFunctionParameters) ![]u8 {
        return self.build();
    }
    
    // Encode function call data
    pub fn encode(self: ContractFunctionParameters, allocator: std.mem.Allocator) ![]u8 {
        _ = allocator; // Parameters struct contains allocator
        return self.build();
    }
    
    // Build function call data
    pub fn build(self: ContractFunctionParameters) ![]u8 {
        var data = std.ArrayList(u8).init(self.allocator);
        defer data.deinit();
        
        // Encode function selector into call data
        try data.appendSlice(&self.function_selector);
        
        // Encode arguments according to Solidity ABI encoding
        const head_size: usize = self.arguments.items.len * 32;
        var tail = std.ArrayList(u8).init(self.allocator);
        defer tail.deinit();
        
        for (self.arguments.items) |arg| {
            switch (arg) {
                .uint8 => |v| {
                    var padded: [32]u8 = .{0} ** 32;
                    padded[31] = v;
                    try data.appendSlice(&padded);
                },
                .int8 => |v| {
                    var padded: [32]u8 = if (v < 0) .{0xFF} ** 32 else .{0} ** 32;
                    padded[31] = @bitCast(v);
                    try data.appendSlice(&padded);
                },
                .uint16 => |v| {
                    var padded: [32]u8 = .{0} ** 32;
                    std.mem.writeInt(u16, padded[30..32], v, .big);
                    try data.appendSlice(&padded);
                },
                .int16 => |v| {
                    var padded: [32]u8 = if (v < 0) .{0xFF} ** 32 else .{0} ** 32;
                    std.mem.writeInt(i16, padded[30..32], v, .big);
                    try data.appendSlice(&padded);
                },
                .uint32 => |v| {
                    var padded: [32]u8 = .{0} ** 32;
                    std.mem.writeInt(u32, padded[28..32], v, .big);
                    try data.appendSlice(&padded);
                },
                .int32 => |v| {
                    var padded: [32]u8 = if (v < 0) .{0xFF} ** 32 else .{0} ** 32;
                    std.mem.writeInt(i32, padded[28..32], v, .big);
                    try data.appendSlice(&padded);
                },
                .uint64 => |v| {
                    var padded: [32]u8 = .{0} ** 32;
                    std.mem.writeInt(u64, padded[24..32], v, .big);
                    try data.appendSlice(&padded);
                },
                .int64 => |v| {
                    var padded: [32]u8 = if (v < 0) .{0xFF} ** 32 else .{0} ** 32;
                    std.mem.writeInt(i64, padded[24..32], v, .big);
                    try data.appendSlice(&padded);
                },
                .uint256, .int256, .bytes32 => |v| {
                    try data.appendSlice(&v);
                },
                .address => |v| {
                    var padded: [32]u8 = .{0} ** 32;
                    @memcpy(padded[12..32], &v);
                    try data.appendSlice(&padded);
                },
                .bool_val => |v| {
                    var padded: [32]u8 = .{0} ** 32;
                    padded[31] = if (v) 1 else 0;
                    try data.appendSlice(&padded);
                },
                .bytes_val, .string_val => |v| {
                    // Dynamic types: store offset in head, data in tail
                    var offset: [32]u8 = .{0} ** 32;
                    const offset_val = head_size + tail.items.len;
                    std.mem.writeInt(u256, &offset, offset_val, .big);
                    try data.appendSlice(&offset);
                    
                    // Encode length and data to tail section
                    var length: [32]u8 = .{0} ** 32;
                    std.mem.writeInt(u256, &length, v.len, .big);
                    try tail.appendSlice(&length);
                    
                    // Encode padded data
                    try tail.appendSlice(v);
                    const padding = (32 - (v.len % 32)) % 32;
                    try tail.appendNTimes(0, padding);
                },
                else => return error.UnsupportedArgumentType,
            }
        }
        
        // Append tail data
        try data.appendSlice(tail.items);
        
        return data.toOwnedSlice();
    }
};

// ContractExecuteTransaction executes a smart contract function
pub const ContractExecuteTransaction = struct {
    base: Transaction,
    contract_id: ?ContractId,
    gas: i64,
    payable_amount: Hbar,
    function_parameters: []const u8,
    
    pub fn init(allocator: std.mem.Allocator) ContractExecuteTransaction {
        return ContractExecuteTransaction{
            .base = Transaction.init(allocator),
            .contract_id = null,
            .gas = DEFAULT_GAS,
            .payable_amount = Hbar.zero(),
            .function_parameters = &[_]u8{},
        };
    }
    
    pub fn deinit(self: *ContractExecuteTransaction) void {
        self.base.deinit();
    }
    
    // SetContractID sets the contract ID to execute
    pub fn setContractId(self: *ContractExecuteTransaction, contract_id: ContractId) !*ContractExecuteTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        self.contract_id = contract_id;
        return self;
    }
    
    // GetContractID returns the contract ID to execute
    pub fn getContractId(self: *const ContractExecuteTransaction) ContractId {
        return self.contract_id orelse ContractId{};
    }
    
    // SetGas sets the gas limit for the contract execution
    pub fn setGas(self: *ContractExecuteTransaction, gas: u64) !*ContractExecuteTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        self.gas = @intCast(gas);
        return self;
    }
    
    // GetGas returns the gas limit for the contract execution
    pub fn getGas(self: *const ContractExecuteTransaction) u64 {
        return @intCast(self.gas);
    }
    
    // SetPayableAmount sets the amount of Hbar sent with the contract execution
    pub fn setPayableAmount(self: *ContractExecuteTransaction, amount: Hbar) !*ContractExecuteTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        self.payable_amount = amount;
        return self;
    }
    
    // GetPayableAmount returns the amount of Hbar sent with the contract execution
    pub fn getPayableAmount(self: *const ContractExecuteTransaction) Hbar {
        return self.payable_amount;
    }
    
    // SetFunctionParameters sets the function parameters for the contract execution
    pub fn setFunctionParameters(self: *ContractExecuteTransaction, parameters: []const u8) !*ContractExecuteTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        self.function_parameters = parameters;
        return self;
    }
    
    // GetFunctionParameters returns the function parameters for the contract execution
    pub fn getFunctionParameters(self: *const ContractExecuteTransaction) []const u8 {
        return self.function_parameters;
    }
    
    // SetFunction sets the function name and parameters for the contract execution
    pub fn setFunction(self: *ContractExecuteTransaction, function_name: []const u8, parameters: ?*ContractFunctionParameters) !*ContractExecuteTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        
        var params = parameters;
        if (params == null) {
            var default_params = ContractFunctionParameters.init(self.base.allocator);
            params = &default_params;
        }
        
        _ = params.?.setFunction(function_name);
        const data = params.?.build() catch return error.InvalidParameter;
        self.function_parameters = data;
        return self;
    }
    
    // Freeze the transaction
    pub fn freeze(self: *ContractExecuteTransaction) HederaError!void {
        try self.base.freeze();
    }
    
    // Freeze with client
    pub fn freezeWith(self: *ContractExecuteTransaction, client: *Client) !*ContractExecuteTransaction {
        try self.base.freezeWith(client);
        return self;
    }
    
    // Sign the transaction
    pub fn sign(self: *ContractExecuteTransaction, private_key: anytype) HederaError!*ContractExecuteTransaction {
        try self.base.sign(private_key);
        return self;
    }
    
    // Sign with operator
    pub fn signWithOperator(self: *ContractExecuteTransaction, client: *Client) HederaError!*ContractExecuteTransaction {
        try self.base.signWithOperator(client);
        return self;
    }
    
    // Execute the transaction
    pub fn execute(self: *ContractExecuteTransaction, client: *Client) !TransactionResponse {
        if (self.contract_id == null) {
            return error.ContractIdRequired;
        }
        
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *ContractExecuteTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Common transaction fields
        try self.writeCommonFields(&writer);
        
        // contractCall = 7 (oneof data)
        var call_writer = ProtoWriter.init(self.base.allocator);
        defer call_writer.deinit();
        
        // contractID = 1
        if (self.contract_id) |contract| {
            var contract_writer = ProtoWriter.init(self.base.allocator);
            defer contract_writer.deinit();
            try contract_writer.writeInt64(1, @intCast(contract.shard));
            try contract_writer.writeInt64(2, @intCast(contract.realm));
            try contract_writer.writeInt64(3, @intCast(contract.num));
            
            if (contract.evm_address) |evm| {
                try contract_writer.writeString(4, evm);
            }
            
            const contract_bytes = try contract_writer.toOwnedSlice();
            defer self.base.allocator.free(contract_bytes);
            try call_writer.writeMessage(1, contract_bytes);
        }
        
        // gas = 2
        try call_writer.writeInt64(2, self.gas);
        
        // amount = 3 (payable amount in tinybars)
        try call_writer.writeInt64(3, self.payable_amount.toTinybars());
        
        // functionParameters = 4
        if (self.function_parameters.len > 0) {
            try call_writer.writeString(4, self.function_parameters);
        }
        
        const call_bytes = try call_writer.toOwnedSlice();
        defer self.base.allocator.free(call_bytes);
        try writer.writeMessage(7, call_bytes);
        
        return writer.toOwnedSlice();
    }
    
    fn writeCommonFields(self: *ContractExecuteTransaction, writer: *ProtoWriter) !void {
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
        if (self.base.node_account_ids.items.len > 0) {
            var node_writer = ProtoWriter.init(self.base.allocator);
            defer node_writer.deinit();
            const node = self.base.node_account_ids.items[0];
            try node_writer.writeInt64(1, @intCast(node.shard));
            try node_writer.writeInt64(2, @intCast(node.realm));
            try node_writer.writeInt64(3, @intCast(node.account));
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

// Contract function result
pub const ContractFunctionResult = struct {
    contract_id: ContractId,
    contract_call_result: []const u8,
    error_message: []const u8,
    bloom: []const u8,
    gas_used: u64,
    logs: []ContractLogInfo,
    created_contract_ids: []ContractId,
    evm_address: ?[]const u8,
    gas: i64,
    amount: i64,
    function_parameters: []const u8,
    sender_id: ?AccountId,
    
    pub const ContractLogInfo = struct {
        contract_id: ContractId,
        bloom: []const u8,
        topics: [][]const u8,
        data: []const u8,
    };
    
    // Get uint256 result
    pub fn getUint256(self: ContractFunctionResult, index: usize) ![32]u8 {
        const offset = index * 32;
        if (offset + 32 > self.contract_call_result.len) {
            return error.IndexOutOfBounds;
        }
        
        var result: [32]u8 = undefined;
        @memcpy(&result, self.contract_call_result[offset .. offset + 32]);
        return result;
    }
    
    // Get uint64 result
    pub fn getUint64(self: ContractFunctionResult, index: usize) !u64 {
        const bytes = try self.getUint256(index);
        return std.mem.readInt(u64, bytes[24..32], .big);
    }
    
    // Get uint32 result
    pub fn getUint32(self: ContractFunctionResult, index: usize) !u32 {
        const bytes = try self.getUint256(index);
        return std.mem.readInt(u32, bytes[28..32], .big);
    }
    
    // Get address result
    pub fn getAddress(self: ContractFunctionResult, index: usize) ![20]u8 {
        const bytes = try self.getUint256(index);
        var address: [20]u8 = undefined;
        @memcpy(&address, bytes[12..32]);
        return address;
    }
    
    // Get bool result
    pub fn getBool(self: ContractFunctionResult, index: usize) !bool {
        const bytes = try self.getUint256(index);
        return bytes[31] != 0;
    }
    
    // Get string result
    pub fn getString(self: ContractFunctionResult, allocator: std.mem.Allocator, index: usize) ![]u8 {
        // Read offset
        const offset_bytes = try self.getUint256(index);
        const offset = std.mem.readInt(u256, &offset_bytes, .big);
        
        // Read length
        const length_start = @as(usize, @intCast(offset));
        if (length_start + 32 > self.contract_call_result.len) {
            return error.IndexOutOfBounds;
        }
        
        var length_bytes: [32]u8 = undefined;
        @memcpy(&length_bytes, self.contract_call_result[length_start .. length_start + 32]);
        const length = std.mem.readInt(u256, &length_bytes, .big);
        
        // Read string data
        const data_start = length_start + 32;
        const data_end = data_start + @as(usize, @intCast(length));
        if (data_end > self.contract_call_result.len) {
            return error.IndexOutOfBounds;
        }
        
        return allocator.dupe(u8, self.contract_call_result[data_start..data_end]);
    }
    
    // Parse ContractFunctionResult from protobuf bytes
    pub fn fromProtobuf(allocator: std.mem.Allocator, bytes: []const u8) !ContractFunctionResult {
        var reader = @import("../protobuf/encoding.zig").ProtoReader.init(bytes);
        
        var result = ContractFunctionResult{
            .contract_id = ContractId{ .entity = @import("../core/id.zig").EntityId{ .shard = 0, .realm = 0, .num = 0 } },
            .contract_call_result = &[_]u8{},
            .error_message = &[_]u8{},
            .bloom = &[_]u8{},
            .gas_used = 0,
            .logs = &[_]ContractLogInfo{},
            .created_contract_ids = &[_]ContractId{},
            .evm_address = null,
            .gas = 0,
            .amount = 0,
            .function_parameters = &[_]u8{},
            .sender_id = null,
        };
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            switch (tag.field_number) {
                1 => {
                    // contractID
                    const contract_bytes = try reader.readMessage();
                    result.contract_id = try ContractId.fromProtobufBytes(allocator, contract_bytes);
                },
                2 => {
                    // contractCallResult
                    result.contract_call_result = try reader.readBytes();
                },
                3 => {
                    // errorMessage
                    result.error_message = try reader.readString();
                },
                4 => {
                    // bloom
                    result.bloom = try reader.readBytes();
                },
                5 => {
                    // gasUsed
                    result.gas_used = try reader.readUint64();
                },
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return result;
    }
};



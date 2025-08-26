const std = @import("std");
const MirrorNodeContractQuery = @import("mirror_node_contract_query.zig").MirrorNodeContractQuery;
const ContractId = @import("../core/id.zig").ContractId;
const AccountId = @import("../core/id.zig").AccountId;
const Client = @import("../network/client.zig").Client;
const ContractFunctionParameters = @import("../contract/contract_abi.zig").ContractFunctionParameters;

/// Query for EVM transient simulation of read-write operations
pub const MirrorNodeContractCallQuery = struct {
    query: MirrorNodeContractQuery,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .query = MirrorNodeContractQuery.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.query.deinit();
    }

    /// Set the contract instance to call
    pub fn setContractId(self: *Self, contract_id: ContractId) !*Self {
        self.query.contract_id = contract_id;
        return self;
    }

    /// Set the 20-byte EVM address of the contract to call
    pub fn setContractEvmAddress(self: *Self, contract_evm_address: []const u8) !*Self {
        if (self.query.contract_evm_address) |addr| {
            if (addr.len > 0) self.query.allocator.free(addr);
        }
        self.query.contract_evm_address = try self.query.allocator.dupe(u8, contract_evm_address);
        self.query.contract_id = null;
        return self;
    }

    /// Set the sender of the transaction simulation
    pub fn setSender(self: *Self, sender: AccountId) !*Self {
        self.query.sender = sender;
        return self;
    }

    /// Set the 20-byte EVM address of the sender
    pub fn setSenderEvmAddress(self: *Self, sender_evm_address: []const u8) !*Self {
        if (self.query.sender_evm_address) |addr| {
            if (addr.len > 0) self.query.allocator.free(addr);
        }
        self.query.sender_evm_address = try self.query.allocator.dupe(u8, sender_evm_address);
        self.query.sender = null;
        return self;
    }

    /// Set the function to call with parameters
    pub fn setFunction(self: *Self, name: []const u8, params: ?*ContractFunctionParameters) !*Self {
        try self.query.setFunction(name, params);
        return self;
    }

    /// Set the function parameters as raw bytes
    pub fn setFunctionParameters(self: *Self, byte_array: []const u8) !*Self {
        if (self.query.call_data.len > 0) {
            self.query.allocator.free(self.query.call_data);
        }
        self.query.call_data = try self.query.allocator.dupe(u8, byte_array);
        return self;
    }

    /// Set the amount of value to send to the contract
    pub fn setValue(self: *Self, value: i64) !*Self {
        self.query.value = value;
        return self;
    }

    /// Set the gas limit for the contract call
    pub fn setGasLimit(self: *Self, gas_limit: i64) !*Self {
        self.query.gas_limit = gas_limit;
        return self;
    }

    /// Set the gas price for the contract call
    pub fn setGasPrice(self: *Self, gas_price: i64) !*Self {
        self.query.gas_price = gas_price;
        return self;
    }

    /// Set the block number for the simulation
    pub fn setBlockNumber(self: *Self, block_number: i64) !*Self {
        self.query.block_number = block_number;
        return self;
    }

    /// Execute the query and return the result
    pub fn execute(self: *Self, client: *Client) ![]u8 {
        return self.query.call(client);
    }
};

test "MirrorNodeContractCallQuery initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var query = MirrorNodeContractCallQuery.init(allocator);
    defer query.deinit();

    try testing.expect(query.query.contract_id == null);
    try testing.expect(query.query.sender == null);
}

test "MirrorNodeContractCallQuery setters" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var query = MirrorNodeContractCallQuery.init(allocator);
    defer query.deinit();

    const contract_id = ContractId.init(0, 0, 100);
    _ = query.setContractId(contract_id);
    _ = query.setValue(1000);
    _ = query.setGasLimit(100000);
    _ = query.setGasPrice(10);
    _ = query.setBlockNumber(12345);

    try testing.expect(query.query.getContractId().?.equals(contract_id));
    try testing.expectEqual(@as(i64, 1000), query.query.getValue());
    try testing.expectEqual(@as(i64, 100000), query.query.getGasLimit());
    try testing.expectEqual(@as(i64, 10), query.query.getGasPrice());
    try testing.expectEqual(@as(i64, 12345), query.query.getBlockNumber());
}
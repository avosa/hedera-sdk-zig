const std = @import("std");
const ContractId = @import("../core/id.zig").ContractId;
const AccountId = @import("../core/id.zig").AccountId;
const Client = @import("../network/client.zig").Client;
const ContractFunctionParameters = @import("../contract/contract_abi.zig").ContractFunctionParameters;

/// Base structure for mirror node contract queries providing EVM execution capabilities
pub const MirrorNodeContractQuery = struct {
    allocator: std.mem.Allocator,
    contract_id: ?ContractId,
    contract_evm_address: ?[]const u8,
    sender: ?AccountId,
    sender_evm_address: ?[]const u8,
    call_data: []const u8,
    value: ?i64,
    gas_limit: ?i64,
    gas_price: ?i64,
    block_number: ?i64,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .contract_id = null,
            .contract_evm_address = null,
            .sender = null,
            .sender_evm_address = null,
            .call_data = &[_]u8{},
            .value = null,
            .gas_limit = null,
            .gas_price = null,
            .block_number = null,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.contract_evm_address) |addr| {
            if (addr.len > 0) self.allocator.free(addr);
        }
        if (self.sender_evm_address) |addr| {
            if (addr.len > 0) self.allocator.free(addr);
        }
        if (self.call_data.len > 0) {
            self.allocator.free(self.call_data);
        }
    }

    /// Get the contract ID
    pub fn getContractId(self: *const Self) ?ContractId {
        return self.contract_id;
    }

    /// Get the contract EVM address
    pub fn getContractEvmAddress(self: *const Self) ?[]const u8 {
        return self.contract_evm_address;
    }

    /// Get the sender account ID
    pub fn getSender(self: *const Self) ?AccountId {
        return self.sender;
    }

    /// Get the sender EVM address
    pub fn getSenderEvmAddress(self: *const Self) ?[]const u8 {
        return self.sender_evm_address;
    }

    /// Set function to call with parameters
    pub fn setFunction(self: *Self, name: []const u8, params: ?*ContractFunctionParameters) !*Self {
        const parameters = params orelse try ContractFunctionParameters.init(self.allocator);
        defer if (params == null) parameters.deinit();

        if (self.call_data.len > 0) {
            self.allocator.free(self.call_data);
        }
        self.call_data = try parameters.build(name);
    }

    /// Get the call data
    pub fn getCallData(self: *const Self) []const u8 {
        return self.call_data;
    }

    /// Get the value to send
    pub fn getValue(self: *const Self) i64 {
        return self.value orelse 0;
    }

    /// Get the gas limit
    pub fn getGasLimit(self: *const Self) i64 {
        return self.gas_limit orelse 0;
    }

    /// Get the gas price
    pub fn getGasPrice(self: *const Self) i64 {
        return self.gas_price orelse 0;
    }

    /// Get the block number
    pub fn getBlockNumber(self: *const Self) i64 {
        return self.block_number orelse 0;
    }

    /// Fill EVM addresses from IDs if needed
    fn fillEvmAddresses(self: *Self) !void {
        // Fill contract EVM address
        if (self.contract_evm_address == null) {
            if (self.contract_id == null) {
                return error.ContractIdNotSet;
            }
            const address = try self.contract_id.?.toEvmAddress(self.allocator);
            self.contract_evm_address = address;
        }

        // Fill sender EVM address
        if (self.sender_evm_address == null and self.sender != null) {
            const address = try self.sender.?.toEvmAddress(self.allocator);
            self.sender_evm_address = address;
        }
    }

    /// Create JSON payload for mirror node request
    fn createJsonPayload(self: *Self, estimate: bool, block_number_str: []const u8) ![]u8 {
        var list = std.ArrayList(u8).init(self.allocator);
        errdefer list.deinit();

        try list.appendSlice("{");
        
        // Add data field (hex encoded)
        try list.appendSlice("\"data\":\"");
        for (self.call_data) |byte| {
            try std.fmt.format(list.writer(), "{x:0>2}", .{byte});
        }
        try list.appendSlice("\",");

        // Add to field
        if (self.contract_evm_address) |addr| {
            try std.fmt.format(list.writer(), "\"to\":\"{s}\",", .{addr});
        }

        // Add estimate field
        try std.fmt.format(list.writer(), "\"estimate\":{},", .{estimate});

        // Add block number
        try std.fmt.format(list.writer(), "\"blockNumber\":\"{s}\"", .{block_number_str});

        // Conditionally add optional fields
        if (self.sender_evm_address) |addr| {
            try std.fmt.format(list.writer(), ",\"from\":\"{s}\"", .{addr});
        }
        if (self.gas_limit) |gas| {
            try std.fmt.format(list.writer(), ",\"gas\":{}", .{gas});
        }
        if (self.gas_price) |price| {
            try std.fmt.format(list.writer(), ",\"gasPrice\":{}", .{price});
        }
        if (self.value) |val| {
            try std.fmt.format(list.writer(), ",\"value\":{}", .{val});
        }

        try list.append('}');
        
        return list.toOwnedSlice();
    }

    /// Perform contract call to mirror node
    fn performContractCallToMirrorNode(self: *Self, client: *Client, json_payload: []const u8) !std.json.Value {
        const mirror_network = client.getMirrorNetwork();
        if (mirror_network == null or mirror_network.?.len == 0) {
            return error.MirrorNodeNotSet;
        }

        const mirror_url = mirror_network.?[0];
        const index = std.mem.indexOf(u8, mirror_url, ":") orelse return error.InvalidMirrorUrlFormat;
        const base_url = mirror_url[0..index];

        const protocol = if (client.getLedgerId() == null) "http" else "https";
        const port = if (client.getLedgerId() == null) ":8545" else "";
        
        var url = std.ArrayList(u8).init(self.allocator);
        defer url.deinit();
        try std.fmt.format(url.writer(), "{s}://{s}{s}/api/v1/contracts/call", .{ protocol, base_url, port });

        // Make HTTP POST request
        var http_client = std.http.Client{ .allocator = self.allocator };
        defer http_client.deinit();

        const uri = try std.Uri.parse(url.items);
        var headers = std.http.Headers{ .allocator = self.allocator };
        defer headers.deinit();
        try headers.append("Content-Type", "application/json");

        var req = try http_client.request(.POST, uri, headers, .{});
        defer req.deinit();

        req.transfer_encoding = .chunked;
        try req.start();
        try req.writer().writeAll(json_payload);
        try req.finish();
        try req.wait();

        if (req.response.status != .ok) {
            return error.MirrorNodeRequestFailed;
        }

        // Parse response
        const body = try req.reader().readAllAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(body);

        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, body, .{});
        return parsed.value;
    }

    /// Estimate gas for the contract call
    pub fn estimateGas(self: *Self, client: *Client) !u64 {
        try self.fillEvmAddresses();
        
        const json_payload = try self.createJsonPayload(true, "latest");
        defer self.allocator.free(json_payload);

        const result = try self.performContractCallToMirrorNode(client, json_payload);
        defer result.deinit();

        const result_str = result.object.get("result") orelse return error.NoResult;
        if (result_str != .string) return error.InvalidResultType;
        
        var hex_str = result_str.string;
        if (std.mem.startsWith(u8, hex_str, "0x")) {
            hex_str = hex_str[2..];
        }

        return try std.fmt.parseInt(u64, hex_str, 16);
    }

    /// Perform contract call and return result
    pub fn call(self: *Self, client: *Client) ![]u8 {
        try self.fillEvmAddresses();

        const block_number_str = if (self.block_number) |num|
            try std.fmt.allocPrint(self.allocator, "{}", .{num})
        else
            try self.allocator.dupe(u8, "latest");
        defer self.allocator.free(block_number_str);

        const json_payload = try self.createJsonPayload(false, block_number_str);
        defer self.allocator.free(json_payload);

        const result = try self.performContractCallToMirrorNode(client, json_payload);
        defer result.deinit();

        const result_str = result.object.get("result") orelse return error.NoResult;
        if (result_str != .string) return error.InvalidResultType;
        return try self.allocator.dupe(u8, result_str.string);
    }
};

test "MirrorNodeContractQuery initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var query = MirrorNodeContractQuery.init(allocator);
    defer query.deinit();

    try testing.expect(query.contract_id == null);
    try testing.expect(query.sender == null);
    try testing.expectEqual(@as(i64, 0), query.getValue());
    try testing.expectEqual(@as(i64, 0), query.getGasLimit());
}
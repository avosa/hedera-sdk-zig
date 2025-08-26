const std = @import("std");
const ContractId = @import("../core/id.zig").ContractId;
const AccountId = @import("../core/id.zig").AccountId;
const Timestamp = @import("../core/timestamp.zig").Timestamp;
const ContractLogInfo = @import("../contract/contract_log_info.zig").ContractLogInfo;
const ContractStateChange = @import("../contract/contract_log_info.zig").ContractStateChange;
const MirrorNodeClient = @import("mirror_node_client.zig").MirrorNodeClient;
const JsonParser = @import("../utils/json.zig").JsonParser;

// Mirror node contract call result query
pub const ContractCallResultQuery = struct {
    mirror_client: *MirrorNodeClient,
    contract_id: ?ContractId,
    timestamp: ?Timestamp,
    transaction_id: ?[]const u8,
    from: ?Timestamp,
    limit: u32,
    order: Order,
    allocator: std.mem.Allocator,

    pub const Order = enum {
        asc,
        desc,
        
        pub fn toString(self: Order) []const u8 {
            return switch (self) {
                .asc => "asc",
                .desc => "desc",
            };
        }
    };

    pub fn init(allocator: std.mem.Allocator, mirror_client: *MirrorNodeClient) ContractCallResultQuery {
        return ContractCallResultQuery{
            .mirror_client = mirror_client,
            .contract_id = null,
            .timestamp = null,
            .transaction_id = null,
            .from = null,
            .limit = 25,
            .order = .desc,
            .allocator = allocator,
        };
    }

    pub fn setContractId(self: *ContractCallResultQuery, contract_id: ContractId) !*ContractCallResultQuery {
        self.contract_id = contract_id;
        return self;
    }

    pub fn setTimestamp(self: *ContractCallResultQuery, timestamp: Timestamp) !*ContractCallResultQuery {
        self.timestamp = timestamp;
        return self;
    }

    pub fn setTransactionId(self: *ContractCallResultQuery, transaction_id: []const u8) !*ContractCallResultQuery {
        self.transaction_id = transaction_id;
        return self;
    }

    pub fn setFrom(self: *ContractCallResultQuery, from: Timestamp) !*ContractCallResultQuery {
        self.from = from;
        return self;
    }

    pub fn setLimit(self: *ContractCallResultQuery, limit: u32) !*ContractCallResultQuery {
        self.limit = @min(limit, 1000);
        return self;
    }

    pub fn setOrder(self: *ContractCallResultQuery, order: Order) !*ContractCallResultQuery {
        self.order = order;
        return self;
    }

    pub fn execute(self: *ContractCallResultQuery) ![]ContractResult {
        const url = try self.buildUrl();
        defer self.allocator.free(url);

        const response = try self.mirror_client.get(url);
        defer self.allocator.free(response);

        return self.parseResults(response);
    }

    fn buildUrl(self: *ContractCallResultQuery) ![]u8 {
        const url = try std.fmt.allocPrint(self.allocator, "/api/v1/contracts/results");

        if (self.contract_id) |contract_id| {
            const new_url = try std.fmt.allocPrint(
                self.allocator,
                "{s}/{d}.{d}.{d}",
                .{ url, contract_id.shard, contract_id.realm, contract_id.num }
            );
            self.allocator.free(url);
            url = new_url;
            return self;
        }

        var query_params = std.ArrayList([]const u8).init(self.allocator);
        defer {
            for (query_params.items) |param| {
                self.allocator.free(param);
            }
            query_params.deinit();
        }

        if (self.timestamp) |timestamp| {
            const param = try std.fmt.allocPrint(
                self.allocator,
                "timestamp={d}.{d:0>9}",
                .{ timestamp.seconds, timestamp.nanos }
            );
            try query_params.append(param);
        }

        if (self.transaction_id) |tx_id| {
            const param = try std.fmt.allocPrint(self.allocator, "transactionid={s}", .{tx_id});
            try query_params.append(param);
        }

        if (self.from) |from| {
            const param = try std.fmt.allocPrint(
                self.allocator,
                "timestamp=gte:{d}.{d:0>9}",
                .{ from.seconds, from.nanos }
            );
            try query_params.append(param);
        }

        if (self.limit != 25) {
            const param = try std.fmt.allocPrint(self.allocator, "limit={d}", .{self.limit});
            try query_params.append(param);
        }

        const param = try std.fmt.allocPrint(self.allocator, "order={s}", .{self.order.toString()});
        try query_params.append(param);

        if (query_params.items.len > 0) {
            var final_url = try std.fmt.allocPrint(self.allocator, "{s}?", .{url});
            self.allocator.free(url);
            
            for (query_params.items, 0..) |query_param, i| {
                const separator = if (i > 0) "&" else "";
                const new_url = try std.fmt.allocPrint(
                    self.allocator,
                    "{s}{s}{s}",
                    .{ final_url, separator, query_param }
                );
                self.allocator.free(final_url);
                final_url = new_url;
            }
            
            return final_url;
        }

        return url;
    }

    fn parseResults(self: *ContractCallResultQuery, json: []const u8) ![]ContractResult {
        var parser = JsonParser.init(self.allocator);
        defer parser.deinit();

        var root = try parser.parse(json);
        defer root.deinit(self.allocator);

        const obj = root.getObject() orelse return error.InvalidJson;
        const results = obj.get("results").?.getArray() orelse return error.InvalidField;
        var contract_results = std.ArrayList(ContractResult).init(self.allocator);
        defer contract_results.deinit();

        for (results) |result| {
            const result_obj = result.getObject() orelse continue;
            const contract_result = try parseContractResult(result_obj, self.allocator);
            try contract_results.append(contract_result);
        }

        return contract_results.toOwnedSlice();
    }
};

// Contract state query for storage slots
pub const ContractStateQuery = struct {
    mirror_client: *MirrorNodeClient,
    contract_id: ContractId,
    slot: ?[32]u8,
    limit: u32,
    order: ContractCallResultQuery.Order,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, mirror_client: *MirrorNodeClient, contract_id: ContractId) ContractStateQuery {
        return ContractStateQuery{
            .mirror_client = mirror_client,
            .contract_id = contract_id,
            .slot = null,
            .limit = 25,
            .order = .desc,
            .allocator = allocator,
        };
    }

    pub fn setSlot(self: *ContractStateQuery, slot: [32]u8) !*ContractStateQuery {
        self.slot = slot;
        return self;
    }

    pub fn setLimit(self: *ContractStateQuery, limit: u32) !*ContractStateQuery {
        self.limit = @min(limit, 1000);
        return self;
    }

    pub fn setOrder(self: *ContractStateQuery, order: ContractCallResultQuery.Order) !*ContractStateQuery {
        self.order = order;
        return self;
    }

    pub fn execute(self: *ContractStateQuery) ![]ContractStateEntry {
        const url = try self.buildUrl();
        defer self.allocator.free(url);

        const response = try self.mirror_client.get(url);
        defer self.allocator.free(response);

        return self.parseState(response);
    }

    fn buildUrl(self: *ContractStateQuery) ![]u8 {
        const url = try std.fmt.allocPrint(
            self.allocator,
            "/api/v1/contracts/{d}.{d}.{d}/state",
            .{ self.contract_id.shard, self.contract_id.realm, self.contract_id.num }
        );

        var query_params = std.ArrayList([]const u8).init(self.allocator);
        defer {
            for (query_params.items) |param| {
                self.allocator.free(param);
            }
            query_params.deinit();
        }

        if (self.slot) |slot| {
            const slot_hex = try std.fmt.allocPrint(self.allocator, "{x}", .{std.fmt.fmtSliceHexLower(&slot)});
            defer self.allocator.free(slot_hex);
            
            const param = try std.fmt.allocPrint(self.allocator, "slot=0x{s}", .{slot_hex});
            try query_params.append(param);
        }

        if (self.limit != 25) {
            const param = try std.fmt.allocPrint(self.allocator, "limit={d}", .{self.limit});
            try query_params.append(param);
        }

        const param = try std.fmt.allocPrint(self.allocator, "order={s}", .{self.order.toString()});
        try query_params.append(param);

        if (query_params.items.len > 0) {
            var final_url = try std.fmt.allocPrint(self.allocator, "{s}?", .{url});
            self.allocator.free(url);
            
            for (query_params.items, 0..) |p, i| {
                const separator = if (i > 0) "&" else "";
                const new_url = try std.fmt.allocPrint(
                    self.allocator,
                    "{s}{s}{s}",
                    .{ final_url, separator, p }
                );
                self.allocator.free(final_url);
                final_url = new_url;
            }
            
            return final_url;
        }

        return url;
    }

    fn parseState(self: *ContractStateQuery, json: []const u8) ![]ContractStateEntry {
        var parser = JsonParser.init(self.allocator);
        defer parser.deinit();

        var root = try parser.parse(json);
        defer root.deinit(self.allocator);

        const obj = root.getObject() orelse return error.InvalidJson;
        const state = obj.get("state").?.getArray() orelse return error.InvalidField;
        var entries = std.ArrayList(ContractStateEntry).init(self.allocator);
        defer entries.deinit();

        for (state) |entry| {
            const entry_obj = entry.getObject() orelse continue;
            const state_entry = try parseStateEntry(entry_obj, self.allocator);
            try entries.append(state_entry);
        }

        return entries.toOwnedSlice();
    }
};

// Contract bytecode query
pub const ContractBytecodeQuery = struct {
    mirror_client: *MirrorNodeClient,
    contract_id: ContractId,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, mirror_client: *MirrorNodeClient, contract_id: ContractId) ContractBytecodeQuery {
        return ContractBytecodeQuery{
            .mirror_client = mirror_client,
            .contract_id = contract_id,
            .allocator = allocator,
        };
    }

    pub fn execute(self: *ContractBytecodeQuery) !ContractBytecode {
        const url = try std.fmt.allocPrint(
            self.allocator,
            "/api/v1/contracts/{d}.{d}.{d}",
            .{ self.contract_id.shard, self.contract_id.realm, self.contract_id.num }
        );
        defer self.allocator.free(url);

        const response = try self.mirror_client.get(url);
        defer self.allocator.free(response);

        return self.parseBytecode(response);
    }

    fn parseBytecode(self: *ContractBytecodeQuery, json: []const u8) !ContractBytecode {
        var parser = JsonParser.init(self.allocator);
        defer parser.deinit();

        var root = try parser.parse(json);
        defer root.deinit(self.allocator);

        const obj = root.getObject() orelse return error.InvalidJson;
        const bytecode_hex = obj.get("bytecode").?.getString() orelse return error.MissingBytecode;
        const runtime_bytecode_hex = obj.get("runtime_bytecode").?.getString() orelse "";

        var bytecode: []u8 = &[_]u8{};
        var runtime_bytecode: []u8 = &[_]u8{};

        if (bytecode_hex.len > 2 and std.mem.startsWith(u8, bytecode_hex, "0x")) {
            const hex_data = bytecode_hex[2..];
            bytecode = try self.allocator.alloc(u8, hex_data.len / 2);
            _ = try std.fmt.hexToBytes(bytecode, hex_data);
        }

        if (runtime_bytecode_hex.len > 2 and std.mem.startsWith(u8, runtime_bytecode_hex, "0x")) {
            const hex_data = runtime_bytecode_hex[2..];
            runtime_bytecode = try self.allocator.alloc(u8, hex_data.len / 2);
            _ = try std.fmt.hexToBytes(runtime_bytecode, hex_data);
        }

        return ContractBytecode{
            .contract_id = self.contract_id,
            .bytecode = bytecode,
            .runtime_bytecode = runtime_bytecode,
        };
    }
};

// Contract action/call result from mirror node
pub const ContractResult = struct {
    contract_id: ContractId,
    transaction_id: []const u8,
    timestamp: Timestamp,
    function_name: []const u8,
    function_parameters: []const u8,
    gas_limit: u64,
    gas_used: u64,
    result: []const u8,
    error_message: ?[]const u8,
    logs: std.ArrayList(ContractLogInfo),
    state_changes: std.ArrayList(ContractStateChange),

    pub fn deinit(self: *ContractResult, allocator: std.mem.Allocator) void {
        allocator.free(self.transaction_id);
        allocator.free(self.function_name);
        allocator.free(self.function_parameters);
        allocator.free(self.result);
        if (self.error_message) |err| {
            allocator.free(err);
        }
        
        for (self.logs.items) |*log| {
            log.deinit();
        }
        self.logs.deinit();
        
        for (self.state_changes.items) |*change| {
            change.deinit();
        }
        self.state_changes.deinit();
    }
};

// Contract state storage entry
pub const ContractStateEntry = struct {
    slot: [32]u8,
    value: [32]u8,
    timestamp: Timestamp,

    pub fn getSlotHex(self: *const ContractStateEntry, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "0x{x}", .{std.fmt.fmtSliceHexLower(&self.slot)});
    }

    pub fn getValueHex(self: *const ContractStateEntry, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "0x{x}", .{std.fmt.fmtSliceHexLower(&self.value)});
    }

    pub fn equals(self: *const ContractStateEntry, other: *const ContractStateEntry) bool {
        return std.mem.eql(u8, &self.slot, &other.slot) and
               std.mem.eql(u8, &self.value, &other.value);
    }
};

// Contract bytecode from mirror node
pub const ContractBytecode = struct {
    contract_id: ContractId,
    bytecode: []const u8,
    runtime_bytecode: []const u8,

    pub fn deinit(self: *ContractBytecode, allocator: std.mem.Allocator) void {
        if (self.bytecode.len > 0) {
            allocator.free(self.bytecode);
        }
        if (self.runtime_bytecode.len > 0) {
            allocator.free(self.runtime_bytecode);
        }
    }

    pub fn getBytecodeHex(self: *const ContractBytecode, allocator: std.mem.Allocator) ![]u8 {
        if (self.bytecode.len == 0) {
            return allocator.dupe(u8, "0x");
        }
        return std.fmt.allocPrint(allocator, "0x{x}", .{std.fmt.fmtSliceHexLower(self.bytecode)});
    }

    pub fn getRuntimeBytecodeHex(self: *const ContractBytecode, allocator: std.mem.Allocator) ![]u8 {
        if (self.runtime_bytecode.len == 0) {
            return allocator.dupe(u8, "0x");
        }
        return std.fmt.allocPrint(allocator, "0x{x}", .{std.fmt.fmtSliceHexLower(self.runtime_bytecode)});
    }
};

fn parseContractResult(obj: std.HashMap([]const u8, JsonValue, std.hash_map.StringContext, std.hash_map.default_max_load_percentage), allocator: std.mem.Allocator) !ContractResult {
    const JsonValue = @import("../utils/json.zig").JsonValue;
    
    const contract_id_str = obj.get("contract_id").?.getString() orelse return error.MissingContractId;
    const contract_id = try parseContractIdFromString(contract_id_str);
    
    const timestamp_str = obj.get("timestamp").?.getString() orelse return error.MissingTimestamp;
    const timestamp = try parseTimestampFromString(timestamp_str);
    
    var result = ContractResult{
        .contract_id = contract_id,
        .transaction_id = try allocator.dupe(u8, obj.get("transaction_id").?.getString() orelse ""),
        .timestamp = timestamp,
        .function_name = try allocator.dupe(u8, obj.get("function_name").?.getString() orelse ""),
        .function_parameters = try allocator.dupe(u8, obj.get("function_parameters").?.getString() orelse ""),
        .gas_limit = @intCast(obj.get("gas_limit").?.getInt() orelse 0),
        .gas_used = @intCast(obj.get("gas_used").?.getInt() orelse 0),
        .result = try allocator.dupe(u8, obj.get("result").?.getString() orelse ""),
        .error_message = if (obj.get("error_message")) |err_val| 
            if (err_val.getString()) |err_str| try allocator.dupe(u8, err_str) else null
        else 
            null,
        .logs = std.ArrayList(ContractLogInfo).init(allocator),
        .state_changes = std.ArrayList(ContractStateChange).init(allocator),
    };

    if (obj.get("logs")) |logs_val| {
        if (logs_val.getArray()) |logs_array| {
            for (logs_array) |log_val| {
                if (log_val.getObject()) |log_obj| {
                    const log = try parseContractLog(log_obj, allocator);
                    try result.logs.append(log);
                }
            }
        }
    }

    return result;
}

fn parseStateEntry(obj: std.HashMap([]const u8, JsonValue, std.hash_map.StringContext, std.hash_map.default_max_load_percentage), allocator: std.mem.Allocator) !ContractStateEntry {
    const JsonValue = @import("../utils/json.zig").JsonValue;
    _ = allocator;
    
    const slot_str = obj.get("slot").?.getString() orelse return error.MissingSlot;
    const value_str = obj.get("value").?.getString() orelse return error.MissingValue;
    const timestamp_str = obj.get("timestamp").?.getString() orelse return error.MissingTimestamp;
    
    var slot: [32]u8 = std.mem.zeroes([32]u8);
    var value: [32]u8 = std.mem.zeroes([32]u8);
    
    if (std.mem.startsWith(u8, slot_str, "0x")) {
        _ = try std.fmt.hexToBytes(&slot, slot_str[2..]);
    }
    
    if (std.mem.startsWith(u8, value_str, "0x")) {
        _ = try std.fmt.hexToBytes(&value, value_str[2..]);
    }
    
    return ContractStateEntry{
        .slot = slot,
        .value = value,
        .timestamp = try parseTimestampFromString(timestamp_str),
    };
}

fn parseContractLog(obj: std.HashMap([]const u8, JsonValue, std.hash_map.StringContext, std.hash_map.default_max_load_percentage), allocator: std.mem.Allocator) !ContractLogInfo {
    const JsonValue = @import("../utils/json.zig").JsonValue;
    
    const contract_id_str = obj.get("address").?.getString() orelse return error.MissingAddress;
    const contract_id = try parseContractIdFromString(contract_id_str);
    
    var log = ContractLogInfo.init(allocator, contract_id);
    
    if (obj.get("data")) |data_val| {
        if (data_val.getString()) |data_str| {
            const hex_data = if (std.mem.startsWith(u8, data_str, "0x")) data_str[2..] else data_str;
            const data = try allocator.alloc(u8, hex_data.len / 2);
            _ = try std.fmt.hexToBytes(data, hex_data);
            try log.setData(data);
        }
    }
    
    if (obj.get("topics")) |topics_val| {
        if (topics_val.getArray()) |topics_array| {
            for (topics_array) |topic_val| {
                if (topic_val.getString()) |topic_str| {
                    var topic: [32]u8 = std.mem.zeroes([32]u8);
                    const hex_topic = if (std.mem.startsWith(u8, topic_str, "0x")) topic_str[2..] else topic_str;
                    _ = try std.fmt.hexToBytes(&topic, hex_topic);
                    try log.addTopic(topic);
                }
            }
        }
    }
    
    return log;
}

fn parseContractIdFromString(str: []const u8) !ContractId {
    var parts = std.mem.tokenizeAny(u8, str, ".");
    const shard_str = parts.next() orelse return error.InvalidContractId;
    const realm_str = parts.next() orelse return error.InvalidContractId;
    const num_str = parts.next() orelse return error.InvalidContractId;
    
    const shard = try std.fmt.parseInt(i64, shard_str, 10);
    const realm = try std.fmt.parseInt(i64, realm_str, 10);
    const num = try std.fmt.parseInt(i64, num_str, 10);
    
    return ContractId{
        .entity = .{
            .shard = shard,
            .realm = realm,
            .num = num,
        },
    };
}

fn parseTimestampFromString(str: []const u8) !Timestamp {
    var parts = std.mem.tokenizeAny(u8, str, ".");
    const seconds_str = parts.next() orelse return error.InvalidTimestamp;
    const nanos_str = parts.next() orelse "0";
    
    const seconds = try std.fmt.parseInt(i64, seconds_str, 10);
    const nanos = try std.fmt.parseInt(i32, nanos_str, 10);
    
    return Timestamp{
        .seconds = seconds,
        .nanos = nanos,
    };
}
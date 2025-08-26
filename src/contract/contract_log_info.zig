const std = @import("std");
const ContractId = @import("../core/id.zig").ContractId;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;

// Contract log information from event emissions
pub const ContractLogInfo = struct {
    contract_id: ContractId,
    bloom: [256]u8,
    topics: std.ArrayList([32]u8),
    data: []u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, contract_id: ContractId) ContractLogInfo {
        return ContractLogInfo{
            .contract_id = contract_id,
            .bloom = std.mem.zeroes([256]u8),
            .topics = std.ArrayList([32]u8).init(allocator),
            .data = &[_]u8{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ContractLogInfo) void {
        self.topics.deinit();
        if (self.data.len > 0) {
            self.allocator.free(self.data);
        }
    }

    pub fn setBloom(self: *ContractLogInfo, bloom: [256]u8) !*ContractLogInfo {
        self.bloom = bloom;
    }

    pub fn addTopic(self: *ContractLogInfo, topic: [32]u8) !void {
        try self.topics.append(topic);
    }

    pub fn setData(self: *ContractLogInfo, data: []const u8) !*ContractLogInfo {
        if (self.data.len > 0) {
            self.allocator.free(self.data);
            return self;
        }
        self.data = try self.allocator.dupe(u8, data);
    }

    pub fn getContractId(self: *const ContractLogInfo) ContractId {
        return self.contract_id;
    }

    pub fn getBloom(self: *const ContractLogInfo) [256]u8 {
        return self.bloom;
    }

    pub fn getTopics(self: *const ContractLogInfo) []const [32]u8 {
        return self.topics.items;
    }

    pub fn getData(self: *const ContractLogInfo) []const u8 {
        return self.data;
    }

    pub fn getTopicCount(self: *const ContractLogInfo) usize {
        return self.topics.items.len;
    }

    pub fn getTopic(self: *const ContractLogInfo, index: usize) ?[32]u8 {
        if (index >= self.topics.items.len) return null;
        return self.topics.items[index];
    }

    // Event signature is typically the first topic (topic[0])
    pub fn getEventSignature(self: *const ContractLogInfo) ?[32]u8 {
        return self.getTopic(0);
    }

    // Indexed parameters are stored in topics[1..n]
    pub fn getIndexedParameters(self: *const ContractLogInfo, allocator: std.mem.Allocator) ![][32]u8 {
        if (self.topics.items.len <= 1) {
            return try allocator.alloc([32]u8, 0);
        }
        return try allocator.dupe([32]u8, self.topics.items[1..]);
    }

    // Non-indexed parameters are stored in data
    pub fn getNonIndexedData(self: *const ContractLogInfo) []const u8 {
        return self.data;
    }

    pub fn toProtobuf(self: *const ContractLogInfo, allocator: std.mem.Allocator) ![]u8 {
        var writer = ProtoWriter.init(allocator);
        defer writer.deinit();

        // contractID = 1
        var contract_writer = ProtoWriter.init(allocator);
        defer contract_writer.deinit();
        try contract_writer.writeInt64(1, @intCast(self.contract_id.shard));
        try contract_writer.writeInt64(2, @intCast(self.contract_id.realm));
        try contract_writer.writeInt64(3, @intCast(self.contract_id.num));
        const contract_bytes = try contract_writer.toOwnedSlice();
        defer allocator.free(contract_bytes);
        try writer.writeMessage(1, contract_bytes);

        // bloom = 2
        try writer.writeBytes(2, &self.bloom);

        // topic = 3 (repeated)
        for (self.topics.items) |topic| {
            try writer.writeBytes(3, &topic);
        }

        // data = 4
        if (self.data.len > 0) {
            try writer.writeBytes(4, self.data);
        }

        return writer.toOwnedSlice();
    }

    pub fn fromProtobuf(data: []const u8, allocator: std.mem.Allocator) !ContractLogInfo {
        var reader = ProtoReader.init(data);
        const contract_id = ContractId.init(0, 0, 0);
        var log_info = ContractLogInfo.init(allocator, contract_id);
        errdefer log_info.deinit();

        while (try reader.next()) |field| {
            switch (field.number) {
                1 => {
                    var contract_reader = ProtoReader.init(field.data);
                    var shard: i64 = 0;
                    var realm: i64 = 0;
                    var num: i64 = 0;

                    while (try contract_reader.next()) |contract_field| {
                        switch (contract_field.number) {
                            1 => shard = try contract_reader.readInt64(contract_field.data),
                            2 => realm = try contract_reader.readInt64(contract_field.data),
                            3 => num = try contract_reader.readInt64(contract_field.data),
                            else => {},
                        }
                    }

                    log_info.contract_id = ContractId.init(@intCast(shard), @intCast(realm), @intCast(num));
                },
                2 => {
                    if (field.data.len == 256) {
                        @memcpy(&log_info.bloom, field.data);
                    }
                },
                3 => {
                    if (field.data.len == 32) {
                        var topic: [32]u8 = undefined;
                        @memcpy(&topic, field.data);
                        try log_info.addTopic(topic);
                    }
                },
                4 => {
                    try log_info.setData(field.data);
                },
                else => {},
            }
        }

        return log_info;
    }

    pub fn clone(self: *const ContractLogInfo, allocator: std.mem.Allocator) !ContractLogInfo {
        var result = ContractLogInfo.init(allocator, self.contract_id);
        errdefer result.deinit();

        result.bloom = self.bloom;
        
        for (self.topics.items) |topic| {
            try result.addTopic(topic);
        }

        if (self.data.len > 0) {
            try result.setData(self.data);
        }

        return result;
    }

    pub fn equals(self: *const ContractLogInfo, other: *const ContractLogInfo) bool {
        if (self.contract_id.shard != other.contract_id.shard or
            self.contract_id.realm != other.contract_id.realm or
            self.contract_id.num != other.contract_id.num) {
            return false;
        }

        if (!std.mem.eql(u8, &self.bloom, &other.bloom)) {
            return false;
        }

        if (self.topics.items.len != other.topics.items.len) {
            return false;
        }

        for (self.topics.items, other.topics.items) |self_topic, other_topic| {
            if (!std.mem.eql(u8, &self_topic, &other_topic)) {
                return false;
            }
        }

        return std.mem.eql(u8, self.data, other.data);
    }

    pub fn toString(self: *const ContractLogInfo, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "ContractLogInfo{{contract={}, topics={d}, data_len={d}}}", .{
            self.contract_id,
            self.topics.items.len,
            self.data.len,
        });
    }
};

// Collection of contract log information
pub const ContractLogInfoList = struct {
    logs: std.ArrayList(ContractLogInfo),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ContractLogInfoList {
        return ContractLogInfoList{
            .logs = std.ArrayList(ContractLogInfo).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ContractLogInfoList) void {
        for (self.logs.items) |*log| {
            log.deinit();
        }
        self.logs.deinit();
    }

    pub fn add(self: *ContractLogInfoList, log: ContractLogInfo) !void {
        try self.logs.append(log);
    }

    pub fn get(self: *const ContractLogInfoList, index: usize) ?*const ContractLogInfo {
        if (index >= self.logs.items.len) return null;
        return &self.logs.items[index];
    }

    pub fn size(self: *const ContractLogInfoList) usize {
        return self.logs.items.len;
    }

    pub fn isEmpty(self: *const ContractLogInfoList) bool {
        return self.logs.items.len == 0;
    }

    pub fn clear(self: *ContractLogInfoList) void {
        for (self.logs.items) |*log| {
            log.deinit();
        }
        self.logs.clearRetainingCapacity();
    }

    pub fn getLogsForContract(self: *const ContractLogInfoList, contract_id: ContractId, allocator: std.mem.Allocator) ![]ContractLogInfo {
        var result = std.ArrayList(ContractLogInfo).init(allocator);
        defer result.deinit();

        for (self.logs.items) |log| {
            if (log.contract_id.shard == contract_id.shard and
                log.contract_id.realm == contract_id.realm and
                log.contract_id.num == contract_id.num) {
                try result.append(try log.clone(allocator));
            }
        }

        return result.toOwnedSlice();
    }

    pub fn filterByTopic(self: *const ContractLogInfoList, topic: [32]u8, allocator: std.mem.Allocator) ![]ContractLogInfo {
        var result = std.ArrayList(ContractLogInfo).init(allocator);
        defer result.deinit();

        for (self.logs.items) |log| {
            for (log.topics.items) |log_topic| {
                if (std.mem.eql(u8, &log_topic, &topic)) {
                    try result.append(try log.clone(allocator));
                    break;
                }
            }
        }

        return result.toOwnedSlice();
    }

    pub fn filterByEventSignature(self: *const ContractLogInfoList, event_signature: [32]u8, allocator: std.mem.Allocator) ![]ContractLogInfo {
        var result = std.ArrayList(ContractLogInfo).init(allocator);
        defer result.deinit();

        for (self.logs.items) |log| {
            if (log.getEventSignature()) |signature| {
                if (std.mem.eql(u8, &signature, &event_signature)) {
                    try result.append(try log.clone(allocator));
                }
            }
        }

        return result.toOwnedSlice();
    }
};

// Contract state change information
pub const ContractStateChange = struct {
    contract_id: ContractId,
    storage_changes: std.ArrayList(StorageChange),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, contract_id: ContractId) ContractStateChange {
        return ContractStateChange{
            .contract_id = contract_id,
            .storage_changes = std.ArrayList(StorageChange).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ContractStateChange) void {
        for (self.storage_changes.items) |*change| {
            change.deinit();
        }
        self.storage_changes.deinit();
    }

    pub fn addStorageChange(self: *ContractStateChange, slot: [32]u8, value_read: [32]u8, value_written: ?[32]u8) !void {
        const change = StorageChange{
            .slot = slot,
            .value_read = value_read,
            .value_written = value_written,
        };
        try self.storage_changes.append(change);
    }

    pub fn getContractId(self: *const ContractStateChange) ContractId {
        return self.contract_id;
    }

    pub fn getStorageChanges(self: *const ContractStateChange) []const StorageChange {
        return self.storage_changes.items;
    }

    pub fn getChangeCount(self: *const ContractStateChange) usize {
        return self.storage_changes.items.len;
    }
};

// Individual storage slot change
pub const StorageChange = struct {
    slot: [32]u8,
    value_read: [32]u8,
    value_written: ?[32]u8,

    pub fn deinit(self: *StorageChange) void {
        _ = self;
    }

    pub fn getSlot(self: *const StorageChange) [32]u8 {
        return self.slot;
    }

    pub fn getValueRead(self: *const StorageChange) [32]u8 {
        return self.value_read;
    }

    pub fn getValueWritten(self: *const StorageChange) ?[32]u8 {
        return self.value_written;
    }

    pub fn wasWritten(self: *const StorageChange) bool {
        return self.value_written != null;
    }

    pub fn equals(self: *const StorageChange, other: *const StorageChange) bool {
        if (!std.mem.eql(u8, &self.slot, &other.slot)) {
            return false;
        }

        if (!std.mem.eql(u8, &self.value_read, &other.value_read)) {
            return false;
        }

        if (self.value_written == null and other.value_written != null) {
            return false;
        }

        if (self.value_written != null and other.value_written == null) {
            return false;
        }

        if (self.value_written != null and other.value_written != null) {
            return std.mem.eql(u8, &self.value_written.?, &other.value_written.?);
        }

        return true;
    }
};
const std = @import("std");
const Hbar = @import("hbar.zig").Hbar;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;

// Fee component breakdown for transaction cost calculation
pub const FeeComponents = struct {
    min: i64,
    max: i64,
    constant: i64,
    bpt: i64, // bytes per transaction
    vpt: i64, // verifications per transaction
    rbh: i64, // resource bytes hour
    sbh: i64, // storage bytes hour
    gas: i64, // gas cost
    tv: i64, // transaction value
    bpr: i64, // bytes per response
    sbpr: i64, // storage bytes per response

    pub fn init() FeeComponents {
        return FeeComponents{
            .min = 0,
            .max = 0,
            .constant = 0,
            .bpt = 0,
            .vpt = 0,
            .rbh = 0,
            .sbh = 0,
            .gas = 0,
            .tv = 0,
            .bpr = 0,
            .sbpr = 0,
        };
    }

    pub fn setMin(self: *FeeComponents, min: i64) !*FeeComponents {
        self.min = min;
        return self;
    }

    pub fn setMax(self: *FeeComponents, max: i64) !*FeeComponents {
        self.max = max;
        return self;
    }

    pub fn setConstant(self: *FeeComponents, constant: i64) !*FeeComponents {
        self.constant = constant;
        return self;
    }

    pub fn setBpt(self: *FeeComponents, bpt: i64) !*FeeComponents {
        self.bpt = bpt;
        return self;
    }

    pub fn setVpt(self: *FeeComponents, vpt: i64) !*FeeComponents {
        self.vpt = vpt;
        return self;
    }

    pub fn setRbh(self: *FeeComponents, rbh: i64) !*FeeComponents {
        self.rbh = rbh;
        return self;
    }

    pub fn setSbh(self: *FeeComponents, sbh: i64) !*FeeComponents {
        self.sbh = sbh;
        return self;
    }

    pub fn setGas(self: *FeeComponents, gas: i64) !*FeeComponents {
        self.gas = gas;
        return self;
    }

    pub fn setTv(self: *FeeComponents, tv: i64) !*FeeComponents {
        self.tv = tv;
        return self;
    }

    pub fn setBpr(self: *FeeComponents, bpr: i64) !*FeeComponents {
        self.bpr = bpr;
        return self;
    }

    pub fn setSbpr(self: *FeeComponents, sbpr: i64) !*FeeComponents {
        self.sbpr = sbpr;
        return self;
    }

    // Calculate total cost based on usage
    pub fn calculateCost(self: *const FeeComponents, usage: *const FeeData) i64 {
        var total: i64 = self.constant;
        
        total += self.bpt * usage.bytes_used;
        total += self.vpt * usage.verifications_used;
        total += self.rbh * usage.resource_bytes_hour;
        total += self.sbh * usage.storage_bytes_hour;
        total += self.gas * usage.gas_used;
        total += self.tv * usage.transaction_value;
        total += self.bpr * usage.bytes_per_response;
        total += self.sbpr * usage.storage_bytes_per_response;

        return @max(self.min, @min(self.max, total));
    }

    pub fn toHbar(self: *const FeeComponents, usage: *const FeeData) Hbar {
        return Hbar.fromTinybars(self.calculateCost(usage));
    }

    pub fn toProtobuf(self: *const FeeComponents, allocator: std.mem.Allocator) ![]u8 {
        var writer = ProtoWriter.init(allocator);
        defer writer.deinit();

        try writer.writeInt64(1, self.min);
        try writer.writeInt64(2, self.max);
        try writer.writeInt64(3, self.constant);
        try writer.writeInt64(4, self.bpt);
        try writer.writeInt64(5, self.vpt);
        try writer.writeInt64(6, self.rbh);
        try writer.writeInt64(7, self.sbh);
        try writer.writeInt64(8, self.gas);
        try writer.writeInt64(9, self.tv);
        try writer.writeInt64(10, self.bpr);
        try writer.writeInt64(11, self.sbpr);

        return writer.toOwnedSlice();
    }

    pub fn fromProtobuf(data: []const u8, allocator: std.mem.Allocator) !FeeComponents {
        _ = allocator;
        var reader = ProtoReader.init(data);
        var components = FeeComponents.init();

        while (try reader.next()) |field| {
            switch (field.number) {
                1 => components.min = try reader.readInt64(field.data),
                2 => components.max = try reader.readInt64(field.data),
                3 => components.constant = try reader.readInt64(field.data),
                4 => components.bpt = try reader.readInt64(field.data),
                5 => components.vpt = try reader.readInt64(field.data),
                6 => components.rbh = try reader.readInt64(field.data),
                7 => components.sbh = try reader.readInt64(field.data),
                8 => components.gas = try reader.readInt64(field.data),
                9 => components.tv = try reader.readInt64(field.data),
                10 => components.bpr = try reader.readInt64(field.data),
                11 => components.sbpr = try reader.readInt64(field.data),
                else => {},
            }
        }

        return components;
    }

    pub fn clone(self: *const FeeComponents) FeeComponents {
        return FeeComponents{
            .min = self.min,
            .max = self.max,
            .constant = self.constant,
            .bpt = self.bpt,
            .vpt = self.vpt,
            .rbh = self.rbh,
            .sbh = self.sbh,
            .gas = self.gas,
            .tv = self.tv,
            .bpr = self.bpr,
            .sbpr = self.sbpr,
        };
    }

    pub fn equals(self: *const FeeComponents, other: *const FeeComponents) bool {
        return self.min == other.min and
               self.max == other.max and
               self.constant == other.constant and
               self.bpt == other.bpt and
               self.vpt == other.vpt and
               self.rbh == other.rbh and
               self.sbh == other.sbh and
               self.gas == other.gas and
               self.tv == other.tv and
               self.bpr == other.bpr and
               self.sbpr == other.sbpr;
    }

    pub fn toString(self: *const FeeComponents, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "FeeComponents{{min={d}, max={d}, constant={d}, bpt={d}, vpt={d}, rbh={d}, sbh={d}, gas={d}, tv={d}, bpr={d}, sbpr={d}}}", .{
            self.min, self.max, self.constant, self.bpt, self.vpt, self.rbh, self.sbh, self.gas, self.tv, self.bpr, self.sbpr
        });
    }
};

// Fee data representing actual resource usage
pub const FeeData = struct {
    bytes_used: i64,
    verifications_used: i64,
    resource_bytes_hour: i64,
    storage_bytes_hour: i64,
    gas_used: i64,
    transaction_value: i64,
    bytes_per_response: i64,
    storage_bytes_per_response: i64,

    pub fn init() FeeData {
        return FeeData{
            .bytes_used = 0,
            .verifications_used = 0,
            .resource_bytes_hour = 0,
            .storage_bytes_hour = 0,
            .gas_used = 0,
            .transaction_value = 0,
            .bytes_per_response = 0,
            .storage_bytes_per_response = 0,
        };
    }

    pub fn setBytesUsed(self: *FeeData, bytes_used: i64) !*FeeData {
        self.bytes_used = bytes_used;
        return self;
    }

    pub fn setVerificationsUsed(self: *FeeData, verifications: i64) !*FeeData {
        self.verifications_used = verifications;
        return self;
    }

    pub fn setResourceBytesHour(self: *FeeData, rbh: i64) !*FeeData {
        self.resource_bytes_hour = rbh;
        return self;
    }

    pub fn setStorageBytesHour(self: *FeeData, sbh: i64) !*FeeData {
        self.storage_bytes_hour = sbh;
        return self;
    }

    pub fn setGasUsed(self: *FeeData, gas: i64) !*FeeData {
        self.gas_used = gas;
        return self;
    }

    pub fn setTransactionValue(self: *FeeData, value: i64) !*FeeData {
        self.transaction_value = value;
        return self;
    }

    pub fn setBytesPerResponse(self: *FeeData, bpr: i64) !*FeeData {
        self.bytes_per_response = bpr;
        return self;
    }

    pub fn setStorageBytesPerResponse(self: *FeeData, sbpr: i64) !*FeeData {
        self.storage_bytes_per_response = sbpr;
        return self;
    }

    pub fn toProtobuf(self: *const FeeData, allocator: std.mem.Allocator) ![]u8 {
        var writer = ProtoWriter.init(allocator);
        defer writer.deinit();

        try writer.writeInt64(1, self.bytes_used);
        try writer.writeInt64(2, self.verifications_used);
        try writer.writeInt64(3, self.resource_bytes_hour);
        try writer.writeInt64(4, self.storage_bytes_hour);
        try writer.writeInt64(5, self.gas_used);
        try writer.writeInt64(6, self.transaction_value);
        try writer.writeInt64(7, self.bytes_per_response);
        try writer.writeInt64(8, self.storage_bytes_per_response);

        return writer.toOwnedSlice();
    }

    pub fn fromProtobuf(data: []const u8, allocator: std.mem.Allocator) !FeeData {
        _ = allocator;
        var reader = ProtoReader.init(data);
        var fee_data = FeeData.init();

        while (try reader.next()) |field| {
            switch (field.number) {
                1 => fee_data.bytes_used = try reader.readInt64(field.data),
                2 => fee_data.verifications_used = try reader.readInt64(field.data),
                3 => fee_data.resource_bytes_hour = try reader.readInt64(field.data),
                4 => fee_data.storage_bytes_hour = try reader.readInt64(field.data),
                5 => fee_data.gas_used = try reader.readInt64(field.data),
                6 => fee_data.transaction_value = try reader.readInt64(field.data),
                7 => fee_data.bytes_per_response = try reader.readInt64(field.data),
                8 => fee_data.storage_bytes_per_response = try reader.readInt64(field.data),
                else => {},
            }
        }

        return fee_data;
    }

    pub fn clone(self: *const FeeData) FeeData {
        return FeeData{
            .bytes_used = self.bytes_used,
            .verifications_used = self.verifications_used,
            .resource_bytes_hour = self.resource_bytes_hour,
            .storage_bytes_hour = self.storage_bytes_hour,
            .gas_used = self.gas_used,
            .transaction_value = self.transaction_value,
            .bytes_per_response = self.bytes_per_response,
            .storage_bytes_per_response = self.storage_bytes_per_response,
        };
    }

    pub fn toString(self: *const FeeData, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "FeeData{{bytes={d}, verifications={d}, rbh={d}, sbh={d}, gas={d}, value={d}, bpr={d}, sbpr={d}}}", .{
            self.bytes_used, self.verifications_used, self.resource_bytes_hour, self.storage_bytes_hour, self.gas_used, self.transaction_value, self.bytes_per_response, self.storage_bytes_per_response
        });
    }
};

// Complete fee schedule for different types of operations
pub const FeeSchedule = struct {
    node_data: FeeComponents,
    network_data: FeeComponents,
    service_data: FeeComponents,

    pub fn init() FeeSchedule {
        return FeeSchedule{
            .node_data = FeeComponents.init(),
            .network_data = FeeComponents.init(),
            .service_data = FeeComponents.init(),
        };
    }

    pub fn setNodeData(self: *FeeSchedule, node_data: FeeComponents) !*FeeSchedule {
        self.node_data = node_data;
        return self;
    }

    pub fn setNetworkData(self: *FeeSchedule, network_data: FeeComponents) !*FeeSchedule {
        self.network_data = network_data;
        return self;
    }

    pub fn setServiceData(self: *FeeSchedule, service_data: FeeComponents) !*FeeSchedule {
        self.service_data = service_data;
        return self;
    }

    pub fn getNodeData(self: *const FeeSchedule) FeeComponents {
        return self.node_data;
    }

    pub fn getNetworkData(self: *const FeeSchedule) FeeComponents {
        return self.network_data;
    }

    pub fn getServiceData(self: *const FeeSchedule) FeeComponents {
        return self.service_data;
    }

    // Calculate total cost across all fee components
    pub fn calculateTotalCost(self: *const FeeSchedule, node_usage: *const FeeData, network_usage: *const FeeData, service_usage: *const FeeData) i64 {
        const node_cost = self.node_data.calculateCost(node_usage);
        const network_cost = self.network_data.calculateCost(network_usage);
        const service_cost = self.service_data.calculateCost(service_usage);
        
        return node_cost + network_cost + service_cost;
    }

    pub fn calculateTotalHbar(self: *const FeeSchedule, node_usage: *const FeeData, network_usage: *const FeeData, service_usage: *const FeeData) Hbar {
        return Hbar.fromTinybars(self.calculateTotalCost(node_usage, network_usage, service_usage));
    }

    pub fn toProtobuf(self: *const FeeSchedule, allocator: std.mem.Allocator) ![]u8 {
        var writer = ProtoWriter.init(allocator);
        defer writer.deinit();

        const node_bytes = try self.node_data.toProtobuf(allocator);
        defer allocator.free(node_bytes);
        try writer.writeMessage(1, node_bytes);

        const network_bytes = try self.network_data.toProtobuf(allocator);
        defer allocator.free(network_bytes);
        try writer.writeMessage(2, network_bytes);

        const service_bytes = try self.service_data.toProtobuf(allocator);
        defer allocator.free(service_bytes);
        try writer.writeMessage(3, service_bytes);

        return writer.toOwnedSlice();
    }

    pub fn fromProtobuf(data: []const u8, allocator: std.mem.Allocator) !FeeSchedule {
        var reader = ProtoReader.init(data);
        var schedule = FeeSchedule.init();

        while (try reader.next()) |field| {
            switch (field.number) {
                1 => schedule.node_data = try FeeComponents.fromProtobuf(field.data, allocator),
                2 => schedule.network_data = try FeeComponents.fromProtobuf(field.data, allocator),
                3 => schedule.service_data = try FeeComponents.fromProtobuf(field.data, allocator),
                else => {},
            }
        }

        return schedule;
    }

    pub fn clone(self: *const FeeSchedule) FeeSchedule {
        return FeeSchedule{
            .node_data = self.node_data.clone(),
            .network_data = self.network_data.clone(),
            .service_data = self.service_data.clone(),
        };
    }

    pub fn equals(self: *const FeeSchedule, other: *const FeeSchedule) bool {
        return self.node_data.equals(&other.node_data) and
               self.network_data.equals(&other.network_data) and
               self.service_data.equals(&other.service_data);
    }

    // Standard fee schedules for common operations
    pub fn cryptoTransferSchedule() FeeSchedule {
        return FeeSchedule{
            .node_data = FeeComponents{
                .min = 100,
                .max = 1000000,
                .constant = 100000,
                .bpt = 1000,
                .vpt = 1000,
                .rbh = 0,
                .sbh = 0,
                .gas = 0,
                .tv = 0,
                .bpr = 0,
                .sbpr = 0,
            },
            .network_data = FeeComponents{
                .min = 100,
                .max = 1000000,
                .constant = 100000,
                .bpt = 1000,
                .vpt = 1000,
                .rbh = 0,
                .sbh = 0,
                .gas = 0,
                .tv = 0,
                .bpr = 0,
                .sbpr = 0,
            },
            .service_data = FeeComponents{
                .min = 100,
                .max = 1000000,
                .constant = 100000,
                .bpt = 1000,
                .vpt = 1000,
                .rbh = 0,
                .sbh = 0,
                .gas = 0,
                .tv = 0,
                .bpr = 0,
                .sbpr = 0,
            },
        };
    }

    pub fn contractCallSchedule() FeeSchedule {
        return FeeSchedule{
            .node_data = FeeComponents{
                .min = 100,
                .max = 10000000,
                .constant = 500000,
                .bpt = 1000,
                .vpt = 1000,
                .rbh = 0,
                .sbh = 0,
                .gas = 852,
                .tv = 0,
                .bpr = 0,
                .sbpr = 0,
            },
            .network_data = FeeComponents{
                .min = 100,
                .max = 10000000,
                .constant = 500000,
                .bpt = 1000,
                .vpt = 1000,
                .rbh = 0,
                .sbh = 0,
                .gas = 852,
                .tv = 0,
                .bpr = 0,
                .sbpr = 0,
            },
            .service_data = FeeComponents{
                .min = 100,
                .max = 10000000,
                .constant = 500000,
                .bpt = 1000,
                .vpt = 1000,
                .rbh = 0,
                .sbh = 0,
                .gas = 852,
                .tv = 0,
                .bpr = 0,
                .sbpr = 0,
            },
        };
    }

    pub fn tokenTransferSchedule() FeeSchedule {
        return FeeSchedule{
            .node_data = FeeComponents{
                .min = 100,
                .max = 1000000,
                .constant = 200000,
                .bpt = 1000,
                .vpt = 1000,
                .rbh = 0,
                .sbh = 0,
                .gas = 0,
                .tv = 0,
                .bpr = 0,
                .sbpr = 0,
            },
            .network_data = FeeComponents{
                .min = 100,
                .max = 1000000,
                .constant = 200000,
                .bpt = 1000,
                .vpt = 1000,
                .rbh = 0,
                .sbh = 0,
                .gas = 0,
                .tv = 0,
                .bpr = 0,
                .sbpr = 0,
            },
            .service_data = FeeComponents{
                .min = 100,
                .max = 1000000,
                .constant = 200000,
                .bpt = 1000,
                .vpt = 1000,
                .rbh = 0,
                .sbh = 0,
                .gas = 0,
                .tv = 0,
                .bpr = 0,
                .sbpr = 0,
            },
        };
    }
};
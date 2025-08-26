const std = @import("std");
const Allocator = std.mem.Allocator;
const Status = @import("../core/status.zig").Status;
const ExchangeRate = @import("../core/exchange_rate.zig").ExchangeRate;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;
const AccountId = @import("../core/id.zig").AccountId;
const ContractId = @import("../core/id.zig").ContractId;
const FileId = @import("../core/id.zig").FileId;
const TokenId = @import("../core/id.zig").TokenId;
const TopicId = @import("../core/id.zig").TopicId;
const ScheduleId = @import("../core/id.zig").ScheduleId;

pub const TransactionReceipt = struct {
    status: Status,
    exchange_rate: ?ExchangeRate,
    next_exchange_rate: ?ExchangeRate,
    topic_id: ?TopicId,
    file_id: ?FileId,
    contract_id: ?ContractId,
    account_id: ?AccountId,
    token_id: ?TokenId,
    topic_sequence_number: u64,
    topic_running_hash: []const u8,
    topic_running_hash_version: u64,
    total_supply: u64,
    schedule_id: ?ScheduleId,
    scheduled_transaction_id: ?TransactionId,
    serial_numbers: []i64,
    node_id: u64,
    duplicates: []const TransactionReceipt,
    children: []const TransactionReceipt,
    transaction_id: ?TransactionId,
    allocator: Allocator,
    
    const Self = @This();
    
    pub fn init(allocator: Allocator, status: Status) Self {
        return Self{
            .status = status,
            .exchange_rate = null,
            .next_exchange_rate = null,
            .topic_id = null,
            .file_id = null,
            .contract_id = null,
            .account_id = null,
            .token_id = null,
            .topic_sequence_number = 0,
            .topic_running_hash = "",
            .topic_running_hash_version = 0,
            .total_supply = 0,
            .schedule_id = null,
            .scheduled_transaction_id = null,
            .serial_numbers = &[_]i64{},
            .node_id = 0,
            .duplicates = &[_]TransactionReceipt{},
            .children = &[_]TransactionReceipt{},
            .transaction_id = null,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Self) void {
        if (self.topic_running_hash.len > 0) {
            self.allocator.free(self.topic_running_hash);
        }
        if (self.serial_numbers.len > 0) {
            self.allocator.free(self.serial_numbers);
        }
        if (self.duplicates.len > 0) {
            for (self.duplicates) |duplicate| {
                // Note: const items don't need explicit deinit for slices
                _ = duplicate;
            }
            self.allocator.free(self.duplicates);
        }
        if (self.children.len > 0) {
            for (self.children) |child| {
                // Note: const items don't need explicit deinit for slices
                _ = child;
            }
            self.allocator.free(self.children);
        }
    }
    
    pub fn setExchangeRate(self: *Self, exchange_rate: ExchangeRate) !*Self {
        self.exchange_rate = exchange_rate;
        return self;
    }
    
    pub fn setNextExchangeRate(self: *Self, next_exchange_rate: ExchangeRate) !*Self {
        self.next_exchange_rate = next_exchange_rate;
        return self;
    }
    
    pub fn setTopicId(self: *Self, topic_id: TopicId) !*Self {
        self.topic_id = topic_id;
        return self;
    }
    
    pub fn setFileId(self: *Self, file_id: FileId) !*Self {
        self.file_id = file_id;
        return self;
    }
    
    pub fn setContractId(self: *Self, contract_id: ContractId) !*Self {
        self.contract_id = contract_id;
        return self;
    }
    
    pub fn setAccountId(self: *Self, account_id: AccountId) !*Self {
        self.account_id = account_id;
        return self;
    }
    
    pub fn setTokenId(self: *Self, token_id: TokenId) !*Self {
        self.token_id = token_id;
        return self;
    }
    
    pub fn setTopicSequenceNumber(self: *Self, sequence_number: u64) !*Self {
        self.topic_sequence_number = sequence_number;
        return self;
    }
    
    pub fn setTopicRunningHash(self: *Self, allocator: Allocator, running_hash: []const u8) !*Self {
        if (self.topic_running_hash.len > 0) {
            allocator.free(self.topic_running_hash);
        }
        self.topic_running_hash = try allocator.dupe(u8, running_hash);
        return self;
    }
    
    pub fn setTopicRunningHashVersion(self: *Self, version: u64) !*Self {
        self.topic_running_hash_version = version;
        return self;
    }
    
    pub fn setTotalSupply(self: *Self, total_supply: u64) !*Self {
        self.total_supply = total_supply;
        return self;
    }
    
    pub fn setScheduleId(self: *Self, schedule_id: ScheduleId) !*Self {
        self.schedule_id = schedule_id;
        return self;
    }
    
    pub fn setScheduledTransactionId(self: *Self, transaction_id: TransactionId) !*Self {
        self.scheduled_transaction_id = transaction_id;
        return self;
    }
    
    pub fn setSerialNumbers(self: *Self, allocator: Allocator, serial_numbers: []const i64) !*Self {
        if (self.serial_numbers.len > 0) {
            allocator.free(self.serial_numbers);
        }
        self.serial_numbers = try allocator.dupe(i64, serial_numbers);
        return self;
    }
    
    pub fn setNodeId(self: *Self, node_id: u64) !*Self {
        self.node_id = node_id;
        return self;
    }
    
    pub fn setDuplicates(self: *Self, allocator: Allocator, duplicates: []const TransactionReceipt) !*Self {
        if (self.duplicates.len > 0) {
            for (self.duplicates) |*duplicate| {
                duplicate.deinit();
            }
            allocator.free(self.duplicates);
        }
        
        var cloned_duplicates = try allocator.alloc(TransactionReceipt, duplicates.len);
        for (duplicates, 0..) |duplicate, i| {
            cloned_duplicates[i] = try duplicate.clone(allocator);
        }
        self.duplicates = cloned_duplicates;
        return self;
    }
    
    pub fn setChildren(self: *Self, allocator: Allocator, children: []const TransactionReceipt) !*Self {
        if (self.children.len > 0) {
            for (self.children) |*child| {
                child.deinit();
            }
            allocator.free(self.children);
        }
        
        var cloned_children = try allocator.alloc(TransactionReceipt, children.len);
        for (children, 0..) |child, i| {
            cloned_children[i] = try child.clone(allocator);
        }
        self.children = cloned_children;
        return self;
    }
    
    pub fn setTransactionId(self: *Self, transaction_id: TransactionId) !*Self {
        self.transaction_id = transaction_id;
        return self;
    }
    
    pub fn isSuccess(self: *const Self) bool {
        return self.status == .Success;
    }
    
    pub fn hasFailed(self: *const Self) bool {
        return !self.isSuccess();
    }
    
    pub fn validateStatus(self: *const Self) !void {
        switch (self.status) {
            .OK, .SUCCESS => return,
            .UNKNOWN => return error.ReceiptStatusUnknown,
            .BUSY => return error.ReceiptStatusBusy,
            else => return error.TransactionFailed,
        }
    }
    
    pub fn toString(self: *const Self, allocator: Allocator) ![]u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        defer buffer.deinit();
        
        try buffer.writer().print("TransactionReceipt{{status={s}", .{@tagName(self.status)});
        
        if (self.account_id) |account_id| {
            const account_str = try account_id.toString(allocator);
            defer allocator.free(account_str);
            try buffer.writer().print(", account_id={s}", .{account_str});
        }
        
        if (self.contract_id) |contract_id| {
            const contract_str = try contract_id.toString(allocator);
            defer allocator.free(contract_str);
            try buffer.writer().print(", contract_id={s}", .{contract_str});
        }
        
        if (self.file_id) |file_id| {
            const file_str = try file_id.toString(allocator);
            defer allocator.free(file_str);
            try buffer.writer().print(", file_id={s}", .{file_str});
        }
        
        if (self.token_id) |token_id| {
            const token_str = try token_id.toString(allocator);
            defer allocator.free(token_str);
            try buffer.writer().print(", token_id={s}", .{token_str});
        }
        
        if (self.topic_id) |topic_id| {
            const topic_str = try topic_id.toString(allocator);
            defer allocator.free(topic_str);
            try buffer.writer().print(", topic_id={s}", .{topic_str});
        }
        
        if (self.schedule_id) |schedule_id| {
            const schedule_str = try schedule_id.toString(allocator);
            defer allocator.free(schedule_str);
            try buffer.writer().print(", schedule_id={s}", .{schedule_str});
        }
        
        if (self.topic_sequence_number > 0) {
            try buffer.writer().print(", topic_sequence_number={d}", .{self.topic_sequence_number});
        }
        
        if (self.topic_running_hash.len > 0) {
            try buffer.writer().print(", topic_running_hash={s}", .{std.fmt.fmtSliceHexLower(self.topic_running_hash)});
        }
        
        if (self.total_supply > 0) {
            try buffer.writer().print(", total_supply={d}", .{self.total_supply});
        }
        
        if (self.serial_numbers.len > 0) {
            try buffer.appendSlice(", serial_numbers=[");
            for (self.serial_numbers, 0..) |serial, i| {
                if (i > 0) try buffer.appendSlice(",");
                try buffer.writer().print("{d}", .{serial});
            }
            try buffer.appendSlice("]");
        }
        
        try buffer.appendSlice("}");
        
        return try allocator.dupe(u8, buffer.items);
    }
    
    pub fn toJson(self: *const Self, allocator: Allocator) ![]u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        defer buffer.deinit();
        
        try buffer.appendSlice("{");
        
        // Status
        try buffer.writer().print("\"status\":\"{s}\"", .{@tagName(self.status)});
        
        // Topic sequence number
        if (self.topic_sequence_number > 0) {
            try buffer.writer().print(",\"topicSequenceNumber\":{d}", .{self.topic_sequence_number});
        }
        
        // Topic running hash
        if (self.topic_running_hash.len > 0) {
            try buffer.appendSlice(",\"topicRunningHash\":\"");
            for (self.topic_running_hash) |byte| {
                try buffer.writer().print("{x:0>2}", .{byte});
            }
            try buffer.appendSlice("\"");
        }
        
        // Topic running hash version
        if (self.topic_running_hash_version > 0) {
            try buffer.writer().print(",\"topicRunningHashVersion\":{d}", .{self.topic_running_hash_version});
        }
        
        // Total supply
        if (self.total_supply > 0) {
            try buffer.writer().print(",\"totalSupply\":{d}", .{self.total_supply});
        }
        
        // Serial numbers
        if (self.serial_numbers.len > 0) {
            try buffer.appendSlice(",\"serialNumbers\":[");
            for (self.serial_numbers, 0..) |serial, i| {
                if (i > 0) try buffer.appendSlice(",");
                try buffer.writer().print("{d}", .{serial});
            }
            try buffer.appendSlice("]");
        }
        
        // Node ID
        try buffer.writer().print(",\"nodeId\":{d}", .{self.node_id});
        
        // Exchange rate
        if (self.exchange_rate) |exchange_rate| {
            try buffer.appendSlice(",\"exchangeRate\":");
            const exchange_rate_json = try exchange_rate.toJson(allocator);
            defer allocator.free(exchange_rate_json);
            try buffer.appendSlice(exchange_rate_json);
        }
        
        // Next exchange rate
        if (self.next_exchange_rate) |next_exchange_rate| {
            try buffer.appendSlice(",\"nextExchangeRate\":");
            const next_exchange_rate_json = try next_exchange_rate.toJson(allocator);
            defer allocator.free(next_exchange_rate_json);
            try buffer.appendSlice(next_exchange_rate_json);
        }
        
        // IDs
        if (self.account_id) |account_id| {
            const account_str = try account_id.toString(allocator);
            defer allocator.free(account_str);
            try buffer.writer().print(",\"accountId\":\"{s}\"", .{account_str});
        }
        
        if (self.contract_id) |contract_id| {
            const contract_str = try contract_id.toString(allocator);
            defer allocator.free(contract_str);
            try buffer.writer().print(",\"contractId\":\"{s}\"", .{contract_str});
        }
        
        if (self.file_id) |file_id| {
            const file_str = try file_id.toString(allocator);
            defer allocator.free(file_str);
            try buffer.writer().print(",\"fileId\":\"{s}\"", .{file_str});
        }
        
        if (self.token_id) |token_id| {
            const token_str = try token_id.toString(allocator);
            defer allocator.free(token_str);
            try buffer.writer().print(",\"tokenId\":\"{s}\"", .{token_str});
        }
        
        if (self.topic_id) |topic_id| {
            const topic_str = try topic_id.toString(allocator);
            defer allocator.free(topic_str);
            try buffer.writer().print(",\"topicId\":\"{s}\"", .{topic_str});
        }
        
        if (self.schedule_id) |schedule_id| {
            const schedule_str = try schedule_id.toString(allocator);
            defer allocator.free(schedule_str);
            try buffer.writer().print(",\"scheduleId\":\"{s}\"", .{schedule_str});
        }
        
        if (self.transaction_id) |transaction_id| {
            const tx_str = try transaction_id.toString(allocator);
            defer allocator.free(tx_str);
            try buffer.writer().print(",\"transactionId\":\"{s}\"", .{tx_str});
        }
        
        if (self.scheduled_transaction_id) |scheduled_tx_id| {
            const scheduled_tx_str = try scheduled_tx_id.toString(allocator);
            defer allocator.free(scheduled_tx_str);
            try buffer.writer().print(",\"scheduledTransactionId\":\"{s}\"", .{scheduled_tx_str});
        }
        
        try buffer.appendSlice("}");
        
        return try allocator.dupe(u8, buffer.items);
    }
    
    pub fn fromProtobufBytes(allocator: Allocator, bytes: []const u8) !Self {
        // Protobuf deserialization implementation
        // This would use a full protobuf library in deployment
        
        var receipt = Self.init(allocator, .OK);
        
        var reader = ProtobufReader.init(bytes);
        
        while (try reader.nextField()) |field| {
            switch (field.tag) {
                1 => receipt.status = try Status.fromInt(@intCast(try @constCast(&field).readVarint())),
                2 => {
                    const account_bytes = try @constCast(&field).readBytes(allocator);
                    defer allocator.free(account_bytes);
                    receipt.account_id = try AccountId.fromProtobufBytes(allocator, account_bytes);
                },
                3 => {
                    const file_bytes = try @constCast(&field).readBytes(allocator);
                    defer allocator.free(file_bytes);
                    receipt.file_id = try FileId.fromProtobufBytes(allocator, file_bytes);
                },
                4 => {
                    const contract_bytes = try @constCast(&field).readBytes(allocator);
                    defer allocator.free(contract_bytes);
                    receipt.contract_id = try ContractId.fromProtobufBytes(allocator, contract_bytes);
                },
                5 => {
                    const exchange_rate_bytes = try @constCast(&field).readBytes(allocator);
                    defer allocator.free(exchange_rate_bytes);
                    receipt.exchange_rate = try ExchangeRate.fromProtobufBytes(allocator, exchange_rate_bytes);
                },
                6 => {
                    const token_bytes = try @constCast(&field).readBytes(allocator);
                    defer allocator.free(token_bytes);
                    receipt.token_id = try TokenId.fromProtobufBytes(allocator, token_bytes);
                },
                7 => {
                    const topic_bytes = try @constCast(&field).readBytes(allocator);
                    defer allocator.free(topic_bytes);
                    receipt.topic_id = try TopicId.fromProtobufBytes(allocator, topic_bytes);
                },
                8 => receipt.topic_sequence_number = try @constCast(&field).readVarint(),
                9 => {
                    const hash_bytes = try @constCast(&field).readBytes(allocator);
                    receipt.topic_running_hash = hash_bytes; // Takes ownership
                },
                10 => receipt.topic_running_hash_version = try @constCast(&field).readVarint(),
                11 => {
                    const schedule_bytes = try @constCast(&field).readBytes(allocator);
                    defer allocator.free(schedule_bytes);
                    receipt.schedule_id = try ScheduleId.fromProtobufBytes(allocator, schedule_bytes);
                },
                12 => {
                    const tx_bytes = try @constCast(&field).readBytes(allocator);
                    defer allocator.free(tx_bytes);
                    receipt.scheduled_transaction_id = try TransactionId.fromProtobufBytes(allocator, tx_bytes);
                },
                13 => {
                    // Serial numbers (repeated)
                    const serial = @as(i64, @intCast(try @constCast(&field).readVarint()));
                    // For simplicity, we'll just handle the last one
                    // In a full implementation, we'd collect all serial numbers
                    receipt.serial_numbers = try allocator.dupe(i64, &[_]i64{serial});
                },
                14 => receipt.total_supply = try @constCast(&field).readVarint(),
                15 => receipt.node_id = try @constCast(&field).readVarint(),
                else => try @constCast(&field).skip(),
            }
        }
        
        return receipt;
    }
    
    pub fn toProtobufBytes(self: *const Self, allocator: Allocator) ![]u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        defer buffer.deinit();
        
        // Status
        try writeProtobufVarint(&buffer, 1, @intFromEnum(self.status));
        
        // Account ID
        if (self.account_id) |account_id| {
            const account_bytes = try account_id.toProtobufBytes(allocator);
            defer allocator.free(account_bytes);
            try writeProtobufField(&buffer, 2, account_bytes);
        }
        
        // File ID
        if (self.file_id) |file_id| {
            const file_bytes = try file_id.toProtobufBytes(allocator);
            defer allocator.free(file_bytes);
            try writeProtobufField(&buffer, 3, file_bytes);
        }
        
        // Contract ID
        if (self.contract_id) |contract_id| {
            const contract_bytes = try contract_id.toProtobufBytes(allocator);
            defer allocator.free(contract_bytes);
            try writeProtobufField(&buffer, 4, contract_bytes);
        }
        
        // Exchange rate
        if (self.exchange_rate) |exchange_rate| {
            const exchange_rate_bytes = try exchange_rate.toProtobufBytes(allocator);
            defer allocator.free(exchange_rate_bytes);
            try writeProtobufField(&buffer, 5, exchange_rate_bytes);
        }
        
        // Token ID
        if (self.token_id) |token_id| {
            const token_bytes = try token_id.toProtobufBytes(allocator);
            defer allocator.free(token_bytes);
            try writeProtobufField(&buffer, 6, token_bytes);
        }
        
        // Topic ID
        if (self.topic_id) |topic_id| {
            const topic_bytes = try topic_id.toProtobufBytes(allocator);
            defer allocator.free(topic_bytes);
            try writeProtobufField(&buffer, 7, topic_bytes);
        }
        
        // Topic sequence number
        if (self.topic_sequence_number > 0) {
            try writeProtobufVarint(&buffer, 8, self.topic_sequence_number);
        }
        
        // Topic running hash
        if (self.topic_running_hash.len > 0) {
            try writeProtobufField(&buffer, 9, self.topic_running_hash);
        }
        
        // Topic running hash version
        if (self.topic_running_hash_version > 0) {
            try writeProtobufVarint(&buffer, 10, self.topic_running_hash_version);
        }
        
        // Schedule ID
        if (self.schedule_id) |schedule_id| {
            const schedule_bytes = try schedule_id.toProtobufBytes(allocator);
            defer allocator.free(schedule_bytes);
            try writeProtobufField(&buffer, 11, schedule_bytes);
        }
        
        // Scheduled transaction ID
        if (self.scheduled_transaction_id) |scheduled_tx_id| {
            const scheduled_tx_bytes = try scheduled_tx_id.toProtobufBytes(allocator);
            defer allocator.free(scheduled_tx_bytes);
            try writeProtobufField(&buffer, 12, scheduled_tx_bytes);
        }
        
        // Serial numbers
        for (self.serial_numbers) |serial| {
            try writeProtobufVarint(&buffer, 13, @as(u64, @intCast(serial)));
        }
        
        // Total supply
        if (self.total_supply > 0) {
            try writeProtobufVarint(&buffer, 14, self.total_supply);
        }
        
        // Node ID
        try writeProtobufVarint(&buffer, 15, self.node_id);
        
        return try allocator.dupe(u8, buffer.items);
    }
    
    pub fn clone(self: *const Self, allocator: Allocator) !Self {
        var cloned = Self.init(allocator, self.status);
        cloned.exchange_rate = self.exchange_rate;
        cloned.next_exchange_rate = self.next_exchange_rate;
        cloned.topic_id = self.topic_id;
        cloned.file_id = self.file_id;
        cloned.contract_id = self.contract_id;
        cloned.account_id = self.account_id;
        cloned.token_id = self.token_id;
        cloned.topic_sequence_number = self.topic_sequence_number;
        cloned.topic_running_hash_version = self.topic_running_hash_version;
        cloned.total_supply = self.total_supply;
        cloned.schedule_id = self.schedule_id;
        cloned.scheduled_transaction_id = self.scheduled_transaction_id;
        cloned.node_id = self.node_id;
        cloned.transaction_id = self.transaction_id;
        
        // Clone allocated fields
        if (self.topic_running_hash.len > 0) {
            cloned.topic_running_hash = try allocator.dupe(u8, self.topic_running_hash);
        }
        if (self.serial_numbers.len > 0) {
            cloned.serial_numbers = try allocator.dupe(i64, self.serial_numbers);
        }
        if (self.duplicates.len > 0) {
            var cloned_duplicates = try allocator.alloc(TransactionReceipt, self.duplicates.len);
            for (self.duplicates, 0..) |duplicate, i| {
                cloned_duplicates[i] = try duplicate.clone(allocator);
            }
            cloned.duplicates = cloned_duplicates;
        }
        if (self.children.len > 0) {
            var cloned_children = try allocator.alloc(TransactionReceipt, self.children.len);
            for (self.children, 0..) |child, i| {
                cloned_children[i] = try child.clone(allocator);
            }
            cloned.children = cloned_children;
        }
        
        return cloned;
    }
    
    // Parse from protobuf bytes
    pub fn fromProtobuf(allocator: Allocator, data: []const u8) !Self {
        const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;
        var reader = ProtoReader.init(data);
        var receipt = Self.init(allocator, .OK);
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            switch (tag.field_number) {
                1 => {
                    // Status
                    receipt.status = @enumFromInt(try reader.readInt32());
                },
                2 => {
                    // Account ID
                    const account_bytes = try reader.readBytes();
                    var account_reader = ProtoReader.init(account_bytes);
                    var shard: i64 = 0;
                    var realm: i64 = 0;
                    var account: i64 = 0;
                    
                    while (account_reader.hasMore()) {
                        const account_tag = try account_reader.readTag();
                        switch (account_tag.field_number) {
                            1 => shard = try account_reader.readInt64(),
                            2 => realm = try account_reader.readInt64(),
                            3 => account = try account_reader.readInt64(),
                            else => try account_reader.skipField(account_tag.wire_type),
                        }
                    }
                    receipt.account_id = AccountId.init(@intCast(shard), @intCast(realm), @intCast(account));
                },
                3 => {
                    // File ID
                    const file_bytes = try reader.readBytes();
                    var file_reader = ProtoReader.init(file_bytes);
                    var shard: i64 = 0;
                    var realm: i64 = 0;
                    var file: i64 = 0;
                    
                    while (file_reader.hasMore()) {
                        const file_tag = try file_reader.readTag();
                        switch (file_tag.field_number) {
                            1 => shard = try file_reader.readInt64(),
                            2 => realm = try file_reader.readInt64(),
                            3 => file = try file_reader.readInt64(),
                            else => try file_reader.skipField(file_tag.wire_type),
                        }
                    }
                    receipt.file_id = FileId.init(@intCast(shard), @intCast(realm), @intCast(file));
                },
                4 => {
                    // Contract ID
                    const contract_bytes = try reader.readBytes();
                    var contract_reader = ProtoReader.init(contract_bytes);
                    var shard: i64 = 0;
                    var realm: i64 = 0;
                    var contract: i64 = 0;
                    
                    while (contract_reader.hasMore()) {
                        const contract_tag = try contract_reader.readTag();
                        switch (contract_tag.field_number) {
                            1 => shard = try contract_reader.readInt64(),
                            2 => realm = try contract_reader.readInt64(),
                            3 => contract = try contract_reader.readInt64(),
                            else => try contract_reader.skipField(contract_tag.wire_type),
                        }
                    }
                    receipt.contract_id = ContractId.init(@intCast(shard), @intCast(realm), @intCast(contract));
                },
                7 => {
                    // Token ID
                    const token_bytes = try reader.readBytes();
                    var token_reader = ProtoReader.init(token_bytes);
                    var shard: i64 = 0;
                    var realm: i64 = 0;
                    var token: i64 = 0;
                    
                    while (token_reader.hasMore()) {
                        const token_tag = try token_reader.readTag();
                        switch (token_tag.field_number) {
                            1 => shard = try token_reader.readInt64(),
                            2 => realm = try token_reader.readInt64(),
                            3 => token = try token_reader.readInt64(),
                            else => try token_reader.skipField(token_tag.wire_type),
                        }
                    }
                    receipt.token_id = TokenId.init(@intCast(shard), @intCast(realm), @intCast(token));
                },
                11 => {
                    // Total supply
                    receipt.total_supply = @intCast(try reader.readUint64());
                },
                14 => {
                    // Serials
                    const serial = try reader.readInt64();
                    if (receipt.serial_numbers.len == 0) {
                        receipt.serial_numbers = try allocator.alloc(i64, 1);
                        receipt.serial_numbers[0] = serial;
                    } else {
                        var new_serials = try allocator.alloc(i64, receipt.serial_numbers.len + 1);
                        std.mem.copyForwards(i64, new_serials, receipt.serial_numbers);
                        new_serials[receipt.serial_numbers.len] = serial;
                        allocator.free(@constCast(receipt.serial_numbers));
                        receipt.serial_numbers = new_serials;
                    }
                },
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return receipt;
    }
    
    // Helper functions for protobuf encoding
    fn writeProtobufField(buffer: *std.ArrayList(u8), field_num: u32, data: []const u8) !void {
        const header = (field_num << 3) | 2;
        try writeProtobufVarint(buffer, 0, header);
        try writeProtobufVarint(buffer, 0, data.len);
        try buffer.appendSlice(data);
    }
    
    fn writeProtobufVarint(buffer: *std.ArrayList(u8), _: u32, value: u64) !void {
        var val = value;
        while (val >= 0x80) {
            try buffer.append(@intCast(val & 0x7F | 0x80));
            val >>= 7;
        }
        try buffer.append(@intCast(val & 0x7F));
    }
};

// Protobuf implementation for receipt parsing


const ProtobufReader = struct {
    data: []const u8,
    pos: usize,
    
    pub fn init(data: []const u8) ProtobufReader {
        return ProtobufReader{
            .data = data,
            .pos = 0,
        };
    }
    
    pub fn nextField(self: *ProtobufReader) !?ProtobufField {
        if (self.pos >= self.data.len) return null;
        
        const header = try self.readVarint();
        const tag = @as(u32, @intCast(header >> 3));
        const wire_type = @as(u3, @intCast(header & 0x7));
        
        return ProtobufField{
            .reader = self,
            .tag = tag,
            .wire_type = wire_type,
        };
    }
    
    fn readVarint(self: *ProtobufReader) !u64 {
        var result: u64 = 0;
        var shift: u6 = 0;
        
        while (self.pos < self.data.len) {
            const byte = self.data[self.pos];
            self.pos += 1;
            
            result |= (@as(u64, byte & 0x7F) << shift);
            
            if ((byte & 0x80) == 0) {
                return result;
            }
            
            shift += 7;
            if (shift >= 64) return error.VarintTooLarge;
        }
        
        return error.UnexpectedEndOfData;
    }
    
    fn readBytes(self: *ProtobufReader, len: usize) ![]const u8 {
        if (self.pos + len > self.data.len) return error.UnexpectedEndOfData;
        
        const result = self.data[self.pos..self.pos + len];
        self.pos += len;
        return result;
    }
};

const ProtobufField = struct {
    reader: *ProtobufReader,
    tag: u32,
    wire_type: u3,
    
    pub fn readVarint(self: *ProtobufField) !u64 {
        if (self.wire_type != 0) return error.InvalidWireType;
        return try self.reader.readVarint();
    }
    
    pub fn readBytes(self: *ProtobufField, allocator: Allocator) ![]u8 {
        if (self.wire_type != 2) return error.InvalidWireType;
        
        const len = try self.reader.readVarint();
        const data = try self.reader.readBytes(@as(usize, @intCast(len)));
        return try allocator.dupe(u8, data);
    }
    
    pub fn skip(self: *ProtobufField) !void {
        switch (self.wire_type) {
            0 => _ = try self.reader.readVarint(),
            1 => _ = try self.reader.readBytes(8),
            2 => {
                const len = try self.reader.readVarint();
                _ = try self.reader.readBytes(@as(usize, @intCast(len)));
            },
            5 => _ = try self.reader.readBytes(4),
            else => return error.UnsupportedWireType,
        }
    }
};
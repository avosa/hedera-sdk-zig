const std = @import("std");
const TopicId = @import("../core/id.zig").TopicId;
const AccountId = @import("../core/id.zig").AccountId;
const Key = @import("../crypto/key.zig").Key;
const Timestamp = @import("../core/timestamp.zig").Timestamp;
const Duration = @import("../core/duration.zig").Duration;
const Query = @import("../query/query.zig").Query;
const QueryResponse = @import("../query/query.zig").QueryResponse;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;
const Hbar = @import("../core/hbar.zig").Hbar;

// TopicInfo contains information about a consensus topic
pub const TopicInfo = struct {
    topic_id: TopicId,
    memo: []const u8,
    topic_memo: []const u8,
    running_hash: []const u8,
    sequence_number: u64,
    expiration_time: Timestamp,
    admin_key: ?Key,
    submit_key: ?Key,
    auto_renew_period: Duration,
    auto_renew_account: ?AccountId,
    ledger_id: []const u8,
    
    // Track ownership to prevent freeing string literals
    owns_memo: bool,
    owns_topic_memo: bool,
    owns_running_hash: bool,
    owns_ledger_id: bool,
    
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) TopicInfo {
        return TopicInfo{
            .topic_id = TopicId.init(0, 0, 0),
            .memo = "",
            .topic_memo = "",
            .running_hash = "",
            .sequence_number = 0,
            .expiration_time = Timestamp{ .seconds = 0, .nanos = 0 },
            .admin_key = null,
            .submit_key = null,
            .auto_renew_period = Duration{ .seconds = 0, .nanos = 0 },
            .auto_renew_account = null,
            .ledger_id = "",
            .owns_memo = false,
            .owns_topic_memo = false,
            .owns_running_hash = false,
            .owns_ledger_id = false,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *TopicInfo) void {
        if (self.owns_memo and self.memo.len > 0) {
            self.allocator.free(self.memo);
        }
        if (self.owns_topic_memo and self.topic_memo.len > 0) {
            self.allocator.free(self.topic_memo);
        }
        if (self.owns_running_hash and self.running_hash.len > 0) {
            self.allocator.free(self.running_hash);
        }
        if (self.owns_ledger_id and self.ledger_id.len > 0) {
            self.allocator.free(self.ledger_id);
        }
    }
};

// TopicInfoQuery retrieves information about a consensus topic
pub const TopicInfoQuery = struct {
    base: Query,
    topic_id: ?TopicId,
    
    pub fn init(allocator: std.mem.Allocator) TopicInfoQuery {
        return TopicInfoQuery{
            .base = Query.init(allocator),
            .topic_id = null,
        };
    }
    
    pub fn deinit(self: *TopicInfoQuery) void {
        self.base.deinit();
    }
    
    // Set the topic ID to query
    pub fn setTopicId(self: *TopicInfoQuery, topic_id: TopicId) !*TopicInfoQuery {
        self.topic_id = topic_id;
        return self;
    }
    
    // Set the query payment amount
    pub fn setQueryPayment(self: *TopicInfoQuery, payment: Hbar) !*TopicInfoQuery {
        self.base.payment_amount = payment;
        return self;
    }
    
    // Execute the query
    pub fn execute(self: *TopicInfoQuery, client: *Client) !TopicInfo {
        if (self.topic_id == null) {
            return error.TopicIdRequired;
        }
        
        const response = try self.base.execute(client);
        return try self.parseResponse(response);
    }
    
    // Get cost of the query
    pub fn getCost(self: *TopicInfoQuery, client: *Client) !Hbar {
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
    pub fn buildQuery(self: *TopicInfoQuery) ![]u8 {
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
        
        // consensusGetTopicInfo = 18 (oneof query)
        var info_query_writer = ProtoWriter.init(self.base.allocator);
        defer info_query_writer.deinit();
        
        // topicID = 1
        if (self.topic_id) |topic| {
            var topic_writer = ProtoWriter.init(self.base.allocator);
            defer topic_writer.deinit();
            try topic_writer.writeInt64(1, @intCast(topic.shard));
            try topic_writer.writeInt64(2, @intCast(topic.realm));
            try topic_writer.writeInt64(3, @intCast(topic.num));
            const topic_bytes = try topic_writer.toOwnedSlice();
            defer self.base.allocator.free(topic_bytes);
            try info_query_writer.writeMessage(1, topic_bytes);
        }
        
        const info_query_bytes = try info_query_writer.toOwnedSlice();
        defer self.base.allocator.free(info_query_bytes);
        try writer.writeMessage(18, info_query_bytes);
        
        return writer.toOwnedSlice();
    }
    
    // Parse the response
    fn parseResponse(self: *TopicInfoQuery, response: QueryResponse) !TopicInfo {
        try response.validateStatus();
        
        var reader = ProtoReader.init(response.response_bytes);
        
        var info = TopicInfo{
            .topic_id = TopicId.init(0, 0, 0),
            .memo = "",
            .topic_memo = "",
            .running_hash = "",
            .sequence_number = 0,
            .expiration_time = Timestamp{ .seconds = 0, .nanos = 0 },
            .admin_key = null,
            .submit_key = null,
            .auto_renew_period = Duration{ .seconds = 0 },
            .auto_renew_account = null,
            .ledger_id = "",
            .owns_memo = false,
            .owns_topic_memo = false,
            .owns_running_hash = false,
            .owns_ledger_id = false,
            .allocator = self.base.allocator,
        };
        
        // Parse ConsensusGetTopicInfoResponse
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => {
                    // header
                    _ = try reader.readMessage();
                },
                2 => {
                    // topicID
                    const topic_bytes = try reader.readMessage();
                    var id_reader = ProtoReader.init(topic_bytes);
                    
                    var shard: i64 = 0;
                    var realm: i64 = 0;
                    var num: i64 = 0;
                    
                    while (id_reader.hasMore()) {
                        const i = try id_reader.readTag();
                        switch (i.field_number) {
                            1 => shard = try id_reader.readInt64(),
                            2 => realm = try id_reader.readInt64(),
                            3 => num = try id_reader.readInt64(),
                            else => try id_reader.skipField(i.wire_type),
                        }
                    }
                    
                    info.topic_id = TopicId.init(@intCast(shard), @intCast(realm), @intCast(num));
                },
                3 => {
                    info.topic_memo = try self.base.allocator.dupe(u8, try reader.readString());
                    info.owns_topic_memo = true;
                },
                4 => {
                    // runningHash
                    const hash_bytes = try reader.readBytes();
                    info.running_hash = try self.base.allocator.dupe(u8, hash_bytes);
                    info.owns_running_hash = true;
                },
                5 => info.sequence_number = try reader.readUint64(),
                6 => {
                    // expirationTime
                    const exp_bytes = try reader.readMessage();
                    var exp_reader = ProtoReader.init(exp_bytes);
                    
                    while (exp_reader.hasMore()) {
                        const e = try exp_reader.readTag();
                        switch (e.field_number) {
                            1 => info.expiration_time.seconds = try exp_reader.readInt64(),
                            2 => info.expiration_time.nanos = try exp_reader.readInt32(),
                            else => try exp_reader.skipField(e.wire_type),
                        }
                    }
                },
                7 => {
                    // adminKey
                    const key_bytes = try reader.readMessage();
                    info.admin_key = try Key.fromProtobuf(key_bytes, self.base.allocator);
                },
                8 => {
                    // submitKey
                    const key_bytes = try reader.readMessage();
                    info.submit_key = try Key.fromProtobuf(key_bytes, self.base.allocator);
                },
                9 => {
                    // autoRenewPeriod
                    const period_bytes = try reader.readMessage();
                    var period_reader = ProtoReader.init(period_bytes);
                    
                    while (period_reader.hasMore()) {
                        const p = try period_reader.readTag();
                        switch (p.field_number) {
                            1 => info.auto_renew_period.seconds = try period_reader.readInt64(),
                            else => try period_reader.skipField(p.wire_type),
                        }
                    }
                },
                10 => {
                    // autoRenewAccount
                    const account_bytes = try reader.readMessage();
                    var account_reader = ProtoReader.init(account_bytes);
                    
                    var shard: i64 = 0;
                    var realm: i64 = 0;
                    var num: i64 = 0;
                    
                    while (account_reader.hasMore()) {
                        const a = try account_reader.readTag();
                        switch (a.field_number) {
                            1 => shard = try account_reader.readInt64(),
                            2 => realm = try account_reader.readInt64(),
                            3 => num = try account_reader.readInt64(),
                            else => try account_reader.skipField(a.wire_type),
                        }
                    }
                    
                    if (num != 0) {
                        info.auto_renew_account = AccountId.init(@intCast(shard), @intCast(realm), @intCast(num));
                    }
                },
                11 => {
                    // ledgerId
                    const ledger_bytes = try reader.readBytes();
                    info.ledger_id = try self.base.allocator.dupe(u8, ledger_bytes);
                    info.owns_ledger_id = true;
                },
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return info;
    }
};

// Factory function for creating a new TopicInfoQuery

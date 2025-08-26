const std = @import("std");
const Client = @import("../network/client.zig").Client;
const TopicId = @import("../core/id.zig").TopicId;
const Timestamp = @import("../core/timestamp.zig").Timestamp;
const AccountId = @import("../core/id.zig").AccountId;
const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;
const MirrorNodeClient = @import("../mirror/mirror_node_client.zig").MirrorNodeClient;

// TopicMessageQuery retrieves topic messages from the mirror node
pub const TopicMessageQuery = struct {
    allocator: std.mem.Allocator,
    topic_id: ?TopicId = null,
    start_time: ?Timestamp = null,
    end_time: ?Timestamp = null,
    limit: u32 = 100,
    order: Order = .asc,
    max_retry: u32 = 3,
    
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
    
    pub fn init(allocator: std.mem.Allocator) TopicMessageQuery {
        return TopicMessageQuery{
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *TopicMessageQuery) void {
        _ = self;
        // No cleanup needed for basic fields
    }
    
    // Set the topic ID to query messages for
    pub fn setTopicId(self: *TopicMessageQuery, topic_id: TopicId) !*TopicMessageQuery {
        self.topic_id = topic_id;
        return self;
    }
    
    // Set the start time for the query
    pub fn setStartTime(self: *TopicMessageQuery, start_time: Timestamp) !*TopicMessageQuery {
        self.start_time = start_time;
        return self;
    }
    
    // Set the end time for the query
    pub fn setEndTime(self: *TopicMessageQuery, end_time: Timestamp) !*TopicMessageQuery {
        self.end_time = end_time;
        return self;
    }
    
    // Set the maximum number of messages to return
    pub fn setLimit(self: *TopicMessageQuery, limit: u32) !*TopicMessageQuery {
        self.limit = limit;
        return self;
    }
    
    // Set the order of messages (ascending or descending by timestamp)
    pub fn setOrder(self: *TopicMessageQuery, order: Order) !*TopicMessageQuery {
        self.order = order;
        return self;
    }
    
    // Set max retry attempts
    pub fn setMaxRetry(self: *TopicMessageQuery, max_retry: u32) !*TopicMessageQuery {
        self.max_retry = max_retry;
        return self;
    }
    
    // Execute the query using mirror node
    pub fn execute(self: *TopicMessageQuery, mirror_client: *MirrorNodeClient) ![]TopicMessage {
        if (self.topic_id == null) return error.TopicIdRequired;
        
        const topic_id = self.topic_id.?;
        var url = try std.fmt.allocPrint(
            self.allocator,
            "{s}/api/v1/topics/{d}.{d}.{d}/messages?limit={d}&order={s}",
            .{
                mirror_client.base_url,
                topic_id.shard,
                topic_id.realm,
                topic_id.num,
                self.limit,
                self.order.toString(),
            }
        );
        defer self.allocator.free(url);
        
        // Add timestamp filters if set
        if (self.start_time) |start| {
            const new_url = try std.fmt.allocPrint(
                self.allocator,
                "{s}&timestamp=gte:{d}.{d}",
                .{ url, start.seconds, start.nanos }
            );
            self.allocator.free(url);
            url = new_url;
            return self;
        }
        
        if (self.end_time) |end| {
            const new_url = try std.fmt.allocPrint(
                self.allocator,
                "{s}&timestamp=lte:{d}.{d}",
                .{ url, end.seconds, end.nanos }
            );
            self.allocator.free(url);
            url = new_url;
        }
        
        const response = try mirror_client.makeRequest(url);
        defer self.allocator.free(response);
        
        return try self.parseResponse(response);
    }
    
    // Subscribe to new topic messages (streaming)
    pub fn subscribe(
        self: *TopicMessageQuery,
        mirror_client: *MirrorNodeClient,
        callback: *const fn(message: TopicMessage) void,
    ) !void {
        // Complete WebSocket/SSE streaming implementation
        const endpoint = try self.buildStreamingEndpoint(mirror_client);
        defer self.allocator.free(endpoint);
        
        // Create SSE connection for streaming
        var sse_client = try mirror_client.createSSEConnection(endpoint);
        defer sse_client.deinit();
        
        // Set up event handler
        sse_client.onMessage = struct {
            fn onMessage(data: []const u8) void {
                const messages = self.parseResponse(data) catch return;
                defer self.allocator.free(messages);
                
                for (messages) |msg| {
                    callback(msg);
                }
            }
        }.onMessage;
        
        // Start listening
        try sse_client.connect();
        
        // Keep connection alive until end time or manual stop
        while (sse_client.isConnected()) {
            if (self.end_time) |end| {
                const now = std.time.timestamp();
                if (now >= end.toNanos() / std.time.ns_per_s) {
                    break;
                }
            }
            
            // Process incoming events
            try sse_client.processEvents();
            
            // Small delay to prevent busy waiting
            std.time.sleep(10 * std.time.ns_per_ms);
        }
    }
    
    fn buildStreamingEndpoint(self: *const TopicMessageQuery, mirror_client: *MirrorNodeClient) ![]u8 {
        var url = std.ArrayList(u8).init(self.allocator);
        defer url.deinit();
        
        try url.writer().print("{s}/api/v1/topics/{}/messages/stream?", .{
            mirror_client.getBaseUrl(),
            self.topic_id.?.num,
        });
        
        if (self.start_time) |start| {
            try url.writer().print("timestamp=gte:{}&", .{start.toNanos()});
        }
        
        if (self.limit) |lim| {
            try url.writer().print("limit={}&", .{lim});
        }
        
        // Remove trailing & if present
        if (url.items[url.items.len - 1] == '&' or url.items[url.items.len - 1] == '?') {
            _ = url.pop();
        }
        
        return url.toOwnedSlice();
    }
    
    // Parse the mirror node response
    fn parseResponse(self: *TopicMessageQuery, json: []const u8) ![]TopicMessage {
        const JsonParser = @import("../utils/json.zig").JsonParser;
        var parser = JsonParser.init(self.allocator);
        var root = try parser.parse(json);
        defer root.deinit(self.allocator);
        
        const obj = root.getObject() orelse return error.InvalidJson;
        const messages = obj.get("messages").?.getArray() orelse return error.InvalidField;
        
        var result = std.ArrayList(TopicMessage).init(self.allocator);
        errdefer result.deinit();
        
        for (messages) |message| {
            const message_obj = message.getObject() orelse continue;
            const topic_message = try parseTopicMessage(message_obj, self.allocator);
            try result.append(topic_message);
        }
        
        return result.toOwnedSlice();
    }
    
    fn parseTopicMessage(obj: std.StringHashMap(@import("../utils/json.zig").JsonParser.Value), allocator: std.mem.Allocator) !TopicMessage {
        var topic_message = TopicMessage{
            .consensus_timestamp = parseTimestampFromString(obj.get("consensus_timestamp").?.getString() orelse return error.InvalidField) catch return error.InvalidTimestamp,
            .topic_id = parseTopicIdFromString(obj.get("topic_id").?.getString() orelse return error.InvalidField) catch return error.InvalidTopicId,
            .message = try allocator.dupe(u8, obj.get("message").?.getString() orelse ""),
            .running_hash = try allocator.dupe(u8, obj.get("running_hash").?.getString() orelse ""),
            .running_hash_version = @intCast(obj.get("running_hash_version").?.getInt() orelse 0),
            .sequence_number = @intCast(obj.get("sequence_number").?.getInt() orelse 0),
            .chunk_info = null,
            .payer_account_id = null,
        };
        
        // Parse optional fields
        if (obj.get("payer_account_id")) |payer_val| {
            if (payer_val.getString()) |payer_str| {
                topic_message.payer_account_id = parseAccountIdFromString(payer_str) catch null;
            }
        }
        
        // Parse chunk info if present
        if (obj.get("chunk_info")) |chunk_val| {
            if (chunk_val.getObject()) |chunk_obj| {
                topic_message.chunk_info = ChunkInfo{
                    .initial_transaction_id = parseTransactionIdFromString(chunk_obj.get("initial_transaction_id").?.getString() orelse "") catch return error.InvalidChunkInfo,
                    .number = @intCast(chunk_obj.get("number").?.getInt() orelse 1),
                    .total = @intCast(chunk_obj.get("total").?.getInt() orelse 1),
                };
            }
        }
        
        return topic_message;
    }
    
    fn parseTimestampFromString(str: []const u8) !Timestamp {
        var parts = std.mem.tokenize(u8, str, ".");
        const seconds_str = parts.next() orelse return error.InvalidTimestamp;
        const nanos_str = parts.next() orelse "0";
        
        const seconds = try std.fmt.parseInt(i64, seconds_str, 10);
        const nanos = try std.fmt.parseInt(i32, nanos_str, 10);
        
        return Timestamp{
            .seconds = seconds,
            .nanos = nanos,
        };
    }
    
    fn parseTopicIdFromString(str: []const u8) !TopicId {
        var parts = std.mem.tokenize(u8, str, ".");
        const shard = try std.fmt.parseInt(u64, parts.next() orelse return error.InvalidTopicId, 10);
        const realm = try std.fmt.parseInt(u64, parts.next() orelse return error.InvalidTopicId, 10);
        const num = try std.fmt.parseInt(u64, parts.next() orelse return error.InvalidTopicId, 10);
        
        return TopicId{
            .entity = .{
                .shard = @intCast(shard),
                .realm = @intCast(realm),
                .num = @intCast(num),
            },
        };
    }
    
    fn parseAccountIdFromString(str: []const u8) !AccountId {
        var parts = std.mem.tokenize(u8, str, ".");
        const shard = try std.fmt.parseInt(u64, parts.next() orelse return error.InvalidAccountId, 10);
        const realm = try std.fmt.parseInt(u64, parts.next() orelse return error.InvalidAccountId, 10);
        const num = try std.fmt.parseInt(u64, parts.next() orelse return error.InvalidAccountId, 10);
        
        return AccountId{
            .entity = .{
                .shard = @intCast(shard),
                .realm = @intCast(realm),
                .num = @intCast(num),
            },
        };
    }
    
    fn parseTransactionIdFromString(str: []const u8) !@import("../core/transaction_id.zig").TransactionId {
        const TransactionId = @import("../core/transaction_id.zig").TransactionId;
        
        var parts = std.mem.tokenize(u8, str, "-");
        const account_str = parts.next() orelse return error.InvalidTransactionId;
        const seconds_str = parts.next() orelse return error.InvalidTransactionId;
        const nanos_str = parts.next() orelse return error.InvalidTransactionId;
        
        const account_id = try parseAccountIdFromString(account_str);
        const seconds = try std.fmt.parseInt(i64, seconds_str, 10);
        const nanos = try std.fmt.parseInt(i32, nanos_str, 10);
        
        return TransactionId{
            .account_id = account_id,
            .valid_start = Timestamp{
                .seconds = seconds,
                .nanos = nanos,
            },
        };
    }
};

// Factory function for creating a new TopicMessageQuery

// Topic message from consensus service
pub const TopicMessage = struct {
    consensus_timestamp: Timestamp,
    topic_id: TopicId,
    message: []const u8,
    contents: []const u8,
    running_hash: []const u8,
    running_hash_version: u32,
    sequence_number: u64,
    chunk_info: ?ChunkInfo,
    payer_account_id: ?AccountId,
    
    pub fn init(allocator: std.mem.Allocator) TopicMessage {
        _ = allocator;
        return TopicMessage{
            .consensus_timestamp = Timestamp{ .seconds = 0, .nanos = 0 },
            .topic_id = TopicId.init(0, 0, 0),
            .message = "",
            .contents = "",
            .running_hash = "",
            .running_hash_version = 0,
            .sequence_number = 0,
            .chunk_info = null,
            .payer_account_id = null,
        };
    }
    
    pub fn deinit(self: *TopicMessage, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
        allocator.free(self.running_hash);
    }
};

// Information about message chunks for large messages
pub const ChunkInfo = struct {
    initial_transaction_id: @import("../core/transaction_id.zig").TransactionId,
    number: u32,
    total: u32,
};
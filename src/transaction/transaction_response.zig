const std = @import("std");
const Allocator = std.mem.Allocator;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;
const AccountId = @import("../core/id.zig").AccountId;
const TransactionReceipt = @import("transaction_receipt.zig").TransactionReceipt;
const TransactionRecord = @import("transaction_record.zig").TransactionRecord;
const TransactionReceiptQuery = @import("../query/transaction_receipt_query.zig").TransactionReceiptQuery;
const Client = @import("../network/client.zig").Client;

pub const TransactionResponse = struct {
    transaction_id: TransactionId,
    scheduled_transaction_id: ?TransactionId,
    node_id: AccountId,
    hash: []const u8,
    transaction_hash: []const u8,  // For Go SDK compatibility
    validate_status: bool,
    include_child_receipts: bool,
    transaction: ?*anyopaque, // TransactionInterface - will be properly typed when we implement the interface system
    allocator: Allocator,
    
    const Self = @This();
    
    pub fn init(
        allocator: Allocator, 
        transaction_id: TransactionId,
        node_id: AccountId,
        hash: []const u8,
    ) !Self {
        return Self{
            .transaction_id = transaction_id,
            .scheduled_transaction_id = null,
            .node_id = node_id,
            .hash = try allocator.dupe(u8, hash),
            .transaction_hash = try allocator.dupe(u8, hash),
            .validate_status = false,
            .include_child_receipts = false,
            .transaction = null,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.hash);
        self.allocator.free(self.transaction_hash);
    }
    
    pub fn setScheduledTransactionId(self: *Self, scheduled_transaction_id: TransactionId) *Self {
        self.scheduled_transaction_id = scheduled_transaction_id;
        return self;
    }
    
    pub fn setValidateStatus(self: *Self, validate_status: bool) *Self {
        self.validate_status = validate_status;
        return self;
    }
    
    pub fn setIncludeChildReceipts(self: *Self, include_child_receipts: bool) *Self {
        self.include_child_receipts = include_child_receipts;
        return self;
    }
    
    pub fn setTransaction(self: *Self, transaction: *anyopaque) *Self {
        self.transaction = transaction;
        return self;
    }
    
    pub fn getReceipt(self: *const Self, client: *Client) !TransactionReceipt {
        return try self.getReceiptQuery(client).execute(client);
    }
    
    // Match Go SDK's GetReceipt naming
    pub fn get_receipt(self: *const Self, client: *Client) !TransactionReceipt {
        return self.getReceipt(client);
    }
    
    pub fn getReceiptAsync(self: *const Self, client: *Client) !TransactionReceipt {
        return try self.getReceiptQuery(client)
            .setValidateStatus(self.validate_status)
            .setIncludeChildReceipts(self.include_child_receipts)
            .executeAsync(client);
    }
    
    pub fn getRecord(self: *const Self, client: *Client) !TransactionRecord {
        const TransactionRecordQuery = @import("../query/transaction_record_query.zig").TransactionRecordQuery;
        
        return try TransactionRecordQuery.init(self.allocator)
            .setTransactionId(self.transaction_id)
            .setIncludeChildRecords(self.include_child_receipts)
            .execute(client);
    }
    
    pub fn getRecordAsync(self: *const Self, client: *Client) !TransactionRecord {
        const TransactionRecordQuery = @import("../query/transaction_record_query.zig").TransactionRecordQuery;
        
        return try TransactionRecordQuery.init(self.allocator)
            .setTransactionId(self.transaction_id)
            .setIncludeChildRecords(self.include_child_receipts)
            .executeAsync(client);
    }
    
    fn getReceiptQuery(self: *const Self, client: *Client) !TransactionReceiptQuery {
        _ = client;
        return TransactionReceiptQuery.init(self.allocator)
            .setTransactionId(self.transaction_id)
            .setValidateStatus(self.validate_status)
            .setIncludeChildReceipts(self.include_child_receipts);
    }
    
    // Retry transaction helper for throttled transactions
    pub fn retryTransaction(self: *Self, client: *Client) !TransactionReceipt {
        const max_retries = 5;
        var backoff_ms: u64 = 250;
        
        var i: usize = 0;
        while (i < max_retries) : (i += 1) {
            if (i > 0) {
                std.time.sleep(backoff_ms * std.time.ns_per_ms);
                backoff_ms *= 2; // Exponential backoff
            }
            
            const receipt = self.getReceipt(client) catch |err| switch (err) {
                error.ReceiptStatusBusy, error.ReceiptStatusUnknown => {
                    if (i == max_retries - 1) return err;
                    continue;
                },
                else => return err,
            };
            
            return receipt;
        }
        
        return error.MaxRetriesExceeded;
    }
    
    pub fn toString(self: *const Self, allocator: Allocator) ![]u8 {
        return try std.fmt.allocPrint(allocator,
            "TransactionResponse{{transaction_id={s}, node_id={s}, hash={s}}}",
            .{ 
                try self.transaction_id.toString(allocator),
                try self.node_id.toString(allocator), 
                std.fmt.fmtSliceHexLower(self.hash)
            }
        );
    }
    
    pub fn toJson(self: *const Self, allocator: Allocator) ![]u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        defer buffer.deinit();
        
        try buffer.appendSlice("{");
        
        // Transaction ID
        try buffer.appendSlice("\"transactionID\":\"");
        const tx_id_str = try self.transaction_id.toString(allocator);
        defer allocator.free(tx_id_str);
        try buffer.appendSlice(tx_id_str);
        try buffer.appendSlice("\",");
        
        // Node ID  
        try buffer.appendSlice("\"nodeID\":\"");
        const node_id_str = try self.node_id.toString(allocator);
        defer allocator.free(node_id_str);
        try buffer.appendSlice(node_id_str);
        try buffer.appendSlice("\",");
        
        // Hash (hex encoded)
        try buffer.appendSlice("\"hash\":\"");
        for (self.hash) |byte| {
            try buffer.writer().print("{x:0>2}", .{byte});
        }
        try buffer.appendSlice("\"");
        
        // Scheduled transaction ID (optional)
        if (self.scheduled_transaction_id) |scheduled_id| {
            try buffer.appendSlice(",\"scheduledTransactionId\":\"");
            const scheduled_id_str = try scheduled_id.toString(allocator);
            defer allocator.free(scheduled_id_str);
            try buffer.appendSlice(scheduled_id_str);
            try buffer.appendSlice("\"");
        }
        
        try buffer.appendSlice("}");
        
        return try allocator.dupe(u8, buffer.items);
    }
    
    pub fn fromJson(allocator: Allocator, json_str: []const u8) !Self {
        const json = @import("std").json;
        
        const parsed = try json.parseFromSlice(json.Value, allocator, json_str, .{});
        defer parsed.deinit();
        
        const obj = parsed.value.object;
        
        // Parse transaction ID
        const tx_id_str = obj.get("transactionID").?.string;
        const transaction_id = try TransactionId.fromString(allocator, tx_id_str);
        
        // Parse node ID
        const node_id_str = obj.get("nodeID").?.string;
        const node_id = try AccountId.fromString(allocator, node_id_str);
        
        // Parse hash (hex encoded)
        const hash_str = obj.get("hash").?.string;
        const hash = try allocator.alloc(u8, hash_str.len / 2);
        _ = try std.fmt.hexToBytes(hash, hash_str);
        
        var response = try Self.init(allocator, transaction_id, node_id, hash);
        
        // Parse optional scheduled transaction ID
        if (obj.get("scheduledTransactionId")) |scheduled_value| {
            const scheduled_id = try TransactionId.fromString(allocator, scheduled_value.string);
            response.scheduled_transaction_id = scheduled_id;
        }
        
        return response;
    }
    
    pub fn getTransactionId(self: *const Self) TransactionId {
        return self.transaction_id;
    }
    
    pub fn getScheduledTransactionId(self: *const Self) ?TransactionId {
        return self.scheduled_transaction_id;
    }
    
    pub fn getNodeId(self: *const Self) AccountId {
        return self.node_id;
    }
    
    pub fn getHash(self: *const Self) []const u8 {
        return self.hash;
    }
    
    pub fn getValidateStatus(self: *const Self) bool {
        return self.validate_status;
    }
    
    pub fn getIncludeChildReceipts(self: *const Self) bool {
        return self.include_child_receipts;
    }
    
    pub fn getTransaction(self: *const Self) ?*anyopaque {
        return self.transaction;
    }
    
    // Wait for the transaction to complete with optional timeout
    pub fn waitForCompletion(self: *const Self, client: *Client, timeout_ms: ?u64) !TransactionReceipt {
        const start_time = std.time.milliTimestamp();
        const timeout = timeout_ms orelse 60000; // Default 1 minute timeout
        
        while (true) {
            const receipt = self.getReceipt(client) catch |err| switch (err) {
                error.ReceiptStatusBusy, error.ReceiptStatusUnknown => {
                    const elapsed = @as(u64, @intCast(std.time.milliTimestamp() - start_time));
                    if (elapsed >= timeout) {
                        return error.TransactionTimeout;
                    }
                    
                    // Wait before retrying
                    std.time.sleep(1000 * std.time.ns_per_ms); // 1 second
                    continue;
                },
                else => return err,
            };
            
            return receipt;
        }
    }
    
    pub fn isSuccess(self: *const Self, client: *Client) !bool {
        const receipt = try self.getReceipt(client);
        return receipt.status == .Success;
    }
    
    pub fn clone(self: *const Self, allocator: Allocator) !Self {
        var cloned = try Self.init(allocator, self.transaction_id, self.node_id, self.hash);
        cloned.scheduled_transaction_id = self.scheduled_transaction_id;
        cloned.validate_status = self.validate_status;
        cloned.include_child_receipts = self.include_child_receipts;
        cloned.transaction = self.transaction;
        return cloned;
    }
    
    pub fn equals(self: *const Self, other: *const Self) bool {
        return self.transaction_id.equals(other.transaction_id) and
               self.node_id.equals(other.node_id) and
               std.mem.eql(u8, self.hash, other.hash) and
               self.validate_status == other.validate_status and
               self.include_child_receipts == other.include_child_receipts;
    }
};


const std = @import("std");
const Allocator = std.mem.Allocator;
const errors = @import("../core/errors.zig");
const HederaError = errors.HederaError;
const Query = @import("../query/query.zig").Query;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;
const AccountId = @import("../core/id.zig").AccountId;
const TransactionReceipt = @import("../transaction/transaction_receipt.zig").TransactionReceipt;
const Client = @import("../network/client.zig").Client;
const Status = @import("../core/status.zig").Status;
const Hbar = @import("../core/hbar.zig").Hbar;
const protobuf = @import("../protobuf/encoding.zig");


pub fn newTransactionReceiptQuery(allocator: Allocator) TransactionReceiptQuery {
    return TransactionReceiptQuery.init(allocator);
}

pub const TransactionReceiptQuery = struct {
    query: Query,
    transaction_id: ?TransactionId,
    validate_status: bool,
    include_duplicates: bool,
    include_children: bool,
    
    const Self = @This();
    
    pub fn init(allocator: Allocator) Self {
        var query = Query.init(allocator);
        query.grpc_service_name = "proto.CryptoService";
        query.grpc_method_name = "getTransactionReceipts";
        query.is_payment_required = false;
        
        return Self{
            .query = query,
            .transaction_id = null,
            .validate_status = true,
            .include_duplicates = false,
            .include_children = false,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.query.deinit();
    }
    
    pub fn setTransactionId(self: *Self, transaction_id: TransactionId) !*Self {
        self.transaction_id = transaction_id;
        return self;
    }
    
    pub fn setValidateStatus(self: *Self, validate: bool) !*Self {
        self.validate_status = validate;
        return self;
    }
    
    pub fn setIncludeDuplicates(self: *Self, include: bool) !*Self {
        self.include_duplicates = include;
        return self;
    }
    
    pub fn setIncludeChildren(self: *Self, include: bool) !*Self {
        self.include_children = include;
        return self;
    }
    
    pub fn setIncludeChildReceipts(self: *Self, include: bool) !*Self {
        return self.setIncludeChildren(include);
    }
    
    pub fn setNodeAccountIds(self: *Self, node_account_ids: []const AccountId) !*Self {
        self.query.setNodeAccountIds(node_account_ids);
        return self;
    }
    
    pub fn setMaxQueryPayment(self: *Self, max_query_payment: anytype) !*Self {
        self.query.setMaxQueryPayment(max_query_payment);
        return self;
    }
    
    pub fn setQueryPayment(self: *Self, query_payment: anytype) !*Self {
        self.query.setQueryPayment(query_payment);
        return self;
    }
    
    pub fn setMaxRetry(self: *Self, max_retry: u32) !*Self {
        self.query.setMaxRetry(max_retry);
        return self;
    }
    
    pub fn setMaxBackoff(self: *Self, max_backoff: anytype) !*Self {
        self.query.setMaxBackoff(max_backoff);
        return self;
    }
    
    pub fn setMinBackoff(self: *Self, min_backoff: anytype) !*Self {
        self.query.setMinBackoff(min_backoff);
        return self;
    }
    
    pub fn setRetryHandler(self: *Self, retry_handler: anytype) !*Self {
        self.query.setRetryHandler(retry_handler);
        return self;
    }
    
    pub fn execute(self: *Self, client: *Client) !TransactionReceipt {
        if (self.transaction_id == null) {
            return error.TransactionIdNotSet;
        }
        
        // Build the query bytes for this specific query
        const query_bytes = try self.buildQuery();
        defer self.query.allocator.free(query_bytes);
        
        // Execute with our custom query bytes
        const response = try self.query.executeWithBytes(client, query_bytes);
        const receipt = try self.parseResponse(response.response_bytes);
        
        if (self.validate_status) {
            try receipt.validateStatus();
        }
        
        return receipt;
    }
    
    pub fn executeAsync(self: *Self, client: *Client) !TransactionReceipt {
        return try self.executeWithRetry(client);
    }
    
    fn executeWithRetry(self: *Self, client: *Client) !TransactionReceipt {
        const max_attempts = 10;
        const initial_backoff_ms: u64 = 250;
        var backoff_ms: u64 = initial_backoff_ms;
        
        var attempt: usize = 0;
        while (attempt < max_attempts) : (attempt += 1) {
            if (attempt > 0) {
                std.time.sleep(backoff_ms * std.time.ns_per_ms);
                backoff_ms = @min(backoff_ms * 2, 8000); // Max 8 seconds
            }
            
            const receipt = self.execute(client) catch |err| switch (err) {
                error.ReceiptStatusUnknown,
                error.ReceiptStatusBusy => {
                    if (attempt == max_attempts - 1) return err;
                    continue;
                },
                else => return err,
            };
            
            return receipt;
        }
        
        return error.MaxRetriesExceeded;
    }
    
    fn buildQuery(self: *const Self) ![]u8 {
        var writer = protobuf.ProtoWriter.init(self.query.allocator);
        defer writer.deinit();
        
        // Build inner TransactionGetReceiptQuery message
        var inner_writer = protobuf.ProtoWriter.init(self.query.allocator);
        defer inner_writer.deinit();
        
        const transaction_id = self.transaction_id.?;
        
        // transactionID = 1
        const tx_id_bytes = try transaction_id.toBytes(self.query.allocator);
        defer self.query.allocator.free(tx_id_bytes);
        try inner_writer.writeMessage(1, tx_id_bytes);
        
        // includeDuplicates = 2
        if (self.include_duplicates) {
            try inner_writer.writeBool(2, true);
        }
        
        // includeChildReceipts = 3
        if (self.include_children) {
            try inner_writer.writeBool(3, true);
        }
        
        const inner_bytes = try inner_writer.toOwnedSlice();
        defer self.query.allocator.free(inner_bytes);
        
        // Wrap in Query message
        // transactionGetReceipt = 2 in Query protobuf
        try writer.writeMessage(2, inner_bytes);
        
        return writer.toOwnedSlice();
    }
    
    fn parseResponse(self: *const Self, response_bytes: []const u8) !TransactionReceipt {
        // Parse TransactionGetReceiptResponse protobuf message
        var reader = protobuf.ProtoReader.init(response_bytes);
        
        var receipt: ?TransactionReceipt = null;
        var child_receipts = std.ArrayList(TransactionReceipt).init(self.query.allocator);
        defer child_receipts.deinit();
        var duplicate_receipts = std.ArrayList(TransactionReceipt).init(self.query.allocator);
        defer duplicate_receipts.deinit();
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            switch (tag.field_number) {
                1 => {
                    // header = 1 (ResponseHeader)
                    try reader.skipField(tag.wire_type);
                },
                2 => {
                    // receipt = 2 (TransactionReceipt)
                    const receipt_bytes = try reader.readBytes();
                    
                    receipt = try TransactionReceipt.fromProtobufBytes(self.query.allocator, receipt_bytes);
                },
                3 => {
                    // duplicateTransactionReceipts = 3 (repeated TransactionReceipt)
                    const duplicate_bytes = try reader.readBytes();
                    
                    const duplicate_receipt = try TransactionReceipt.fromProtobufBytes(self.query.allocator, duplicate_bytes);
                    try duplicate_receipts.append(duplicate_receipt);
                },
                4 => {
                    // childTransactionReceipts = 4 (repeated TransactionReceipt)  
                    const child_bytes = try reader.readBytes();
                    
                    const child_receipt = try TransactionReceipt.fromProtobufBytes(self.query.allocator, child_bytes);
                    try child_receipts.append(child_receipt);
                },
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        if (receipt) |*r| {
            // Add child receipts if any were found
            if (child_receipts.items.len > 0) {
                const children = try self.query.allocator.dupe(TransactionReceipt, child_receipts.items);
                r.children = children;
            }
            
            // Add duplicate receipts if any were found
            if (duplicate_receipts.items.len > 0) {
                const duplicates = try self.query.allocator.dupe(TransactionReceipt, duplicate_receipts.items);
                r.duplicates = duplicates;
            }
            
            return r.*;
        }
        
        return HederaError.InvalidProtobuf;
    }
    
    pub fn getCost(self: *Self, client: *Client) !Hbar {
        _ = self;
        _ = client;
        // Transaction receipt queries are free
        return Hbar.zero();
    }
    
    pub fn getTransactionId(self: *const Self) ?TransactionId {
        return self.transaction_id;
    }
    
    pub fn getValidateStatus(self: *const Self) bool {
        return self.validate_status;
    }
    
    pub fn getIncludeDuplicates(self: *const Self) bool {
        return self.include_duplicates;
    }
    
    pub fn getIncludeChildren(self: *const Self) bool {
        return self.include_children;
    }
    
    pub fn toString(self: *const Self, allocator: Allocator) ![]u8 {
        const tx_id_str = if (self.transaction_id) |tx_id| 
            try tx_id.toString(allocator)
        else 
            try allocator.dupe(u8, "null");
        defer allocator.free(tx_id_str);
        
        return try std.fmt.allocPrint(allocator,
            "TransactionReceiptQuery{{transaction_id={s}, validate_status={}, include_duplicates={}, include_children={}}}",
            .{ tx_id_str, self.validate_status, self.include_duplicates, self.include_children }
        );
    }
};
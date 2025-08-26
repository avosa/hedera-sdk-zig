// Transaction Receipt Query - fetches receipts from Hedera network
// Handles receipt retrieval and parsing with comprehensive error handling

const std = @import("std");
const ProtoWriter = @import("../protobuf/writer.zig").ProtoWriter;
const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;
const AccountId = @import("../core/id.zig").AccountId;
const TransactionReceipt = @import("transaction_receipt.zig").TransactionReceipt;
const Status = @import("../core/status.zig").Status;
const Query = @import("../query/query.zig").Query;
const QueryResponse = @import("../query/query.zig").QueryResponse;
const Client = @import("../network/client.zig").Client;
const Hbar = @import("../core/hbar.zig").Hbar;

// Receipt query for fetching transaction results
pub const TransactionReceiptQuery = struct {
    base: Query,
    transaction_id: ?TransactionId,
    include_duplicates: bool,
    include_children: bool,
    validate_status: bool,
    
    pub fn init(allocator: std.mem.Allocator) TransactionReceiptQuery {
        var query = TransactionReceiptQuery{
            .base = Query.init(allocator),
            .transaction_id = null,
            .include_duplicates = false,
            .include_children = false,
            .validate_status = true,
        };
        query.base.grpc_service_name = "proto.CryptoService";
        query.base.grpc_method_name = "getTransactionReceipts";
        query.base.is_payment_required = false;  // Receipt queries are free
        return query;
    }
    
    pub fn deinit(self: *TransactionReceiptQuery) void {
        self.base.deinit();
    }
    
    // Set the transaction ID
    pub fn setTransactionId(self: *TransactionReceiptQuery, transaction_id: TransactionId) !*TransactionReceiptQuery {
        self.transaction_id = transaction_id;
        return self;
    }
    
    // Set include duplicates flag
    pub fn setIncludeDuplicates(self: *TransactionReceiptQuery, include: bool) !*TransactionReceiptQuery {
        self.include_duplicates = include;
        return self;
    }
    
    // Set include children flag
    pub fn setIncludeChildren(self: *TransactionReceiptQuery, include: bool) !*TransactionReceiptQuery {
        self.include_children = include;
        return self;
    }
    
    // Set validate status flag
    pub fn setValidateStatus(self: *TransactionReceiptQuery, validate: bool) !*TransactionReceiptQuery {
        self.validate_status = validate;
        return self;
    }
    
    // Build query protobuf
    pub fn buildQuery(self: *TransactionReceiptQuery) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // transactionGetReceipt = 4 (oneof query)
        var receipt_query_writer = ProtoWriter.init(self.base.allocator);
        defer receipt_query_writer.deinit();
        
        // header = 1 (inside the specific query)
        var header_writer = ProtoWriter.init(self.base.allocator);
        defer header_writer.deinit();
        
        // payment = 1 (optional for free queries - Receipt queries are free)
        // responseType = 2 (must be present even if 0)
        try header_writer.writeTag(2, .Varint);
        try header_writer.writeVarint(@as(u64, @intCast(@intFromEnum(self.base.response_type))));
        
        const header_bytes = try header_writer.toOwnedSlice();
        defer self.base.allocator.free(header_bytes);
        try receipt_query_writer.writeMessage(1, header_bytes);
        
        // transactionID = 2
        if (self.transaction_id) |tx_id| {
            const tx_id_bytes = try self.encodeTransactionId(tx_id);
            defer self.base.allocator.free(tx_id_bytes);
            try receipt_query_writer.writeMessage(2, tx_id_bytes);
        }
        
        // includeDuplicates = 3
        if (self.include_duplicates) {
            try receipt_query_writer.writeBool(3, true);
        }
        
        // includeChildReceipts = 4
        if (self.include_children) {
            try receipt_query_writer.writeBool(4, true);
        }
        
        const receipt_query_bytes = try receipt_query_writer.toOwnedSlice();
        defer self.base.allocator.free(receipt_query_bytes);
        try writer.writeMessage(4, receipt_query_bytes);
        
        return writer.toOwnedSlice();
    }
    
    fn encodeTransactionId(self: *TransactionReceiptQuery, tx_id: TransactionId) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // transactionValidStart = 1
        var timestamp_writer = ProtoWriter.init(self.base.allocator);
        defer timestamp_writer.deinit();
        try timestamp_writer.writeInt64(1, tx_id.valid_start.seconds);
        try timestamp_writer.writeInt32(2, tx_id.valid_start.nanos);
        const timestamp_bytes = try timestamp_writer.toOwnedSlice();
        defer self.base.allocator.free(timestamp_bytes);
        try writer.writeMessage(1, timestamp_bytes);
        
        // accountID = 2
        var account_writer = ProtoWriter.init(self.base.allocator);
        defer account_writer.deinit();
        try account_writer.writeInt64(1, @intCast(tx_id.account_id.shard));
        try account_writer.writeInt64(2, @intCast(tx_id.account_id.realm));
        try account_writer.writeInt64(3, @intCast(tx_id.account_id.account));
        const account_bytes = try account_writer.toOwnedSlice();
        defer self.base.allocator.free(account_bytes);
        try writer.writeMessage(2, account_bytes);
        
        // scheduled = 3
        if (tx_id.scheduled) {
            try writer.writeBool(3, true);
        }
        
        // nonce = 4
        if (tx_id.nonce) |nonce| {
            try writer.writeInt32(4, @intCast(nonce));
        }
        
        return writer.toOwnedSlice();
    }
    
    // Execute query on network
    pub fn execute(self: *TransactionReceiptQuery, client: *Client) !TransactionReceipt {
        if (self.transaction_id == null) {
            return error.TransactionIdRequired;
        }
        
        // Build the query bytes directly
        const query_bytes = try self.buildQuery();
        defer self.base.allocator.free(query_bytes);
        
        // Execute with the built bytes
        const response = try self.base.executeWithBytes(client, query_bytes);
        return try self.parseResponse(response);
    }
    
    // Parse the response
    fn parseResponse(self: *TransactionReceiptQuery, response: QueryResponse) !TransactionReceipt {
        // For receipt queries, we don't validate status here as the status in the receipt is what matters
        
        var reader = ProtoReader.init(response.response_bytes);
        var receipt = TransactionReceipt.init(self.base.allocator, Status.OK);
        
        // Parse TransactionGetReceiptResponse
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => {
                    // header
                    _ = try reader.readMessage();
                },
                2 => {
                    // receipt
                    const receipt_bytes = try reader.readMessage();
                    receipt = try TransactionReceipt.fromProtobuf(self.base.allocator, receipt_bytes);
                },
                3 => {
                    // duplicates
                    const duplicate_bytes = try reader.readMessage();
                    _ = duplicate_bytes;
                    // Duplicates will be parsed when needed
                },
                4 => {
                    // childTransactionReceipts
                    const child_bytes = try reader.readMessage();
                    _ = child_bytes;
                    // Children will be parsed when needed
                },
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        // Validate status if requested
        if (self.validate_status) {
            if (receipt.status != .SUCCESS) {
                return error.ReceiptStatusError;
            }
        }
        
        return receipt;
    }
};
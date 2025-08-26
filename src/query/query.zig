const std = @import("std");
const AccountId = @import("../core/id.zig").AccountId;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;
const Timestamp = @import("../core/transaction_id.zig").Timestamp;
const Hbar = @import("../core/hbar.zig").Hbar;
const Client = @import("../network/client.zig").Client;
const Node = @import("../network/node.zig").Node;
const GrpcConnection = @import("../network/grpc_plain.zig").GrpcPlainConnection;
const Transaction = @import("../transaction/transaction.zig").Transaction;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;
const errors = @import("../core/errors.zig");
const HederaError = errors.HederaError;
// Query header type
pub const ResponseType = enum(i32) {
    AnswerOnly = 0,
    AnswerStateProof = 1,
    CostAnswer = 2,
    CostAnswerStateProof = 3,
};

// Query response header
pub const ResponseHeader = struct {
    node_transaction_precheck_code: i32,
    response_type: ResponseType,
    cost: u64,
    state_proof: ?[]const u8 = null,
    
    pub fn encode(self: ResponseHeader, writer: *ProtoWriter) !void {
        try writer.writeInt32(1, self.node_transaction_precheck_code);
        try writer.writeInt32(2, @intFromEnum(self.response_type));
        try writer.writeUint64(3, self.cost);
        if (self.state_proof) |proof| {
            try writer.writeString(4, proof);
        }
    }
    
    pub fn decode(reader: *ProtoReader) !ResponseHeader {
        var header = ResponseHeader{
            .node_transaction_precheck_code = 0,
            .response_type = .AnswerOnly,
            .cost = 0,
        };
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => header.node_transaction_precheck_code = try reader.readInt32(),
                2 => header.response_type = @enumFromInt(try reader.readInt32()),
                3 => header.cost = try reader.readUint64(),
                4 => header.state_proof = try reader.readString(),
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return header;
    }
};

// Base query structure
pub const Query = struct {
    allocator: std.mem.Allocator,
    node_account_ids: std.ArrayList(AccountId),
    payment_transaction_id: ?TransactionId,
    payment_amount: ?Hbar,
    max_payment_amount: ?Hbar,
    payment_transactions: std.ArrayList(Transaction),
    query_payments: std.AutoHashMap(AccountId, Hbar),
    response_type: ResponseType,
    timestamp: ?Timestamp,
    max_attempts: u32,
    
    // gRPC service and method routing
    grpc_service_name: []const u8,
    grpc_method_name: []const u8,
    max_backoff: i64,
    min_backoff: i64,
    grpc_deadline: ?i64,
    is_payment_required: bool,
    executed: std.atomic.Value(bool),
    
    pub fn init(allocator: std.mem.Allocator) Query {
        return Query{
            .allocator = allocator,
            .node_account_ids = std.ArrayList(AccountId).init(allocator),
            .payment_transaction_id = null,
            .payment_amount = null,
            .max_payment_amount = null,
            .payment_transactions = std.ArrayList(Transaction).init(allocator),
            .query_payments = std.AutoHashMap(AccountId, Hbar).init(allocator),
            .response_type = .AnswerOnly,
            .timestamp = null,
            .max_attempts = 10,
            .grpc_service_name = "proto.CryptoService",
            .grpc_method_name = "cryptoGetAccountBalance",
            .max_backoff = 8_000_000_000,
            .min_backoff = 250_000_000,
            .grpc_deadline = null,
            .is_payment_required = true,
            .executed = std.atomic.Value(bool).init(false),
        };
    }
    
    pub fn deinit(self: *Query) void {
        self.node_account_ids.deinit();
        self.payment_transactions.deinit();
        self.query_payments.deinit();
    }
    
    // Set node account IDs
    pub fn setNodeAccountIds(self: *Query, node_ids: []const AccountId) !*Query {
        self.node_account_ids.clearRetainingCapacity();
        for (node_ids) |id| {
            self.node_account_ids.append(id) catch return error.OutOfMemory;
        }
        return self;
    }
    
    // Set max query payment
    pub fn setMaxQueryPayment(self: *Query, amount: Hbar) !*Query {
        self.max_payment_amount = amount;
        return self;
    }
    
    // Set query payment
    pub fn setQueryPayment(self: *Query, amount: Hbar) !*Query {
        self.payment_amount = amount;
        return self;
    }
    
    // Set max retry attempts
    pub fn setMaxRetry(self: *Query, max_retry: u32) !*Query {
        self.max_attempts = max_retry;
        return self;
    }
    
    // Set request timeout
    pub fn setRequestTimeout(self: *Query, timeout_ms: i64) !*Query {
        self.grpc_deadline = timeout_ms;
        return self;
    }
    
    // Get cost of query
    pub fn getCost(self: *Query, client: *Client) HederaError!Hbar {
        // Create cost query
        var cost_query = self.*;
        cost_query.response_type = .CostAnswer;
        cost_query.is_payment_required = false;
        cost_query.executed = .{ .raw = false }; // Reset executed flag for cost query
        
        const response = try cost_query.executeInternal(client, true);
        return Hbar.fromTinybars(@intCast(response.header.cost));
    }
    
    // Generate payment transaction
    fn generatePaymentTransaction(self: *Query, client: *Client, node_id: AccountId, _: Hbar) HederaError!Transaction {
        const operator = client.operator orelse return error.MissingOperatorAccountId;
        
        // Create crypto transfer transaction for payment
        var payment = Transaction.init(self.allocator);
        
        // Set transaction details
        const tx_id = TransactionId.generate(operator.account_id);
        _ = try payment.setTransactionId(tx_id);
        _ = try payment.setNodeAccountIds(&[_]AccountId{node_id});
        _ = try payment.setTransactionMemo("Query payment");
        
        // Return the configured payment transaction
        return payment;
    }
    
    // Make payment for query
    fn makePayment(self: *Query, client: *Client, node_id: AccountId) HederaError!void {
        if (!self.is_payment_required) return;
        
        // Check if we already have a payment for this node
        if (self.query_payments.get(node_id)) |_| {
            return;
        }
        
        // Determine payment amount
        const payment_amount = self.payment_amount orelse blk: {
            // Get cost if not set
            const cost = try self.getCost(client);
            break :blk cost;
        };
        
        // Check against max payment
        if (self.max_payment_amount) |max| {
            if (payment_amount.compare(max) == .gt) {
                return error.InsufficientTxFee; // Exceeds max query payment
            }
        }
        
        // Generate and execute payment transaction
        const payment_tx = try self.generatePaymentTransaction(client, node_id, payment_amount);
        try self.payment_transactions.append(payment_tx);
        try self.query_payments.put(node_id, payment_amount);
    }
    
    // Internal execute with pre-built bytes
    fn executeInternalWithBytes(self: *Query, client: *Client, query_bytes: []const u8, is_cost_query: bool) HederaError!QueryResponse {
        // Set node IDs if not set
        if (self.node_account_ids.items.len == 0) {
            const nodes = try client.selectNodesForRequest(1);
            defer client.allocator.free(nodes);
            for (nodes) |node| {
                try errors.handleAppendError(&self.node_account_ids, node.account_id);
            }
        }
        
        // Generate payment if required and not cost query
        if (!is_cost_query and self.is_payment_required) {
            for (self.node_account_ids.items) |node_id| {
                try self.makePayment(client, node_id);
            }
        }
        
        // Execute on network via client
        const response_bytes = client.executeQueryRequest(query_bytes, self.node_account_ids.items[0], self.grpc_service_name, self.grpc_method_name) catch |err| {
            return switch (err) {
                error.NoHealthyNodes => error.NoHealthyNodes,
                error.NodeNotFound => error.InvalidNodeAccount,
                error.ConnectionClosed => error.ConnectionFailed,
                else => error.UnknownError,
            };
        };
        
        // Parse response header from protobuf
        var reader = ProtoReader.init(response_bytes);
        var header = ResponseHeader{
            .node_transaction_precheck_code = 0,
            .response_type = .AnswerOnly,
            .cost = 0,
            .state_proof = null,
        };
        
        // Extract header from response
        while (reader.hasMore()) {
            const tag = reader.readTag() catch break;
            if (tag.field_number == 1) {
                // Response header field
                const header_bytes = reader.readBytes() catch break;
                var header_reader = ProtoReader.init(header_bytes);
                while (header_reader.hasMore()) {
                    const header_tag = header_reader.readTag() catch break;
                    switch (header_tag.field_number) {
                        1 => header.node_transaction_precheck_code = header_reader.readInt32() catch 0,
                        2 => header.response_type = @enumFromInt(header_reader.readInt32() catch 0),
                        3 => header.cost = header_reader.readUint64() catch 0,
                        else => header_reader.skipField(header_tag.wire_type) catch {},
                    }
                }
                break;
            }
            reader.skipField(tag.wire_type) catch break;
        }
        
        return QueryResponse{
            .header = header,
            .response_bytes = response_bytes,
        };
    }
    
    // Internal execute without executed flag check
    fn executeInternal(self: *Query, client: *Client, is_cost_query: bool) HederaError!QueryResponse {
        // Set node account IDs if not set
        if (self.node_account_ids.items.len == 0) {
            const nodes = try client.selectNodesForRequest(1);
            defer client.allocator.free(nodes);
            
            for (nodes) |node| {
                try self.node_account_ids.append(node.account_id);
            }
        }
        
        // Make payment if required and not a cost query
        if (self.is_payment_required and !is_cost_query) {
            for (self.node_account_ids.items) |node_id| {
                try self.makePayment(client, node_id);
            }
        }
        
        // Build query bytes
        const query_bytes = try self.buildQuery();
        defer self.allocator.free(query_bytes);
        
        // Execute on network via client
        const response_bytes = client.executeQueryRequest(query_bytes, self.node_account_ids.items[0], self.grpc_service_name, self.grpc_method_name) catch |err| {
            return switch (err) {
                error.NoHealthyNodes => error.NoHealthyNodes,
                error.NodeNotFound => error.InvalidNodeAccount,
                error.ConnectionClosed => error.ConnectionFailed,
                error.StreamReset => error.ConnectionFailed,
                error.NoDataReceived => error.InvalidParameter,
                else => error.UnknownError,
            };
        };
        
        // Parse response header
        var reader = ProtoReader.init(response_bytes);
        const header = ResponseHeader.decode(&reader) catch {
            return error.InvalidProtobuf;
        };
        
        return QueryResponse{
            .header = header,
            .response_bytes = response_bytes,
        };
    }
    
    // Execute query
    pub fn execute(self: *Query, client: *Client) HederaError!QueryResponse {
        if (self.executed.swap(true, .acquire)) {
            return error.InvalidParameter; // Query already executed
        }
        
        return self.executeInternal(client, false);
    }
    
    // Execute query with pre-built bytes
    pub fn executeWithBytes(self: *Query, client: *Client, query_bytes: []const u8) HederaError!QueryResponse {
        if (self.executed.swap(true, .acquire)) {
            return error.InvalidParameter; // Query already executed
        }
        
        return self.executeInternalWithBytes(client, query_bytes, false);
    }
    
    // Build query request
    fn buildRequest(self: *Query) HederaError!QueryRequest {
        const query_bytes = try self.buildQuery();
        
        return QueryRequest{
            .query_bytes = query_bytes,
            .node_account_id = if (self.node_account_ids.items.len > 0) self.node_account_ids.items[0] else AccountId{},
            .grpc_service_name = self.grpc_service_name,
            .grpc_method_name = self.grpc_method_name,
        };
    }
    
    // Build query (to be implemented by specific query types)
    pub fn buildQuery(self: *Query) ![]u8 {
        var writer = ProtoWriter.init(self.allocator);
        defer writer.deinit();
        
        // Common query header fields
        if (self.payment_amount) |payment| {
            var payment_writer = ProtoWriter.init(self.allocator);
            defer payment_writer.deinit();
            
            try payment_writer.writeUint64(1, @intCast(payment.toTinybars()));
            const payment_bytes = try payment_writer.toOwnedSlice();
            defer self.allocator.free(payment_bytes);
            
            try writer.writeMessage(1, payment_bytes);
        }
        
        // Response type
        try writer.writeUint32(2, @intCast(@intFromEnum(self.response_type)));
        
        return writer.toOwnedSlice();
    }
    
    // Set response type
    pub fn setIncludeCostAnswer(self: *Query, include: bool) !*Query {
        if (include) {
            self.response_type = .CostAnswer;
        } else {
            self.response_type = .AnswerOnly;
        }
        return self;
    }
    
    // Set state proof requirement
    pub fn setIncludeStateProof(self: *Query, include: bool) !*Query {
        if (include) {
            self.response_type = switch (self.response_type) {
                .AnswerOnly, .AnswerStateProof => .AnswerStateProof,
                .CostAnswer, .CostAnswerStateProof => .CostAnswerStateProof,
            };
        }
        return self;
    }
    
    // Set gRPC deadline
    pub fn setGrpcDeadline(self: *Query, deadline_ns: i64) !*Query {
        self.grpc_deadline = deadline_ns;
        return self;
    }
    
    // Set max attempts
    pub fn setMaxAttempts(self: *Query, attempts: u32) !*Query {
        self.max_attempts = attempts;
        return self;
    }
    
    // Set backoff parameters
    pub fn setMaxBackoff(self: *Query, backoff_ns: i64) !*Query {
        self.max_backoff = backoff_ns;
        return self;
    }
    
    pub fn setMinBackoff(self: *Query, backoff_ns: i64) !*Query {
        self.min_backoff = backoff_ns;
        return self;
    }
};

// Query request for network submission
const QueryRequest = struct {
    query_bytes: []const u8,
    node_account_id: AccountId,
    grpc_service_name: []const u8,
    grpc_method_name: []const u8,
    
    pub const Response = struct {
        header: ResponseHeader,
        response_bytes: []const u8,
    };
    
    pub fn execute(self: QueryRequest, conn: *GrpcConnection) !Response {
        // Submit query via gRPC
        const response_bytes = try conn.call(
            self.grpc_service_name,
            self.grpc_method_name,
            self.query_bytes,
        );
        
        // Parse response header
        var reader = ProtoReader.init(response_bytes);
        const header = ResponseHeader.decode(&reader) catch {
            return error.InvalidProtobuf;
        };
        
        return Response{
            .header = header,
            .response_bytes = response_bytes,
        };
    }
};

// Query response
pub const QueryResponse = struct {
    header: ResponseHeader,
    response_bytes: []const u8,
    
    pub fn getCost(self: QueryResponse) Hbar {
        return Hbar.fromTinybars(@intCast(self.header.cost)) catch Hbar.zero();
    }
    
    pub fn getStateProof(self: QueryResponse) ?[]const u8 {
        return self.header.state_proof;
    }
    
    pub fn validateStatus(self: QueryResponse) !void {
        if (self.header.node_transaction_precheck_code != 0 and self.header.node_transaction_precheck_code != 22) { // 0=OK, 22=SUCCESS
            return error.InvalidParameter;
        }
    }
};
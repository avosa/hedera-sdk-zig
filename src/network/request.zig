const std = @import("std");
const AccountId = @import("../core/id.zig").AccountId;
const Duration = @import("../core/duration.zig").Duration;
const StatusCode = @import("../core/status.zig").StatusCode;

pub const RequestType = enum {
    Query,
    Transaction,
};

pub const ResponseType = enum {
    Query,
    Transaction,
};

pub const Request = struct {
    type: RequestType,
    transaction: ?*anyopaque,
    query: ?*anyopaque,
    node_account_id: AccountId,
    max_retry: u32,
    timeout: Duration,
    
    pub fn init(request_type: RequestType, node_id: AccountId) Request {
        return Request{
            .type = request_type,
            .transaction = null,
            .query = null,
            .node_account_id = node_id,
            .max_retry = 3,
            .timeout = Duration.fromSeconds(30),
        };
    }
};

pub const Response = struct {
    type: ResponseType,
    transaction_response: ?*anyopaque,
    query_response: ?*anyopaque,
    node_account_id: AccountId,
    status: StatusCode,
    
    pub fn init(response_type: ResponseType, node_id: AccountId, status: StatusCode) Response {
        return Response{
            .type = response_type,
            .transaction_response = null,
            .query_response = null,
            .node_account_id = node_id,
            .status = status,
        };
    }
};
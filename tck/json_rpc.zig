const std = @import("std");
const json = std.json;
pub const JSONRPC_VERSION = "2.0";
pub const Request = struct {
    jsonrpc: []const u8 = JSONRPC_VERSION,
    method: []const u8,
    params: ?json.Value = null,
    id: ?json.Value = null,
    parsed_json: json.Parsed(json.Value),
    pub fn parse(allocator: std.mem.Allocator, data: []const u8) !Request {
        const parsed = try json.parseFromSlice(json.Value, allocator, data, .{});
        const obj = parsed.value.object;
        const jsonrpc = obj.get("jsonrpc") orelse return error.InvalidRequest;
        const method = obj.get("method") orelse return error.InvalidRequest;
        if (!std.mem.eql(u8, jsonrpc.string, JSONRPC_VERSION)) {
            return error.InvalidJSONRPCVersion;
        }
        return Request{
            .jsonrpc = try allocator.dupe(u8, jsonrpc.string),
            .method = try allocator.dupe(u8, method.string),
            .params = if (obj.get("params")) |p| p else null,
            .id = if (obj.get("id")) |i| i else null,
            .parsed_json = parsed,
        };
    }
    pub fn deinit(self: *Request, allocator: std.mem.Allocator) void {
        allocator.free(self.jsonrpc);
        allocator.free(self.method);
        self.parsed_json.deinit();
    }
};
pub const Response = struct {
    jsonrpc: []const u8 = JSONRPC_VERSION,
    result: ?json.Value = null,
    @"error": ?Error = null,
    id: ?json.Value = null,
    pub fn success(allocator: std.mem.Allocator, result: json.Value, id: ?json.Value) !Response {
        _ = allocator; 
        return Response{
            .result = result,
            .id = id,
        };
    }
    pub fn err(code: i32, message: []const u8, data: ?json.Value, id: ?json.Value) Response {
        return Response{
            .@"error" = Error{
                .code = code,
                .message = message,
                .data = data,
            },
            .id = id,
        };
    }
    pub fn stringify(self: Response, allocator: std.mem.Allocator) ![]u8 {
        const id_str = if (self.id) |id| switch (id) {
            .integer => |i| try std.fmt.allocPrint(allocator, "{d}", .{i}),
            .string => |s| try std.fmt.allocPrint(allocator, "\"{s}\"", .{s}),
            .null => try std.fmt.allocPrint(allocator, "null", .{}),
            else => try std.fmt.allocPrint(allocator, "null", .{}),
        } else try std.fmt.allocPrint(allocator, "null", .{});
        defer allocator.free(id_str);
        if (self.@"error") |e| {
            return try std.fmt.allocPrint(allocator,
                "{{\"jsonrpc\":\"{s}\",\"error\":{{\"code\":{d},\"message\":\"{s}\"}},\"id\":{s}}}",
                .{ JSONRPC_VERSION, e.code, e.message, id_str }
            );
        } else if (self.result) |result| {
            var result_str = std.ArrayList(u8).init(allocator);
            defer result_str.deinit();
            try std.json.stringify(result, .{}, result_str.writer());
            return try std.fmt.allocPrint(allocator,
                "{{\"jsonrpc\":\"{s}\",\"result\":{s},\"id\":{s}}}",
                .{ JSONRPC_VERSION, result_str.items, id_str }
            );
        } else {
            return try std.fmt.allocPrint(allocator,
                "{{\"jsonrpc\":\"{s}\",\"result\":null,\"id\":{s}}}",
                .{ JSONRPC_VERSION, id_str }
            );
        }
    }
    pub fn deinit(self: *Response, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};
pub const Error = struct {
    code: i32,
    message: []const u8,
    data: ?json.Value = null,
};
pub const ErrorCode = struct {
    pub const PARSE_ERROR: i32 = -32700;
    pub const INVALID_REQUEST: i32 = -32600;
    pub const METHOD_NOT_FOUND: i32 = -32601;
    pub const INVALID_PARAMS: i32 = -32602;
    pub const INTERNAL_ERROR: i32 = -32603;
    pub const SERVER_ERROR: i32 = -32000; 
    pub const HEDERA_ERROR: i32 = -32001;
    pub const CLIENT_NOT_CONFIGURED: i32 = -32002;
    pub const TRANSACTION_FAILED: i32 = -32003;
    pub const QUERY_FAILED: i32 = -32004;
    pub const KEY_PARSE_ERROR: i32 = -32005;
    pub const ACCOUNT_ID_PARSE_ERROR: i32 = -32006;
};
pub const Method = enum {
    setup,
    reset,
    createAccount,
    updateAccount,
    deleteAccount,
    approveAllowance,
    deleteAllowance,
    transferCrypto,
    createToken,
    updateToken,
    deleteToken,
    updateTokenFeeSchedule,
    associateToken,
    dissociateToken,
    pauseToken,
    unpauseToken,
    freezeToken,
    unfreezeToken,
    grantTokenKyc,
    revokeTokenKyc,
    mintToken,
    burnToken,
    wipeToken,
    claimToken,
    airdropToken,
    cancelAirdrop,
    rejectToken,
    createFile,
    updateFile,
    deleteFile,
    appendFile,
    createTopic,
    updateTopic,
    deleteTopic,
    submitTopicMessage,
    createContract,
    updateContract,
    deleteContract,
    executeContract,
    generateKey,
    createSchedule,
    signSchedule,
    deleteSchedule,
    getScheduleInfo,
    createNode,
    updateNode,
    deleteNode,
    getAccountInfo,
    getAccountBalance,
    getTokenInfo,
    getTokenBalance,
    getFileInfo,
    getFileContents,
    getTopicInfo,
    getContractInfo,
    getTransactionRecord,
    getTransactionReceipt,
    pub fn fromString(method: []const u8) ?Method {
        inline for (std.meta.fields(Method)) |field| {
            if (std.mem.eql(u8, field.name, method)) {
                return @field(Method, field.name);
            }
        }
        return null;
    }
};

const std = @import("std");
const Query = @import("../query/query.zig").Query;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;
const Timestamp = @import("../core/timestamp.zig").Timestamp;

// NetworkGetExecutionTimeQuery gets network execution times
pub const NetworkGetExecutionTimeQuery = struct {
    base: Query,
    
    pub fn init(allocator: std.mem.Allocator) NetworkGetExecutionTimeQuery {
        return NetworkGetExecutionTimeQuery{
            .base = Query.init(allocator),
        };
    }
    
    pub fn deinit(self: *NetworkGetExecutionTimeQuery) void {
        self.base.deinit();
    }
    
    // Execute the query
    pub fn execute(self: *NetworkGetExecutionTimeQuery, client: *Client) !NetworkExecutionTimes {
        const response = try self.base.execute(client);
        defer self.base.allocator.free(response);
        
        return try self.parseResponse(response);
    }
    
    // Build query body
    pub fn buildQuery(self: *NetworkGetExecutionTimeQuery) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // networkGetExecutionTime = 81 (oneof query)
        var query_writer = ProtoWriter.init(self.base.allocator);
        defer query_writer.deinit();
        
        // Empty message for this query
        const query_bytes = try query_writer.toOwnedSlice();
        defer self.base.allocator.free(query_bytes);
        try writer.writeMessage(81, query_bytes);
        
        return writer.toOwnedSlice();
    }
    
    // Parse response
    fn parseResponse(self: *NetworkGetExecutionTimeQuery, data: []const u8) !NetworkExecutionTimes {
        var reader = ProtoReader.init(data);
        var execution_times = NetworkExecutionTimes{
            .execution_times = std.ArrayList(TransactionExecutionTime).init(self.base.allocator),
        };
        
        while (try reader.next()) |field| {
            switch (field.number) {
                1 => {
                    // executionTimes (repeated)
                    const exec_time = try parseExecutionTime(field.data);
                    try execution_times.execution_times.append(exec_time);
                },
                else => {},
            }
        }
        
        return execution_times;
    }
    
    fn parseExecutionTime(data: []const u8) !TransactionExecutionTime {
        var reader = ProtoReader.init(data);
        var exec_time = TransactionExecutionTime{
            .transaction_type = .unknown,
            .execution_time_ms = 0,
        };
        
        while (try reader.next()) |field| {
            switch (field.number) {
                1 => {
                    // transactionType
                    const type_code = try reader.readInt32(field.data);
                    exec_time.transaction_type = TransactionType.fromCode(type_code);
                },
                2 => {
                    // executionTimeInMillis
                    exec_time.execution_time_ms = try reader.readInt64(field.data);
                },
                else => {},
            }
        }
        
        return exec_time;
    }
};

// Network execution times response
pub const NetworkExecutionTimes = struct {
    execution_times: std.ArrayList(TransactionExecutionTime),
    
    pub fn deinit(self: *NetworkExecutionTimes) void {
        self.execution_times.deinit();
    }
};

// Transaction execution time
pub const TransactionExecutionTime = struct {
    transaction_type: TransactionType,
    execution_time_ms: i64,
};

// Transaction types for execution time tracking
pub const TransactionType = enum {
    unknown,
    crypto_create_account,
    crypto_update_account,
    crypto_transfer,
    crypto_delete,
    contract_create,
    contract_call,
    contract_update,
    contract_delete,
    file_create,
    file_update,
    file_delete,
    token_create,
    token_associate,
    token_dissociate,
    token_mint,
    token_burn,
    token_freeze,
    token_unfreeze,
    token_grant_kyc,
    token_revoke_kyc,
    token_wipe,
    token_update,
    token_delete,
    topic_create,
    topic_update,
    topic_delete,
    topic_message_submit,
    schedule_create,
    schedule_delete,
    schedule_sign,
    freeze,
    system_delete,
    system_undelete,
    
    pub fn fromCode(code: i32) TransactionType {
        return switch (code) {
            10 => .crypto_create_account,
            11 => .crypto_update_account,
            12 => .crypto_transfer,
            13 => .crypto_delete,
            20 => .contract_create,
            21 => .contract_call,
            22 => .contract_update,
            23 => .contract_delete,
            30 => .file_create,
            31 => .file_update,
            32 => .file_delete,
            40 => .token_create,
            41 => .token_associate,
            42 => .token_dissociate,
            43 => .token_mint,
            44 => .token_burn,
            45 => .token_freeze,
            46 => .token_unfreeze,
            47 => .token_grant_kyc,
            48 => .token_revoke_kyc,
            49 => .token_wipe,
            50 => .token_update,
            51 => .token_delete,
            60 => .topic_create,
            61 => .topic_update,
            62 => .topic_delete,
            63 => .topic_message_submit,
            70 => .schedule_create,
            71 => .schedule_delete,
            72 => .schedule_sign,
            80 => .freeze,
            90 => .system_delete,
            91 => .system_undelete,
            else => .unknown,
        };
    }
};

// NetworkGetVersionInfoQuery gets network version information
pub const NetworkGetVersionInfoQuery = struct {
    base: Query,
    
    pub fn init(allocator: std.mem.Allocator) NetworkGetVersionInfoQuery {
        return NetworkGetVersionInfoQuery{
            .base = Query.init(allocator),
        };
    }
    
    pub fn deinit(self: *NetworkGetVersionInfoQuery) void {
        self.base.deinit();
    }
    
    // Execute the query
    pub fn execute(self: *NetworkGetVersionInfoQuery, client: *Client) !NetworkVersionInfo {
        const response = try self.base.execute(client);
        defer self.base.allocator.free(response);
        
        return try self.parseResponse(response);
    }
    
    // Build query body
    pub fn buildQuery(self: *NetworkGetVersionInfoQuery) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // networkGetVersionInfo = 80 (oneof query)
        var query_writer = ProtoWriter.init(self.base.allocator);
        defer query_writer.deinit();
        
        // Empty message for this query
        const query_bytes = try query_writer.toOwnedSlice();
        defer self.base.allocator.free(query_bytes);
        try writer.writeMessage(80, query_bytes);
        
        return writer.toOwnedSlice();
    }
    
    // Parse response
    fn parseResponse(self: *NetworkGetVersionInfoQuery, data: []const u8) !NetworkVersionInfo {
        var reader = ProtoReader.init(data);
        var version_info = NetworkVersionInfo{
            .hapi_proto_version = null,
            .hedera_services_version = null,
        };
        
        while (try reader.next()) |field| {
            switch (field.number) {
                1 => {
                    // hapiProtoVersion
                    version_info.hapi_proto_version = try parseSemanticVersion(field.data, self.base.allocator);
                },
                2 => {
                    // hederaServicesVersion
                    version_info.hedera_services_version = try parseSemanticVersion(field.data, self.base.allocator);
                },
                else => {},
            }
        }
        
        return version_info;
    }
    
    fn parseSemanticVersion(data: []const u8, allocator: std.mem.Allocator) !SemanticVersion {
        var reader = ProtoReader.init(data);
        var version = SemanticVersion{
            .major = 0,
            .minor = 0,
            .patch = 0,
            .pre = null,
            .build = null,
        };
        
        while (try reader.next()) |field| {
            switch (field.number) {
                1 => version.major = try reader.readInt32(field.data),
                2 => version.minor = try reader.readInt32(field.data),
                3 => version.patch = try reader.readInt32(field.data),
                4 => version.pre = try allocator.dupe(u8, field.data),
                5 => version.build = try allocator.dupe(u8, field.data),
                else => {},
            }
        }
        
        return version;
    }
};

// Network version information
pub const NetworkVersionInfo = struct {
    hapi_proto_version: ?SemanticVersion,
    hedera_services_version: ?SemanticVersion,
    
    pub fn deinit(self: *NetworkVersionInfo, allocator: std.mem.Allocator) void {
        if (self.hapi_proto_version) |*version| version.deinit(allocator);
        if (self.hedera_services_version) |*version| version.deinit(allocator);
    }
};

// Semantic version
pub const SemanticVersion = struct {
    major: i32,
    minor: i32,
    patch: i32,
    pre: ?[]const u8,
    build: ?[]const u8,
    
    pub fn deinit(self: *SemanticVersion, allocator: std.mem.Allocator) void {
        if (self.pre) |pre| allocator.free(pre);
        if (self.build) |build| allocator.free(build);
    }
    
    pub fn toString(self: SemanticVersion, allocator: std.mem.Allocator) ![]u8 {
        if (self.pre != null and self.build != null) {
            return std.fmt.allocPrint(allocator, "{d}.{d}.{d}-{s}+{s}", .{ self.major, self.minor, self.patch, self.pre.?, self.build.? });
        } else if (self.pre != null) {
            return std.fmt.allocPrint(allocator, "{d}.{d}.{d}-{s}", .{ self.major, self.minor, self.patch, self.pre.? });
        } else if (self.build != null) {
            return std.fmt.allocPrint(allocator, "{d}.{d}.{d}+{s}", .{ self.major, self.minor, self.patch, self.build.? });
        } else {
            return std.fmt.allocPrint(allocator, "{d}.{d}.{d}", .{ self.major, self.minor, self.patch });
        }
    }
};
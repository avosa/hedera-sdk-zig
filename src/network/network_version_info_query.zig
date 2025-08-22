const std = @import("std");
const Query = @import("../query/query.zig").Query;
const QueryResponse = @import("../query/query.zig").QueryResponse;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;
const Hbar = @import("../core/hbar.zig").Hbar;

// SemanticVersion represents a semantic version
pub const SemanticVersion = struct {
    major: i32,
    minor: i32,
    patch: i32,
    pre: []const u8,
    build: []const u8,
    
    allocator: std.mem.Allocator,
    
    pub fn init(major: i32, minor: i32, patch: i32, allocator: std.mem.Allocator) SemanticVersion {
        return SemanticVersion{
            .major = major,
            .minor = minor,
            .patch = patch,
            .pre = "",
            .build = "",
            .allocator = allocator,
        };
    }
    
    pub fn toString(self: SemanticVersion, allocator: std.mem.Allocator) ![]u8 {
        if (self.pre.len > 0) {
            if (self.build.len > 0) {
                return try std.fmt.allocPrint(allocator, "{d}.{d}.{d}-{s}+{s}", .{ self.major, self.minor, self.patch, self.pre, self.build });
            } else {
                return try std.fmt.allocPrint(allocator, "{d}.{d}.{d}-{s}", .{ self.major, self.minor, self.patch, self.pre });
            }
        } else if (self.build.len > 0) {
            return try std.fmt.allocPrint(allocator, "{d}.{d}.{d}+{s}", .{ self.major, self.minor, self.patch, self.build });
        } else {
            return try std.fmt.allocPrint(allocator, "{d}.{d}.{d}", .{ self.major, self.minor, self.patch });
        }
    }
    
    pub fn deinit(self: *SemanticVersion) void {
        if (self.pre.len > 0) {
            self.allocator.free(self.pre);
        }
        if (self.build.len > 0) {
            self.allocator.free(self.build);
        }
    }
    
    pub fn decode(reader: *ProtoReader, allocator: std.mem.Allocator) !SemanticVersion {
        var version = SemanticVersion{
            .major = 0,
            .minor = 0,
            .patch = 0,
            .pre = "",
            .build = "",
            .allocator = allocator,
        };
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => version.major = try reader.readInt32(),
                2 => version.minor = try reader.readInt32(),
                3 => version.patch = try reader.readInt32(),
                4 => version.pre = try allocator.dupe(u8, try reader.readString()),
                5 => version.build = try allocator.dupe(u8, try reader.readString()),
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return version;
    }
};

// NetworkVersionInfo contains version information about the Hedera network
pub const NetworkVersionInfo = struct {
    hapi_proto_version: SemanticVersion,
    hedera_services_version: SemanticVersion,
    
    pub fn deinit(self: *NetworkVersionInfo) void {
        self.hapi_proto_version.deinit();
        self.hedera_services_version.deinit();
    }
};

// NetworkVersionInfoQuery retrieves version information about the network
pub const NetworkVersionInfoQuery = struct {
    base: Query,
    max_retry: u32,
    
    pub fn init(allocator: std.mem.Allocator) NetworkVersionInfoQuery {
        var query = NetworkVersionInfoQuery{
            .base = Query.init(allocator),
            .max_retry = 3,
        };
        query.base.is_payment_required = false; // Version info is free
        return query;
    }
    
    pub fn deinit(self: *NetworkVersionInfoQuery) void {
        self.base.deinit();
    }
    
    // Execute the query
    pub fn execute(self: *NetworkVersionInfoQuery, client: *Client) !NetworkVersionInfo {
        const response = try self.base.execute(client);
        return try self.parseResponse(response);
    }
    
    // Get cost of the query (always free)
    pub fn getCost(self: *NetworkVersionInfoQuery, client: *Client) !Hbar {
        _ = self;
        _ = client;
        return Hbar.zero();
    }
    
    // Build the query
    pub fn buildQuery(self: *NetworkVersionInfoQuery) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Query message structure
        // header = 1
        var header_writer = ProtoWriter.init(self.base.allocator);
        defer header_writer.deinit();
        
        // responseType = 2
        try header_writer.writeInt32(2, @intFromEnum(self.base.response_type));
        
        const header_bytes = try header_writer.toOwnedSlice();
        defer self.base.allocator.free(header_bytes);
        try writer.writeMessage(1, header_bytes);
        
        // networkGetVersionInfo = 11 (oneof query)
        var version_query_writer = ProtoWriter.init(self.base.allocator);
        defer version_query_writer.deinit();
        
        // Empty message for version info query
        const version_query_bytes = try version_query_writer.toOwnedSlice();
        defer self.base.allocator.free(version_query_bytes);
        try writer.writeMessage(11, version_query_bytes);
        
        return writer.toOwnedSlice();
    }
    
    // Parse the response
    fn parseResponse(self: *NetworkVersionInfoQuery, response: QueryResponse) !NetworkVersionInfo {
        try response.validateStatus();
        
        var reader = ProtoReader.init(response.response_bytes);
        
        var info = NetworkVersionInfo{
            .hapi_proto_version = SemanticVersion{
                .major = 0,
                .minor = 0,
                .patch = 0,
                .pre = "",
                .build = "",
                .allocator = self.base.allocator,
            },
            .hedera_services_version = SemanticVersion{
                .major = 0,
                .minor = 0,
                .patch = 0,
                .pre = "",
                .build = "",
                .allocator = self.base.allocator,
            },
        };
        
        // Parse NetworkGetVersionInfoResponse
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => {
                    // header
                    _ = try reader.readMessage();
                },
                2 => {
                    // hapiProtoVersion
                    const version_bytes = try reader.readMessage();
                    var version_reader = ProtoReader.init(version_bytes);
                    info.hapi_proto_version = try SemanticVersion.decode(&version_reader, self.base.allocator);
                },
                3 => {
                    // hederaServicesVersion
                    const version_bytes = try reader.readMessage();
                    var version_reader = ProtoReader.init(version_bytes);
                    info.hedera_services_version = try SemanticVersion.decode(&version_reader, self.base.allocator);
                },
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return info;
    }
};
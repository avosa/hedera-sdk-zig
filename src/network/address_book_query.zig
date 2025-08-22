const std = @import("std");
const Query = @import("../query/query.zig").Query;
const Client = @import("../network/client.zig").Client;
const FileId = @import("../core/id.zig").FileId;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;
const AccountId = @import("../core/id.zig").AccountId;

// AddressBookQuery retrieves the current address book of the network
pub const AddressBookQuery = struct {
    base: Query,
    file_id: ?FileId = null,
    limit: ?i32 = null,
    
    pub fn init(allocator: std.mem.Allocator) AddressBookQuery {
        return AddressBookQuery{
            .base = Query.init(allocator),
        };
    }
    
    pub fn deinit(self: *AddressBookQuery) void {
        self.base.deinit();
    }
    
    // Set the file ID of the address book to query
    pub fn setFileId(self: *AddressBookQuery, file_id: FileId) *AddressBookQuery {
        self.file_id = file_id;
    }
    
    // Set the maximum number of node addresses to return
    pub fn setLimit(self: *AddressBookQuery, limit: i32) *AddressBookQuery {
        self.limit = limit;
    }
    
    // Execute the query
    pub fn execute(self: *AddressBookQuery, client: *Client) !NodeAddressBook {
        const response = try self.base.execute(client);
        defer self.base.allocator.free(response);
        
        return try self.parseResponse(response);
    }
    
    // Build query body
    pub fn buildQuery(self: *AddressBookQuery) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // nodeGetInfo = 59 (oneof query)
        var query_writer = ProtoWriter.init(self.base.allocator);
        defer query_writer.deinit();
        
        // fileID = 1
        if (self.file_id) |file_id| {
            var file_writer = ProtoWriter.init(self.base.allocator);
            defer file_writer.deinit();
            try file_writer.writeInt64(1, @intCast(file_id.shard));
            try file_writer.writeInt64(2, @intCast(file_id.realm));
            try file_writer.writeInt64(3, @intCast(file_id.num));
            const file_bytes = try file_writer.toOwnedSlice();
            defer self.base.allocator.free(file_bytes);
            try query_writer.writeMessage(1, file_bytes);
            return self;
        }
        
        // limit = 2
        if (self.limit) |limit| {
            try query_writer.writeInt32(2, limit);
        }
        
        const query_bytes = try query_writer.toOwnedSlice();
        defer self.base.allocator.free(query_bytes);
        try writer.writeMessage(59, query_bytes);
        
        return writer.toOwnedSlice();
    }
    
    // Parse response
    fn parseResponse(self: *AddressBookQuery, data: []const u8) !NodeAddressBook {
        var reader = ProtoReader.init(data);
        var result = NodeAddressBook{
            .node_addresses = std.ArrayList(NodeAddress).init(self.base.allocator),
        };
        
        while (try reader.next()) |field| {
            switch (field.number) {
                1 => {
                    // nodeAddress (repeated)
                    const node_address = try parseNodeAddress(field.data, self.base.allocator);
                    try result.node_addresses.append(node_address);
                },
                else => {},
            }
        }
        
        return result;
    }
    
    fn parseNodeAddress(data: []const u8, allocator: std.mem.Allocator) !NodeAddress {
        var reader = ProtoReader.init(data);
        var address = NodeAddress{
            .ip_address = &[_]u8{},
            .port_no = 0,
            .memo = &[_]u8{},
            .rsa_pub_key = &[_]u8{},
            .node_id = 0,
            .node_account_id = null,
            .node_cert_hash = &[_]u8{},
            .service_endpoints = std.ArrayList(ServiceEndpoint).init(allocator),
            .description = &[_]u8{},
            .stake = 0,
        };
        
        while (try reader.next()) |field| {
            switch (field.number) {
                1 => address.ip_address = field.data,
                2 => address.port_no = try reader.readInt32(field.data),
                3 => address.memo = field.data,
                4 => address.rsa_pub_key = field.data,
                5 => address.node_id = try reader.readInt64(field.data),
                6 => {
                    // nodeAccountId
                    address.node_account_id = try parseAccountId(field.data);
                },
                7 => address.node_cert_hash = field.data,
                8 => {
                    // serviceEndpoint (repeated)
                    const endpoint = try parseServiceEndpoint(field.data, allocator);
                    try address.service_endpoints.append(endpoint);
                },
                9 => address.description = field.data,
                10 => address.stake = try reader.readInt64(field.data),
                else => {},
            }
        }
        
        return address;
    }
    
    fn parseAccountId(data: []const u8) !AccountId {
        var reader = ProtoReader.init(data);
        var shard: i64 = 0;
        var realm: i64 = 0;
        var num: i64 = 0;
        
        while (try reader.next()) |field| {
            switch (field.number) {
                1 => shard = try reader.readInt64(field.data),
                2 => realm = try reader.readInt64(field.data),
                3 => num = try reader.readInt64(field.data),
                else => {},
            }
        }
        
        return AccountId{
            .entity = .{
                .shard = shard,
                .realm = realm,
                .num = num,
            },
        };
    }
    
    fn parseServiceEndpoint(data: []const u8, allocator: std.mem.Allocator) !ServiceEndpoint {
        _ = allocator;
        var reader = ProtoReader.init(data);
        var endpoint = ServiceEndpoint{
            .ip_address_v4 = &[_]u8{},
            .port = 0,
            .domain_name = &[_]u8{},
        };
        
        while (try reader.next()) |field| {
            switch (field.number) {
                1 => endpoint.ip_address_v4 = field.data,
                2 => endpoint.port = try reader.readInt32(field.data),
                3 => endpoint.domain_name = field.data,
                else => {},
            }
        }
        
        return endpoint;
    }
};

// Node address book
pub const NodeAddressBook = struct {
    node_addresses: std.ArrayList(NodeAddress),
    
    pub fn deinit(self: *NodeAddressBook) void {
        for (self.node_addresses.items) |*address| {
            address.service_endpoints.deinit();
        }
        self.node_addresses.deinit();
    }
};

// Node address
pub const NodeAddress = struct {
    ip_address: []const u8,
    port_no: i32,
    memo: []const u8,
    rsa_pub_key: []const u8,
    node_id: i64,
    node_account_id: ?AccountId,
    node_cert_hash: []const u8,
    service_endpoints: std.ArrayList(ServiceEndpoint),
    description: []const u8,
    stake: i64,
};

// Service endpoint
pub const ServiceEndpoint = struct {
    ip_address_v4: []const u8,
    port: i32,
    domain_name: []const u8,
};
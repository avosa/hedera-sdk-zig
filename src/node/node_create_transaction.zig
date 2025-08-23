const std = @import("std");
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const AccountId = @import("../core/id.zig").AccountId;
const Key = @import("../crypto/key.zig").Key;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const errors = @import("../core/errors.zig");

// ServiceEndpoint represents a network service endpoint
pub const ServiceEndpoint = struct {
    ip_address: []const u8,
    port: u32,
    domain_name: []const u8,
};

// NodeCreateTransaction creates a new consensus node in the network
pub const NodeCreateTransaction = struct {
    base: Transaction,
    account_id: ?AccountId = null,
    description: ?[]const u8 = null,
    gossip_endpoints: std.ArrayList(ServiceEndpoint),
    service_endpoints: std.ArrayList(ServiceEndpoint),
    gossip_ca_certificate: ?[]const u8 = null,
    grpc_certificate_hash: ?[]const u8 = null,
    admin_key: ?Key = null,
    
    pub fn init(allocator: std.mem.Allocator) NodeCreateTransaction {
        return NodeCreateTransaction{
            .base = Transaction.init(allocator),
            .gossip_endpoints = std.ArrayList(ServiceEndpoint).init(allocator),
            .service_endpoints = std.ArrayList(ServiceEndpoint).init(allocator),
        };
    }
    
    pub fn deinit(self: *NodeCreateTransaction) void {
        self.base.deinit();
        if (self.description) |desc| {
            self.base.allocator.free(desc);
        }
        for (self.gossip_endpoints.items) |endpoint| {
            self.base.allocator.free(endpoint.ip_address);
            self.base.allocator.free(endpoint.domain_name);
        }
        self.gossip_endpoints.deinit();
        for (self.service_endpoints.items) |endpoint| {
            self.base.allocator.free(endpoint.ip_address);
            self.base.allocator.free(endpoint.domain_name);
        }
        self.service_endpoints.deinit();
        if (self.gossip_ca_certificate) |cert| {
            self.base.allocator.free(cert);
        }
        if (self.grpc_certificate_hash) |hash| {
            self.base.allocator.free(hash);
        }
    }
    
    // Set the account ID for the node
    pub fn setAccountId(self: *NodeCreateTransaction, account_id: AccountId) errors.HederaError!*NodeCreateTransaction {
        if (self.base.frozen) return errors.HederaError.InvalidTransaction;
        self.account_id = account_id;
        return self;
    }
    
    // Set the description
    pub fn setDescription(self: *NodeCreateTransaction, description: []const u8) errors.HederaError!*NodeCreateTransaction {
        if (self.base.frozen) return errors.HederaError.InvalidTransaction;
        if (self.description) |old| {
            self.base.allocator.free(old);
        }
        self.description = errors.handleDupeError(self.base.allocator, description) catch return errors.HederaError.OutOfMemory;
        return self;
    }
    
    // Add a gossip endpoint
    pub fn addGossipEndpoint(self: *NodeCreateTransaction, endpoint: ServiceEndpoint) errors.HederaError!void {
        const duped_ip = errors.handleDupeError(self.base.allocator, endpoint.ip_address) catch return errors.HederaError.OutOfMemory;
        const duped_domain = errors.handleDupeError(self.base.allocator, endpoint.domain_name) catch return errors.HederaError.OutOfMemory;
        errors.handleAppendError(&self.gossip_endpoints, ServiceEndpoint{
            .ip_address = duped_ip,
            .port = endpoint.port,
            .domain_name = duped_domain,
        }) catch return errors.HederaError.OutOfMemory;
    }
    
    // Add a service endpoint
    pub fn addServiceEndpoint(self: *NodeCreateTransaction, endpoint: ServiceEndpoint) errors.HederaError!void {
        const duped_ip = errors.handleDupeError(self.base.allocator, endpoint.ip_address) catch return errors.HederaError.OutOfMemory;
        const duped_domain = errors.handleDupeError(self.base.allocator, endpoint.domain_name) catch return errors.HederaError.OutOfMemory;
        errors.handleAppendError(&self.service_endpoints, ServiceEndpoint{
            .ip_address = duped_ip,
            .port = endpoint.port,
            .domain_name = duped_domain,
        }) catch return errors.HederaError.OutOfMemory;
    }
    
    // Set the gossip CA certificate
    pub fn setGossipCaCertificate(self: *NodeCreateTransaction, certificate: []const u8) errors.HederaError!*NodeCreateTransaction {
        if (self.base.frozen) return errors.HederaError.InvalidTransaction;
        if (self.gossip_ca_certificate) |old| {
            self.base.allocator.free(old);
        }
        self.gossip_ca_certificate = errors.handleDupeError(self.base.allocator, certificate) catch return errors.HederaError.OutOfMemory;
        return self;
    }
    
    // Set the gRPC certificate hash
    pub fn setGrpcCertificateHash(self: *NodeCreateTransaction, hash: []const u8) errors.HederaError!*NodeCreateTransaction {
        if (self.base.frozen) return errors.HederaError.InvalidTransaction;
        if (self.grpc_certificate_hash) |old| {
            self.base.allocator.free(old);
        }
        self.grpc_certificate_hash = errors.handleDupeError(self.base.allocator, hash) catch return errors.HederaError.OutOfMemory;
        return self;
    }
    
    // Set the admin key
    pub fn setAdminKey(self: *NodeCreateTransaction, key: Key) errors.HederaError!*NodeCreateTransaction {
        if (self.base.frozen) return errors.HederaError.InvalidTransaction;
        self.admin_key = key;
        return self;
    }
    
    // Execute the transaction
    pub fn execute(self: *NodeCreateTransaction, client: *Client) !TransactionResponse {
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *NodeCreateTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Write common transaction fields
        try self.writeCommonFields(&writer);
        
        // nodeCreate = 61 (oneof data)
        var node_writer = ProtoWriter.init(self.base.allocator);
        defer node_writer.deinit();
        
        // accountId = 1
        if (self.account_id) |account_id| {
            var account_writer = ProtoWriter.init(self.base.allocator);
            defer account_writer.deinit();
            try account_writer.writeInt64(1, @intCast(account_id.shard));
            try account_writer.writeInt64(2, @intCast(account_id.realm));
            try account_writer.writeInt64(3, @intCast(account_id.account));
            const account_bytes = try account_writer.toOwnedSlice();
            defer self.base.allocator.free(account_bytes);
            try node_writer.writeMessage(1, account_bytes);
        }
        
        // description = 2
        if (self.description) |description| {
            try node_writer.writeString(2, description);
        }
        
        // gossipEndpoint = 3 (repeated)
        for (self.gossip_endpoints.items) |endpoint| {
            var endpoint_writer = ProtoWriter.init(self.base.allocator);
            defer endpoint_writer.deinit();
            
            if (endpoint.ip_address.len > 0) {
                try endpoint_writer.writeString(1, endpoint.ip_address);
            }
            try endpoint_writer.writeInt32(2, @intCast(endpoint.port));
            if (endpoint.domain_name.len > 0) {
                try endpoint_writer.writeString(3, endpoint.domain_name);
            }
            
            const endpoint_bytes = try endpoint_writer.toOwnedSlice();
            defer self.base.allocator.free(endpoint_bytes);
            try node_writer.writeMessage(3, endpoint_bytes);
        }
        
        // serviceEndpoint = 4 (repeated)
        for (self.service_endpoints.items) |endpoint| {
            var endpoint_writer = ProtoWriter.init(self.base.allocator);
            defer endpoint_writer.deinit();
            
            if (endpoint.ip_address.len > 0) {
                try endpoint_writer.writeString(1, endpoint.ip_address);
            }
            try endpoint_writer.writeInt32(2, @intCast(endpoint.port));
            if (endpoint.domain_name.len > 0) {
                try endpoint_writer.writeString(3, endpoint.domain_name);
            }
            
            const endpoint_bytes = try endpoint_writer.toOwnedSlice();
            defer self.base.allocator.free(endpoint_bytes);
            try node_writer.writeMessage(4, endpoint_bytes);
        }
        
        // gossipCaCertificate = 5
        if (self.gossip_ca_certificate) |cert| {
            try node_writer.writeBytes(5, cert);
        }
        
        // grpcCertificateHash = 6
        if (self.grpc_certificate_hash) |hash| {
            try node_writer.writeBytes(6, hash);
        }
        
        // adminKey = 7
        if (self.admin_key) |key| {
            const key_bytes = try key.toProtobuf(self.base.allocator);
            defer self.base.allocator.free(key_bytes);
            try node_writer.writeMessage(7, key_bytes);
        }
        
        const node_bytes = try node_writer.toOwnedSlice();
        defer self.base.allocator.free(node_bytes);
        try writer.writeMessage(61, node_bytes);
        
        return writer.toOwnedSlice();
    }
    
    fn writeCommonFields(self: *NodeCreateTransaction, writer: *ProtoWriter) !void {
        // Write standard transaction fields
        try self.base.writeCommonFields(writer);
    }
};
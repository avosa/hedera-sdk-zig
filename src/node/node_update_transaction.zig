const std = @import("std");
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const AccountId = @import("../core/id.zig").AccountId;
const Key = @import("../crypto/key.zig").Key;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const ServiceEndpoint = @import("node_create_transaction.zig").ServiceEndpoint;
const errors = @import("../core/errors.zig");

// NodeUpdateTransaction updates a consensus node in the network
pub const NodeUpdateTransaction = struct {
    base: Transaction,
    node_id: ?u64 = null,
    account_id: ?AccountId = null,
    description: ?[]const u8 = null,
    gossip_endpoints: ?std.ArrayList(ServiceEndpoint) = null,
    service_endpoints: ?std.ArrayList(ServiceEndpoint) = null,
    gossip_ca_certificate: ?[]const u8 = null,
    grpc_certificate_hash: ?[]const u8 = null,
    admin_key: ?Key = null,
    
    pub fn init(allocator: std.mem.Allocator) NodeUpdateTransaction {
        return NodeUpdateTransaction{
            .base = Transaction.init(allocator),
        };
    }
    
    pub fn deinit(self: *NodeUpdateTransaction) void {
        self.base.deinit();
        if (self.description) |desc| {
            self.base.allocator.free(desc);
        }
        if (self.gossip_endpoints) |*endpoints| {
            for (endpoints.items) |endpoint| {
                self.base.allocator.free(endpoint.ip_address);
                self.base.allocator.free(endpoint.domain_name);
            }
            endpoints.deinit();
        }
        if (self.service_endpoints) |*endpoints| {
            for (endpoints.items) |endpoint| {
                self.base.allocator.free(endpoint.ip_address);
                self.base.allocator.free(endpoint.domain_name);
            }
            endpoints.deinit();
        }
        if (self.gossip_ca_certificate) |cert| {
            self.base.allocator.free(cert);
        }
        if (self.grpc_certificate_hash) |hash| {
            self.base.allocator.free(hash);
        }
    }
    
    // Set the node ID to update
    pub fn setNodeId(self: *NodeUpdateTransaction, node_id: u64) !*NodeUpdateTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        self.node_id = node_id;
        return self;
    }
    
    // Set the account ID for the node
    pub fn setAccountId(self: *NodeUpdateTransaction, account_id: AccountId) !*NodeUpdateTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        self.account_id = account_id;
        return self;
    }
    
    // Set the description
    pub fn setDescription(self: *NodeUpdateTransaction, description: []const u8) !*NodeUpdateTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        if (self.description) |old| {
            self.base.allocator.free(old);
        }
        self.description = errors.handleDupeError(self.base.allocator, description) catch return error.InvalidParameter;
        return self;
    }
    
    // Set gossip endpoints (replaces all)
    pub fn setGossipEndpoints(self: *NodeUpdateTransaction, endpoints: []const ServiceEndpoint) !*NodeUpdateTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        
        if (self.gossip_endpoints) |*old| {
            for (old.items) |endpoint| {
                self.base.allocator.free(endpoint.ip_address);
                self.base.allocator.free(endpoint.domain_name);
            }
            old.deinit();
        }
        
        var new_endpoints = std.ArrayList(ServiceEndpoint).init(self.base.allocator);
        for (endpoints) |endpoint| {
            const duped_ip = errors.handleDupeError(self.base.allocator, endpoint.ip_address) catch return error.InvalidParameter;
            const duped_domain = errors.handleDupeError(self.base.allocator, endpoint.domain_name) catch return error.InvalidParameter;
            errors.handleAppendError(&new_endpoints, ServiceEndpoint{
                .ip_address = duped_ip,
                .port = endpoint.port,
                .domain_name = duped_domain,
            }) catch return error.InvalidParameter;
        }
        self.gossip_endpoints = new_endpoints;
        return self;
    }
    
    // Set service endpoints (replaces all)
    pub fn setServiceEndpoints(self: *NodeUpdateTransaction, endpoints: []const ServiceEndpoint) !*NodeUpdateTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        
        if (self.service_endpoints) |*old| {
            for (old.items) |endpoint| {
                self.base.allocator.free(endpoint.ip_address);
                self.base.allocator.free(endpoint.domain_name);
            }
            old.deinit();
        }
        
        var new_endpoints = std.ArrayList(ServiceEndpoint).init(self.base.allocator);
        for (endpoints) |endpoint| {
            const duped_ip = errors.handleDupeError(self.base.allocator, endpoint.ip_address) catch return error.InvalidParameter;
            const duped_domain = errors.handleDupeError(self.base.allocator, endpoint.domain_name) catch return error.InvalidParameter;
            errors.handleAppendError(&new_endpoints, ServiceEndpoint{
                .ip_address = duped_ip,
                .port = endpoint.port,
                .domain_name = duped_domain,
            }) catch return error.InvalidParameter;
        }
        self.service_endpoints = new_endpoints;
        return self;
    }
    
    // Set the gossip CA certificate
    pub fn setGossipCaCertificate(self: *NodeUpdateTransaction, certificate: []const u8) !*NodeUpdateTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        if (self.gossip_ca_certificate) |old| {
            self.base.allocator.free(old);
        }
        self.gossip_ca_certificate = errors.handleDupeError(self.base.allocator, certificate) catch return error.InvalidParameter;
        return self;
    }
    
    // Set the gRPC certificate hash
    pub fn setGrpcCertificateHash(self: *NodeUpdateTransaction, hash: []const u8) !*NodeUpdateTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        if (self.grpc_certificate_hash) |old| {
            self.base.allocator.free(old);
        }
        self.grpc_certificate_hash = errors.handleDupeError(self.base.allocator, hash) catch return error.InvalidParameter;
        return self;
    }
    
    // Set the admin key
    pub fn setAdminKey(self: *NodeUpdateTransaction, key: Key) !*NodeUpdateTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        self.admin_key = key;
        return self;
    }
    
    // Execute the transaction
    pub fn execute(self: *NodeUpdateTransaction, client: *Client) !TransactionResponse {
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *NodeUpdateTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Write common transaction fields
        try self.writeCommonFields(&writer);
        
        // nodeUpdate = 63 (oneof data)
        var node_writer = ProtoWriter.init(self.base.allocator);
        defer node_writer.deinit();
        
        // nodeId = 1
        if (self.node_id) |node_id| {
            try node_writer.writeUint64(1, node_id);
        }
        
        // accountId = 2
        if (self.account_id) |account_id| {
            var account_writer = ProtoWriter.init(self.base.allocator);
            defer account_writer.deinit();
            try account_writer.writeInt64(1, @intCast(account_id.shard));
            try account_writer.writeInt64(2, @intCast(account_id.realm));
            try account_writer.writeInt64(3, @intCast(account_id.account));
            const account_bytes = try account_writer.toOwnedSlice();
            defer self.base.allocator.free(account_bytes);
            try node_writer.writeMessage(2, account_bytes);
        }
        
        // description = 3
        if (self.description) |description| {
            // Wrap in StringValue
            var desc_writer = ProtoWriter.init(self.base.allocator);
            defer desc_writer.deinit();
            try desc_writer.writeString(1, description);
            const desc_bytes = try desc_writer.toOwnedSlice();
            defer self.base.allocator.free(desc_bytes);
            try node_writer.writeMessage(3, desc_bytes);
        }
        
        // gossipEndpoint = 4 (repeated)
        if (self.gossip_endpoints) |endpoints| {
            for (endpoints.items) |endpoint| {
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
        }
        
        // serviceEndpoint = 5 (repeated)
        if (self.service_endpoints) |endpoints| {
            for (endpoints.items) |endpoint| {
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
                try node_writer.writeMessage(5, endpoint_bytes);
            }
        }
        
        // gossipCaCertificate = 6
        if (self.gossip_ca_certificate) |cert| {
            // Wrap in BytesValue
            var cert_writer = ProtoWriter.init(self.base.allocator);
            defer cert_writer.deinit();
            try cert_writer.writeBytes(1, cert);
            const cert_bytes = try cert_writer.toOwnedSlice();
            defer self.base.allocator.free(cert_bytes);
            try node_writer.writeMessage(6, cert_bytes);
        }
        
        // grpcCertificateHash = 7
        if (self.grpc_certificate_hash) |hash| {
            // Wrap in BytesValue
            var hash_writer = ProtoWriter.init(self.base.allocator);
            defer hash_writer.deinit();
            try hash_writer.writeBytes(1, hash);
            const hash_bytes = try hash_writer.toOwnedSlice();
            defer self.base.allocator.free(hash_bytes);
            try node_writer.writeMessage(7, hash_bytes);
        }
        
        // adminKey = 8
        if (self.admin_key) |key| {
            const key_bytes = try key.toProtobuf(self.base.allocator);
            defer self.base.allocator.free(key_bytes);
            try node_writer.writeMessage(8, key_bytes);
        }
        
        const node_bytes = try node_writer.toOwnedSlice();
        defer self.base.allocator.free(node_bytes);
        try writer.writeMessage(63, node_bytes);
        
        return writer.toOwnedSlice();
    }
    
    fn writeCommonFields(self: *NodeUpdateTransaction, writer: *ProtoWriter) !void {
        // Write standard transaction fields
        try self.base.writeCommonFields(writer);
    }
    
    // Freeze the transaction with client
    pub fn freezeWith(self: *NodeUpdateTransaction, client: *Client) !*NodeUpdateTransaction {
        try self.base.freezeWith(client);
        return self;
    }
};



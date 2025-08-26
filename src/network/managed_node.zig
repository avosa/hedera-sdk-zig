const std = @import("std");
const AccountId = @import("../core/id.zig").AccountId;
const LedgerId = @import("../core/ledger_id.zig").LedgerId;
const Duration = @import("../core/duration.zig").Duration;
const Timestamp = @import("../core/timestamp.zig").Timestamp;
const GrpcConnection = @import("grpc_tls.zig").GrpcTlsConnection;
const Node = @import("node.zig").Node;

pub const ServiceEndpoint = struct {
    ip_address_v4: []const u8,
    port: u32,
    
    pub fn init(ip: []const u8, port: u32) ServiceEndpoint {
        return ServiceEndpoint{
            .ip_address_v4 = ip,
            .port = port,
        };
    }
};

// Health status of a managed node
pub const NodeHealth = enum {
    Healthy,
    Unhealthy,
    Unknown,

    pub fn toString(self: NodeHealth) []const u8 {
        return switch (self) {
            .Healthy => "Healthy",
            .Unhealthy => "Unhealthy",
            .Unknown => "Unknown",
        };
    }
};

// Statistics for a managed node
pub const NodeStats = struct {
    requests_attempted: u64,
    requests_succeeded: u64,
    requests_failed: u64,
    total_response_time: Duration,
    last_response_time: ?Duration,
    last_request_time: ?Timestamp,
    consecutive_failures: u32,
    backoff_until: ?Timestamp,

    pub fn init() NodeStats {
        return NodeStats{
            .requests_attempted = 0,
            .requests_succeeded = 0,
            .requests_failed = 0,
            .total_response_time = Duration.ZERO,
            .last_response_time = null,
            .last_request_time = null,
            .consecutive_failures = 0,
            .backoff_until = null,
        };
    }

    pub fn recordRequest(self: *NodeStats) void {
        self.requests_attempted += 1;
        self.last_request_time = Timestamp.now();
    }

    pub fn recordSuccess(self: *NodeStats, response_time: Duration) void {
        self.requests_succeeded += 1;
        self.total_response_time = self.total_response_time.add(response_time);
        self.last_response_time = response_time;
        self.consecutive_failures = 0;
        self.backoff_until = null;
    }

    pub fn recordFailure(self: *NodeStats, backoff_duration: Duration) void {
        self.requests_failed += 1;
        self.consecutive_failures += 1;
        if (self.last_request_time) |last_time| {
            self.backoff_until = last_time.add(backoff_duration);
        }
    }

    pub fn getSuccessRate(self: *const NodeStats) f64 {
        if (self.requests_attempted == 0) return 0.0;
        return @as(f64, @floatFromInt(self.requests_succeeded)) / @as(f64, @floatFromInt(self.requests_attempted));
    }

    pub fn getAverageResponseTime(self: *const NodeStats) Duration {
        if (self.requests_succeeded == 0) return Duration.ZERO;
        return self.total_response_time.divide(@intCast(self.requests_succeeded));
    }

    pub fn isInBackoff(self: *const NodeStats, current_time: Timestamp) bool {
        if (self.backoff_until) |backoff_time| {
            return current_time.compare(backoff_time) < 0;
        }
        return false;
    }

    pub fn getBackoffRemaining(self: *const NodeStats, current_time: Timestamp) ?Duration {
        if (self.backoff_until) |backoff_time| {
            if (current_time.compare(backoff_time) < 0) {
                return backoff_time.subtract(current_time);
            }
        }
        return null;
    }

    pub fn reset(self: *NodeStats) void {
        self.* = NodeStats.init();
    }
};

// Address information for a node
pub const NodeAddress = struct {
    node_id: i64,
    account_id: ?AccountId,
    address: []const u8,
    port: u16,
    tls_port: ?u16,
    rsa_pub_key: []const u8,
    node_account_id: AccountId,
    node_cert_hash: ?[]const u8,
    service_endpoints: std.ArrayList(ServiceEndpoint),
    description: []const u8,
    
    // Track ownership
    owns_address: bool,
    owns_rsa_key: bool,
    owns_description: bool,

    pub fn init(allocator: std.mem.Allocator, address: []const u8, port: u16) !NodeAddress {
        return NodeAddress{
            .node_id = 0,
            .account_id = null,
            .address = try allocator.dupe(u8, address),
            .port = port,
            .tls_port = null,
            .rsa_pub_key = "",
            .node_account_id = AccountId.init(0, 0, 0),
            .node_cert_hash = null,
            .service_endpoints = std.ArrayList(ServiceEndpoint).init(allocator),
            .description = "",
            .owns_address = true,
            .owns_rsa_key = false,
            .owns_description = false,
        };
    }

    pub fn initWithTls(allocator: std.mem.Allocator, address: []const u8, port: u16, tls_port: u16) !NodeAddress {
        return NodeAddress{
            .node_id = 0,
            .account_id = null,
            .address = try allocator.dupe(u8, address),
            .port = port,
            .tls_port = tls_port,
            .rsa_pub_key = "",
            .node_account_id = AccountId.init(0, 0, 0),
            .node_cert_hash = null,
            .service_endpoints = std.ArrayList(ServiceEndpoint).init(allocator),
            .description = "",
            .owns_address = true,
            .owns_rsa_key = false,
            .owns_description = false,
        };
    }

    pub fn deinit(self: *NodeAddress, allocator: std.mem.Allocator) void {
        if (self.owns_address) {
            allocator.free(self.address);
        }
        if (self.owns_rsa_key and self.rsa_pub_key.len > 0) {
            allocator.free(self.rsa_pub_key);
        }
        if (self.owns_description and self.description.len > 0) {
            allocator.free(self.description);
        }
        self.service_endpoints.deinit();
        if (self.node_cert_hash) |hash| {
            allocator.free(hash);
        }
    }

    pub fn getEndpoint(self: *const NodeAddress, use_tls: bool) []const u8 {
        if (use_tls and self.tls_port != null) {
            return self.address;
        }
        return self.address;
    }

    pub fn getPort(self: *const NodeAddress, use_tls: bool) u16 {
        if (use_tls and self.tls_port != null) {
            return self.tls_port.?;
        }
        return self.port;
    }

    pub fn toString(self: *const NodeAddress, allocator: std.mem.Allocator) ![]u8 {
        if (self.tls_port) |tls_port| {
            return std.fmt.allocPrint(allocator, "{}:{} (TLS: {})", .{ self.address, self.port, tls_port });
        } else {
            return std.fmt.allocPrint(allocator, "{}:{}", .{ self.address, self.port });
        }
    }

    pub fn clone(self: *const NodeAddress, allocator: std.mem.Allocator) !NodeAddress {
        return NodeAddress{
            .address = try allocator.dupe(u8, self.address),
            .port = self.port,
            .tls_port = self.tls_port,
        };
    }
};

// Managed node with health monitoring and statistics
pub const ManagedNode = struct {
    account_id: AccountId,
    address: NodeAddress,
    health: NodeHealth,
    stats: NodeStats,
    grpc_client: ?GrpcConnection,
    allocator: std.mem.Allocator,
    min_backoff: Duration,
    max_backoff: Duration,
    current_backoff: Duration,
    enable_tls: bool,
    cert_hash: ?[32]u8,

    pub fn init(allocator: std.mem.Allocator, account_id: AccountId, address: NodeAddress) ManagedNode {
        return ManagedNode{
            .account_id = account_id,
            .address = address,
            .health = .Unknown,
            .stats = NodeStats.init(),
            .grpc_client = null,
            .allocator = allocator,
            .min_backoff = Duration.fromMilliseconds(250),
            .max_backoff = Duration.fromSeconds(8),
            .current_backoff = Duration.fromMilliseconds(250),
            .enable_tls = false,
            .cert_hash = null,
        };
    }

    pub fn deinit(self: *ManagedNode) void {
        self.address.deinit(self.allocator);
        if (self.grpc_client) |*client| {
            client.deinit();
        }
    }

    pub fn setTlsEnabled(self: *ManagedNode, enabled: bool) !*ManagedNode {
        self.enable_tls = enabled;
        return self;
    }

    pub fn setCertificateHash(self: *ManagedNode, cert_hash: [32]u8) !*ManagedNode {
        self.cert_hash = cert_hash;
        return self;
    }

    pub fn setBackoffLimits(self: *ManagedNode, min_backoff: Duration, max_backoff: Duration) !*ManagedNode {
        self.min_backoff = min_backoff;
        self.max_backoff = max_backoff;
        return self;
    }

    pub fn getAccountId(self: *const ManagedNode) AccountId {
        return self.account_id;
    }

    pub fn getAddress(self: *const ManagedNode) *const NodeAddress {
        return &self.address;
    }

    pub fn getHealth(self: *const ManagedNode) NodeHealth {
        return self.health;
    }

    pub fn getStats(self: *const ManagedNode) *const NodeStats {
        return &self.stats;
    }

    pub fn isHealthy(self: *const ManagedNode) bool {
        return self.health == .Healthy;
    }

    pub fn isInBackoff(self: *const ManagedNode) bool {
        return self.stats.isInBackoff(Timestamp.now());
    }

    pub fn getBackoffRemaining(self: *const ManagedNode) ?Duration {
        return self.stats.getBackoffRemaining(Timestamp.now());
    }

    // Connect to the node and establish gRPC client
    pub fn connect(self: *ManagedNode) !void {
        if (self.grpc_client != null) return;

        const endpoint = self.address.getEndpoint(self.enable_tls);
        const port = self.address.getPort(self.enable_tls);

        const address = try std.net.Address.parseIp(endpoint, port);
        const node = Node{
            .account_id = self.account_id,
            .address = address,
            .hostname = endpoint,
        };
        self.grpc_client = try GrpcConnection.init(self.allocator, node);
        if (self.enable_tls) {
            try self.grpc_client.?.connect();
        }
    }

    // Disconnect from the node
    pub fn disconnect(self: *ManagedNode) void {
        if (self.grpc_client) |*client| {
            client.deinit();
            self.grpc_client = null;
        }
    }

    // Perform health check on the node
    pub fn healthCheck(self: *ManagedNode) !NodeHealth {
        const start_time = Timestamp.now();
        
        if (self.isInBackoff()) {
            return self.health;
        }

        self.stats.recordRequest();

        // Connect if not already connected
        self.connect() catch {
            self.recordFailure();
            self.health = .Unhealthy;
            return self.health;
        };

        // Perform comprehensive health check with version query
        const success = self.performHealthCheckRequest() catch false;
        
        const end_time = Timestamp.now();
        const response_time = end_time.subtract(start_time);

        if (success) {
            self.recordSuccess(response_time);
            self.health = .Healthy;
        } else {
            self.recordFailure();
            self.health = .Unhealthy;
        }

        return self.health;
    }

    fn performHealthCheckRequest(self: *ManagedNode) !bool {
        if (self.grpc_client) |*client| {
            const request_data = try self.buildVersionInfoRequest();
            defer self.allocator.free(request_data);
            
            const response = client.sendRequest(request_data) catch return false;
            defer self.allocator.free(response);
            
            return self.parseVersionInfoResponse(response) catch false;
        }
        
        const test_socket = std.net.tcpConnectToAddress(try std.net.Address.parseIp(
            self.address.address, 
            self.address.port
        )) catch return false;
        defer test_socket.close();
        
        return true;
    }
    
    fn buildVersionInfoRequest(self: *ManagedNode) ![]u8 {
        const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
        
        var writer = ProtoWriter.init(self.allocator);
        defer writer.deinit();
        
        var query_writer = ProtoWriter.init(self.allocator);
        defer query_writer.deinit();
        
        const query_bytes = try query_writer.toOwnedSlice();
        defer self.allocator.free(query_bytes);
        try writer.writeMessage(4, query_bytes);
        
        return writer.toOwnedSlice();
    }
    
    fn parseVersionInfoResponse(self: *ManagedNode, response_data: []const u8) !bool {
        _ = self;
        return response_data.len > 0;
    }

    fn recordSuccess(self: *ManagedNode, response_time: Duration) void {
        self.stats.recordSuccess(response_time);
        self.current_backoff = self.min_backoff;
    }

    fn recordFailure(self: *ManagedNode) void {
        self.current_backoff = self.current_backoff.multiply(2);
        if (self.current_backoff.compare(self.max_backoff) > 0) {
            self.current_backoff = self.max_backoff;
        }
        self.stats.recordFailure(self.current_backoff);
    }

    // Reset node statistics and health
    pub fn reset(self: *ManagedNode) void {
        self.stats.reset();
        self.health = .Unknown;
        self.current_backoff = self.min_backoff;
    }

    // Get detailed node information
    pub fn getNodeInfo(self: *const ManagedNode, allocator: std.mem.Allocator) !NodeInfo {
        return NodeInfo{
            .account_id = self.account_id,
            .address = try self.address.clone(allocator),
            .health = self.health,
            .stats = self.stats,
            .is_connected = self.grpc_client != null,
            .tls_enabled = self.enable_tls,
            .cert_hash = self.cert_hash,
        };
    }

    pub fn clone(self: *const ManagedNode, allocator: std.mem.Allocator) !ManagedNode {
        return ManagedNode{
            .account_id = self.account_id,
            .address = try self.address.clone(allocator),
            .health = self.health,
            .stats = self.stats,
            .grpc_client = null,
            .allocator = allocator,
            .min_backoff = self.min_backoff,
            .max_backoff = self.max_backoff,
            .current_backoff = self.current_backoff,
            .enable_tls = self.enable_tls,
            .cert_hash = self.cert_hash,
        };
    }

    pub fn equals(self: *const ManagedNode, other: *const ManagedNode) bool {
        return self.account_id.equals(other.account_id) and
               std.mem.eql(u8, self.address.address, other.address.address) and
               self.address.port == other.address.port;
    }

    pub fn toString(self: *const ManagedNode, allocator: std.mem.Allocator) ![]u8 {
        const address_str = try self.address.toString(allocator);
        defer allocator.free(address_str);

        return std.fmt.allocPrint(allocator, "ManagedNode{{account={}, address={s}, health={s}, success_rate={d:.2}%}}", .{
            self.account_id,
            address_str,
            self.health.toString(),
            self.stats.getSuccessRate() * 100.0,
        });
    }
};

// Complete node information structure
pub const NodeInfo = struct {
    account_id: AccountId,
    address: NodeAddress,
    health: NodeHealth,
    stats: NodeStats,
    is_connected: bool,
    tls_enabled: bool,
    cert_hash: ?[32]u8,

    pub fn deinit(self: *NodeInfo, allocator: std.mem.Allocator) void {
        self.address.deinit(allocator);
    }

    pub fn toString(self: *const NodeInfo, allocator: std.mem.Allocator) ![]u8 {
        const address_str = try self.address.toString(allocator);
        defer allocator.free(address_str);

        return std.fmt.allocPrint(allocator, "NodeInfo{{account={}, address={s}, health={s}, connected={}, tls={}, success_rate={d:.2}%}}", .{
            self.account_id,
            address_str,
            self.health.toString(),
            self.is_connected,
            self.tls_enabled,
            self.stats.getSuccessRate() * 100.0,
        });
    }
};
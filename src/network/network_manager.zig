const std = @import("std");
const Client = @import("client.zig").Client;
const Node = @import("node.zig").Node;
const Network = @import("network.zig").Network;
const AccountId = @import("../core/id.zig").AccountId;
const MirrorNodeClient = @import("../mirror/mirror_node_client.zig").MirrorNodeClient;
const AddressBookQuery = @import("address_book_query.zig").AddressBookQuery;
const NetworkGetVersionInfoQuery = @import("network_status_query.zig").NetworkGetVersionInfoQuery;
const NetworkGetExecutionTimeQuery = @import("network_status_query.zig").NetworkGetExecutionTimeQuery;

// NetworkManager provides comprehensive network management capabilities
pub const NetworkManager = struct {
    allocator: std.mem.Allocator,
    network: ?*Network = null,
    mirror_client: ?*MirrorNodeClient = null,
    health_check_interval_ms: u64 = 30000, // 30 seconds
    max_retry_attempts: u32 = 3,
    connection_timeout_ms: u64 = 5000, // 5 seconds
    request_timeout_ms: u64 = 30000, // 30 seconds
    
    // Node health tracking
    node_health: std.HashMap(AccountId, NodeHealth, AccountIdContext, std.hash_map.default_max_load_percentage),
    last_health_check: i64 = 0,
    
    pub fn init(allocator: std.mem.Allocator) NetworkManager {
        return NetworkManager{
            .allocator = allocator,
            .node_health = std.HashMap(AccountId, NodeHealth, AccountIdContext, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }
    
    pub fn deinit(self: *NetworkManager) void {
        self.node_health.deinit();
        if (self.mirror_client) |client| {
            client.deinit();
        }
    }
    
    // Set the network to manage
    pub fn setNetwork(self: *NetworkManager, network: *Network) *NetworkManager {
        self.network = network;
        return self;
    }
    
    // Set mirror node client
    pub fn setMirrorClient(self: *NetworkManager, mirror_client: *MirrorNodeClient) *NetworkManager {
        self.mirror_client = mirror_client;
        return self;
    }
    
    // Configure health check parameters
    pub fn setHealthCheckConfig(
        self: *NetworkManager,
        interval_ms: u64,
        connection_timeout_ms: u64,
        request_timeout_ms: u64,
    ) *NetworkManager {
        self.health_check_interval_ms = interval_ms;
        self.connection_timeout_ms = connection_timeout_ms;
        self.request_timeout_ms = request_timeout_ms;
        return self;
    }
    
    // Discover network nodes from address book
    pub fn discoverNodes(self: *NetworkManager, client: *Client) !void {
        var address_book_query = AddressBookQuery.init(self.allocator);
        defer address_book_query.deinit();
        
        const address_book = try address_book_query.execute(client);
        defer address_book.deinit();
        
        // Update network with discovered nodes
        if (self.network) |network| {
            network.clearNodes();
            
            for (address_book.node_addresses.items) |node_address| {
                if (node_address.node_account_id) |account_id| {
                    // Use first service endpoint if available
                    var endpoint = "127.0.0.1:50211"; // Default
                    if (node_address.service_endpoints.items.len > 0) {
                        const service_endpoint = node_address.service_endpoints.items[0];
                        endpoint = try std.fmt.allocPrint(
                            self.allocator,
                            "{s}:{d}",
                            .{ service_endpoint.ip_address_v4, service_endpoint.port }
                        );
                        defer self.allocator.free(endpoint);
                    }
                    
                    const node = Node.init(account_id, endpoint);
                    try network.addNode(node);
                    
                    // Initialize health tracking
                    try self.node_health.put(account_id, NodeHealth{
                        .account_id = account_id,
                        .is_healthy = true,
                        .last_check_time = 0,
                        .response_time_ms = 0,
                        .error_count = 0,
                        .consecutive_failures = 0,
                    });
                }
            }
        }
    }
    
    // Perform health checks on all nodes
    pub fn performHealthChecks(self: *NetworkManager, client: *Client) !HealthCheckResults {
        const current_time = std.time.timestamp();
        
        // Skip if not enough time has passed since last check
        if (current_time - self.last_health_check < @divTrunc(@as(i64, @intCast(self.health_check_interval_ms)), 1000)) {
            return self.getLastHealthCheckResults();
        }
        
        var results = HealthCheckResults{
            .total_nodes = 0,
            .healthy_nodes = 0,
            .unhealthy_nodes = 0,
            .nodes_checked = 0,
            .average_response_time_ms = 0,
            .details = std.ArrayList(NodeHealthDetail).init(self.allocator),
        };
        
        if (self.network == null) return results;
        
        var total_response_time: u64 = 0;
        var healthy_count: u32 = 0;
        
        var iterator = self.node_health.iterator();
        while (iterator.next()) |entry| {
            const account_id = entry.key_ptr.*;
            const health = entry.value_ptr;
            
            results.total_nodes += 1;
            
            // Perform health check
            const check_result = try self.checkNodeHealth(client, account_id);
            
            // Update health status
            health.last_check_time = current_time;
            health.response_time_ms = check_result.response_time_ms;
            
            if (check_result.is_healthy) {
                health.is_healthy = true;
                health.consecutive_failures = 0;
                healthy_count += 1;
                total_response_time += check_result.response_time_ms;
            } else {
                health.is_healthy = false;
                health.error_count += 1;
                health.consecutive_failures += 1;
            }
            
            // Add to results
            try results.details.append(NodeHealthDetail{
                .account_id = account_id,
                .is_healthy = health.is_healthy,
                .response_time_ms = health.response_time_ms,
                .error_count = health.error_count,
                .consecutive_failures = health.consecutive_failures,
                .last_error = check_result.last_error,
            });
            
            results.nodes_checked += 1;
        }
        
        results.healthy_nodes = healthy_count;
        results.unhealthy_nodes = results.total_nodes - healthy_count;
        
        if (healthy_count > 0) {
            results.average_response_time_ms = total_response_time / healthy_count;
        }
        
        self.last_health_check = current_time;
        return results;
    }
    
    // Check health of a single node
    fn checkNodeHealth(self: *NetworkManager, client: *Client, node_account_id: AccountId) !NodeCheckResult {
        const start_time = std.time.milliTimestamp();
        
        // Try a simple version info query as health check
        var version_query = NetworkGetVersionInfoQuery.init(self.allocator);
        defer version_query.deinit();
        
        // Create a client instance for the specific node
        const node_client = try self.createNodeSpecificClient(client, node_account_id);
        defer node_client.deinit();
        
        const version_info = version_query.execute(&node_client) catch |err| {
            return NodeCheckResult{
                .is_healthy = false,
                .response_time_ms = @intCast(std.time.milliTimestamp() - start_time),
                .last_error = err,
            };
        };
        defer version_info.deinit(self.allocator);
        
        const response_time = std.time.milliTimestamp() - start_time;
        
        return NodeCheckResult{
            .is_healthy = true,
            .response_time_ms = @intCast(response_time),
            .last_error = null,
        };
    }
    
    // Create client configured for specific node
    fn createNodeSpecificClient(self: *NetworkManager, base_client: *Client, node_account_id: AccountId) !Client {
        var node_client = try base_client.clone(self.allocator);
        
        if (self.network) |network| {
            const nodes = network.getNodes();
            for (nodes) |node| {
                if (node.getAccountId().equals(node_account_id)) {
                    var single_node_network = Network.init(self.allocator);
                    try single_node_network.addNode(node);
                    node_client.setNetwork(single_node_network);
                    break;
                }
            }
        }
        
        node_client.setRequestTimeout(self.request_timeout_ms)
                   .setMaxRetries(1);
        
        return node_client;
    }
    
    // Get nodes by health status
    pub fn getHealthyNodes(self: *NetworkManager) ![]AccountId {
        var healthy_nodes = std.ArrayList(AccountId).init(self.allocator);
        errdefer healthy_nodes.deinit();
        
        var iterator = self.node_health.iterator();
        while (iterator.next()) |entry| {
            const account_id = entry.key_ptr.*;
            const health = entry.value_ptr;
            
            if (health.is_healthy) {
                try healthy_nodes.append(account_id);
            }
        }
        
        return healthy_nodes.toOwnedSlice();
    }
    
    // Get unhealthy nodes
    pub fn getUnhealthyNodes(self: *NetworkManager) ![]AccountId {
        var unhealthy_nodes = std.ArrayList(AccountId).init(self.allocator);
        errdefer unhealthy_nodes.deinit();
        
        var iterator = self.node_health.iterator();
        while (iterator.next()) |entry| {
            const account_id = entry.key_ptr.*;
            const health = entry.value_ptr;
            
            if (!health.is_healthy) {
                try unhealthy_nodes.append(account_id);
            }
        }
        
        return unhealthy_nodes.toOwnedSlice();
    }
    
    // Get network statistics
    pub fn getNetworkStats(self: *NetworkManager, client: *Client) !NetworkStats {
        // Get execution times
        var exec_query = NetworkGetExecutionTimeQuery.init(self.allocator);
        defer exec_query.deinit();
        
        const execution_times = try exec_query.execute(client);
        defer execution_times.deinit();
        
        // Calculate average execution time
        var total_time: i64 = 0;
        var count: usize = 0;
        
        for (execution_times.execution_times.items) |exec_time| {
            total_time += exec_time.execution_time_ms;
            count += 1;
        }
        
        const avg_execution_time = if (count > 0) @divTrunc(total_time, @as(i64, @intCast(count))) else 0;
        
        // Get health check results
        const health_results = try self.performHealthChecks(client);
        defer health_results.deinit();
        
        return NetworkStats{
            .total_nodes = health_results.total_nodes,
            .healthy_nodes = health_results.healthy_nodes,
            .unhealthy_nodes = health_results.unhealthy_nodes,
            .average_response_time_ms = health_results.average_response_time_ms,
            .average_execution_time_ms = avg_execution_time,
            .network_utilization_percent = try self.calculateNetworkUtilization(),
        };
    }
    
    // Calculate network utilization based on node health and response times
    fn calculateNetworkUtilization(self: *NetworkManager) !f64 {
        if (self.node_health.count() == 0) return 0.0;
        
        var total_utilization: f64 = 0.0;
        var healthy_nodes: u32 = 0;
        
        var iterator = self.node_health.iterator();
        while (iterator.next()) |entry| {
            const health = entry.value_ptr;
            
            if (health.is_healthy) {
                healthy_nodes += 1;
                
                const response_factor = @min(1.0, @as(f64, @floatFromInt(health.response_time_ms)) / 1000.0);
                const failure_factor = 1.0 - (@as(f64, @floatFromInt(health.consecutive_failures)) * 0.1);
                const node_utilization = (1.0 - response_factor) * failure_factor * 100.0;
                
                total_utilization += @max(0.0, @min(100.0, node_utilization));
            }
        }
        
        if (healthy_nodes == 0) return 0.0;
        
        const avg_utilization = total_utilization / @as(f64, @floatFromInt(healthy_nodes));
        const health_factor = @as(f64, @floatFromInt(healthy_nodes)) / @as(f64, @floatFromInt(self.node_health.count()));
        
        return avg_utilization * health_factor;
    }
    
    // Get last health check results without performing new checks
    fn getLastHealthCheckResults(self: *NetworkManager) HealthCheckResults {
        var results = HealthCheckResults{
            .total_nodes = 0,
            .healthy_nodes = 0,
            .unhealthy_nodes = 0,
            .nodes_checked = 0,
            .average_response_time_ms = 0,
            .details = std.ArrayList(NodeHealthDetail).init(self.allocator),
        };
        
        var total_response_time: u64 = 0;
        var healthy_count: u32 = 0;
        
        var iterator = self.node_health.iterator();
        while (iterator.next()) |entry| {
            const account_id = entry.key_ptr.*;
            const health = entry.value_ptr;
            
            results.total_nodes += 1;
            results.nodes_checked += 1;
            
            if (health.is_healthy) {
                healthy_count += 1;
                total_response_time += health.response_time_ms;
            }
            
            results.details.append(NodeHealthDetail{
                .account_id = account_id,
                .is_healthy = health.is_healthy,
                .response_time_ms = health.response_time_ms,
                .error_count = health.error_count,
                .consecutive_failures = health.consecutive_failures,
                .last_error = null,
            }) catch {};
        }
        
        results.healthy_nodes = healthy_count;
        results.unhealthy_nodes = results.total_nodes - healthy_count;
        
        if (healthy_count > 0) {
            results.average_response_time_ms = total_response_time / healthy_count;
        }
        
        return results;
    }
};

// Node health information
const NodeHealth = struct {
    account_id: AccountId,
    is_healthy: bool,
    last_check_time: i64,
    response_time_ms: u64,
    error_count: u32,
    consecutive_failures: u32,
};

// Single node health check result
const NodeCheckResult = struct {
    is_healthy: bool,
    response_time_ms: u64,
    last_error: ?anyerror,
};

// Health check results for all nodes
pub const HealthCheckResults = struct {
    total_nodes: u32,
    healthy_nodes: u32,
    unhealthy_nodes: u32,
    nodes_checked: u32,
    average_response_time_ms: u64,
    details: std.ArrayList(NodeHealthDetail),
    
    pub fn deinit(self: *HealthCheckResults) void {
        self.details.deinit();
    }
};

// Detailed health information for a single node
pub const NodeHealthDetail = struct {
    account_id: AccountId,
    is_healthy: bool,
    response_time_ms: u64,
    error_count: u32,
    consecutive_failures: u32,
    last_error: ?anyerror,
};

// Network statistics
pub const NetworkStats = struct {
    total_nodes: u32,
    healthy_nodes: u32,
    unhealthy_nodes: u32,
    average_response_time_ms: u64,
    average_execution_time_ms: i64,
    network_utilization_percent: f64,
};

// Context for AccountId hash map
const AccountIdContext = struct {
    pub fn hash(self: @This(), account_id: AccountId) u64 {
        _ = self;
        return std.hash.Wyhash.hash(0, std.mem.asBytes(&account_id));
    }
    
    pub fn eql(self: @This(), a: AccountId, b: AccountId) bool {
        _ = self;
        return a.entity.shard == b.entity.shard and
               a.entity.realm == b.entity.realm and
               a.entity.num == b.entity.num;
    }
};
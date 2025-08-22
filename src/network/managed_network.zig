const std = @import("std");
const AccountId = @import("../core/id.zig").AccountId;
const LedgerId = @import("../core/ledger_id.zig").LedgerId;
const Duration = @import("../core/duration.zig").Duration;
const Timestamp = @import("../core/timestamp.zig").Timestamp;
const ManagedNode = @import("managed_node.zig").ManagedNode;
const NodeAddress = @import("managed_node.zig").NodeAddress;
const NodeHealth = @import("managed_node.zig").NodeHealth;
const NodeStats = @import("managed_node.zig").NodeStats;
const NodeInfo = @import("managed_node.zig").NodeInfo;

// Configuration for managed network behavior
pub const NetworkConfig = struct {
    max_nodes_per_transaction: u32,
    max_node_attempts: u32,
    min_node_readmit_period: Duration,
    max_node_readmit_period: Duration,
    node_min_backoff: Duration,
    node_max_backoff: Duration,
    health_check_period: Duration,
    enable_load_balancing: bool,
    enable_automatic_failover: bool,
    transport_security: bool,

    pub fn init() NetworkConfig {
        return NetworkConfig{
            .max_nodes_per_transaction = 3,
            .max_node_attempts = 10,
            .min_node_readmit_period = Duration.fromSeconds(8),
            .max_node_readmit_period = Duration.fromMinutes(5),
            .node_min_backoff = Duration.fromMilliseconds(250),
            .node_max_backoff = Duration.fromSeconds(8),
            .health_check_period = Duration.fromSeconds(30),
            .enable_load_balancing = true,
            .enable_automatic_failover = true,
            .transport_security = true,
        };
    }

    pub fn mainnet() NetworkConfig {
        var config = NetworkConfig.init();
        config.transport_security = true;
        return config;
    }

    pub fn testnet() NetworkConfig {
        var config = NetworkConfig.init();
        config.transport_security = true;
        return config;
    }

    pub fn localNode() NetworkConfig {
        var config = NetworkConfig.init();
        config.transport_security = false;
        config.max_nodes_per_transaction = 1;
        return config;
    }
};

// Load balancing strategy for node selection
pub const LoadBalancingStrategy = enum {
    RoundRobin,
    Random,
    LeastConnections,
    WeightedRandom,
    FastestResponse,

    pub fn toString(self: LoadBalancingStrategy) []const u8 {
        return switch (self) {
            .RoundRobin => "RoundRobin",
            .Random => "Random",
            .LeastConnections => "LeastConnections",
            .WeightedRandom => "WeightedRandom",
            .FastestResponse => "FastestResponse",
        };
    }
};

// Network-wide statistics and health information
pub const NetworkStats = struct {
    total_nodes: u32,
    healthy_nodes: u32,
    unhealthy_nodes: u32,
    unknown_nodes: u32,
    total_requests: u64,
    successful_requests: u64,
    failed_requests: u64,
    average_response_time: Duration,
    fastest_node_response: Duration,
    slowest_node_response: Duration,
    last_health_check: ?Timestamp,

    pub fn init() NetworkStats {
        return NetworkStats{
            .total_nodes = 0,
            .healthy_nodes = 0,
            .unhealthy_nodes = 0,
            .unknown_nodes = 0,
            .total_requests = 0,
            .successful_requests = 0,
            .failed_requests = 0,
            .average_response_time = Duration.ZERO,
            .fastest_node_response = Duration.MAX,
            .slowest_node_response = Duration.ZERO,
            .last_health_check = null,
        };
    }

    pub fn getSuccessRate(self: *const NetworkStats) f64 {
        if (self.total_requests == 0) return 0.0;
        return @as(f64, @floatFromInt(self.successful_requests)) / @as(f64, @floatFromInt(self.total_requests));
    }

    pub fn getHealthyNodePercentage(self: *const NetworkStats) f64 {
        if (self.total_nodes == 0) return 0.0;
        return @as(f64, @floatFromInt(self.healthy_nodes)) / @as(f64, @floatFromInt(self.total_nodes)) * 100.0;
    }

    pub fn toString(self: *const NetworkStats, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "NetworkStats{{total_nodes={d}, healthy={d} ({d:.1}%), success_rate={d:.2}%, avg_response={s}}}", .{
            self.total_nodes,
            self.healthy_nodes,
            self.getHealthyNodePercentage(),
            self.getSuccessRate() * 100.0,
            self.average_response_time.toString(),
        });
    }
};

// Managed network with automatic health monitoring and load balancing
pub const ManagedNetwork = struct {
    ledger_id: LedgerId,
    nodes: std.HashMap(AccountId, ManagedNode, AccountIdContext, std.hash_map.default_max_load_percentage),
    healthy_nodes: std.ArrayList(AccountId),
    config: NetworkConfig,
    stats: NetworkStats,
    load_balancing_strategy: LoadBalancingStrategy,
    round_robin_index: u32,
    allocator: std.mem.Allocator,
    health_check_thread: ?std.Thread,
    shutdown_requested: bool,
    mutex: std.Thread.Mutex,

    const AccountIdContext = struct {
        pub fn hash(self: @This(), account_id: AccountId) u64 {
            _ = self;
            var hasher = std.hash.Wyhash.init(0);
            hasher.update(std.mem.asBytes(&account_id.entity.shard));
            hasher.update(std.mem.asBytes(&account_id.entity.realm));
            hasher.update(std.mem.asBytes(&account_id.entity.num));
            return hasher.final();
        }

        pub fn eql(self: @This(), a: AccountId, b: AccountId) bool {
            _ = self;
            return a.entity.shard == b.entity.shard and
                   a.entity.realm == b.entity.realm and
                   a.entity.num == b.entity.num;
        }
    };

    pub fn init(allocator: std.mem.Allocator, ledger_id: LedgerId) ManagedNetwork {
        return ManagedNetwork{
            .ledger_id = ledger_id,
            .nodes = std.HashMap(AccountId, ManagedNode, AccountIdContext, std.hash_map.default_max_load_percentage).init(allocator),
            .healthy_nodes = std.ArrayList(AccountId).init(allocator),
            .config = NetworkConfig.init(),
            .stats = NetworkStats.init(),
            .load_balancing_strategy = .RoundRobin,
            .round_robin_index = 0,
            .allocator = allocator,
            .health_check_thread = null,
            .shutdown_requested = false,
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn deinit(self: *ManagedNetwork) void {
        self.shutdown();
        
        var iter = self.nodes.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.nodes.deinit();
        self.healthy_nodes.deinit();
    }

    pub fn setConfig(self: *ManagedNetwork, config: NetworkConfig) *ManagedNetwork {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        self.config = config;
        return self;
    }

    pub fn setLoadBalancingStrategy(self: *ManagedNetwork, strategy: LoadBalancingStrategy) *ManagedNetwork {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        self.load_balancing_strategy = strategy;
        return self;
    }

    // Add a node to the managed network
    pub fn addNode(self: *ManagedNetwork, account_id: AccountId, address: NodeAddress) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var node = ManagedNode.init(self.allocator, account_id, address);
        node.setTlsEnabled(self.config.transport_security)
            .setBackoffLimits(self.config.node_min_backoff, self.config.node_max_backoff);

        try self.nodes.put(account_id, node);
        self.stats.total_nodes += 1;
        self.stats.unknown_nodes += 1;
    }

    // Remove a node from the managed network
    pub fn removeNode(self: *ManagedNetwork, account_id: AccountId) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.nodes.fetchRemove(account_id)) |kv| {
            var node = kv.value;
            node.deinit();
            
            self.stats.total_nodes -= 1;
            switch (node.getHealth()) {
                .Healthy => self.stats.healthy_nodes -= 1,
                .Unhealthy => self.stats.unhealthy_nodes -= 1,
                .Unknown => self.stats.unknown_nodes -= 1,
            }

            self.removeFromHealthyList(account_id);
            return true;
        }
        return false;
    }

    // Get a node for transaction execution
    pub fn getNodeForTransaction(self: *ManagedNetwork) ?AccountId {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.healthy_nodes.items.len == 0) {
            return null;
        }

        return switch (self.load_balancing_strategy) {
            .RoundRobin => self.getNodeRoundRobin(),
            .Random => self.getNodeRandom(),
            .LeastConnections => self.getNodeLeastConnections(),
            .WeightedRandom => self.getNodeWeightedRandom(),
            .FastestResponse => self.getNodeFastestResponse(),
        };
    }

    // Get multiple nodes for transaction execution
    pub fn getNodesForTransaction(self: *ManagedNetwork) ![]AccountId {
        self.mutex.lock();
        defer self.mutex.unlock();

        const count = @min(self.config.max_nodes_per_transaction, @as(u32, @intCast(self.healthy_nodes.items.len)));
        if (count == 0) {
            return self.allocator.alloc(AccountId, 0);
        }

        var result = try self.allocator.alloc(AccountId, count);
        for (0..count) |i| {
            if (self.getNodeForTransaction()) |node_id| {
                result[i] = node_id;
            } else {
                break;
            }
        }

        return result;
    }

    fn getNodeRoundRobin(self: *ManagedNetwork) AccountId {
        const index = self.round_robin_index % @as(u32, @intCast(self.healthy_nodes.items.len));
        self.round_robin_index +%= 1;
        return self.healthy_nodes.items[index];
    }

    fn getNodeRandom(self: *ManagedNetwork) AccountId {
        const index = std.crypto.random.intRangeLessThan(usize, 0, self.healthy_nodes.items.len);
        return self.healthy_nodes.items[index];
    }

    fn getNodeLeastConnections(self: *ManagedNetwork) AccountId {
        var best_node = self.healthy_nodes.items[0];
        var min_requests: u64 = std.math.maxInt(u64);

        for (self.healthy_nodes.items) |node_id| {
            if (self.nodes.get(node_id)) |node| {
                if (node.getStats().requests_attempted < min_requests) {
                    min_requests = node.getStats().requests_attempted;
                    best_node = node_id;
                }
            }
        }

        return best_node;
    }

    fn getNodeWeightedRandom(self: *ManagedNetwork) AccountId {
        var total_weight: f64 = 0.0;
        var weights = self.allocator.alloc(f64, self.healthy_nodes.items.len) catch return self.getNodeRandom();
        defer self.allocator.free(weights);

        for (self.healthy_nodes.items, 0..) |node_id, i| {
            if (self.nodes.get(node_id)) |node| {
                const success_rate = node.getStats().getSuccessRate();
                weights[i] = @max(0.1, success_rate);
                total_weight += weights[i];
            } else {
                weights[i] = 0.1;
                total_weight += 0.1;
            }
        }

        const random_value = std.crypto.random.float(f64) * total_weight;
        var current_weight: f64 = 0.0;

        for (weights, 0..) |weight, i| {
            current_weight += weight;
            if (random_value <= current_weight) {
                return self.healthy_nodes.items[i];
            }
        }

        return self.healthy_nodes.items[self.healthy_nodes.items.len - 1];
    }

    fn getNodeFastestResponse(self: *ManagedNetwork) AccountId {
        var best_node = self.healthy_nodes.items[0];
        var fastest_response = Duration.MAX;

        for (self.healthy_nodes.items) |node_id| {
            if (self.nodes.get(node_id)) |node| {
                const avg_response = node.getStats().getAverageResponseTime();
                if (avg_response.compare(fastest_response) < 0) {
                    fastest_response = avg_response;
                    best_node = node_id;
                }
            }
        }

        return best_node;
    }

    // Start automatic health checking
    pub fn startHealthChecking(self: *ManagedNetwork) !void {
        if (self.health_check_thread != null) return;

        self.shutdown_requested = false;
        self.health_check_thread = try std.Thread.spawn(.{}, healthCheckLoop, .{self});
    }

    // Stop automatic health checking
    pub fn stopHealthChecking(self: *ManagedNetwork) void {
        if (self.health_check_thread) |thread| {
            self.shutdown_requested = true;
            thread.join();
            self.health_check_thread = null;
        }
    }

    fn healthCheckLoop(self: *ManagedNetwork) void {
        while (!self.shutdown_requested) {
            self.performHealthChecks();
            std.time.sleep(@intCast(self.config.health_check_period.toNanoseconds()));
        }
    }

    // Perform health checks on all nodes
    pub fn performHealthChecks(self: *ManagedNetwork) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var iter = self.nodes.iterator();
        while (iter.next()) |entry| {
            const health = entry.value_ptr.healthCheck() catch .Unhealthy;
            self.updateNodeHealth(entry.key_ptr.*, health);
        }

        self.updateNetworkStats();
        self.stats.last_health_check = Timestamp.now();
    }

    fn updateNodeHealth(self: *ManagedNetwork, account_id: AccountId, health: NodeHealth) void {
        if (self.nodes.getPtr(account_id)) |node| {
            const old_health = node.getHealth();
            
            if (old_health != health) {
                switch (old_health) {
                    .Healthy => self.stats.healthy_nodes -= 1,
                    .Unhealthy => self.stats.unhealthy_nodes -= 1,
                    .Unknown => self.stats.unknown_nodes -= 1,
                }

                switch (health) {
                    .Healthy => {
                        self.stats.healthy_nodes += 1;
                        self.addToHealthyList(account_id);
                    },
                    .Unhealthy => {
                        self.stats.unhealthy_nodes += 1;
                        self.removeFromHealthyList(account_id);
                    },
                    .Unknown => {
                        self.stats.unknown_nodes += 1;
                        self.removeFromHealthyList(account_id);
                    },
                }
            }
        }
    }

    fn addToHealthyList(self: *ManagedNetwork, account_id: AccountId) void {
        for (self.healthy_nodes.items) |existing_id| {
            if (existing_id.equals(account_id)) return;
        }
        self.healthy_nodes.append(account_id) catch {};
    }

    fn removeFromHealthyList(self: *ManagedNetwork, account_id: AccountId) void {
        for (self.healthy_nodes.items, 0..) |existing_id, i| {
            if (existing_id.equals(account_id)) {
                _ = self.healthy_nodes.orderedRemove(i);
                return;
            }
        }
    }

    fn updateNetworkStats(self: *ManagedNetwork) void {
        var total_requests: u64 = 0;
        var successful_requests: u64 = 0;
        var total_response_time = Duration.ZERO;
        var successful_responses: u64 = 0;
        var fastest_response = Duration.MAX;
        var slowest_response = Duration.ZERO;

        var iter = self.nodes.iterator();
        while (iter.next()) |entry| {
            const stats = entry.value_ptr.getStats();
            total_requests += stats.requests_attempted;
            successful_requests += stats.requests_succeeded;

            if (stats.requests_succeeded > 0) {
                const avg_response = stats.getAverageResponseTime();
                total_response_time = total_response_time.add(avg_response.multiply(@intCast(stats.requests_succeeded)));
                successful_responses += stats.requests_succeeded;

                if (avg_response.compare(fastest_response) < 0) {
                    fastest_response = avg_response;
                }
                if (avg_response.compare(slowest_response) > 0) {
                    slowest_response = avg_response;
                }
            }
        }

        self.stats.total_requests = total_requests;
        self.stats.successful_requests = successful_requests;
        self.stats.failed_requests = total_requests - successful_requests;

        if (successful_responses > 0) {
            self.stats.average_response_time = total_response_time.divide(@intCast(successful_responses));
            self.stats.fastest_node_response = fastest_response;
            self.stats.slowest_node_response = slowest_response;
        }
    }

    // Get network statistics
    pub fn getStats(self: *const ManagedNetwork) NetworkStats {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.stats;
    }

    // Get all node information
    pub fn getAllNodes(self: *ManagedNetwork, allocator: std.mem.Allocator) ![]NodeInfo {
        self.mutex.lock();
        defer self.mutex.unlock();

        var result = std.ArrayList(NodeInfo).init(allocator);
        defer result.deinit();

        var iter = self.nodes.iterator();
        while (iter.next()) |entry| {
            const node_info = try entry.value_ptr.getNodeInfo(allocator);
            try result.append(node_info);
        }

        return result.toOwnedSlice();
    }

    // Get healthy nodes
    pub fn getHealthyNodes(self: *const ManagedNetwork, allocator: std.mem.Allocator) ![]AccountId {
        self.mutex.lock();
        defer self.mutex.unlock();
        return allocator.dupe(AccountId, self.healthy_nodes.items);
    }

    // Reset all node statistics
    pub fn resetStats(self: *ManagedNetwork) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var iter = self.nodes.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.reset();
        }

        self.stats = NetworkStats.init();
        self.stats.total_nodes = @intCast(self.nodes.count());
        self.stats.unknown_nodes = self.stats.total_nodes;
    }

    pub fn shutdown(self: *ManagedNetwork) void {
        self.stopHealthChecking();
    }

    pub fn toString(self: *const ManagedNetwork, allocator: std.mem.Allocator) ![]u8 {
        const stats_str = try self.stats.toString(allocator);
        defer allocator.free(stats_str);

        return std.fmt.allocPrint(allocator, "ManagedNetwork{{ledger_id={}, strategy={s}, {s}}}", .{
            self.ledger_id,
            self.load_balancing_strategy.toString(),
            stats_str,
        });
    }
};
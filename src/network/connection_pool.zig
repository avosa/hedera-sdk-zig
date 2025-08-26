// Connection pool optimizations
// Provides efficient connection management and pooling

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const Thread = std.Thread;
const Mutex = Thread.Mutex;
const Condition = Thread.Condition;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const AtomicBool = std.atomic.Atomic(bool);
const AtomicUsize = std.atomic.Atomic(usize);

// Connection state
pub const ConnectionState = enum {
    idle,
    active,
    connecting,
    disconnected,
    err,
    
    pub fn toString(self: ConnectionState) []const u8 {
        return switch (self) {
            .idle => "IDLE",
            .active => "ACTIVE",
            .connecting => "CONNECTING",
            .disconnected => "DISCONNECTED",
            .err => "ERROR",
        };
    }
};

// Connection statistics
pub const ConnectionStats = struct {
    created_at: i64,
    last_used: i64,
    usage_count: u64,
    bytes_sent: u64,
    bytes_received: u64,
    error_count: u64,
    
    pub fn init() ConnectionStats {
        const now = std.time.milliTimestamp();
        return ConnectionStats{
            .created_at = now,
            .last_used = now,
            .usage_count = 0,
            .bytes_sent = 0,
            .bytes_received = 0,
            .error_count = 0,
        };
    }
    
    pub fn updateUsage(self: *ConnectionStats, bytes_sent: u64, bytes_received: u64, success: bool) void {
        self.last_used = std.time.milliTimestamp();
        self.usage_count += 1;
        self.bytes_sent += bytes_sent;
        self.bytes_received += bytes_received;
        
        if (!success) {
            self.error_count += 1;
        }
    }
    
    pub fn getAge(self: ConnectionStats) u64 {
        return @as(u64, @intCast(std.time.milliTimestamp() - self.created_at));
    }
    
    pub fn getIdleTime(self: ConnectionStats) u64 {
        return @as(u64, @intCast(std.time.milliTimestamp() - self.last_used));
    }
    
    pub fn getErrorRate(self: ConnectionStats) f64 {
        if (self.usage_count == 0) return 0.0;
        return @as(f64, @floatFromInt(self.error_count)) / @as(f64, @floatFromInt(self.usage_count));
    }
};

// Connection wrapper
pub const PooledConnection = struct {
    id: u64,
    endpoint: []const u8,
    state: ConnectionState,
    stats: ConnectionStats,
    connection_data: ?*anyopaque,
    last_health_check: i64,
    mutex: Mutex,
    
    pub fn init(allocator: Allocator, id: u64, endpoint: []const u8) !PooledConnection {
        return PooledConnection{
            .id = id,
            .endpoint = try allocator.dupe(u8, endpoint),
            .state = .idle,
            .stats = ConnectionStats.init(),
            .connection_data = null,
            .last_health_check = std.time.milliTimestamp(),
            .mutex = Mutex{},
        };
    }
    
    pub fn deinit(self: *PooledConnection, allocator: Allocator) void {
        allocator.free(self.endpoint);
    }
    
    pub fn setState(self: *PooledConnection, state: ConnectionState) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.state = state;
    }
    
    pub fn getState(self: *PooledConnection) ConnectionState {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.state;
    }
    
    pub fn updateStats(self: *PooledConnection, bytes_sent: u64, bytes_received: u64, success: bool) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.stats.updateUsage(bytes_sent, bytes_received, success);
    }
    
    pub fn isHealthy(self: *PooledConnection, max_idle_time: u64, max_error_rate: f64) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.state == .err or self.state == .disconnected) return false;
        if (self.stats.getIdleTime() > max_idle_time) return false;
        if (self.stats.getErrorRate() > max_error_rate) return false;
        
        return true;
    }
};

// Connection pool configuration
pub const ConnectionPoolConfig = struct {
    min_connections: u32,
    max_connections: u32,
    connection_timeout_ms: u64,
    idle_timeout_ms: u64,
    max_connection_age_ms: u64,
    health_check_interval_ms: u64,
    max_error_rate: f64,
    connection_retry_delay_ms: u64,
    enable_keepalive: bool,
    keepalive_interval_ms: u64,
    
    pub fn init() ConnectionPoolConfig {
        return ConnectionPoolConfig{
            .min_connections = 2,
            .max_connections = 10,
            .connection_timeout_ms = 30000,
            .idle_timeout_ms = 300000, // 5 minutes
            .max_connection_age_ms = 1800000, // 30 minutes
            .health_check_interval_ms = 60000, // 1 minute
            .max_error_rate = 0.1, // 10%
            .connection_retry_delay_ms = 5000,
            .enable_keepalive = true,
            .keepalive_interval_ms = 30000, // 30 seconds
        };
    }
};

// Connection factory interface
pub const ConnectionFactory = struct {
    createFn: *const fn (allocator: Allocator, endpoint: []const u8) anyerror!*anyopaque,
    destroyFn: *const fn (allocator: Allocator, connection: *anyopaque) void,
    healthCheckFn: *const fn (connection: *anyopaque) bool,
    
    pub fn create(self: ConnectionFactory, allocator: Allocator, endpoint: []const u8) !*anyopaque {
        return self.createFn(allocator, endpoint);
    }
    
    pub fn destroy(self: ConnectionFactory, allocator: Allocator, connection: *anyopaque) void {
        return self.destroyFn(allocator, connection);
    }
    
    pub fn healthCheck(self: ConnectionFactory, connection: *anyopaque) bool {
        return self.healthCheckFn(connection);
    }
};

// Connection pool implementation
pub const ConnectionPool = struct {
    allocator: Allocator,
    endpoint: []const u8,
    config: ConnectionPoolConfig,
    factory: ConnectionFactory,
    connections: ArrayList(*PooledConnection),
    available_connections: ArrayList(*PooledConnection),
    next_connection_id: AtomicUsize,
    total_connections: AtomicUsize,
    active_connections: AtomicUsize,
    mutex: Mutex,
    condition: Condition,
    shutdown: AtomicBool,
    health_check_thread: ?Thread,
    
    pub fn init(
        allocator: Allocator,
        endpoint: []const u8,
        config: ConnectionPoolConfig,
        factory: ConnectionFactory,
    ) !ConnectionPool {
        var pool = ConnectionPool{
            .allocator = allocator,
            .endpoint = try allocator.dupe(u8, endpoint),
            .config = config,
            .factory = factory,
            .connections = ArrayList(*PooledConnection).init(allocator),
            .available_connections = ArrayList(*PooledConnection).init(allocator),
            .next_connection_id = AtomicUsize.init(1),
            .total_connections = AtomicUsize.init(0),
            .active_connections = AtomicUsize.init(0),
            .mutex = Mutex{},
            .condition = Condition{},
            .shutdown = AtomicBool.init(false),
            .health_check_thread = null,
        };
        
        // Pre-populate with minimum connections
        try pool.ensureMinimumConnections();
        
        // Start health check thread
        pool.health_check_thread = try Thread.spawn(.{}, healthCheckWorker, .{&pool});
        
        return pool;
    }
    
    pub fn deinit(self: *ConnectionPool) void {
        // Signal shutdown
        self.shutdown.store(true, .Release);
        
        // Wait for health check thread to finish
        if (self.health_check_thread) |thread| {
            thread.join();
        }
        
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // Clean up all connections
        for (self.connections.items) |connection| {
            if (connection.connection_data) |data| {
                self.factory.destroy(self.allocator, data);
            }
            connection.deinit(self.allocator);
            self.allocator.destroy(connection);
        }
        
        self.connections.deinit();
        self.available_connections.deinit();
        self.allocator.free(self.endpoint);
    }
    
    pub fn acquireConnection(self: *ConnectionPool, timeout_ms: ?u64) !*PooledConnection {
        const start_time = std.time.milliTimestamp();
        const timeout = timeout_ms orelse self.config.connection_timeout_ms;
        
        while (true) {
            self.mutex.lock();
            
            // Check for available connection
            if (self.available_connections.items.len > 0) {
                const connection = self.available_connections.pop();
                connection.setState(.active);
                _ = self.active_connections.fetchAdd(1, .Acquire);
                self.mutex.unlock();
                return connection;
            }
            
            // Check if we can create a new connection
            const current_total = self.total_connections.load(.Acquire);
            if (current_total < self.config.max_connections) {
                self.mutex.unlock();
                
                if (try self.createConnection()) |connection| {
                    connection.setState(.active);
                    _ = self.active_connections.fetchAdd(1, .Acquire);
                    return connection;
                }
            } else {
                // Wait for a connection to become available
                const elapsed = @as(u64, @intCast(std.time.milliTimestamp() - start_time));
                if (elapsed >= timeout) {
                    self.mutex.unlock();
                    return error.ConnectionTimeout;
                }
                
                self.condition.timedWait(&self.mutex, timeout - elapsed) catch {};
                self.mutex.unlock();
            }
        }
    }
    
    pub fn releaseConnection(self: *ConnectionPool, connection: *PooledConnection) void {
        connection.setState(.idle);
        
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // Return connection to available pool
        self.available_connections.append(connection) catch {
            // If we can't add it back, destroy it
            self.destroyConnection(connection);
            return;
        };
        
        _ = self.active_connections.fetchSub(1, .Release);
        self.condition.signal();
    }
    
    pub fn getStats(self: *ConnectionPool) PoolStats {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        var stats = PoolStats{
            .total_connections = self.total_connections.load(.Acquire),
            .active_connections = self.active_connections.load(.Acquire),
            .available_connections = @as(u32, @intCast(self.available_connections.items.len)),
            .total_usage_count = 0,
            .total_bytes_sent = 0,
            .total_bytes_received = 0,
            .total_error_count = 0,
            .avg_connection_age = 0.0,
            .avg_error_rate = 0.0,
        };
        
        var total_age: u64 = 0;
        var total_error_rate: f64 = 0.0;
        
        for (self.connections.items) |connection| {
            connection.mutex.lock();
            stats.total_usage_count += connection.stats.usage_count;
            stats.total_bytes_sent += connection.stats.bytes_sent;
            stats.total_bytes_received += connection.stats.bytes_received;
            stats.total_error_count += connection.stats.error_count;
            total_age += connection.stats.getAge();
            total_error_rate += connection.stats.getErrorRate();
            connection.mutex.unlock();
        }
        
        if (self.connections.items.len > 0) {
            stats.avg_connection_age = @as(f64, @floatFromInt(total_age)) / @as(f64, @floatFromInt(self.connections.items.len));
            stats.avg_error_rate = total_error_rate / @as(f64, @floatFromInt(self.connections.items.len));
        }
        
        return stats;
    }
    
    fn ensureMinimumConnections(self: *ConnectionPool) !void {
        while (self.total_connections.load(.Acquire) < self.config.min_connections) {
            _ = try self.createConnection();
        }
    }
    
    fn createConnection(self: *ConnectionPool) !?*PooledConnection {
        const connection_id = self.next_connection_id.fetchAdd(1, .Acquire);
        
        const pooled_connection = try self.allocator.create(PooledConnection);
        pooled_connection.* = try PooledConnection.init(self.allocator, connection_id, self.endpoint);
        
        // Create actual connection
        pooled_connection.setState(.connecting);
        pooled_connection.connection_data = self.factory.create(self.allocator, self.endpoint) catch |err| {
            pooled_connection.setState(.err);
            pooled_connection.deinit(self.allocator);
            self.allocator.destroy(pooled_connection);
            return err;
        };
        
        pooled_connection.setState(.idle);
        
        self.mutex.lock();
        defer self.mutex.unlock();
        
        try self.connections.append(pooled_connection);
        try self.available_connections.append(pooled_connection);
        _ = self.total_connections.fetchAdd(1, .Acquire);
        
        return pooled_connection;
    }
    
    fn destroyConnection(self: *ConnectionPool, connection: *PooledConnection) void {
        if (connection.connection_data) |data| {
            self.factory.destroy(self.allocator, data);
        }
        
        // Remove from connections list
        for (self.connections.items, 0..) |conn, index| {
            if (conn == connection) {
                _ = self.connections.orderedRemove(index);
                break;
            }
        }
        
        // Remove from available connections list
        for (self.available_connections.items, 0..) |conn, index| {
            if (conn == connection) {
                _ = self.available_connections.orderedRemove(index);
                break;
            }
        }
        
        connection.deinit(self.allocator);
        self.allocator.destroy(connection);
        _ = self.total_connections.fetchSub(1, .Release);
    }
    
    fn performHealthCheck(self: *ConnectionPool) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        var unhealthy_connections = ArrayList(*PooledConnection).init(self.allocator);
        defer unhealthy_connections.deinit();
        
        for (self.connections.items) |connection| {
            if (!connection.isHealthy(self.config.idle_timeout_ms, self.config.max_error_rate)) {
                unhealthy_connections.append(connection) catch continue;
                continue;
            }
            
            // Perform connection-level health check
            if (connection.connection_data) |data| {
                if (!self.factory.healthCheck(data)) {
                    connection.setState(.err);
                    unhealthy_connections.append(connection) catch continue;
                }
            }
        }
        
        // Remove unhealthy connections
        for (unhealthy_connections.items) |connection| {
            self.destroyConnection(connection);
        }
        
        // Ensure minimum connections
        self.ensureMinimumConnections() catch {};
    }
    
    fn healthCheckWorker(self: *ConnectionPool) void {
        while (!self.shutdown.load(.Acquire)) {
            self.performHealthCheck();
            
            // Sleep for health check interval
            std.time.sleep(self.config.health_check_interval_ms * std.time.ns_per_ms);
        }
    }
};

// Pool statistics
pub const PoolStats = struct {
    total_connections: u32,
    active_connections: u32,
    available_connections: u32,
    total_usage_count: u64,
    total_bytes_sent: u64,
    total_bytes_received: u64,
    total_error_count: u64,
    avg_connection_age: f64,
    avg_error_rate: f64,
};

// Connection pool manager for multiple endpoints
pub const ConnectionPoolManager = struct {
    allocator: Allocator,
    pools: HashMap([]const u8, *ConnectionPool, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    config: ConnectionPoolConfig,
    factory: ConnectionFactory,
    mutex: Mutex,
    
    pub fn init(allocator: Allocator, config: ConnectionPoolConfig, factory: ConnectionFactory) ConnectionPoolManager {
        return ConnectionPoolManager{
            .allocator = allocator,
            .pools = HashMap([]const u8, *ConnectionPool, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .config = config,
            .factory = factory,
            .mutex = Mutex{},
        };
    }
    
    pub fn deinit(self: *ConnectionPoolManager) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        var iter = self.pools.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.pools.deinit();
    }
    
    pub fn getPool(self: *ConnectionPoolManager, endpoint: []const u8) !*ConnectionPool {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.pools.get(endpoint)) |pool| {
            return pool;
        }
        
        const pool = try self.allocator.create(ConnectionPool);
        pool.* = try ConnectionPool.init(self.allocator, endpoint, self.config, self.factory);
        
        const endpoint_copy = try self.allocator.dupe(u8, endpoint);
        try self.pools.put(endpoint_copy, pool);
        
        return pool;
    }
    
    pub fn acquireConnection(self: *ConnectionPoolManager, endpoint: []const u8, timeout_ms: ?u64) !*PooledConnection {
        const pool = try self.getPool(endpoint);
        return pool.acquireConnection(timeout_ms);
    }
    
    pub fn releaseConnection(self: *ConnectionPoolManager, endpoint: []const u8, connection: *PooledConnection) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.pools.get(endpoint)) |pool| {
            pool.releaseConnection(connection);
        }
    }
    
    pub fn getAllStats(self: *ConnectionPoolManager, allocator: Allocator) ![]PoolStatsWithEndpoint {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        var stats_list = ArrayList(PoolStatsWithEndpoint).init(allocator);
        
        var iter = self.pools.iterator();
        while (iter.next()) |entry| {
            const endpoint = entry.key_ptr.*;
            const pool = entry.value_ptr.*;
            const stats = pool.getStats();
            
            const stats_with_endpoint = PoolStatsWithEndpoint{
                .endpoint = try allocator.dupe(u8, endpoint),
                .stats = stats,
            };
            
            try stats_list.append(stats_with_endpoint);
        }
        
        return stats_list.toOwnedSlice();
    }
};

// Pool stats with endpoint information
pub const PoolStatsWithEndpoint = struct {
    endpoint: []const u8,
    stats: PoolStats,
    
    pub fn deinit(self: PoolStatsWithEndpoint, allocator: Allocator) void {
        allocator.free(self.endpoint);
    }
};

// Load balancing strategies for connection pools
pub const LoadBalancingStrategy = enum {
    round_robin,
    least_connections,
    least_response_time,
    weighted_round_robin,
    
    pub fn selectPool(self: LoadBalancingStrategy, pools: []const *ConnectionPool, weights: ?[]const u32) ?*ConnectionPool {
        if (pools.len == 0) return null;
        
        return switch (self) {
            .round_robin => selectRoundRobin(pools),
            .least_connections => selectLeastConnections(pools),
            .least_response_time => selectLeastResponseTime(pools),
            .weighted_round_robin => selectWeightedRoundRobin(pools, weights orelse &[_]u32{}),
        };
    }
    
    fn selectRoundRobin(pools: []const *ConnectionPool) *ConnectionPool {
        // Round-robin selection using timestamp-based indexing
        const index = @mod(std.time.milliTimestamp(), @as(i64, @intCast(pools.len)));
        return pools[@intCast(index)];
    }
    
    fn selectLeastConnections(pools: []const *ConnectionPool) *ConnectionPool {
        var min_connections: u32 = std.math.maxInt(u32);
        var selected_pool: ?*ConnectionPool = null;
        
        for (pools) |pool| {
            const active_connections = pool.active_connections.load(.Acquire);
            if (active_connections < min_connections) {
                min_connections = active_connections;
                selected_pool = pool;
            }
        }
        
        return selected_pool orelse pools[0];
    }
    
    fn selectLeastResponseTime(pools: []const *ConnectionPool) *ConnectionPool {
        // Would need to track response times - simplified implementation
        return selectLeastConnections(pools);
    }
    
    fn selectWeightedRoundRobin(pools: []const *ConnectionPool, weights: []const u32) *ConnectionPool {
        if (weights.len != pools.len) return selectRoundRobin(pools);
        
        var total_weight: u32 = 0;
        for (weights) |weight| {
            total_weight += weight;
        }
        
        if (total_weight == 0) return pools[0];
        
        const random_value = @mod(@as(u32, @intCast(std.time.milliTimestamp())), total_weight);
        var current_weight: u32 = 0;
        
        for (pools, weights) |pool, weight| {
            current_weight += weight;
            if (random_value < current_weight) {
                return pool;
            }
        }
        
        return pools[0];
    }
};

// Test cases
test "ConnectionStats operations" {
    var stats = ConnectionStats.init();
    
    const initial_time = stats.created_at;
    try testing.expect(stats.last_used >= initial_time);
    try testing.expectEqual(@as(u64, 0), stats.usage_count);
    
    stats.updateUsage(1024, 512, true);
    try testing.expectEqual(@as(u64, 1), stats.usage_count);
    try testing.expectEqual(@as(u64, 1024), stats.bytes_sent);
    try testing.expectEqual(@as(u64, 512), stats.bytes_received);
    try testing.expectEqual(@as(u64, 0), stats.error_count);
    
    stats.updateUsage(0, 0, false);
    try testing.expectEqual(@as(u64, 1), stats.error_count);
    try testing.expect(stats.getErrorRate() > 0.0);
}

test "PooledConnection basic operations" {
    const allocator = testing.allocator;
    
    var connection = try PooledConnection.init(allocator, 1, "test.endpoint.com:443");
    defer connection.deinit(allocator);
    
    try testing.expectEqual(@as(u64, 1), connection.id);
    try testing.expect(std.mem.eql(u8, "test.endpoint.com:443", connection.endpoint));
    try testing.expectEqual(ConnectionState.idle, connection.getState());
    
    connection.setState(.active);
    try testing.expectEqual(ConnectionState.active, connection.getState());
    
    connection.updateStats(1024, 512, true);
    try testing.expectEqual(@as(u64, 1), connection.stats.usage_count);
    
    try testing.expect(connection.isHealthy(60000, 0.1));
}

test "ConnectionPoolConfig default values" {
    const config = ConnectionPoolConfig.init();
    
    try testing.expectEqual(@as(u32, 2), config.min_connections);
    try testing.expectEqual(@as(u32, 10), config.max_connections);
    try testing.expect(config.connection_timeout_ms > 0);
    try testing.expect(config.idle_timeout_ms > 0);
    try testing.expect(config.enable_keepalive);
}
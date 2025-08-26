// Performance monitoring utilities
// Provides comprehensive performance tracking and analysis

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const Thread = std.Thread;
const Mutex = Thread.Mutex;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;

// Performance metrics
pub const PerformanceMetrics = struct {
    request_count: u64,
    total_duration_ms: u64,
    min_duration_ms: u64,
    max_duration_ms: u64,
    avg_duration_ms: f64,
    error_count: u64,
    success_count: u64,
    bytes_sent: u64,
    bytes_received: u64,
    last_updated: i64,
    
    pub fn init() PerformanceMetrics {
        return PerformanceMetrics{
            .request_count = 0,
            .total_duration_ms = 0,
            .min_duration_ms = std.math.maxInt(u64),
            .max_duration_ms = 0,
            .avg_duration_ms = 0.0,
            .error_count = 0,
            .success_count = 0,
            .bytes_sent = 0,
            .bytes_received = 0,
            .last_updated = std.time.milliTimestamp(),
        };
    }
    
    pub fn update(self: *PerformanceMetrics, duration_ms: u64, success: bool, bytes_sent: u64, bytes_received: u64) void {
        self.request_count += 1;
        self.total_duration_ms += duration_ms;
        self.bytes_sent += bytes_sent;
        self.bytes_received += bytes_received;
        
        if (duration_ms < self.min_duration_ms) {
            self.min_duration_ms = duration_ms;
        }
        
        if (duration_ms > self.max_duration_ms) {
            self.max_duration_ms = duration_ms;
        }
        
        self.avg_duration_ms = @as(f64, @floatFromInt(self.total_duration_ms)) / @as(f64, @floatFromInt(self.request_count));
        
        if (success) {
            self.success_count += 1;
        } else {
            self.error_count += 1;
        }
        
        self.last_updated = std.time.milliTimestamp();
    }
    
    pub fn getSuccessRate(self: PerformanceMetrics) f64 {
        if (self.request_count == 0) return 0.0;
        return @as(f64, @floatFromInt(self.success_count)) / @as(f64, @floatFromInt(self.request_count));
    }
    
    pub fn getThroughput(self: PerformanceMetrics, window_ms: u64) f64 {
        if (window_ms == 0) return 0.0;
        return @as(f64, @floatFromInt(self.request_count)) / (@as(f64, @floatFromInt(window_ms)) / 1000.0);
    }
    
    pub fn getBandwidthMbps(self: PerformanceMetrics, window_ms: u64) f64 {
        if (window_ms == 0) return 0.0;
        const total_bytes = self.bytes_sent + self.bytes_received;
        const bits = total_bytes * 8;
        const seconds = @as(f64, @floatFromInt(window_ms)) / 1000.0;
        return (@as(f64, @floatFromInt(bits)) / seconds) / (1024.0 * 1024.0);
    }
};

// Performance sample for time series analysis
pub const PerformanceSample = struct {
    timestamp: i64,
    duration_ms: u64,
    success: bool,
    bytes_sent: u64,
    bytes_received: u64,
    operation_type: []const u8,
    node_endpoint: []const u8,
    error_code: ?u32,
    
    pub fn init(
        duration_ms: u64,
        success: bool,
        bytes_sent: u64,
        bytes_received: u64,
        operation_type: []const u8,
        node_endpoint: []const u8,
        error_code: ?u32,
    ) PerformanceSample {
        return PerformanceSample{
            .timestamp = std.time.milliTimestamp(),
            .duration_ms = duration_ms,
            .success = success,
            .bytes_sent = bytes_sent,
            .bytes_received = bytes_received,
            .operation_type = operation_type,
            .node_endpoint = node_endpoint,
            .error_code = error_code,
        };
    }
};

// Thread-safe performance monitor
pub const PerformanceMonitor = struct {
    allocator: Allocator,
    mutex: Mutex,
    global_metrics: PerformanceMetrics,
    operation_metrics: HashMap([]const u8, PerformanceMetrics, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    node_metrics: HashMap([]const u8, PerformanceMetrics, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    samples: ArrayList(PerformanceSample),
    max_samples: usize,
    enabled: bool,
    start_time: i64,
    
    pub fn init(allocator: Allocator, max_samples: usize) PerformanceMonitor {
        return PerformanceMonitor{
            .allocator = allocator,
            .mutex = Mutex{},
            .global_metrics = PerformanceMetrics.init(),
            .operation_metrics = HashMap([]const u8, PerformanceMetrics, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .node_metrics = HashMap([]const u8, PerformanceMetrics, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .samples = ArrayList(PerformanceSample).init(allocator),
            .max_samples = max_samples,
            .enabled = true,
            .start_time = std.time.milliTimestamp(),
        };
    }
    
    pub fn deinit(self: *PerformanceMonitor) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        self.operation_metrics.deinit();
        self.node_metrics.deinit();
        
        // Free sample string references
        for (self.samples.items) |sample| {
            self.allocator.free(sample.operation_type);
            self.allocator.free(sample.node_endpoint);
        }
        self.samples.deinit();
    }
    
    pub fn setEnabled(self: *PerformanceMonitor, enabled: bool) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.enabled = enabled;
    }
    
    pub fn recordOperation(
        self: *PerformanceMonitor,
        duration_ms: u64,
        success: bool,
        bytes_sent: u64,
        bytes_received: u64,
        operation_type: []const u8,
        node_endpoint: []const u8,
        error_code: ?u32,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (!self.enabled) return;
        
        // Update global metrics
        self.global_metrics.update(duration_ms, success, bytes_sent, bytes_received);
        
        // Update operation-specific metrics
        const op_key = try self.allocator.dupe(u8, operation_type);
        var op_metrics = self.operation_metrics.get(op_key) orelse PerformanceMetrics.init();
        op_metrics.update(duration_ms, success, bytes_sent, bytes_received);
        try self.operation_metrics.put(op_key, op_metrics);
        
        // Update node-specific metrics
        const node_key = try self.allocator.dupe(u8, node_endpoint);
        var node_metrics = self.node_metrics.get(node_key) orelse PerformanceMetrics.init();
        node_metrics.update(duration_ms, success, bytes_sent, bytes_received);
        try self.node_metrics.put(node_key, node_metrics);
        
        // Store sample for time series analysis
        const sample = PerformanceSample.init(
            duration_ms,
            success,
            bytes_sent,
            bytes_received,
            try self.allocator.dupe(u8, operation_type),
            try self.allocator.dupe(u8, node_endpoint),
            error_code,
        );
        
        try self.samples.append(sample);
        
        // Trim samples if needed
        if (self.samples.items.len > self.max_samples) {
            const old_sample = self.samples.orderedRemove(0);
            self.allocator.free(old_sample.operation_type);
            self.allocator.free(old_sample.node_endpoint);
        }
    }
    
    pub fn getGlobalMetrics(self: *PerformanceMonitor) PerformanceMetrics {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.global_metrics;
    }
    
    pub fn getOperationMetrics(self: *PerformanceMonitor, operation_type: []const u8) ?PerformanceMetrics {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.operation_metrics.get(operation_type);
    }
    
    pub fn getNodeMetrics(self: *PerformanceMonitor, node_endpoint: []const u8) ?PerformanceMetrics {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.node_metrics.get(node_endpoint);
    }
    
    pub fn getSampleCount(self: *PerformanceMonitor) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.samples.items.len;
    }
    
    pub fn getUptime(self: *PerformanceMonitor) u64 {
        const now = std.time.milliTimestamp();
        return @as(u64, @intCast(now - self.start_time));
    }
    
    // Get recent samples within time window
    pub fn getRecentSamples(self: *PerformanceMonitor, allocator: Allocator, window_ms: u64) ![]PerformanceSample {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const cutoff_time = std.time.milliTimestamp() - @as(i64, @intCast(window_ms));
        var recent_samples = ArrayList(PerformanceSample).init(allocator);
        
        for (self.samples.items) |sample| {
            if (sample.timestamp >= cutoff_time) {
                try recent_samples.append(sample);
            }
        }
        
        return recent_samples.toOwnedSlice();
    }
    
    // Calculate percentiles for response times
    pub fn calculatePercentiles(self: *PerformanceMonitor, allocator: Allocator) !PercentileStats {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.samples.items.len == 0) {
            return PercentileStats{
                .p50 = 0,
                .p95 = 0,
                .p99 = 0,
                .p999 = 0,
            };
        }
        
        var durations = ArrayList(u64).init(allocator);
        defer durations.deinit();
        
        for (self.samples.items) |sample| {
            try durations.append(sample.duration_ms);
        }
        
        std.mem.sort(u64, durations.items, {}, comptime std.sort.asc(u64));
        
        return PercentileStats{
            .p50 = getPercentile(durations.items, 50),
            .p95 = getPercentile(durations.items, 95),
            .p99 = getPercentile(durations.items, 99),
            .p999 = getPercentile(durations.items, 99.9),
        };
    }
    
    // Clear all collected data
    pub fn reset(self: *PerformanceMonitor) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        self.global_metrics = PerformanceMetrics.init();
        
        // Clear operation metrics
        var op_iter = self.operation_metrics.iterator();
        while (op_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.operation_metrics.clearRetainingCapacity();
        
        // Clear node metrics  
        var node_iter = self.node_metrics.iterator();
        while (node_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.node_metrics.clearRetainingCapacity();
        
        // Clear samples
        for (self.samples.items) |sample| {
            self.allocator.free(sample.operation_type);
            self.allocator.free(sample.node_endpoint);
        }
        self.samples.clearRetainingCapacity();
        
        self.start_time = std.time.milliTimestamp();
    }
    
    // Generate performance report
    pub fn generateReport(self: *PerformanceMonitor, allocator: Allocator) ![]u8 {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        var report = ArrayList(u8).init(allocator);
        const writer = report.writer();
        
        try writer.print("Performance Report\n");
        try writer.print("=============================\n\n");
        
        const uptime = self.getUptime();
        try writer.print("Uptime: {} ms\n", .{uptime});
        
        try writer.print("Global Metrics:\n");
        try writer.print("  Requests: {}\n", .{self.global_metrics.request_count});
        try writer.print("  Success Rate: {d:.2}%\n", .{self.global_metrics.getSuccessRate() * 100});
        try writer.print("  Avg Response Time: {d:.2} ms\n", .{self.global_metrics.avg_duration_ms});
        try writer.print("  Min Response Time: {} ms\n", .{self.global_metrics.min_duration_ms});
        try writer.print("  Max Response Time: {} ms\n", .{self.global_metrics.max_duration_ms});
        try writer.print("  Throughput: {d:.2} req/s\n", .{self.global_metrics.getThroughput(uptime)});
        try writer.print("  Bandwidth: {d:.2} Mbps\n", .{self.global_metrics.getBandwidthMbps(uptime)});
        
        try writer.print("\nOperation Metrics:\n");
        var op_iter = self.operation_metrics.iterator();
        while (op_iter.next()) |entry| {
            const op_type = entry.key_ptr.*;
            const metrics = entry.value_ptr.*;
            try writer.print("  {}:\n", .{op_type});
            try writer.print("    Requests: {}\n", .{metrics.request_count});
            try writer.print("    Success Rate: {d:.2}%\n", .{metrics.getSuccessRate() * 100});
            try writer.print("    Avg Response Time: {d:.2} ms\n", .{metrics.avg_duration_ms});
        }
        
        try writer.print("\nNode Metrics:\n");
        var node_iter = self.node_metrics.iterator();
        while (node_iter.next()) |entry| {
            const node = entry.key_ptr.*;
            const metrics = entry.value_ptr.*;
            try writer.print("  {}:\n", .{node});
            try writer.print("    Requests: {}\n", .{metrics.request_count});
            try writer.print("    Success Rate: {d:.2}%\n", .{metrics.getSuccessRate() * 100});
            try writer.print("    Avg Response Time: {d:.2} ms\n", .{metrics.avg_duration_ms});
        }
        
        return report.toOwnedSlice();
    }
};

// Percentile statistics
pub const PercentileStats = struct {
    p50: u64,
    p95: u64,
    p99: u64,
    p999: u64,
};

// Helper function to calculate percentiles
fn getPercentile(sorted_data: []const u64, percentile: f64) u64 {
    if (sorted_data.len == 0) return 0;
    
    const index = (percentile / 100.0) * @as(f64, @floatFromInt(sorted_data.len - 1));
    const lower_index = @as(usize, @intFromFloat(@floor(index)));
    const upper_index = @min(lower_index + 1, sorted_data.len - 1);
    
    if (lower_index == upper_index) {
        return sorted_data[lower_index];
    }
    
    const weight = index - @floor(index);
    return @as(u64, @intFromFloat(@as(f64, @floatFromInt(sorted_data[lower_index])) * (1.0 - weight) + 
                                @as(f64, @floatFromInt(sorted_data[upper_index])) * weight));
}

// Performance timer for measuring operation durations
pub const PerformanceTimer = struct {
    start_time: i64,
    
    pub fn start() PerformanceTimer {
        return PerformanceTimer{
            .start_time = std.time.nanoTimestamp(),
        };
    }
    
    pub fn elapsed(self: PerformanceTimer) u64 {
        const now = std.time.nanoTimestamp();
        return @as(u64, @intCast(@divFloor(now - self.start_time, std.time.ns_per_ms)));
    }
    
    pub fn elapsedNanos(self: PerformanceTimer) u64 {
        const now = std.time.nanoTimestamp();
        return @as(u64, @intCast(now - self.start_time));
    }
};

// Memory usage monitor
pub const MemoryMonitor = struct {
    initial_usage: usize,
    peak_usage: usize,
    current_usage: usize,
    
    pub fn init() MemoryMonitor {
        // Initialize memory monitoring using system information
        return MemoryMonitor{
            .initial_usage = 0,
            .peak_usage = 0,
            .current_usage = 0,
        };
    }
    
    pub fn updateUsage(self: *MemoryMonitor, usage: usize) void {
        self.current_usage = usage;
        if (usage > self.peak_usage) {
            self.peak_usage = usage;
        }
    }
    
    pub fn getMemoryGrowth(self: MemoryMonitor) usize {
        return self.current_usage - self.initial_usage;
    }
};

// Global performance monitor instance
var global_monitor: ?*PerformanceMonitor = null;
var global_monitor_mutex: Mutex = Mutex{};

// Initialize global performance monitor
pub fn initGlobalMonitor(allocator: Allocator, max_samples: usize) !void {
    global_monitor_mutex.lock();
    defer global_monitor_mutex.unlock();
    
    if (global_monitor != null) return;
    
    global_monitor = try allocator.create(PerformanceMonitor);
    global_monitor.?.* = PerformanceMonitor.init(allocator, max_samples);
}

// Get global performance monitor
pub fn getGlobalMonitor() ?*PerformanceMonitor {
    global_monitor_mutex.lock();
    defer global_monitor_mutex.unlock();
    return global_monitor;
}

// Cleanup global performance monitor
pub fn deinitGlobalMonitor(allocator: Allocator) void {
    global_monitor_mutex.lock();
    defer global_monitor_mutex.unlock();
    
    if (global_monitor) |monitor| {
        monitor.deinit();
        allocator.destroy(monitor);
        global_monitor = null;
    }
}

// Test cases
test "PerformanceMetrics basic operations" {
    var metrics = PerformanceMetrics.init();
    
    // Record some operations
    metrics.update(100, true, 1024, 512);
    metrics.update(150, true, 2048, 1024);
    metrics.update(200, false, 512, 0);
    
    try testing.expectEqual(@as(u64, 3), metrics.request_count);
    try testing.expectEqual(@as(u64, 2), metrics.success_count);
    try testing.expectEqual(@as(u64, 1), metrics.error_count);
    try testing.expect(metrics.avg_duration_ms > 0);
    try testing.expect(metrics.getSuccessRate() > 0.6);
}

test "PerformanceTimer functionality" {
    const timer = PerformanceTimer.start();
    
    // Simulate some work
    std.time.sleep(1 * std.time.ns_per_ms);
    
    const elapsed = timer.elapsed();
    try testing.expect(elapsed >= 1);
}

test "PerformanceMonitor thread safety" {
    const allocator = testing.allocator;
    var monitor = PerformanceMonitor.init(allocator, 100);
    defer monitor.deinit();
    
    try monitor.recordOperation(100, true, 1024, 512, "test_op", "node1", null);
    try monitor.recordOperation(150, false, 2048, 0, "test_op", "node2", 500);
    
    const global_metrics = monitor.getGlobalMetrics();
    try testing.expectEqual(@as(u64, 2), global_metrics.request_count);
    
    const op_metrics = monitor.getOperationMetrics("test_op");
    try testing.expect(op_metrics != null);
    try testing.expectEqual(@as(u64, 2), op_metrics.?.request_count);
}

test "PerformanceMonitor percentile calculation" {
    const allocator = testing.allocator;
    var monitor = PerformanceMonitor.init(allocator, 100);
    defer monitor.deinit();
    
    // Add samples with known durations
    try monitor.recordOperation(100, true, 1024, 512, "test", "node1", null);
    try monitor.recordOperation(200, true, 1024, 512, "test", "node1", null);
    try monitor.recordOperation(300, true, 1024, 512, "test", "node1", null);
    try monitor.recordOperation(400, true, 1024, 512, "test", "node1", null);
    try monitor.recordOperation(500, true, 1024, 512, "test", "node1", null);
    
    const percentiles = try monitor.calculatePercentiles(allocator);
    try testing.expect(percentiles.p50 >= 200);
    try testing.expect(percentiles.p95 >= 400);
}
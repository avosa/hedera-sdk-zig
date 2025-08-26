// Debug utilities
// Provides comprehensive debugging, tracing, and introspection capabilities

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const Thread = std.Thread;
const Mutex = Thread.Mutex;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;

// Debug levels for fine-grained control
pub const DebugLevel = enum(u8) {
    off = 0,
    critical = 1,
    high = 2,
    medium = 3,
    low = 4,
    verbose = 5,
    
    pub fn toString(self: DebugLevel) []const u8 {
        return switch (self) {
            .off => "OFF",
            .critical => "CRITICAL",
            .high => "HIGH",
            .medium => "MEDIUM",
            .low => "LOW",
            .verbose => "VERBOSE",
        };
    }
};

// Debug categories for different SDK components
pub const DebugCategory = enum {
    network,
    crypto,
    transaction,
    query,
    protobuf,
    validation,
    performance,
    memory,
    threading,
    general,
    
    pub fn toString(self: DebugCategory) []const u8 {
        return switch (self) {
            .network => "NETWORK",
            .crypto => "CRYPTO",
            .transaction => "TRANSACTION",
            .query => "QUERY",
            .protobuf => "PROTOBUF",
            .validation => "VALIDATION",
            .performance => "PERFORMANCE",
            .memory => "MEMORY",
            .threading => "THREADING",
            .general => "GENERAL",
        };
    }
};

// Debug event for tracking SDK operations
pub const DebugEvent = struct {
    timestamp: i64,
    level: DebugLevel,
    category: DebugCategory,
    thread_id: u32,
    source_info: SourceInfo,
    message: []const u8,
    data: ?[]const u8,
    context: HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    
    pub const SourceInfo = struct {
        file: []const u8,
        function: []const u8,
        line: u32,
        
        pub fn init(file: []const u8, function: []const u8, line: u32) SourceInfo {
            return SourceInfo{
                .file = file,
                .function = function,
                .line = line,
            };
        }
    };
    
    pub fn init(
        allocator: Allocator,
        level: DebugLevel,
        category: DebugCategory,
        source_info: SourceInfo,
        message: []const u8,
        data: ?[]const u8,
    ) !DebugEvent {
        return DebugEvent{
            .timestamp = std.time.milliTimestamp(),
            .level = level,
            .category = category,
            .thread_id = @intCast(Thread.getCurrentId()),
            .source_info = source_info,
            .message = try allocator.dupe(u8, message),
            .data = if (data) |d| try allocator.dupe(u8, d) else null,
            .context = HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }
    
    pub fn deinit(self: DebugEvent, allocator: Allocator) void {
        allocator.free(self.message);
        if (self.data) |data| {
            allocator.free(data);
        }
        
        var iter = self.context.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.context.deinit();
    }
    
    pub fn addContext(self: *DebugEvent, allocator: Allocator, key: []const u8, value: []const u8) !void {
        const key_copy = try allocator.dupe(u8, key);
        const value_copy = try allocator.dupe(u8, value);
        try self.context.put(key_copy, value_copy);
    }
};

// Memory tracker for debugging memory issues
pub const MemoryTracker = struct {
    allocator: Allocator,
    allocations: HashMap(usize, AllocationInfo, std.hash_map.AutoContext(usize), std.hash_map.default_max_load_percentage),
    total_allocated: usize,
    total_freed: usize,
    peak_memory: usize,
    current_memory: usize,
    allocation_count: u64,
    free_count: u64,
    mutex: Mutex,
    
    const AllocationInfo = struct {
        size: usize,
        timestamp: i64,
        source_info: DebugEvent.SourceInfo,
    };
    
    pub fn init(allocator: Allocator) MemoryTracker {
        return MemoryTracker{
            .allocator = allocator,
            .allocations = HashMap(usize, AllocationInfo, std.hash_map.AutoContext(usize), std.hash_map.default_max_load_percentage).init(allocator),
            .total_allocated = 0,
            .total_freed = 0,
            .peak_memory = 0,
            .current_memory = 0,
            .allocation_count = 0,
            .free_count = 0,
            .mutex = Mutex{},
        };
    }
    
    pub fn deinit(self: *MemoryTracker) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.allocations.deinit();
    }
    
    pub fn trackAllocation(self: *MemoryTracker, ptr: usize, size: usize, source_info: DebugEvent.SourceInfo) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const info = AllocationInfo{
            .size = size,
            .timestamp = std.time.milliTimestamp(),
            .source_info = source_info,
        };
        
        self.allocations.put(ptr, info) catch return;
        self.total_allocated += size;
        self.current_memory += size;
        self.allocation_count += 1;
        
        if (self.current_memory > self.peak_memory) {
            self.peak_memory = self.current_memory;
        }
    }
    
    pub fn trackFree(self: *MemoryTracker, ptr: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.allocations.fetchRemove(ptr)) |entry| {
            self.total_freed += entry.value.size;
            self.current_memory -= entry.value.size;
            self.free_count += 1;
        }
    }
    
    pub fn getStats(self: *MemoryTracker) MemoryStats {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        return MemoryStats{
            .total_allocated = self.total_allocated,
            .total_freed = self.total_freed,
            .current_memory = self.current_memory,
            .peak_memory = self.peak_memory,
            .allocation_count = self.allocation_count,
            .free_count = self.free_count,
            .active_allocations = self.allocations.count(),
        };
    }
    
    pub fn detectLeaks(self: *MemoryTracker, allocator: Allocator) ![]LeakInfo {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        var leaks = ArrayList(LeakInfo).init(allocator);
        
        var iter = self.allocations.iterator();
        while (iter.next()) |entry| {
            const leak = LeakInfo{
                .address = entry.key_ptr.*,
                .size = entry.value_ptr.size,
                .timestamp = entry.value_ptr.timestamp,
                .source_info = entry.value_ptr.source_info,
            };
            try leaks.append(leak);
        }
        
        return leaks.toOwnedSlice();
    }
};

// Memory statistics
pub const MemoryStats = struct {
    total_allocated: usize,
    total_freed: usize,
    current_memory: usize,
    peak_memory: usize,
    allocation_count: u64,
    free_count: u64,
    active_allocations: u32,
};

// Memory leak information
pub const LeakInfo = struct {
    address: usize,
    size: usize,
    timestamp: i64,
    source_info: DebugEvent.SourceInfo,
};

// Call stack tracer for debugging execution flow
pub const CallStackTracer = struct {
    allocator: Allocator,
    stack: ArrayList(CallInfo),
    max_depth: usize,
    mutex: Mutex,
    
    const CallInfo = struct {
        function_name: []const u8,
        file: []const u8,
        line: u32,
        timestamp: i64,
        thread_id: u32,
    };
    
    pub fn init(allocator: Allocator, max_depth: usize) CallStackTracer {
        return CallStackTracer{
            .allocator = allocator,
            .stack = ArrayList(CallInfo).init(allocator),
            .max_depth = max_depth,
            .mutex = Mutex{},
        };
    }
    
    pub fn deinit(self: *CallStackTracer) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        for (self.stack.items) |call| {
            self.allocator.free(call.function_name);
            self.allocator.free(call.file);
        }
        self.stack.deinit();
    }
    
    pub fn enterFunction(self: *CallStackTracer, function_name: []const u8, file: []const u8, line: u32) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.stack.items.len >= self.max_depth) {
            // Remove oldest entry if at max depth
            const oldest = self.stack.orderedRemove(0);
            self.allocator.free(oldest.function_name);
            self.allocator.free(oldest.file);
        }
        
        const call = CallInfo{
            .function_name = try self.allocator.dupe(u8, function_name),
            .file = try self.allocator.dupe(u8, file),
            .line = line,
            .timestamp = std.time.milliTimestamp(),
            .thread_id = @intCast(Thread.getCurrentId()),
        };
        
        try self.stack.append(call);
    }
    
    pub fn exitFunction(self: *CallStackTracer) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.stack.items.len > 0) {
            const call = self.stack.pop();
            self.allocator.free(call.function_name);
            self.allocator.free(call.file);
        }
    }
    
    pub fn getCallStack(self: *CallStackTracer, allocator: Allocator) ![]CallInfo {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        var stack_copy = ArrayList(CallInfo).init(allocator);
        
        for (self.stack.items) |call| {
            const call_copy = CallInfo{
                .function_name = try allocator.dupe(u8, call.function_name),
                .file = try allocator.dupe(u8, call.file),
                .line = call.line,
                .timestamp = call.timestamp,
                .thread_id = call.thread_id,
            };
            try stack_copy.append(call_copy);
        }
        
        return stack_copy.toOwnedSlice();
    }
    
    pub fn printCallStack(self: *CallStackTracer, writer: anytype) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        try writer.writeAll("Call Stack Trace:\n");
        try writer.writeAll("================\n");
        
        for (self.stack.items, 0..) |call, index| {
            try writer.print("#{}: {}:{} in {} (thread: {}, time: {})\n", .{
                index,
                call.file,
                call.line,
                call.function_name,
                call.thread_id,
                call.timestamp,
            });
        }
    }
};

// Performance profiler for debugging performance issues
pub const PerformanceProfiler = struct {
    allocator: Allocator,
    profiles: HashMap([]const u8, ProfileData, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    active_profiles: HashMap([]const u8, i64, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    mutex: Mutex,
    
    const ProfileData = struct {
        total_time: u64,
        call_count: u64,
        min_time: u64,
        max_time: u64,
        avg_time: f64,
    };
    
    pub fn init(allocator: Allocator) PerformanceProfiler {
        return PerformanceProfiler{
            .allocator = allocator,
            .profiles = HashMap([]const u8, ProfileData, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .active_profiles = HashMap([]const u8, i64, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .mutex = Mutex{},
        };
    }
    
    pub fn deinit(self: *PerformanceProfiler) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        var profile_iter = self.profiles.iterator();
        while (profile_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.profiles.deinit();
        
        var active_iter = self.active_profiles.iterator();
        while (active_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.active_profiles.deinit();
    }
    
    pub fn startProfile(self: *PerformanceProfiler, name: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const name_copy = try self.allocator.dupe(u8, name);
        const start_time = std.time.nanoTimestamp();
        try self.active_profiles.put(name_copy, start_time);
    }
    
    pub fn endProfile(self: *PerformanceProfiler, name: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const end_time = std.time.nanoTimestamp();
        
        if (self.active_profiles.fetchRemove(name)) |entry| {
            const start_time = entry.value;
            const duration_ns = @as(u64, @intCast(end_time - start_time));
            const duration_ms = @divFloor(duration_ns, std.time.ns_per_ms);
            
            var profile_data = self.profiles.get(name) orelse ProfileData{
                .total_time = 0,
                .call_count = 0,
                .min_time = std.math.maxInt(u64),
                .max_time = 0,
                .avg_time = 0.0,
            };
            
            profile_data.total_time += duration_ms;
            profile_data.call_count += 1;
            
            if (duration_ms < profile_data.min_time) {
                profile_data.min_time = duration_ms;
            }
            
            if (duration_ms > profile_data.max_time) {
                profile_data.max_time = duration_ms;
            }
            
            profile_data.avg_time = @as(f64, @floatFromInt(profile_data.total_time)) / @as(f64, @floatFromInt(profile_data.call_count));
            
            try self.profiles.put(entry.key, profile_data);
        }
    }
    
    pub fn getProfileData(self: *PerformanceProfiler, name: []const u8) ?ProfileData {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.profiles.get(name);
    }
    
    pub fn printProfiles(self: *PerformanceProfiler, writer: anytype) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        try writer.writeAll("Performance Profiles:\n");
        try writer.writeAll("====================\n");
        
        var iter = self.profiles.iterator();
        while (iter.next()) |entry| {
            const name = entry.key_ptr.*;
            const data = entry.value_ptr.*;
            
            try writer.print("Function: {s}\n", .{name});
            try writer.print("  Total Time: {} ms\n", .{data.total_time});
            try writer.print("  Call Count: {}\n", .{data.call_count});
            try writer.print("  Avg Time: {d:.2} ms\n", .{data.avg_time});
            try writer.print("  Min Time: {} ms\n", .{data.min_time});
            try writer.print("  Max Time: {} ms\n", .{data.max_time});
            try writer.writeAll("\n");
        }
    }
};

// Main debug manager
pub const DebugManager = struct {
    allocator: Allocator,
    level: DebugLevel,
    enabled_categories: HashMap(DebugCategory, bool, std.hash_map.AutoContext(DebugCategory), std.hash_map.default_max_load_percentage),
    events: ArrayList(DebugEvent),
    memory_tracker: ?MemoryTracker,
    call_stack_tracer: ?CallStackTracer,
    performance_profiler: ?PerformanceProfiler,
    max_events: usize,
    mutex: Mutex,
    
    pub fn init(allocator: Allocator, level: DebugLevel, max_events: usize) DebugManager {
        var manager = DebugManager{
            .allocator = allocator,
            .level = level,
            .enabled_categories = HashMap(DebugCategory, bool, std.hash_map.AutoContext(DebugCategory), std.hash_map.default_max_load_percentage).init(allocator),
            .events = ArrayList(DebugEvent).init(allocator),
            .memory_tracker = null,
            .call_stack_tracer = null,
            .performance_profiler = null,
            .max_events = max_events,
            .mutex = Mutex{},
        };
        
        // Enable all categories by default
        const categories = [_]DebugCategory{
            .network, .crypto, .transaction, .query, .protobuf,
            .validation, .performance, .memory, .threading, .general,
        };
        
        for (categories) |category| {
            manager.enabled_categories.put(category, true) catch {};
        }
        
        return manager;
    }
    
    pub fn deinit(self: *DebugManager) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        for (self.events.items) |event| {
            event.deinit(self.allocator);
        }
        self.events.deinit();
        self.enabled_categories.deinit();
        
        if (self.memory_tracker) |*tracker| {
            tracker.deinit();
        }
        
        if (self.call_stack_tracer) |*tracer| {
            tracer.deinit();
        }
        
        if (self.performance_profiler) |*profiler| {
            profiler.deinit();
        }
    }
    
    pub fn setLevel(self: *DebugManager, level: DebugLevel) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.level = level;
    }
    
    pub fn setCategoryEnabled(self: *DebugManager, category: DebugCategory, enabled: bool) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.enabled_categories.put(category, enabled);
    }
    
    pub fn enableMemoryTracking(self: *DebugManager) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.memory_tracker = MemoryTracker.init(self.allocator);
    }
    
    pub fn enableCallStackTracing(self: *DebugManager, max_depth: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.call_stack_tracer = CallStackTracer.init(self.allocator, max_depth);
    }
    
    pub fn enablePerformanceProfiling(self: *DebugManager) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.performance_profiler = PerformanceProfiler.init(self.allocator);
    }
    
    pub fn isEnabled(self: *DebugManager, level: DebugLevel, category: DebugCategory) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (@intFromEnum(level) > @intFromEnum(self.level)) return false;
        return self.enabled_categories.get(category) orelse false;
    }
    
    pub fn logDebug(
        self: *DebugManager,
        level: DebugLevel,
        category: DebugCategory,
        source_info: DebugEvent.SourceInfo,
        message: []const u8,
        data: ?[]const u8,
    ) !void {
        if (!self.isEnabled(level, category)) return;
        
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const event = try DebugEvent.init(self.allocator, level, category, source_info, message, data);
        
        try self.events.append(event);
        
        // Trim events if needed
        if (self.events.items.len > self.max_events) {
            const old_event = self.events.orderedRemove(0);
            old_event.deinit(self.allocator);
        }
    }
    
    pub fn getMemoryTracker(self: *DebugManager) ?*MemoryTracker {
        return if (self.memory_tracker) |*tracker| tracker else null;
    }
    
    pub fn getCallStackTracer(self: *DebugManager) ?*CallStackTracer {
        return if (self.call_stack_tracer) |*tracer| tracer else null;
    }
    
    pub fn getPerformanceProfiler(self: *DebugManager) ?*PerformanceProfiler {
        return if (self.performance_profiler) |*profiler| profiler else null;
    }
    
    pub fn generateReport(self: *DebugManager, allocator: Allocator) ![]u8 {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        var report = ArrayList(u8).init(allocator);
        const writer = report.writer();
        
        try writer.writeAll("Debug Report\n");
        try writer.writeAll("=======================\n\n");
        
        try writer.print("Debug Level: {s}\n", .{self.level.toString()});
        try writer.print("Event Count: {}\n\n", .{self.events.items.len});
        
        // Recent events
        try writer.writeAll("Recent Debug Events:\n");
        try writer.writeAll("-------------------\n");
        
        const recent_count = @min(10, self.events.items.len);
        const start_idx = self.events.items.len - recent_count;
        
        for (self.events.items[start_idx..]) |event| {
            try writer.print("[{}] [{s}] [{s}] {s}:{} - {s}\n", .{
                event.timestamp,
                event.level.toString(),
                event.category.toString(),
                event.source_info.function,
                event.source_info.line,
                event.message,
            });
        }
        
        // Memory tracker report
        if (self.memory_tracker) |tracker| {
            const stats = tracker.getStats();
            try writer.writeAll("\nMemory Tracker Report:\n");
            try writer.writeAll("---------------------\n");
            try writer.print("Total Allocated: {} bytes\n", .{stats.total_allocated});
            try writer.print("Total Freed: {} bytes\n", .{stats.total_freed});
            try writer.print("Current Memory: {} bytes\n", .{stats.current_memory});
            try writer.print("Peak Memory: {} bytes\n", .{stats.peak_memory});
            try writer.print("Allocation Count: {}\n", .{stats.allocation_count});
            try writer.print("Free Count: {}\n", .{stats.free_count});
            try writer.print("Active Allocations: {}\n", .{stats.active_allocations});
        }
        
        return report.toOwnedSlice();
    }
};

// Global debug manager instance
var global_debug_manager: ?*DebugManager = null;
var global_debug_mutex: Mutex = Mutex{};

// Initialize global debug manager
pub fn initGlobalDebugManager(allocator: Allocator, level: DebugLevel, max_events: usize) !void {
    global_debug_mutex.lock();
    defer global_debug_mutex.unlock();
    
    if (global_debug_manager != null) return;
    
    global_debug_manager = try allocator.create(DebugManager);
    global_debug_manager.?.* = DebugManager.init(allocator, level, max_events);
}

// Get global debug manager
pub fn getGlobalDebugManager() ?*DebugManager {
    global_debug_mutex.lock();
    defer global_debug_mutex.unlock();
    return global_debug_manager;
}

// Cleanup global debug manager
pub fn deinitGlobalDebugManager(allocator: Allocator) void {
    global_debug_mutex.lock();
    defer global_debug_mutex.unlock();
    
    if (global_debug_manager) |manager| {
        manager.deinit();
        allocator.destroy(manager);
        global_debug_manager = null;
    }
}

// Convenience macros for debugging
pub inline fn debugTrace(category: DebugCategory, comptime format: []const u8, args: anytype) void {
    if (getGlobalDebugManager()) |manager| {
        const message = std.fmt.allocPrint(manager.allocator, format, args) catch return;
        defer manager.allocator.free(message);
        
        manager.logDebug(
            .verbose,
            category,
            DebugEvent.SourceInfo.init(@src().file, @src().fn_name, @src().line),
            message,
            null,
        ) catch {};
    }
}

pub inline fn debugInfo(category: DebugCategory, comptime format: []const u8, args: anytype) void {
    if (getGlobalDebugManager()) |manager| {
        const message = std.fmt.allocPrint(manager.allocator, format, args) catch return;
        defer manager.allocator.free(message);
        
        manager.logDebug(
            .medium,
            category,
            DebugEvent.SourceInfo.init(@src().file, @src().fn_name, @src().line),
            message,
            null,
        ) catch {};
    }
}

pub inline fn debugError(category: DebugCategory, comptime format: []const u8, args: anytype) void {
    if (getGlobalDebugManager()) |manager| {
        const message = std.fmt.allocPrint(manager.allocator, format, args) catch return;
        defer manager.allocator.free(message);
        
        manager.logDebug(
            .critical,
            category,
            DebugEvent.SourceInfo.init(@src().file, @src().fn_name, @src().line),
            message,
            null,
        ) catch {};
    }
}

// Test cases
test "DebugLevel operations" {
    try testing.expect(@intFromEnum(DebugLevel.critical) < @intFromEnum(DebugLevel.verbose));
    try testing.expect(std.mem.eql(u8, "HIGH", DebugLevel.high.toString()));
}

test "DebugEvent creation" {
    const allocator = testing.allocator;
    
    var event = try DebugEvent.init(
        allocator,
        .medium,
        .general,
        DebugEvent.SourceInfo.init("test.zig", "test_function", 42),
        "Test message",
        null,
    );
    defer event.deinit(allocator);
    
    try testing.expectEqual(DebugLevel.medium, event.level);
    try testing.expectEqual(DebugCategory.general, event.category);
    try testing.expect(std.mem.eql(u8, "Test message", event.message));
}

test "MemoryTracker basic operations" {
    const allocator = testing.allocator;
    
    var tracker = MemoryTracker.init(allocator);
    defer tracker.deinit();
    
    const source_info = DebugEvent.SourceInfo.init("test.zig", "test_function", 42);
    
    tracker.trackAllocation(0x1000, 256, source_info);
    tracker.trackAllocation(0x2000, 512, source_info);
    tracker.trackFree(0x1000);
    
    const stats = tracker.getStats();
    try testing.expectEqual(@as(usize, 768), stats.total_allocated);
    try testing.expectEqual(@as(usize, 256), stats.total_freed);
    try testing.expectEqual(@as(usize, 512), stats.current_memory);
    try testing.expectEqual(@as(u64, 2), stats.allocation_count);
    try testing.expectEqual(@as(u64, 1), stats.free_count);
}

test "DebugManager basic functionality" {
    const allocator = testing.allocator;
    
    var manager = DebugManager.init(allocator, .medium, 100);
    defer manager.deinit();
    
    try testing.expect(manager.isEnabled(.critical, .general));
    try testing.expect(manager.isEnabled(.medium, .network));
    try testing.expect(!manager.isEnabled(.verbose, .general));
    
    try manager.setCategoryEnabled(.network, false);
    try testing.expect(!manager.isEnabled(.medium, .network));
}
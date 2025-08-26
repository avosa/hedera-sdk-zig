// Query caching mechanisms for Hedera SDK
// Provides intelligent caching of query results with TTL and invalidation strategies

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const Thread = std.Thread;
const Mutex = Thread.Mutex;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const AtomicBool = std.atomic.Atomic(bool);

// Cache entry metadata
pub const CacheEntryMetadata = struct {
    created_at: i64,
    last_accessed: i64,
    access_count: u64,
    ttl_ms: u64,
    size_bytes: usize,
    tags: []const []const u8,
    
    pub fn init(allocator: Allocator, ttl_ms: u64, tags: []const []const u8) !CacheEntryMetadata {
        const now = std.time.milliTimestamp();
        var tags_copy = ArrayList([]const u8).init(allocator);
        
        for (tags) |tag| {
            try tags_copy.append(try allocator.dupe(u8, tag));
        }
        
        return CacheEntryMetadata{
            .created_at = now,
            .last_accessed = now,
            .access_count = 0,
            .ttl_ms = ttl_ms,
            .size_bytes = 0,
            .tags = try tags_copy.toOwnedSlice(),
        };
    }
    
    pub fn deinit(self: CacheEntryMetadata, allocator: Allocator) void {
        for (self.tags) |tag| {
            allocator.free(tag);
        }
        allocator.free(self.tags);
    }
    
    pub fn isExpired(self: CacheEntryMetadata) bool {
        const now = std.time.milliTimestamp();
        return (now - self.created_at) > @as(i64, @intCast(self.ttl_ms));
    }
    
    pub fn updateAccess(self: *CacheEntryMetadata) void {
        self.last_accessed = std.time.milliTimestamp();
        self.access_count += 1;
    }
    
    pub fn hasTag(self: CacheEntryMetadata, tag: []const u8) bool {
        for (self.tags) |existing_tag| {
            if (std.mem.eql(u8, existing_tag, tag)) return true;
        }
        return false;
    }
};

// Cache entry
pub const CacheEntry = struct {
    key: []const u8,
    value: []const u8,
    metadata: CacheEntryMetadata,
    
    pub fn init(allocator: Allocator, key: []const u8, value: []const u8, metadata: CacheEntryMetadata) !CacheEntry {
        var entry_metadata = metadata;
        entry_metadata.size_bytes = key.len + value.len;
        
        return CacheEntry{
            .key = try allocator.dupe(u8, key),
            .value = try allocator.dupe(u8, value),
            .metadata = entry_metadata,
        };
    }
    
    pub fn deinit(self: CacheEntry, allocator: Allocator) void {
        allocator.free(self.key);
        allocator.free(self.value);
        self.metadata.deinit(allocator);
    }
    
    pub fn clone(self: CacheEntry, allocator: Allocator) !CacheEntry {
        var cloned_tags = ArrayList([]const u8).init(allocator);
        for (self.metadata.tags) |tag| {
            try cloned_tags.append(try allocator.dupe(u8, tag));
        }
        
        var cloned_metadata = self.metadata;
        cloned_metadata.tags = try cloned_tags.toOwnedSlice();
        
        return CacheEntry{
            .key = try allocator.dupe(u8, self.key),
            .value = try allocator.dupe(u8, self.value),
            .metadata = cloned_metadata,
        };
    }
};

// Cache eviction strategy
pub const EvictionStrategy = enum {
    lru, // Least Recently Used
    lfu, // Least Frequently Used
    ttl, // Time To Live
    size, // Size-based
    
    pub fn shouldEvict(self: EvictionStrategy, entry: *const CacheEntry, context: EvictionContext) bool {
        return switch (self) {
            .lru => shouldEvictLRU(entry, context),
            .lfu => shouldEvictLFU(entry, context),
            .ttl => shouldEvictTTL(entry, context),
            .size => shouldEvictSize(entry, context),
        };
    }
    
    fn shouldEvictLRU(entry: *const CacheEntry, context: EvictionContext) bool {
        const now = std.time.milliTimestamp();
        const idle_time = now - entry.metadata.last_accessed;
        return idle_time > @as(i64, @intCast(context.max_idle_time_ms));
    }
    
    fn shouldEvictLFU(entry: *const CacheEntry, context: EvictionContext) bool {
        return entry.metadata.access_count < context.min_access_count;
    }
    
    fn shouldEvictTTL(entry: *const CacheEntry, _: EvictionContext) bool {
        return entry.metadata.isExpired();
    }
    
    fn shouldEvictSize(entry: *const CacheEntry, context: EvictionContext) bool {
        return entry.metadata.size_bytes > context.max_entry_size_bytes;
    }
};

// Eviction context for decision making
pub const EvictionContext = struct {
    max_idle_time_ms: u64,
    min_access_count: u64,
    max_entry_size_bytes: usize,
    current_cache_size: usize,
    max_cache_size: usize,
};

// Cache statistics
pub const CacheStats = struct {
    total_entries: usize,
    total_size_bytes: usize,
    hit_count: u64,
    miss_count: u64,
    eviction_count: u64,
    expired_count: u64,
    
    pub fn init() CacheStats {
        return CacheStats{
            .total_entries = 0,
            .total_size_bytes = 0,
            .hit_count = 0,
            .miss_count = 0,
            .eviction_count = 0,
            .expired_count = 0,
        };
    }
    
    pub fn getHitRatio(self: CacheStats) f64 {
        const total_requests = self.hit_count + self.miss_count;
        if (total_requests == 0) return 0.0;
        return @as(f64, @floatFromInt(self.hit_count)) / @as(f64, @floatFromInt(total_requests));
    }
    
    pub fn getAverageEntrySize(self: CacheStats) f64 {
        if (self.total_entries == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_size_bytes)) / @as(f64, @floatFromInt(self.total_entries));
    }
};

// Cache configuration
pub const QueryCacheConfig = struct {
    max_entries: usize,
    max_size_bytes: usize,
    default_ttl_ms: u64,
    max_key_size: usize,
    max_value_size: usize,
    eviction_strategy: EvictionStrategy,
    cleanup_interval_ms: u64,
    enable_compression: bool,
    enable_statistics: bool,
    
    pub fn init() QueryCacheConfig {
        return QueryCacheConfig{
            .max_entries = 10000,
            .max_size_bytes = 100 * 1024 * 1024, // 100MB
            .default_ttl_ms = 300000, // 5 minutes
            .max_key_size = 1024,
            .max_value_size = 10 * 1024 * 1024, // 10MB
            .eviction_strategy = .lru,
            .cleanup_interval_ms = 60000, // 1 minute
            .enable_compression = true,
            .enable_statistics = true,
        };
    }
};

// Query cache implementation
pub const QueryCache = struct {
    allocator: Allocator,
    config: QueryCacheConfig,
    entries: HashMap([]const u8, *CacheEntry, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    tag_index: HashMap([]const u8, ArrayList(*CacheEntry), std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    stats: CacheStats,
    current_size: usize,
    mutex: Mutex,
    cleanup_thread: ?Thread,
    shutdown: AtomicBool,
    
    pub fn init(allocator: Allocator, config: QueryCacheConfig) !QueryCache {
        var cache = QueryCache{
            .allocator = allocator,
            .config = config,
            .entries = HashMap([]const u8, *CacheEntry, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .tag_index = HashMap([]const u8, ArrayList(*CacheEntry), std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .stats = CacheStats.init(),
            .current_size = 0,
            .mutex = Mutex{},
            .cleanup_thread = null,
            .shutdown = AtomicBool.init(false),
        };
        
        // Start cleanup thread
        cache.cleanup_thread = try Thread.spawn(.{}, cleanupWorker, .{&cache});
        
        return cache;
    }
    
    pub fn deinit(self: *QueryCache) void {
        // Signal shutdown
        self.shutdown.store(true, .Release);
        
        // Wait for cleanup thread
        if (self.cleanup_thread) |thread| {
            thread.join();
        }
        
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // Clean up all entries
        var entry_iter = self.entries.iterator();
        while (entry_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit(self.allocator);
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.entries.deinit();
        
        // Clean up tag index
        var tag_iter = self.tag_index.iterator();
        while (tag_iter.next()) |tag_entry| {
            self.allocator.free(tag_entry.key_ptr.*);
            tag_entry.value_ptr.deinit();
        }
        self.tag_index.deinit();
    }
    
    pub fn get(self: *QueryCache, key: []const u8) ?[]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.entries.get(key)) |entry| {
            // Check if expired
            if (entry.metadata.isExpired()) {
                self.removeEntryUnsafe(key);
                self.stats.expired_count += 1;
                self.stats.miss_count += 1;
                return null;
            }
            
            // Update access metadata
            entry.metadata.updateAccess();
            
            if (self.config.enable_statistics) {
                self.stats.hit_count += 1;
            }
            
            return entry.value;
        }
        
        if (self.config.enable_statistics) {
            self.stats.miss_count += 1;
        }
        
        return null;
    }
    
    pub fn put(self: *QueryCache, key: []const u8, value: []const u8, ttl_ms: ?u64, tags: ?[]const []const u8) !void {
        if (key.len > self.config.max_key_size or value.len > self.config.max_value_size) {
            return error.EntrySizeExceeded;
        }
        
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const effective_ttl = ttl_ms orelse self.config.default_ttl_ms;
        const effective_tags = tags orelse &[_][]const u8{};
        
        // Check if entry already exists
        if (self.entries.get(key)) |_| {
            self.removeEntryUnsafe(key);
        }
        
        // Ensure we have space
        try self.ensureSpaceForEntry(key.len + value.len);
        
        // Create new entry
        const metadata = try CacheEntryMetadata.init(self.allocator, effective_ttl, effective_tags);
        const entry = try self.allocator.create(CacheEntry);
        entry.* = try CacheEntry.init(self.allocator, key, value, metadata);
        
        // Store entry
        const key_copy = try self.allocator.dupe(u8, key);
        try self.entries.put(key_copy, entry);
        
        // Update tag index
        for (entry.metadata.tags) |tag| {
            var tag_entries = self.tag_index.get(tag) orelse blk: {
                const new_list = ArrayList(*CacheEntry).init(self.allocator);
                const tag_copy = try self.allocator.dupe(u8, tag);
                try self.tag_index.put(tag_copy, new_list);
                break :blk self.tag_index.get(tag).?;
            };
            
            try tag_entries.append(entry);
        }
        
        // Update stats
        self.current_size += entry.metadata.size_bytes;
        if (self.config.enable_statistics) {
            self.stats.total_entries += 1;
            self.stats.total_size_bytes += entry.metadata.size_bytes;
        }
    }
    
    pub fn remove(self: *QueryCache, key: []const u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        return self.removeEntryUnsafe(key);
    }
    
    pub fn clear(self: *QueryCache) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // Clean up all entries
        var entry_iter = self.entries.iterator();
        while (entry_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit(self.allocator);
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.entries.clearRetainingCapacity();
        
        // Clear tag index
        var tag_iter = self.tag_index.iterator();
        while (tag_iter.next()) |tag_entry| {
            self.allocator.free(tag_entry.key_ptr.*);
            tag_entry.value_ptr.clearRetainingCapacity();
        }
        self.tag_index.clearRetainingCapacity();
        
        // Reset stats and size
        self.current_size = 0;
        self.stats = CacheStats.init();
    }
    
    pub fn invalidateByTag(self: *QueryCache, tag: []const u8) u32 {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        var invalidated_count: u32 = 0;
        
        if (self.tag_index.get(tag)) |tag_entries| {
            var entries_to_remove = ArrayList([]const u8).init(self.allocator);
            defer entries_to_remove.deinit();
            
            for (tag_entries.items) |entry| {
                entries_to_remove.append(entry.key) catch continue;
            }
            
            for (entries_to_remove.items) |key| {
                if (self.removeEntryUnsafe(key)) {
                    invalidated_count += 1;
                }
            }
        }
        
        return invalidated_count;
    }
    
    pub fn getStats(self: *QueryCache) CacheStats {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        var current_stats = self.stats;
        current_stats.total_entries = self.entries.count();
        current_stats.total_size_bytes = self.current_size;
        
        return current_stats;
    }
    
    pub fn getKeys(self: *QueryCache, allocator: Allocator) ![][]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        var keys = ArrayList([]const u8).init(allocator);
        
        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            try keys.append(try allocator.dupe(u8, entry.key_ptr.*));
        }
        
        return keys.toOwnedSlice();
    }
    
    pub fn exportEntries(self: *QueryCache, allocator: Allocator) ![]CacheEntry {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        var entries = ArrayList(CacheEntry).init(allocator);
        
        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            const cloned_entry = try entry.value_ptr.*.clone(allocator);
            try entries.append(cloned_entry);
        }
        
        return entries.toOwnedSlice();
    }
    
    pub fn importEntries(self: *QueryCache, entries: []const CacheEntry) !void {
        for (entries) |entry| {
            try self.put(entry.key, entry.value, entry.metadata.ttl_ms, entry.metadata.tags);
        }
    }
    
    fn removeEntryUnsafe(self: *QueryCache, key: []const u8) bool {
        if (self.entries.fetchRemove(key)) |removed| {
            const entry = removed.value;
            
            // Remove from tag index
            for (entry.metadata.tags) |tag| {
                if (self.tag_index.getPtr(tag)) |tag_entries| {
                    for (tag_entries.items, 0..) |indexed_entry, index| {
                        if (indexed_entry == entry) {
                            _ = tag_entries.orderedRemove(index);
                            break;
                        }
                    }
                    
                    // Remove empty tag entries
                    if (tag_entries.items.len == 0) {
                        _ = self.tag_index.remove(tag);
                        self.allocator.free(tag);
                    }
                }
            }
            
            // Update stats
            self.current_size -= entry.metadata.size_bytes;
            if (self.config.enable_statistics) {
                if (self.stats.total_entries > 0) self.stats.total_entries -= 1;
                if (self.stats.total_size_bytes >= entry.metadata.size_bytes) {
                    self.stats.total_size_bytes -= entry.metadata.size_bytes;
                }
            }
            
            // Clean up
            self.allocator.free(removed.key);
            entry.deinit(self.allocator);
            self.allocator.destroy(entry);
            
            return true;
        }
        
        return false;
    }
    
    fn ensureSpaceForEntry(self: *QueryCache, entry_size: usize) !void {
        // Check if we exceed max entries
        while (self.entries.count() >= self.config.max_entries) {
            try self.evictOneEntry();
        }
        
        // Check if we exceed max size
        while (self.current_size + entry_size > self.config.max_size_bytes) {
            try self.evictOneEntry();
        }
    }
    
    fn evictOneEntry(self: *QueryCache) !void {
        if (self.entries.count() == 0) return;
        
        const context = EvictionContext{
            .max_idle_time_ms = self.config.default_ttl_ms,
            .min_access_count = 1,
            .max_entry_size_bytes = self.config.max_value_size,
            .current_cache_size = self.current_size,
            .max_cache_size = self.config.max_size_bytes,
        };
        
        var candidate_key: ?[]const u8 = null;
        var best_score: i64 = std.math.maxInt(i64);
        
        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            const score = self.calculateEvictionScore(entry.value_ptr.*, context);
            if (score < best_score) {
                best_score = score;
                candidate_key = entry.key_ptr.*;
            }
        }
        
        if (candidate_key) |key| {
            _ = self.removeEntryUnsafe(key);
            if (self.config.enable_statistics) {
                self.stats.eviction_count += 1;
            }
        }
    }
    
    fn calculateEvictionScore(self: *QueryCache, entry: *const CacheEntry, _: EvictionContext) i64 {
        return switch (self.config.eviction_strategy) {
            .lru => entry.metadata.last_accessed,
            .lfu => -@as(i64, @intCast(entry.metadata.access_count)),
            .ttl => entry.metadata.created_at,
            .size => @as(i64, @intCast(entry.metadata.size_bytes)),
        };
    }
    
    fn performCleanup(self: *QueryCache) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        var expired_keys = ArrayList([]const u8).init(self.allocator);
        defer expired_keys.deinit();
        
        // Find expired entries
        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.metadata.isExpired()) {
                expired_keys.append(entry.key_ptr.*) catch continue;
            }
        }
        
        // Remove expired entries
        for (expired_keys.items) |key| {
            _ = self.removeEntryUnsafe(key);
            if (self.config.enable_statistics) {
                self.stats.expired_count += 1;
            }
        }
    }
    
    fn cleanupWorker(self: *QueryCache) void {
        while (!self.shutdown.load(.Acquire)) {
            self.performCleanup();
            
            // Sleep for cleanup interval
            std.time.sleep(self.config.cleanup_interval_ms * std.time.ns_per_ms);
        }
    }
};

// Cache key builder for query results
pub const QueryCacheKeyBuilder = struct {
    allocator: Allocator,
    components: ArrayList([]const u8),
    
    pub fn init(allocator: Allocator) QueryCacheKeyBuilder {
        return QueryCacheKeyBuilder{
            .allocator = allocator,
            .components = ArrayList([]const u8).init(allocator),
        };
    }
    
    pub fn deinit(self: *QueryCacheKeyBuilder) void {
        for (self.components.items) |component| {
            self.allocator.free(component);
        }
        self.components.deinit();
    }
    
    pub fn addComponent(self: *QueryCacheKeyBuilder, component: []const u8) !void {
        const component_copy = try self.allocator.dupe(u8, component);
        try self.components.append(component_copy);
    }
    
    pub fn addU64(self: *QueryCacheKeyBuilder, value: u64) !void {
        const component = try std.fmt.allocPrint(self.allocator, "{}", .{value});
        try self.components.append(component);
    }
    
    pub fn addBool(self: *QueryCacheKeyBuilder, value: bool) !void {
        const component = try self.allocator.dupe(u8, if (value) "true" else "false");
        try self.components.append(component);
    }
    
    pub fn build(self: *QueryCacheKeyBuilder) ![]u8 {
        var total_length: usize = 0;
        for (self.components.items) |component| {
            total_length += component.len + 1; // +1 for separator
        }
        
        if (total_length == 0) {
            return try self.allocator.dupe(u8, "empty");
        }
        
        var key = try self.allocator.alloc(u8, total_length - 1); // -1 for last separator
        var offset: usize = 0;
        
        for (self.components.items, 0..) |component, index| {
            std.mem.copy(u8, key[offset..offset + component.len], component);
            offset += component.len;
            
            if (index < self.components.items.len - 1) {
                key[offset] = ':';
                offset += 1;
            }
        }
        
        return key;
    }
};

// Test cases
test "CacheEntryMetadata basic operations" {
    const allocator = testing.allocator;
    
    const tags = [_][]const u8{ "account", "balance" };
    var metadata = try CacheEntryMetadata.init(allocator, 60000, &tags);
    defer metadata.deinit(allocator);
    
    try testing.expectEqual(@as(u64, 60000), metadata.ttl_ms);
    try testing.expect(metadata.hasTag("account"));
    try testing.expect(metadata.hasTag("balance"));
    try testing.expect(!metadata.hasTag("transaction"));
    
    try testing.expect(!metadata.isExpired());
    metadata.updateAccess();
    try testing.expectEqual(@as(u64, 1), metadata.access_count);
}

test "QueryCache basic operations" {
    const allocator = testing.allocator;
    
    const config = QueryCacheConfig.init();
    config.max_entries = 5;
    config.default_ttl_ms = 60000;
    
    var cache = try QueryCache.init(allocator, config);
    defer cache.deinit();
    
    // Test put and get
    try cache.put("key1", "value1", null, null);
    
    if (cache.get("key1")) |value| {
        try testing.expect(std.mem.eql(u8, "value1", value));
    } else {
        try testing.expect(false); // Should have found the value
    }
    
    // Test miss
    try testing.expect(cache.get("nonexistent") == null);
    
    // Test stats
    const stats = cache.getStats();
    try testing.expectEqual(@as(usize, 1), stats.total_entries);
    try testing.expect(stats.getHitRatio() > 0.0);
}

test "QueryCache with tags and invalidation" {
    const allocator = testing.allocator;
    
    const config = QueryCacheConfig.init();
    var cache = try QueryCache.init(allocator, config);
    defer cache.deinit();
    
    const tags = [_][]const u8{"account", "0.0.123"};
    try cache.put("account_balance", "1000", null, &tags);
    try cache.put("account_info", "info_data", null, &tags);
    
    // Test tag-based invalidation
    const invalidated = cache.invalidateByTag("account");
    try testing.expect(invalidated > 0);
    
    try testing.expect(cache.get("account_balance") == null);
    try testing.expect(cache.get("account_info") == null);
}

test "QueryCacheKeyBuilder operations" {
    const allocator = testing.allocator;
    
    var builder = QueryCacheKeyBuilder.init(allocator);
    defer builder.deinit();
    
    try builder.addComponent("AccountBalanceQuery");
    try builder.addU64(123);
    try builder.addBool(true);
    
    const key = try builder.build();
    defer allocator.free(key);
    
    try testing.expect(std.mem.eql(u8, "AccountBalanceQuery:123:true", key));
}
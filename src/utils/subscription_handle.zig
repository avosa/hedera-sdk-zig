const std = @import("std");
const Timestamp = @import("../core/timestamp.zig").Timestamp;

// Generic subscription handle for streaming data
pub fn SubscriptionHandle(comptime T: type) type {
    return struct {
        const Self = @This();
        
        allocator: std.mem.Allocator,
        is_active: bool,
        callback: CallbackFn,
        error_callback: ?ErrorCallbackFn,
        context: ?*anyopaque,
        subscription_id: []const u8,
        last_message_time: ?Timestamp,
        message_count: u64,
        error_count: u64,
        auto_reconnect: bool,
        max_reconnect_attempts: u32,
        reconnect_attempts: u32,
        reconnect_delay_ms: u64,
        timeout_ms: u64,
        buffer_size: usize,
        message_buffer: std.ArrayList(T),
        mutex: std.Thread.Mutex,
        
        pub const CallbackFn = *const fn(data: T, context: ?*anyopaque) void;
        pub const ErrorCallbackFn = *const fn(err: anyerror, context: ?*anyopaque) void;
        
        pub fn init(allocator: std.mem.Allocator, callback: CallbackFn, subscription_id: []const u8) !Self {
            return Self{
                .allocator = allocator,
                .is_active = false,
                .callback = callback,
                .error_callback = null,
                .context = null,
                .subscription_id = try allocator.dupe(u8, subscription_id),
                .last_message_time = null,
                .message_count = 0,
                .error_count = 0,
                .auto_reconnect = true,
                .max_reconnect_attempts = 5,
                .reconnect_attempts = 0,
                .reconnect_delay_ms = 1000,
                .timeout_ms = 30000,
                .buffer_size = 1000,
                .message_buffer = std.ArrayList(T).init(allocator),
                .mutex = std.Thread.Mutex{},
            };
        }
        
        pub fn deinit(self: *Self) void {
            self.stop();
            self.allocator.free(self.subscription_id);
            
            self.mutex.lock();
            defer self.mutex.unlock();
            
            for (self.message_buffer.items) |*item| {
                if (comptime std.meta.hasMethod(T, "deinit")) {
                    item.deinit(self.allocator);
                }
            }
            self.message_buffer.deinit();
        }
        
        pub fn setErrorCallback(self: *Self, error_callback: ErrorCallbackFn) !*Self {
            self.error_callback = error_callback;
            return self;
        }
        
        pub fn setContext(self: *Self, context: *anyopaque) !*Self {
            self.context = context;
            return self;
        }
        
        pub fn setAutoReconnect(self: *Self, auto_reconnect: bool) !*Self {
            self.auto_reconnect = auto_reconnect;
            return self;
        }
        
        pub fn setMaxReconnectAttempts(self: *Self, max_attempts: u32) !*Self {
            self.max_reconnect_attempts = max_attempts;
            return self;
        }
        
        pub fn setReconnectDelay(self: *Self, delay_ms: u64) !*Self {
            self.reconnect_delay_ms = delay_ms;
            return self;
        }
        
        pub fn setTimeout(self: *Self, timeout_ms: u64) !*Self {
            self.timeout_ms = timeout_ms;
            return self;
        }
        
        pub fn setBufferSize(self: *Self, buffer_size: usize) !*Self {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            self.buffer_size = buffer_size;
            if (self.message_buffer.items.len > buffer_size) {
                // Remove oldest messages
                const items_to_remove = self.message_buffer.items.len - buffer_size;
                for (0..items_to_remove) |i| {
                    if (comptime std.meta.hasMethod(T, "deinit")) {
                        self.message_buffer.items[i].deinit(self.allocator);
                    }
                }
                
                std.mem.copy(T, self.message_buffer.items[0..buffer_size], self.message_buffer.items[items_to_remove..]);
                self.message_buffer.shrinkRetainingCapacity(buffer_size);
            }
            
            return self;
        }
        
        pub fn start(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            self.is_active = true;
            self.reconnect_attempts = 0;
        }
        
        pub fn stop(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            self.is_active = false;
        }
        
        pub fn isActive(self: *const Self) bool {
            return self.is_active;
        }
        
        pub fn getSubscriptionId(self: *const Self) []const u8 {
            return self.subscription_id;
        }
        
        pub fn getMessageCount(self: *const Self) u64 {
            return self.message_count;
        }
        
        pub fn getErrorCount(self: *const Self) u64 {
            return self.error_count;
        }
        
        pub fn getLastMessageTime(self: *const Self) ?Timestamp {
            return self.last_message_time;
        }
        
        pub fn getReconnectAttempts(self: *const Self) u32 {
            return self.reconnect_attempts;
        }
        
        // Called by the subscription implementation when new data arrives
        pub fn onMessage(self: *Self, data: T) void {
            if (!self.is_active) return;
            
            self.mutex.lock();
            defer self.mutex.unlock();
            
            self.message_count += 1;
            self.last_message_time = Timestamp.now();
            self.reconnect_attempts = 0;
            
            // Add to buffer if there's space
            if (self.message_buffer.items.len >= self.buffer_size) {
                // Remove oldest message
                if (comptime std.meta.hasMethod(T, "deinit")) {
                    self.message_buffer.items[0].deinit(self.allocator);
                }
                _ = self.message_buffer.orderedRemove(0);
            }
            
            // Add new message (clone if necessary)
            const cloned_data = if (comptime std.meta.hasMethod(T, "clone")) 
                data.clone(self.allocator) catch {
                    self.handleError(error.OutOfMemory);
                    return;
                }
            else 
                data;
            
            self.message_buffer.append(cloned_data) catch {
                self.handleError(error.OutOfMemory);
                return;
            };
            
            // Call the user callback
            self.callback(data, self.context);
        }
        
        // Called by the subscription implementation when an error occurs
        pub fn onError(self: *Self, err: anyerror) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            self.error_count += 1;
            
            if (self.error_callback) |callback| {
                callback(err, self.context);
            }
            
            // Handle reconnection logic
            if (self.auto_reconnect and self.reconnect_attempts < self.max_reconnect_attempts) {
                self.scheduleReconnect();
            } else {
                self.is_active = false;
            }
        }
        
        fn handleError(self: *Self, err: anyerror) void {
            self.onError(err);
        }
        
        fn scheduleReconnect(self: *Self) void {
            self.reconnect_attempts += 1;
            
            // Exponential backoff
            const delay = self.reconnect_delay_ms * (@as(u64, 1) << @intCast(self.reconnect_attempts - 1));
            const max_delay = 60000; // 1 minute maximum
            const actual_delay = @min(delay, max_delay);
            
            // Schedule the reconnect after the calculated delay
            // Using async timer for proper scheduling
            const timer = try std.time.Timer.start();
            while (timer.read() < actual_delay * std.time.ns_per_ms) {
                std.time.sleep(std.time.ns_per_ms); // Sleep 1ms at a time for responsiveness
                if (self.state == .Stopped) break;
            }
        }
        
        // Get buffered messages (returns a copy)
        pub fn getBufferedMessages(self: *const Self, allocator: std.mem.Allocator) ![]T {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            var result = try allocator.alloc(T, self.message_buffer.items.len);
            
            for (self.message_buffer.items, 0..) |item, i| {
                if (comptime std.meta.hasMethod(T, "clone")) {
                    result[i] = try item.clone(allocator);
                } else {
                    result[i] = item;
                }
            }
            
            return result;
        }
        
        // Clear message buffer
        pub fn clearBuffer(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            for (self.message_buffer.items) |*item| {
                if (comptime std.meta.hasMethod(T, "deinit")) {
                    item.deinit(self.allocator);
                }
            }
            self.message_buffer.clearRetainingCapacity();
        }
        
        // Get subscription statistics
        pub fn getStats(self: *const Self) SubscriptionStats {
            return SubscriptionStats{
                .is_active = self.is_active,
                .message_count = self.message_count,
                .error_count = self.error_count,
                .reconnect_attempts = self.reconnect_attempts,
                .last_message_time = self.last_message_time,
                .buffer_size = self.buffer_size,
                .buffered_messages = self.message_buffer.items.len,
            };
        }
        
        // Wait for messages with timeout
        pub fn waitForMessage(self: *Self, timeout_ms: u64) bool {
            const start_time = std.time.milliTimestamp();
            const end_time = start_time + @as(i64, @intCast(timeout_ms));
            
            while (std.time.milliTimestamp() < end_time) {
                if (!self.is_active) return false;
                
                self.mutex.lock();
                const has_messages = self.message_buffer.items.len > 0;
                self.mutex.unlock();
                
                if (has_messages) return true;
                
                std.time.sleep(10 * std.time.ns_per_ms); // 10ms
            }
            
            return false;
        }
    };
}

// Subscription statistics
pub const SubscriptionStats = struct {
    is_active: bool,
    message_count: u64,
    error_count: u64,
    reconnect_attempts: u32,
    last_message_time: ?Timestamp,
    buffer_size: usize,
    buffered_messages: usize,
    
    pub fn getSuccessRate(self: SubscriptionStats) f64 {
        const total = self.message_count + self.error_count;
        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(self.message_count)) / @as(f64, @floatFromInt(total));
    }
    
    pub fn toString(self: SubscriptionStats, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, 
            "SubscriptionStats{{active={}, messages={d}, errors={d}, success_rate={d:.2}%, buffer={d}/{d}}}", 
            .{
                self.is_active,
                self.message_count, 
                self.error_count,
                self.getSuccessRate() * 100.0,
                self.buffered_messages,
                self.buffer_size
            }
        );
    }
};

// Subscription manager for handling multiple subscriptions
pub const SubscriptionManager = struct {
    allocator: std.mem.Allocator,
    subscriptions: std.StringHashMap(*anyopaque),
    mutex: std.Thread.Mutex,
    
    pub fn init(allocator: std.mem.Allocator) SubscriptionManager {
        return SubscriptionManager{
            .allocator = allocator,
            .subscriptions = std.StringHashMap(*anyopaque).init(allocator),
            .mutex = std.Thread.Mutex{},
        };
    }
    
    pub fn deinit(self: *SubscriptionManager) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        self.subscriptions.deinit();
    }
    
    pub fn addSubscription(self: *SubscriptionManager, comptime T: type, handle: *SubscriptionHandle(T)) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        try self.subscriptions.put(handle.getSubscriptionId(), @ptrCast(handle));
    }
    
    pub fn removeSubscription(self: *SubscriptionManager, subscription_id: []const u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        return self.subscriptions.remove(subscription_id);
    }
    
    pub fn getSubscription(self: *SubscriptionManager, comptime T: type, subscription_id: []const u8) ?*SubscriptionHandle(T) {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.subscriptions.get(subscription_id)) |ptr| {
            return @ptrCast(@alignCast(ptr));
        }
        return null;
    }
    
    pub fn stopAll(self: *SubscriptionManager) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        var iterator = self.subscriptions.iterator();
        while (iterator.next()) |entry| {
            // Stop each subscription handle using type-erased interface
            // Each subscription implements stop() method
            const subscription = entry.value_ptr.*;
            subscription.vtable.stop(subscription.ptr);
        }
    }
    
    pub fn getSubscriptionCount(self: *const SubscriptionManager) usize {
        return self.subscriptions.count();
    }
    
    pub fn getActiveSubscriptionCount(self: *SubscriptionManager) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        var count: usize = 0;
        var iterator = self.subscriptions.iterator();
        while (iterator.next()) |entry| {
            // Check if each subscription is actually active
            const subscription = entry.value_ptr.*;
            if (subscription.vtable.isActive(subscription.ptr)) {
                count += 1;
            }
        }
        return count;
    }
};

// Topic message subscription handle
pub const TopicMessageSubscription = SubscriptionHandle(@import("../topic/topic_message_query.zig").TopicMessage);

// Contract result subscription handle  
pub const ContractResultSubscription = SubscriptionHandle(@import("../mirror/contract_query.zig").ContractResult);

// Transaction subscription handle
pub const TransactionSubscription = SubscriptionHandle(@import("../query/transaction_record_query.zig").TransactionRecord);

// Generic event subscription
pub const EventSubscription = SubscriptionHandle(BlockchainEvent);

// Blockchain event for generic subscriptions
pub const BlockchainEvent = struct {
    event_type: EventType,
    timestamp: Timestamp,
    data: []const u8,
    
    pub const EventType = enum {
        transaction,
        contract_call,
        topic_message,
        token_transfer,
        account_create,
        file_update,
        
        pub fn toString(self: EventType) []const u8 {
            return switch (self) {
                .transaction => "transaction",
                .contract_call => "contract_call",
                .topic_message => "topic_message",
                .token_transfer => "token_transfer",
                .account_create => "account_create",
                .file_update => "file_update",
            };
        }
    };
    
    pub fn deinit(self: *BlockchainEvent, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }
    
    pub fn clone(self: *const BlockchainEvent, allocator: std.mem.Allocator) !BlockchainEvent {
        return BlockchainEvent{
            .event_type = self.event_type,
            .timestamp = self.timestamp,
            .data = try allocator.dupe(u8, self.data),
        };
    }
};
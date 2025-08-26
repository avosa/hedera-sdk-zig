// Extended retry mechanisms
// Provides advanced retry strategies with backoff, jitter, and circuit breaker patterns

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const Thread = std.Thread;
const Mutex = Thread.Mutex;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const AtomicBool = std.atomic.Atomic(bool);
const AtomicUsize = std.atomic.Atomic(usize);
const HederaError = @import("../core/errors.zig").HederaError;

// Retry policy configuration
pub const RetryPolicy = struct {
    max_attempts: u32,
    initial_delay_ms: u64,
    max_delay_ms: u64,
    multiplier: f64,
    jitter_type: JitterType,
    retryable_errors: []const HederaError,
    backoff_strategy: BackoffStrategy,
    deadline_ms: ?u64,
    
    pub const JitterType = enum {
        none,
        full,
        equal,
        decorrelated,
        
        pub fn applyJitter(self: JitterType, delay_ms: u64, rng: std.rand.Random) u64 {
            return switch (self) {
                .none => delay_ms,
                .full => rng.intRangeAtMost(u64, 0, delay_ms),
                .equal => delay_ms / 2 + rng.intRangeAtMost(u64, 0, delay_ms / 2),
                .decorrelated => @min(@as(u64, @intFromFloat(@as(f64, @floatFromInt(delay_ms)) * 3.0)), rng.intRangeAtMost(u64, delay_ms / 2, delay_ms * 3)),
            };
        }
    };
    
    pub const BackoffStrategy = enum {
        fixed,
        linear,
        exponential,
        fibonacci,
        custom,
        
        pub fn calculateDelay(self: BackoffStrategy, attempt: u32, initial_delay: u64, multiplier: f64, max_delay: u64) u64 {
            const delay = switch (self) {
                .fixed => initial_delay,
                .linear => initial_delay + @as(u64, @intCast(attempt - 1)) * @as(u64, @intFromFloat(initial_delay * multiplier)),
                .exponential => @min(max_delay, @as(u64, @intFromFloat(@as(f64, @floatFromInt(initial_delay)) * std.math.pow(f64, multiplier, @as(f64, @floatFromInt(attempt - 1)))))),
                .fibonacci => calculateFibonacciDelay(attempt, initial_delay),
                .custom => initial_delay, // Would be customized by caller
            };
            
            return @min(delay, max_delay);
        }
        
        fn calculateFibonacciDelay(attempt: u32, initial_delay: u64) u64 {
            if (attempt <= 2) return initial_delay;
            
            var a: u64 = 1;
            var b: u64 = 1;
            var i: u32 = 2;
            
            while (i < attempt) {
                const temp = a + b;
                a = b;
                b = temp;
                i += 1;
            }
            
            return initial_delay * b;
        }
    };
    
    pub fn init() RetryPolicy {
        const default_retryable_errors = [_]HederaError{
            HederaError.NetworkTimeout,
            HederaError.ConnectionFailed,
            HederaError.Busy,
            HederaError.RequestTimeout,
            HederaError.GrpcError,
        };
        
        return RetryPolicy{
            .max_attempts = 3,
            .initial_delay_ms = 1000,
            .max_delay_ms = 30000,
            .multiplier = 2.0,
            .jitter_type = .equal,
            .retryable_errors = &default_retryable_errors,
            .backoff_strategy = .exponential,
            .deadline_ms = null,
        };
    }
    
    pub fn withMaxAttempts(self: RetryPolicy, max_attempts: u32) RetryPolicy {
        var policy = self;
        policy.max_attempts = max_attempts;
        return policy;
    }
    
    pub fn withBackoffStrategy(self: RetryPolicy, strategy: BackoffStrategy) RetryPolicy {
        var policy = self;
        policy.backoff_strategy = strategy;
        return policy;
    }
    
    pub fn withJitter(self: RetryPolicy, jitter_type: JitterType) RetryPolicy {
        var policy = self;
        policy.jitter_type = jitter_type;
        return policy;
    }
    
    pub fn withDeadline(self: RetryPolicy, deadline_ms: u64) RetryPolicy {
        var policy = self;
        policy.deadline_ms = deadline_ms;
        return policy;
    }
    
    pub fn isRetryable(self: RetryPolicy, err: HederaError) bool {
        for (self.retryable_errors) |retryable_err| {
            if (err == retryable_err) return true;
        }
        return false;
    }
    
    pub fn calculateNextDelay(self: RetryPolicy, attempt: u32, rng: std.rand.Random) u64 {
        const base_delay = self.backoff_strategy.calculateDelay(attempt, self.initial_delay_ms, self.multiplier, self.max_delay_ms);
        return self.jitter_type.applyJitter(base_delay, rng);
    }
};

// Retry attempt information
pub const RetryAttempt = struct {
    attempt_number: u32,
    start_time: i64,
    end_time: ?i64,
    error_value: ?HederaError,
    delay_before_ms: u64,
    
    pub fn init(attempt_number: u32, delay_before_ms: u64) RetryAttempt {
        return RetryAttempt{
            .attempt_number = attempt_number,
            .start_time = std.time.milliTimestamp(),
            .end_time = null,
            .error_value = null,
            .delay_before_ms = delay_before_ms,
        };
    }
    
    pub fn complete(self: *RetryAttempt, error_value: ?HederaError) void {
        self.end_time = std.time.milliTimestamp();
        self.error_value = error_value;
    }
    
    pub fn getDuration(self: RetryAttempt) ?u64 {
        if (self.end_time) |end| {
            return @as(u64, @intCast(end - self.start_time));
        }
        return null;
    }
    
    pub fn wasSuccessful(self: RetryAttempt) bool {
        return self.error_value == null;
    }
};

// Retry context to track retry state
pub const RetryContext = struct {
    policy: RetryPolicy,
    attempts: ArrayList(RetryAttempt),
    start_time: i64,
    deadline: ?i64,
    last_error: ?HederaError,
    rng: std.rand.DefaultPrng,
    
    pub fn init(allocator: Allocator, policy: RetryPolicy) RetryContext {
        const rng = std.rand.DefaultPrng.init(@as(u64, @bitCast(std.time.milliTimestamp())));
        
        return RetryContext{
            .policy = policy,
            .attempts = ArrayList(RetryAttempt).init(allocator),
            .start_time = std.time.milliTimestamp(),
            .deadline = if (policy.deadline_ms) |deadline| std.time.milliTimestamp() + @as(i64, @intCast(deadline)) else null,
            .last_error = null,
            .rng = rng,
        };
    }
    
    pub fn deinit(self: *RetryContext) void {
        self.attempts.deinit();
    }
    
    pub fn shouldRetry(self: *RetryContext, err: HederaError) bool {
        self.last_error = err;
        
        // Check if we've exceeded max attempts
        if (self.attempts.items.len >= self.policy.max_attempts) {
            return false;
        }
        
        // Check if deadline has passed
        if (self.deadline) |deadline| {
            if (std.time.milliTimestamp() >= deadline) {
                return false;
            }
        }
        
        // Check if error is retryable
        return self.policy.isRetryable(err);
    }
    
    pub fn recordAttempt(self: *RetryContext, err: ?HederaError) !void {
        if (self.attempts.items.len > 0) {
            // Complete the last attempt
            var last_attempt = &self.attempts.items[self.attempts.items.len - 1];
            last_attempt.complete(err);
        }
    }
    
    pub fn prepareNextAttempt(self: *RetryContext) !?u64 {
        const next_attempt_number = @as(u32, @intCast(self.attempts.items.len + 1));
        
        if (next_attempt_number > self.policy.max_attempts) {
            return null;
        }
        
        // Check deadline
        if (self.deadline) |deadline| {
            if (std.time.milliTimestamp() >= deadline) {
                return null;
            }
        }
        
        const delay_ms = if (next_attempt_number == 1) 0 else self.policy.calculateNextDelay(next_attempt_number - 1, self.rng.random());
        
        const attempt = RetryAttempt.init(next_attempt_number, delay_ms);
        try self.attempts.append(attempt);
        
        return delay_ms;
    }
    
    pub fn getTotalDuration(self: RetryContext) u64 {
        return @as(u64, @intCast(std.time.milliTimestamp() - self.start_time));
    }
    
    pub fn getTotalDelayTime(self: RetryContext) u64 {
        var total: u64 = 0;
        for (self.attempts.items) |attempt| {
            total += attempt.delay_before_ms;
        }
        return total;
    }
    
    pub fn getLastError(self: RetryContext) ?HederaError {
        return self.last_error;
    }
    
    pub fn getAttemptCount(self: RetryContext) u32 {
        return @as(u32, @intCast(self.attempts.items.len));
    }
};

// Circuit breaker state
pub const CircuitBreakerState = enum {
    closed,
    open,
    half_open,
    
    pub fn toString(self: CircuitBreakerState) []const u8 {
        return switch (self) {
            .closed => "CLOSED",
            .open => "OPEN",
            .half_open => "HALF_OPEN",
        };
    }
};

// Circuit breaker configuration
pub const CircuitBreakerConfig = struct {
    failure_threshold: u32,
    success_threshold: u32,
    timeout_ms: u64,
    window_size_ms: u64,
    minimum_throughput: u32,
    failure_rate_threshold: f64,
    
    pub fn init() CircuitBreakerConfig {
        return CircuitBreakerConfig{
            .failure_threshold = 5,
            .success_threshold = 3,
            .timeout_ms = 60000, // 1 minute
            .window_size_ms = 30000, // 30 seconds
            .minimum_throughput = 10,
            .failure_rate_threshold = 0.5, // 50%
        };
    }
};

// Circuit breaker metrics
pub const CircuitBreakerMetrics = struct {
    request_count: u64,
    success_count: u64,
    failure_count: u64,
    window_start: i64,
    consecutive_failures: u32,
    consecutive_successes: u32,
    
    pub fn init() CircuitBreakerMetrics {
        return CircuitBreakerMetrics{
            .request_count = 0,
            .success_count = 0,
            .failure_count = 0,
            .window_start = std.time.milliTimestamp(),
            .consecutive_failures = 0,
            .consecutive_successes = 0,
        };
    }
    
    pub fn recordSuccess(self: *CircuitBreakerMetrics) void {
        self.request_count += 1;
        self.success_count += 1;
        self.consecutive_successes += 1;
        self.consecutive_failures = 0;
    }
    
    pub fn recordFailure(self: *CircuitBreakerMetrics) void {
        self.request_count += 1;
        self.failure_count += 1;
        self.consecutive_failures += 1;
        self.consecutive_successes = 0;
    }
    
    pub fn getFailureRate(self: CircuitBreakerMetrics) f64 {
        if (self.request_count == 0) return 0.0;
        return @as(f64, @floatFromInt(self.failure_count)) / @as(f64, @floatFromInt(self.request_count));
    }
    
    pub fn shouldResetWindow(self: CircuitBreakerMetrics, window_size_ms: u64) bool {
        const now = std.time.milliTimestamp();
        return (now - self.window_start) > @as(i64, @intCast(window_size_ms));
    }
    
    pub fn resetWindow(self: *CircuitBreakerMetrics) void {
        self.request_count = 0;
        self.success_count = 0;
        self.failure_count = 0;
        self.window_start = std.time.milliTimestamp();
        // Don't reset consecutive counters as they track across windows
    }
};

// Circuit breaker implementation
pub const CircuitBreaker = struct {
    config: CircuitBreakerConfig,
    state: CircuitBreakerState,
    metrics: CircuitBreakerMetrics,
    last_failure_time: i64,
    mutex: Mutex,
    
    pub fn init(config: CircuitBreakerConfig) CircuitBreaker {
        return CircuitBreaker{
            .config = config,
            .state = .closed,
            .metrics = CircuitBreakerMetrics.init(),
            .last_failure_time = 0,
            .mutex = Mutex{},
        };
    }
    
    pub fn canExecute(self: *CircuitBreaker) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // Reset metrics window if needed
        if (self.metrics.shouldResetWindow(self.config.window_size_ms)) {
            self.metrics.resetWindow();
        }
        
        return switch (self.state) {
            .closed => true,
            .open => {
                const now = std.time.milliTimestamp();
                if (now - self.last_failure_time > @as(i64, @intCast(self.config.timeout_ms))) {
                    self.state = .half_open;
                    return true;
                }
                return false;
            },
            .half_open => true,
        };
    }
    
    pub fn recordSuccess(self: *CircuitBreaker) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        self.metrics.recordSuccess();
        
        switch (self.state) {
            .closed => {},
            .open => {},
            .half_open => {
                if (self.metrics.consecutive_successes >= self.config.success_threshold) {
                    self.state = .closed;
                    self.metrics.consecutive_successes = 0;
                }
            },
        }
    }
    
    pub fn recordFailure(self: *CircuitBreaker) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        self.metrics.recordFailure();
        self.last_failure_time = std.time.milliTimestamp();
        
        switch (self.state) {
            .closed => {
                if (self.shouldTripCircuit()) {
                    self.state = .open;
                }
            },
            .open => {},
            .half_open => {
                self.state = .open;
            },
        }
    }
    
    pub fn getState(self: *CircuitBreaker) CircuitBreakerState {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.state;
    }
    
    pub fn getMetrics(self: *CircuitBreaker) CircuitBreakerMetrics {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.metrics;
    }
    
    pub fn reset(self: *CircuitBreaker) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        self.state = .closed;
        self.metrics = CircuitBreakerMetrics.init();
        self.last_failure_time = 0;
    }
    
    fn shouldTripCircuit(self: CircuitBreaker) bool {
        // Check minimum throughput
        if (self.metrics.request_count < self.config.minimum_throughput) {
            return false;
        }
        
        // Check consecutive failures
        if (self.metrics.consecutive_failures >= self.config.failure_threshold) {
            return true;
        }
        
        // Check failure rate
        if (self.metrics.getFailureRate() >= self.config.failure_rate_threshold) {
            return true;
        }
        
        return false;
    }
};

// Enhanced retry executor with circuit breaker
pub const RetryExecutor = struct {
    allocator: Allocator,
    circuit_breakers: HashMap([]const u8, *CircuitBreaker, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    default_circuit_breaker_config: CircuitBreakerConfig,
    mutex: Mutex,
    
    pub fn init(allocator: Allocator) RetryExecutor {
        return RetryExecutor{
            .allocator = allocator,
            .circuit_breakers = HashMap([]const u8, *CircuitBreaker, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .default_circuit_breaker_config = CircuitBreakerConfig.init(),
            .mutex = Mutex{},
        };
    }
    
    pub fn deinit(self: *RetryExecutor) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        var iter = self.circuit_breakers.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.circuit_breakers.deinit();
    }
    
    pub fn getCircuitBreaker(self: *RetryExecutor, key: []const u8) !*CircuitBreaker {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.circuit_breakers.get(key)) |breaker| {
            return breaker;
        }
        
        const breaker = try self.allocator.create(CircuitBreaker);
        breaker.* = CircuitBreaker.init(self.default_circuit_breaker_config);
        
        const key_copy = try self.allocator.dupe(u8, key);
        try self.circuit_breakers.put(key_copy, breaker);
        
        return breaker;
    }
    
    pub fn execute(
        self: *RetryExecutor,
        comptime T: type,
        operation: *const fn () anyerror!T,
        policy: RetryPolicy,
        circuit_breaker_key: ?[]const u8,
    ) !T {
        var context = RetryContext.init(self.allocator, policy);
        defer context.deinit();
        
        var circuit_breaker: ?*CircuitBreaker = null;
        if (circuit_breaker_key) |key| {
            circuit_breaker = try self.getCircuitBreaker(key);
        }
        
        while (true) {
            // Check circuit breaker
            if (circuit_breaker) |breaker| {
                if (!breaker.canExecute()) {
                    return HederaError.NetworkTimeout; // Circuit open
                }
            }
            
            const delay_ms = try context.prepareNextAttempt() orelse {
                // No more attempts allowed
                if (context.getLastError()) |last_err| {
                    return last_err;
                } else {
                    return HederaError.UnknownError;
                }
            };
            
            // Apply delay
            if (delay_ms > 0) {
                std.time.sleep(delay_ms * std.time.ns_per_ms);
            }
            
            // Execute operation
            const result = operation();
            
            if (result) |value| {
                // Success
                try context.recordAttempt(null);
                if (circuit_breaker) |breaker| {
                    breaker.recordSuccess();
                }
                return value;
            } else |err| {
                // Convert error to HederaError if possible
                const hedera_error = convertToHederaError(err);
                
                try context.recordAttempt(hedera_error);
                
                if (circuit_breaker) |breaker| {
                    breaker.recordFailure();
                }
                
                if (!context.shouldRetry(hedera_error)) {
                    return err;
                }
            }
        }
    }
    
    pub fn executeAsync(
        self: *RetryExecutor,
        comptime T: type,
        operation: *const fn () anyerror!T,
        policy: RetryPolicy,
        circuit_breaker_key: ?[]const u8,
        callback: *const fn (result: anyerror!T) void,
    ) !Thread {
        const ExecuteParams = struct {
            executor: *RetryExecutor,
            operation: *const fn () anyerror!T,
            policy: RetryPolicy,
            circuit_breaker_key: ?[]const u8,
            callback: *const fn (result: anyerror!T) void,
        };
        
        const params = ExecuteParams{
            .executor = self,
            .operation = operation,
            .policy = policy,
            .circuit_breaker_key = circuit_breaker_key,
            .callback = callback,
        };
        
        return try Thread.spawn(.{}, executeAsyncWorker, .{T, params});
    }
    
    fn executeAsyncWorker(comptime T: type, params: anytype) void {
        const result = params.executor.execute(T, params.operation, params.policy, params.circuit_breaker_key);
        params.callback(result);
    }
    
    pub fn getCircuitBreakerStats(self: *RetryExecutor, allocator: Allocator) ![]CircuitBreakerStats {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        var stats_list = ArrayList(CircuitBreakerStats).init(allocator);
        
        var iter = self.circuit_breakers.iterator();
        while (iter.next()) |entry| {
            const key = entry.key_ptr.*;
            const breaker = entry.value_ptr.*;
            
            const stats = CircuitBreakerStats{
                .key = try allocator.dupe(u8, key),
                .state = breaker.getState(),
                .metrics = breaker.getMetrics(),
            };
            
            try stats_list.append(stats);
        }
        
        return stats_list.toOwnedSlice();
    }
};

// Circuit breaker statistics
pub const CircuitBreakerStats = struct {
    key: []const u8,
    state: CircuitBreakerState,
    metrics: CircuitBreakerMetrics,
    
    pub fn deinit(self: CircuitBreakerStats, allocator: Allocator) void {
        allocator.free(self.key);
    }
};

// Helper function to convert generic errors to HederaError
fn convertToHederaError(err: anyerror) HederaError {
    // This is a simplified conversion - in practice, you'd have more sophisticated mapping
    return switch (err) {
        error.ConnectionRefused, error.NetworkUnreachable => HederaError.ConnectionFailed,
        error.Timeout => HederaError.NetworkTimeout,
        error.OutOfMemory => HederaError.OutOfMemory,
        else => HederaError.UnknownError,
    };
}

// Predefined retry policies
pub const RetryPolicies = struct {
    pub fn defaultPolicy() RetryPolicy {
        return RetryPolicy.init();
    }
    
    pub fn aggressiveRetry() RetryPolicy {
        return RetryPolicy.init()
            .withMaxAttempts(5)
            .withBackoffStrategy(.exponential)
            .withJitter(.full);
    }
    
    pub fn conservativeRetry() RetryPolicy {
        return RetryPolicy.init()
            .withMaxAttempts(2)
            .withBackoffStrategy(.linear)
            .withJitter(.none);
    }
    
    pub fn fastRetry() RetryPolicy {
        var policy = RetryPolicy.init();
        policy.initial_delay_ms = 100;
        policy.max_delay_ms = 5000;
        policy.multiplier = 1.5;
        return policy.withMaxAttempts(4).withJitter(.equal);
    }
    
    pub fn networkOptimized() RetryPolicy {
        var policy = RetryPolicy.init();
        policy.initial_delay_ms = 500;
        policy.max_delay_ms = 15000;
        policy.multiplier = 2.0;
        return policy
            .withMaxAttempts(3)
            .withBackoffStrategy(.exponential)
            .withJitter(.decorrelated);
    }
};

// Test cases
test "RetryPolicy basic configuration" {
    var policy = RetryPolicy.init();
    
    try testing.expectEqual(@as(u32, 3), policy.max_attempts);
    try testing.expectEqual(@as(u64, 1000), policy.initial_delay_ms);
    try testing.expect(policy.isRetryable(HederaError.NetworkTimeout));
    try testing.expect(!policy.isRetryable(HederaError.InvalidSignature));
    
    policy = policy.withMaxAttempts(5).withJitter(.full);
    try testing.expectEqual(@as(u32, 5), policy.max_attempts);
    try testing.expectEqual(RetryPolicy.JitterType.full, policy.jitter_type);
}

test "BackoffStrategy delay calculations" {
    const strategy = RetryPolicy.BackoffStrategy.exponential;
    
    const delay1 = strategy.calculateDelay(1, 1000, 2.0, 30000);
    const delay2 = strategy.calculateDelay(2, 1000, 2.0, 30000);
    const delay3 = strategy.calculateDelay(3, 1000, 2.0, 30000);
    
    try testing.expectEqual(@as(u64, 1000), delay1);
    try testing.expectEqual(@as(u64, 2000), delay2);
    try testing.expectEqual(@as(u64, 4000), delay3);
}

test "RetryContext attempt tracking" {
    const allocator = testing.allocator;
    
    const policy = RetryPolicy.init().withMaxAttempts(3);
    var context = RetryContext.init(allocator, policy);
    defer context.deinit();
    
    // First attempt
    const delay1 = try context.prepareNextAttempt();
    try testing.expect(delay1 != null);
    try testing.expectEqual(@as(u64, 0), delay1.?); // First attempt has no delay
    
    try context.recordAttempt(HederaError.NetworkTimeout);
    try testing.expect(context.shouldRetry(HederaError.NetworkTimeout));
    
    // Second attempt
    const delay2 = try context.prepareNextAttempt();
    try testing.expect(delay2 != null);
    try testing.expect(delay2.? > 0); // Should have delay
    
    try context.recordAttempt(HederaError.NetworkTimeout);
    try testing.expect(context.shouldRetry(HederaError.NetworkTimeout));
    
    // Third attempt
    const delay3 = try context.prepareNextAttempt();
    try testing.expect(delay3 != null);
    
    try context.recordAttempt(HederaError.NetworkTimeout);
    try testing.expect(!context.shouldRetry(HederaError.NetworkTimeout)); // Max attempts reached
}

test "CircuitBreaker state transitions" {
    const config = CircuitBreakerConfig.init();
    var breaker = CircuitBreaker.init(config);
    
    try testing.expectEqual(CircuitBreakerState.closed, breaker.getState());
    try testing.expect(breaker.canExecute());
    
    // Record failures to trip the circuit
    for (0..config.failure_threshold) |_| {
        breaker.recordFailure();
    }
    
    // Should still be closed due to minimum throughput requirement
    try testing.expectEqual(CircuitBreakerState.closed, breaker.getState());
    
    // Record enough requests to meet minimum throughput
    for (0..config.minimum_throughput) |_| {
        breaker.recordFailure();
    }
    
    try testing.expectEqual(CircuitBreakerState.open, breaker.getState());
    try testing.expect(!breaker.canExecute());
}

test "JitterType applications" {
    var rng = std.rand.DefaultPrng.init(42);
    const random = rng.random();
    
    const base_delay: u64 = 1000;
    
    const none_jitter = RetryPolicy.JitterType.none.applyJitter(base_delay, random);
    try testing.expectEqual(base_delay, none_jitter);
    
    const full_jitter = RetryPolicy.JitterType.full.applyJitter(base_delay, random);
    try testing.expect(full_jitter <= base_delay);
    
    const equal_jitter = RetryPolicy.JitterType.equal.applyJitter(base_delay, random);
    try testing.expect(equal_jitter >= base_delay / 2);
    try testing.expect(equal_jitter <= base_delay);
}
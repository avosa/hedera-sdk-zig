const std = @import("std");
const Duration = @import("../core/duration.zig").Duration;

pub const RetryConfig = struct {
    max_attempts: u32,
    min_backoff: Duration,
    max_backoff: Duration,
    backoff_multiplier: f64,
    jitter: f64,
    
    pub fn init() RetryConfig {
        return RetryConfig{
            .max_attempts = 3,
            .min_backoff = Duration.fromMillis(250),
            .max_backoff = Duration.fromSeconds(8),
            .backoff_multiplier = 2.0,
            .jitter = 0.1,
        };
    }
};
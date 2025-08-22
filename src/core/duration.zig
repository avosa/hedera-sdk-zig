const std = @import("std");

// Duration represents a time duration in seconds and nanoseconds
pub const Duration = struct {
    seconds: i64,
    nanos: i32,
    
    pub fn init(seconds: i64, nanos: i32) Duration {
        return Duration{
            .seconds = seconds,
            .nanos = nanos,
        };
    }
    
    // Create duration from seconds
    pub fn fromSeconds(seconds: i64) Duration {
        return Duration{
            .seconds = seconds,
            .nanos = 0,
        };
    }
    
    // Create duration from milliseconds
    pub fn fromMilliseconds(millis: i64) Duration {
        return Duration{
            .seconds = @divFloor(millis, 1000),
            .nanos = @intCast(@mod(millis, 1000) * 1_000_000),
        };
    }
    
    // Alias for fromMilliseconds (Go SDK compatibility)
    pub fn fromMillis(millis: i64) Duration {
        return fromMilliseconds(millis);
    }
    
    // Create duration from minutes
    pub fn fromMinutes(minutes: i64) Duration {
        return Duration{
            .seconds = minutes * 60,
            .nanos = 0,
        };
    }
    
    // Create duration from hours
    pub fn fromHours(hours: i64) Duration {
        return Duration{
            .seconds = hours * 3600,
            .nanos = 0,
        };
    }
    
    // Create duration from days
    pub fn fromDays(days: i64) Duration {
        return Duration{
            .seconds = days * 86400,
            .nanos = 0,
        };
    }
    
    // Convert to milliseconds
    pub fn toMilliseconds(self: Duration) i64 {
        return self.seconds * 1000 + @divFloor(self.nanos, 1_000_000);
    }
    
    pub fn toNanoseconds(self: Duration) i64 {
        return self.seconds * 1_000_000_000 + self.nanos;
    }
    
    // Convert to seconds
    pub fn toSeconds(self: Duration) i64 {
        return self.seconds;
    }
    
    // Convert to minutes
    pub fn toMinutes(self: Duration) f64 {
        return @as(f64, @floatFromInt(self.seconds)) / 60.0 + 
               @as(f64, @floatFromInt(self.nanos)) / (60.0 * 1_000_000_000.0);
    }
    
    // Convert to hours
    pub fn toHours(self: Duration) f64 {
        return @as(f64, @floatFromInt(self.seconds)) / 3600.0 + 
               @as(f64, @floatFromInt(self.nanos)) / (3600.0 * 1_000_000_000.0);
    }
    
    // Convert to days
    pub fn toDays(self: Duration) f64 {
        return @as(f64, @floatFromInt(self.seconds)) / 86400.0 + 
               @as(f64, @floatFromInt(self.nanos)) / (86400.0 * 1_000_000_000.0);
    }
    
    // Sums two durations together
    pub fn add(self: Duration, other: Duration) Duration {
        var total_nanos = self.nanos + other.nanos;
        var carry_seconds: i64 = 0;
        
        if (total_nanos >= 1_000_000_000) {
            carry_seconds = 1;
            total_nanos -= 1_000_000_000;
        } else if (total_nanos < 0) {
            carry_seconds = -1;
            total_nanos += 1_000_000_000;
        }
        
        return Duration{
            .seconds = self.seconds + other.seconds + carry_seconds,
            .nanos = total_nanos,
        };
    }
    
    // Subtract durations
    pub fn subtract(self: Duration, other: Duration) Duration {
        var diff_nanos = self.nanos - other.nanos;
        var borrow_seconds: i64 = 0;
        
        if (diff_nanos < 0) {
            borrow_seconds = 1;
            diff_nanos += 1_000_000_000;
        }
        
        return Duration{
            .seconds = self.seconds - other.seconds - borrow_seconds,
            .nanos = diff_nanos,
        };
    }
    
    // Check if duration is negative
    pub fn isNegative(self: Duration) bool {
        return self.seconds < 0 or (self.seconds == 0 and self.nanos < 0);
    }
    
    // Check if duration is zero
    pub fn isZero(self: Duration) bool {
        return self.seconds == 0 and self.nanos == 0;
    }
    
    // Check if duration is positive
    pub fn isPositive(self: Duration) bool {
        return self.seconds > 0 or (self.seconds == 0 and self.nanos > 0);
    }
    
    // Compare durations
    pub fn equals(self: Duration, other: Duration) bool {
        return self.seconds == other.seconds and self.nanos == other.nanos;
    }
    
    pub fn lessThan(self: Duration, other: Duration) bool {
        if (self.seconds < other.seconds) return true;
        if (self.seconds > other.seconds) return false;
        return self.nanos < other.nanos;
    }
    
    pub fn greaterThan(self: Duration, other: Duration) bool {
        if (self.seconds > other.seconds) return true;
        if (self.seconds < other.seconds) return false;
        return self.nanos > other.nanos;
    }
    
    pub fn lessThanOrEqual(self: Duration, other: Duration) bool {
        return !self.greaterThan(other);
    }
    
    pub fn greaterThanOrEqual(self: Duration, other: Duration) bool {
        return !self.lessThan(other);
    }
    
    // Absolute value
    pub fn abs(self: Duration) Duration {
        if (self.isNegative()) {
            return Duration{
                .seconds = -self.seconds,
                .nanos = -self.nanos,
            };
        }
        return self;
    }
    
    // Constants
    pub const ZERO = Duration{ .seconds = 0, .nanos = 0 };
    pub const SECOND = Duration{ .seconds = 1, .nanos = 0 };
    pub const MINUTE = Duration{ .seconds = 60, .nanos = 0 };
    pub const HOUR = Duration{ .seconds = 3600, .nanos = 0 };
    pub const DAY = Duration{ .seconds = 86400, .nanos = 0 };
    pub const WEEK = Duration{ .seconds = 604800, .nanos = 0 };
};
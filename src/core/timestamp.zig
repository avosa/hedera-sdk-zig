const std = @import("std");
const Duration = @import("duration.zig").Duration;

// Timestamp represents a point in time with nanosecond precision
pub const Timestamp = struct {
    seconds: i64,
    nanos: i32,
    
    pub fn init(seconds: i64, nanos: i32) Timestamp {
        return Timestamp{
            .seconds = seconds,
            .nanos = nanos,
        };
    }
    
    // Create timestamp from Unix seconds
    pub fn fromUnixSeconds(seconds: i64) Timestamp {
        return Timestamp{
            .seconds = seconds,
            .nanos = 0,
        };
    }
    
    // Create timestamp from Unix milliseconds
    pub fn fromUnixMilliseconds(millis: i64) Timestamp {
        return Timestamp{
            .seconds = @divFloor(millis, 1000),
            .nanos = @intCast(@mod(millis, 1000) * 1_000_000),
        };
    }
    
    // Create timestamp from Unix microseconds
    pub fn fromUnixMicroseconds(micros: i64) Timestamp {
        return Timestamp{
            .seconds = @divFloor(micros, 1_000_000),
            .nanos = @intCast(@mod(micros, 1_000_000) * 1000),
        };
    }
    
    // Create timestamp from seconds
    pub fn fromSeconds(seconds: i64) Timestamp {
        return Timestamp{
            .seconds = seconds,
            .nanos = 0,
        };
    }
    
    // Create timestamp from Unix nanoseconds
    pub fn fromUnixNanoseconds(nanos: i64) Timestamp {
        return Timestamp{
            .seconds = @divFloor(nanos, 1_000_000_000),
            .nanos = @intCast(@mod(nanos, 1_000_000_000)),
        };
    }
    
    // Get current timestamp
    pub fn now() Timestamp {
        const nanos = std.time.nanoTimestamp();
        return fromUnixNanoseconds(@intCast(nanos));
    }
    
    // Convert to Unix seconds
    pub fn toUnixSeconds(self: Timestamp) i64 {
        return self.seconds;
    }
    
    // Convert to Unix milliseconds
    pub fn toUnixMilliseconds(self: Timestamp) i64 {
        return self.seconds * 1000 + @divFloor(self.nanos, 1_000_000);
    }
    
    // Convert to Unix microseconds
    pub fn toUnixMicroseconds(self: Timestamp) i64 {
        return self.seconds * 1_000_000 + @divFloor(self.nanos, 1000);
    }
    
    // Convert to Unix nanoseconds
    pub fn toUnixNanoseconds(self: Timestamp) i64 {
        return self.seconds * 1_000_000_000 + self.nanos;
    }
    
    // Adds a duration to the timestamp
    pub fn add(self: Timestamp, duration: Duration) Timestamp {
        var total_nanos = self.nanos + duration.nanos;
        var carry_seconds: i64 = 0;
        
        if (total_nanos >= 1_000_000_000) {
            carry_seconds = 1;
            total_nanos -= 1_000_000_000;
        } else if (total_nanos < 0) {
            carry_seconds = -1;
            total_nanos += 1_000_000_000;
        }
        
        return Timestamp{
            .seconds = self.seconds + duration.seconds + carry_seconds,
            .nanos = total_nanos,
        };
    }
    
    // Subtract duration from timestamp
    pub fn subtract(self: Timestamp, duration: Duration) Timestamp {
        var diff_nanos = self.nanos - duration.nanos;
        var borrow_seconds: i64 = 0;
        
        if (diff_nanos < 0) {
            borrow_seconds = 1;
            diff_nanos += 1_000_000_000;
        }
        
        return Timestamp{
            .seconds = self.seconds - duration.seconds - borrow_seconds,
            .nanos = diff_nanos,
        };
    }
    
    // Get duration between timestamps
    pub fn durationSince(self: Timestamp, other: Timestamp) Duration {
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
    
    // Compare timestamps
    pub fn compare(self: Timestamp, other: Timestamp) std.math.Order {
        if (self.seconds < other.seconds) return .lt;
        if (self.seconds > other.seconds) return .gt;
        if (self.nanos < other.nanos) return .lt;
        if (self.nanos > other.nanos) return .gt;
        return .eq;
    }
    
    pub fn equals(self: Timestamp, other: Timestamp) bool {
        return self.seconds == other.seconds and self.nanos == other.nanos;
    }
    
    pub fn before(self: Timestamp, other: Timestamp) bool {
        if (self.seconds < other.seconds) return true;
        if (self.seconds > other.seconds) return false;
        return self.nanos < other.nanos;
    }
    
    pub fn after(self: Timestamp, other: Timestamp) bool {
        if (self.seconds > other.seconds) return true;
        if (self.seconds < other.seconds) return false;
        return self.nanos > other.nanos;
    }
    
    pub fn beforeOrEqual(self: Timestamp, other: Timestamp) bool {
        return !self.after(other);
    }
    
    pub fn afterOrEqual(self: Timestamp, other: Timestamp) bool {
        return !self.before(other);
    }
    
    // Check if timestamp is zero
    pub fn isZero(self: Timestamp) bool {
        return self.seconds == 0 and self.nanos == 0;
    }
    
    // Format timestamp as string
    pub fn toString(self: Timestamp, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{d}.{d:0>9}", .{ self.seconds, self.nanos });
    }
    
    // Parse timestamp from string
    pub fn fromString(str: []const u8) !Timestamp {
        var parts = std.mem.split(u8, str, ".");
        
        const seconds_str = parts.next() orelse return error.InvalidTimestamp;
        const seconds = try std.fmt.parseInt(i64, seconds_str, 10);
        
        var nanos: i32 = 0;
        if (parts.next()) |nanos_str| {
            // Pad or truncate to 9 digits
            var nanos_buf: [9]u8 = .{'0'} ** 9;
            const copy_len = @min(nanos_str.len, 9);
            @memcpy(nanos_buf[0..copy_len], nanos_str[0..copy_len]);
            nanos = try std.fmt.parseInt(i32, &nanos_buf, 10);
        }
        
        return Timestamp{
            .seconds = seconds,
            .nanos = nanos,
        };
    }
    
    // Constants
    pub const ZERO = Timestamp{ .seconds = 0, .nanos = 0 };
    pub const UNIX_EPOCH = Timestamp{ .seconds = 0, .nanos = 0 };
    pub const MAX = Timestamp{ .seconds = std.math.maxInt(i64), .nanos = 999_999_999 };
    pub const MIN = Timestamp{ .seconds = std.math.minInt(i64), .nanos = 0 };
};
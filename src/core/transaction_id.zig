const std = @import("std");
const AccountId = @import("id.zig").AccountId;

// Timestamp structure for transaction valid start time
pub const Timestamp = struct {
    seconds: i64,
    nanos: i32,
    
    pub fn now() Timestamp {
        const ns = std.time.nanoTimestamp();
        return Timestamp{
            .seconds = @intCast(@divFloor(ns, std.time.ns_per_s)),
            .nanos = @intCast(@mod(ns, std.time.ns_per_s)),
        };
    }
    
    pub fn fromUnixTimestamp(seconds: i64) Timestamp {
        return Timestamp{
            .seconds = seconds,
            .nanos = 0,
        };
    }
    
    pub fn plusSeconds(self: Timestamp, seconds: i64) Timestamp {
        return Timestamp{
            .seconds = self.seconds + seconds,
            .nanos = self.nanos,
        };
    }
    
    pub fn plusNanos(self: Timestamp, nanos: i32) Timestamp {
        const total_nanos = @as(i64, self.nanos) + nanos;
        const extra_seconds = @divFloor(total_nanos, std.time.ns_per_s);
        const final_nanos = @mod(total_nanos, std.time.ns_per_s);
        
        return Timestamp{
            .seconds = self.seconds + extra_seconds,
            .nanos = @intCast(final_nanos),
        };
    }
    
    pub fn toNanos(self: Timestamp) i128 {
        return @as(i128, self.seconds) * std.time.ns_per_s + self.nanos;
    }
    
    pub fn toString(self: Timestamp, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{d}.{d:0>9}", .{ self.seconds, self.nanos });
    }
    
    pub fn equals(self: Timestamp, other: Timestamp) bool {
        return self.seconds == other.seconds and self.nanos == other.nanos;
    }
    
    pub fn compare(self: Timestamp, other: Timestamp) std.math.Order {
        if (self.seconds < other.seconds) return .lt;
        if (self.seconds > other.seconds) return .gt;
        if (self.nanos < other.nanos) return .lt;
        if (self.nanos > other.nanos) return .gt;
        return .eq;
    }
};

// Duration structure for time intervals
pub const Duration = struct {
    seconds: i64,
    
    pub fn fromSeconds(seconds: i64) Duration {
        return Duration{ .seconds = seconds };
    }
    
    pub fn fromMinutes(minutes: i64) Duration {
        return Duration{ .seconds = minutes * 60 };
    }
    
    pub fn fromHours(hours: i64) Duration {
        return Duration{ .seconds = hours * 3600 };
    }
    
    pub fn fromDays(days: i64) Duration {
        return Duration{ .seconds = days * 86400 };
    }
    
    pub fn toSeconds(self: Duration) i64 {
        return self.seconds;
    }
    
    pub fn toNanos(self: Duration) i128 {
        return @as(i128, self.seconds) * std.time.ns_per_s;
    }
};

// TransactionId uniquely identifies a transaction
pub const TransactionId = struct {
    account_id: AccountId,
    valid_start: Timestamp,
    scheduled: bool = false,
    nonce: ?u32 = null,
    
    // Generate a new transaction ID for the given account
    pub fn generate(account_id: AccountId) TransactionId {
        return TransactionId{
            .account_id = account_id,
            .valid_start = Timestamp.now(),
            .scheduled = false,
            .nonce = null,
        };
    }
    
    // Generate with specific timestamp
    pub fn generateWithTimestamp(account_id: AccountId, timestamp: Timestamp) TransactionId {
        return TransactionId{
            .account_id = account_id,
            .valid_start = timestamp,
            .scheduled = false,
            .nonce = null,
        };
    }
    
    // Create a scheduled transaction ID
    pub fn generateScheduled(account_id: AccountId) TransactionId {
        return TransactionId{
            .account_id = account_id,
            .valid_start = Timestamp.now(),
            .scheduled = true,
            .nonce = null,
        };
    }
    
    // Set nonce for the transaction ID
    pub fn withNonce(self: TransactionId, nonce: u32) TransactionId {
        var new_id = self;
        new_id.nonce = nonce;
        return new_id;
    }
    
    // Parse from string format: "accountId@seconds.nanos"
    pub fn fromString(allocator: std.mem.Allocator, str: []const u8) !TransactionId {
        // Check for scheduled prefix
        var scheduled = false;
        var parse_str = str;
        
        if (std.mem.startsWith(u8, str, "scheduled-")) {
            scheduled = true;
            parse_str = str[10..];
        }
        
        // Split by @ to separate account ID and timestamp
        const at_index = std.mem.indexOf(u8, parse_str, "@") orelse return error.InvalidParameter;
        
        const account_str = parse_str[0..at_index];
        const timestamp_str = parse_str[at_index + 1 ..];
        
        // Parse account ID
        const account_id = try AccountId.fromString(allocator, account_str);
        
        // Check for nonce suffix
        var nonce: ?u32 = null;
        var time_str = timestamp_str;
        
        if (std.mem.indexOf(u8, timestamp_str, "?nonce=")) |nonce_index| {
            time_str = timestamp_str[0..nonce_index];
            const nonce_str = timestamp_str[nonce_index + 7 ..];
            nonce = try std.fmt.parseInt(u32, nonce_str, 10);
        }
        
        // Parse timestamp (seconds.nanos)
        const dot_index = std.mem.indexOf(u8, time_str, ".") orelse return error.InvalidParameter;
        
        const seconds_str = time_str[0..dot_index];
        const nanos_str = time_str[dot_index + 1 ..];
        
        const seconds = try std.fmt.parseInt(i64, seconds_str, 10);
        const nanos = try std.fmt.parseInt(i32, nanos_str, 10);
        
        return TransactionId{
            .account_id = account_id,
            .valid_start = Timestamp{
                .seconds = seconds,
                .nanos = nanos,
            },
            .scheduled = scheduled,
            .nonce = nonce,
        };
    }
    
    // Convert to string format
    pub fn toString(self: TransactionId, allocator: std.mem.Allocator) ![]u8 {
        const account_str = try self.account_id.toString(allocator);
        defer allocator.free(account_str);
        
        const timestamp_str = try self.valid_start.toString(allocator);
        defer allocator.free(timestamp_str);
        
        var result: []u8 = undefined;
        
        if (self.scheduled) {
            if (self.nonce) |n| {
                result = try std.fmt.allocPrint(allocator, "scheduled-{s}@{s}?nonce={d}", .{ account_str, timestamp_str, n });
            } else {
                result = try std.fmt.allocPrint(allocator, "scheduled-{s}@{s}", .{ account_str, timestamp_str });
            }
        } else {
            if (self.nonce) |n| {
                result = try std.fmt.allocPrint(allocator, "{s}@{s}?nonce={d}", .{ account_str, timestamp_str, n });
            } else {
                result = try std.fmt.allocPrint(allocator, "{s}@{s}", .{ account_str, timestamp_str });
            }
        }
        
        return result;
    }
    
    // Convert to bytes for hashing/signing
    pub fn toBytes(self: TransactionId, allocator: std.mem.Allocator) ![]u8 {
        var bytes = std.ArrayList(u8).init(allocator);
        defer bytes.deinit();
        
        // Write account ID bytes
        const account_bytes = try self.account_id.toBytes(allocator);
        defer allocator.free(account_bytes);
        try bytes.appendSlice(account_bytes);
        
        // Write timestamp (8 bytes seconds + 4 bytes nanos)
        var timestamp_bytes: [12]u8 = undefined;
        std.mem.writeInt(i64, timestamp_bytes[0..8], self.valid_start.seconds, .big);
        std.mem.writeInt(i32, timestamp_bytes[8..12], self.valid_start.nanos, .big);
        try bytes.appendSlice(&timestamp_bytes);
        
        // Write scheduled flag
        try bytes.append(if (self.scheduled) 1 else 0);
        
        // Write nonce if present
        if (self.nonce) |n| {
            var nonce_bytes: [4]u8 = undefined;
            std.mem.writeInt(u32, &nonce_bytes, n, .big);
            try bytes.appendSlice(&nonce_bytes);
        }
        
        return bytes.toOwnedSlice();
    }
    
    pub fn equals(self: TransactionId, other: TransactionId) bool {
        return self.account_id.equals(other.account_id) and
               self.valid_start.equals(other.valid_start) and
               self.scheduled == other.scheduled and
               self.nonce == other.nonce;
    }
    
    // Get the record ID for this transaction (used for querying transaction records)
    pub fn getRecordId(self: TransactionId) TransactionId {
        // For scheduled transactions, the record ID is the same
        // For regular transactions, clear the nonce
        var record_id = self;
        if (!self.scheduled) {
            record_id.nonce = null;
        }
        return record_id;
    }
    
    // Check if this transaction ID is valid (has required fields)
    pub fn isValid(self: TransactionId) bool {
        return !self.account_id.isZero() and self.valid_start.seconds > 0;
    }
    
    pub fn fromBytes(bytes: []const u8) !TransactionId {
        return fromProtobufBytes(std.heap.page_allocator, bytes);
    }
    
    pub fn fromProtobufBytes(allocator: std.mem.Allocator, bytes: []const u8) !TransactionId {
        var reader = @import("../protobuf/encoding.zig").ProtoReader.init(bytes);
        
        var account_bytes: []const u8 = undefined;
        var timestamp_bytes: []const u8 = undefined;
        var scheduled = false;
        var nonce: ?u32 = null;
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            switch (tag.field_number) {
                1 => account_bytes = try reader.readMessage(),
                2 => timestamp_bytes = try reader.readMessage(),
                3 => scheduled = try reader.readBool(),
                4 => nonce = @intCast(try reader.readVarint()),
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        const account_id = try AccountId.fromProtobufBytes(allocator, account_bytes);
        
        // Parse timestamp
        var ts_reader = @import("../protobuf/encoding.zig").ProtoReader.init(timestamp_bytes);
        var seconds: i64 = 0;
        var nanos: i32 = 0;
        
        while (ts_reader.hasMore()) {
            const ts_tag = try ts_reader.readTag();
            switch (ts_tag.field_number) {
                1 => seconds = try ts_reader.readInt64(),
                2 => nanos = try ts_reader.readInt32(),
                else => try ts_reader.skipField(ts_tag.wire_type),
            }
        }
        
        return TransactionId{
            .account_id = account_id,
            .valid_start = Timestamp{ .seconds = seconds, .nanos = nanos },
            .scheduled = scheduled,
            .nonce = nonce,
        };
    }
};
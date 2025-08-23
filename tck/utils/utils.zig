const std = @import("std");
const hedera = @import("hedera");
const json = std.json;

// Parse account ID from string (format: "0.0.123")
pub fn parseAccountId(allocator: std.mem.Allocator, id_str: []const u8) !hedera.AccountId {
    return try hedera.AccountId.fromString(allocator, id_str);
}

// Parse token ID from string (format: "0.0.456")
pub fn parseTokenId(allocator: std.mem.Allocator, id_str: []const u8) !hedera.TokenId {
    return try hedera.TokenId.fromString(allocator, id_str);
}

// Parse topic ID from string (format: "0.0.789")
pub fn parseTopicId(allocator: std.mem.Allocator, id_str: []const u8) !hedera.TopicId {
    return try hedera.TopicId.fromString(allocator, id_str);
}

// Parse file ID from string (format: "0.0.111")
pub fn parseFileId(allocator: std.mem.Allocator, id_str: []const u8) !hedera.FileId {
    return try hedera.FileId.fromString(allocator, id_str);
}

// Parse contract ID from string (format: "0.0.222")
pub fn parseContractId(allocator: std.mem.Allocator, id_str: []const u8) !hedera.ContractId {
    return try hedera.ContractId.fromString(allocator, id_str);
}

// Parse schedule ID from string (format: "0.0.333")
pub fn parseScheduleId(allocator: std.mem.Allocator, id_str: []const u8) !hedera.ScheduleId {
    return try hedera.ScheduleId.fromString(allocator, id_str);
}

// Parse private key from string
pub fn parsePrivateKey(allocator: std.mem.Allocator, key_str: []const u8) !hedera.PrivateKey {
    return try hedera.PrivateKey.fromString(allocator, key_str);
}

// Parse public key from string
pub fn parsePublicKey(allocator: std.mem.Allocator, key_str: []const u8) !hedera.PublicKey {
    return try hedera.PublicKey.fromString(allocator, key_str);
}

// Parse key (simplified for now - just string keys)
pub fn parseKey(allocator: std.mem.Allocator, key_value: json.Value) !hedera.Key {
    switch (key_value) {
        .string => |key_str| {
            // Try to parse as public key first
            if (hedera.PublicKey.fromString(allocator, key_str)) |pub_key| {
                return hedera.Key.fromPublicKey(pub_key);
            } else |_| {
                // Try private key
                const priv_key = try hedera.PrivateKey.fromString(allocator, key_str);
                defer priv_key.deinit();
                return hedera.Key.fromPublicKey(priv_key.getPublicKey());
            }
        },
        else => return error.InvalidKeyType,
    }
}

// Parse duration from seconds string
pub fn parseDuration(seconds_str: []const u8) !hedera.Duration {
    const seconds = try std.fmt.parseInt(i64, seconds_str, 10);
    return hedera.Duration.fromSeconds(seconds);
}

// Parse timestamp from seconds string
pub fn parseTimestamp(seconds_str: []const u8) !hedera.Timestamp {
    const seconds = try std.fmt.parseInt(i64, seconds_str, 10);
    return hedera.Timestamp.fromSeconds(seconds);
}

// Parse Hbar amount from tinybar string
pub fn parseHbar(tinybar_str: []const u8) !hedera.Hbar {
    const tinybars = try std.fmt.parseInt(i64, tinybar_str, 10);
    return hedera.Hbar.fromTinybars(tinybars);
}

// Helper to split ID string
fn splitIdString(allocator: std.mem.Allocator, id_str: []const u8) ![][]const u8 {
    var parts = std.ArrayList([]const u8).init(allocator);
    defer parts.deinit();
    
    var it = std.mem.tokenize(u8, id_str, ".");
    while (it.next()) |part| {
        try parts.append(part);
    }
    
    return try parts.toOwnedSlice();
}

// Extract string from JSON value
pub fn getString(value: json.Value, key: []const u8) ?[]const u8 {
    switch (value) {
        .object => |obj| {
            if (obj.get(key)) |v| {
                switch (v) {
                    .string => |s| return s,
                    else => return null,
                }
            }
        },
        else => {},
    }
    return null;
}

// Extract integer from JSON value
pub fn getInt(value: json.Value, key: []const u8) ?i64 {
    switch (value) {
        .object => |obj| {
            if (obj.get(key)) |v| {
                switch (v) {
                    .integer => |i| return i,
                    else => return null,
                }
            }
        },
        else => {},
    }
    return null;
}

// Extract boolean from JSON value
pub fn getBool(value: json.Value, key: []const u8) ?bool {
    switch (value) {
        .object => |obj| {
            if (obj.get(key)) |v| {
                switch (v) {
                    .bool => |b| return b,
                    else => return null,
                }
            }
        },
        else => {},
    }
    return null;
}

// Create response with status and additional fields
pub fn createResponse(allocator: std.mem.Allocator, status: []const u8, fields: ?json.ObjectMap) !json.Value {
    var response_obj = json.ObjectMap.init(allocator);
    
    // Add status field
    try response_obj.put("status", json.Value{ .string = try allocator.dupe(u8, status) });
    
    // Add additional fields if provided
    if (fields) |field_map| {
        var iterator = field_map.iterator();
        while (iterator.next()) |entry| {
            try response_obj.put(entry.key_ptr.*, entry.value_ptr.*);
        }
    }
    
    return json.Value{ .object = response_obj };
}
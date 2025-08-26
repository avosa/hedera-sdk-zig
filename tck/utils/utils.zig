const std = @import("std");
const hedera = @import("hedera");
const json = std.json;
pub fn parseAccountId(allocator: std.mem.Allocator, id_str: []const u8) !hedera.AccountId {
    return try hedera.AccountId.fromString(allocator, id_str);
}
pub fn parseTokenId(allocator: std.mem.Allocator, id_str: []const u8) !hedera.TokenId {
    return try hedera.TokenId.fromString(allocator, id_str);
}
pub fn parseTopicId(allocator: std.mem.Allocator, id_str: []const u8) !hedera.TopicId {
    return try hedera.TopicId.fromString(allocator, id_str);
}
pub fn parseFileId(allocator: std.mem.Allocator, id_str: []const u8) !hedera.FileId {
    return try hedera.FileId.fromString(allocator, id_str);
}
pub fn parseContractId(allocator: std.mem.Allocator, id_str: []const u8) !hedera.ContractId {
    return try hedera.ContractId.fromString(allocator, id_str);
}
pub fn parseScheduleId(allocator: std.mem.Allocator, id_str: []const u8) !hedera.ScheduleId {
    return try hedera.ScheduleId.fromString(allocator, id_str);
}
pub fn parsePrivateKey(allocator: std.mem.Allocator, key_str: []const u8) !hedera.PrivateKey {
    return try hedera.PrivateKey.fromString(allocator, key_str);
}
pub fn parsePublicKey(allocator: std.mem.Allocator, key_str: []const u8) !hedera.PublicKey {
    return try hedera.PublicKey.fromString(allocator, key_str);
}
pub fn parseKey(allocator: std.mem.Allocator, key_str: []const u8) !hedera.Key {
    if (hedera.PublicKey.fromString(allocator, key_str)) |pub_key| {
        return hedera.Key.fromPublicKey(pub_key);
    } else |_| {
        var priv_key = try hedera.PrivateKey.fromString(allocator, key_str);
        defer priv_key.deinit();
        return hedera.Key.fromPublicKey(priv_key.getPublicKey());
    }
}
pub fn parseDuration(seconds_str: []const u8) !hedera.Duration {
    const seconds = try std.fmt.parseInt(i64, seconds_str, 10);
    return hedera.Duration.fromSeconds(seconds);
}
pub fn parseTimestamp(seconds_str: []const u8) !hedera.Timestamp {
    const seconds = try std.fmt.parseInt(i64, seconds_str, 10);
    return hedera.Timestamp.fromSeconds(seconds);
}
pub fn parseHbar(tinybar_str: []const u8) !hedera.Hbar {
    const tinybars = try std.fmt.parseInt(i64, tinybar_str, 10);
    return try hedera.Hbar.fromTinybars(tinybars);
}
fn splitIdString(allocator: std.mem.Allocator, id_str: []const u8) ![][]const u8 {
    var parts = std.ArrayList([]const u8).init(allocator);
    defer parts.deinit();
    var it = std.mem.tokenize(u8, id_str, ".");
    while (it.next()) |part| {
        try parts.append(part);
    }
    return try parts.toOwnedSlice();
}
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
pub fn createResponse(allocator: std.mem.Allocator, status: []const u8, fields: ?json.ObjectMap) !json.Value {
    var response_obj = json.ObjectMap.init(allocator);
    try response_obj.put("status", json.Value{ .string = try allocator.dupe(u8, status) });
    if (fields) |field_map| {
        var iterator = field_map.iterator();
        while (iterator.next()) |entry| {
            try response_obj.put(entry.key_ptr.*, entry.value_ptr.*);
        }
    }
    return json.Value{ .object = response_obj };
}
pub fn createErrorMap(allocator: std.mem.Allocator, message: []const u8) !json.ObjectMap {
    var error_map = json.ObjectMap.init(allocator);
    try error_map.put("error", json.Value{ .string = message });
    return error_map;
}
pub fn getStringParam(value: json.Value, key: []const u8) ![]const u8 {
    if (value.object.get(key)) |param| {
        switch (param) {
            .string => |s| return s,
            else => return error.InvalidParameterType,
        }
    }
    return error.MissingParameter;
}
pub fn getOptionalStringParam(value: json.Value, key: []const u8) !?[]const u8 {
    if (value.object.get(key)) |param| {
        switch (param) {
            .string => |s| return s,
            .null => return null,
            else => return error.InvalidParameterType,
        }
    }
    return null;
}
pub fn getNumberParam(value: json.Value, key: []const u8) !i64 {
    if (value.object.get(key)) |param| {
        switch (param) {
            .integer => |i| return i,
            .float => |f| return @intFromFloat(f),
            else => return error.InvalidParameterType,
        }
    }
    return error.MissingParameter;
}
pub fn getOptionalNumberParam(value: json.Value, key: []const u8) !?i64 {
    if (value.object.get(key)) |param| {
        switch (param) {
            .integer => |i| return i,
            .float => |f| return @intFromFloat(f),
            .null => return null,
            else => return error.InvalidParameterType,
        }
    }
    return null;
}
pub fn getBoolParam(value: json.Value, key: []const u8) !bool {
    if (value.object.get(key)) |param| {
        switch (param) {
            .bool => |b| return b,
            else => return error.InvalidParameterType,
        }
    }
    return error.MissingParameter;
}
pub fn getOptionalBoolParam(value: json.Value, key: []const u8) !?bool {
    if (value.object.get(key)) |param| {
        switch (param) {
            .bool => |b| return b,
            .null => return null,
            else => return error.InvalidParameterType,
        }
    }
    return null;
}
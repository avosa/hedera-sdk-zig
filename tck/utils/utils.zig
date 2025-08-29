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

// Apply common transaction parameters to any transaction
pub fn applyCommonTransactionParams(tx: anytype, params: json.Value, allocator: std.mem.Allocator) !void {
    // Set transaction ID if provided
    if (getString(params, "transactionId")) |tx_id_str| {
        const tx_id = try parseTransactionId(allocator, tx_id_str);
        _ = tx.setTransactionId(tx_id) catch |err| {
            std.log.warn("Failed to set transaction ID: {}", .{err});
        };
    }
    
    // Set transaction memo if provided
    if (getString(params, "transactionMemo")) |memo| {
        _ = tx.setTransactionMemo(memo) catch |err| {
            std.log.warn("Failed to set transaction memo: {}", .{err});
        };
    }
    
    // Set max transaction fee if provided
    if (getString(params, "maxTransactionFee")) |fee_str| {
        const fee = try parseHbar(fee_str);
        _ = tx.setMaxTransactionFee(fee) catch |err| {
            std.log.warn("Failed to set max transaction fee: {}", .{err});
        };
    }
    
    // Set transaction valid duration if provided
    if (getString(params, "transactionValidDuration")) |duration_str| {
        const duration = try parseDuration(duration_str);
        _ = tx.setTransactionValidDuration(duration) catch |err| {
            std.log.warn("Failed to set transaction valid duration: {}", .{err});
        };
    }
    
    // Set node account IDs if provided
    if (params.object.get("nodeAccountIds")) |node_ids_value| {
        if (node_ids_value == .array) {
            var node_ids = std.ArrayList(hedera.AccountId).init(allocator);
            defer node_ids.deinit();
            
            for (node_ids_value.array.items) |node_id_value| {
                if (node_id_value == .string) {
                    const node_id = try parseAccountId(allocator, node_id_value.string);
                    try node_ids.append(node_id);
                }
            }
            
            if (node_ids.items.len > 0) {
                _ = tx.setNodeAccountIds(node_ids.items) catch |err| {
                    std.log.warn("Failed to set node account IDs: {}", .{err});
                };
            }
        }
    }
    
    // Set gRPC deadline if provided
    if (getString(params, "grpcDeadline")) |deadline_str| {
        const deadline = try parseDuration(deadline_str);
        _ = tx.setGrpcDeadline(deadline) catch |err| {
            std.log.warn("Failed to set gRPC deadline: {}", .{err});
        };
    }
    
    // Set regenerate transaction ID if provided
    if (getBool(params, "regenerateTransactionId")) |regenerate| {
        _ = tx.setRegenerateTransactionId(regenerate) catch |err| {
            std.log.warn("Failed to set regenerate transaction ID: {}", .{err});
        };
    }
}

pub fn parseTransactionId(allocator: std.mem.Allocator, tx_id_str: []const u8) !hedera.TransactionId {
    // Parse format: "0.0.123@1234567890.123456789"
    var parts = std.mem.splitScalar(u8, tx_id_str, '@');
    const account_str = parts.next() orelse return error.InvalidTransactionId;
    const timestamp_str = parts.next() orelse return error.InvalidTransactionId;
    
    const account_id = try parseAccountId(allocator, account_str);
    
    // Parse timestamp directly
    var time_parts = std.mem.splitScalar(u8, timestamp_str, '.');
    const seconds_str = time_parts.next() orelse return error.InvalidTimestamp;
    const nanos_str = time_parts.next() orelse "0";
    
    const seconds = try std.fmt.parseInt(i64, seconds_str, 10);
    const nanos = try std.fmt.parseInt(i32, nanos_str, 10);
    
    // Use the generate function and then modify the timestamp
    var tx_id = hedera.TransactionId.generate(account_id);
    tx_id.valid_start.seconds = seconds;
    tx_id.valid_start.nanos = nanos;
    
    return tx_id;
}


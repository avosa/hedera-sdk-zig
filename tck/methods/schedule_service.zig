const std = @import("std");
const hedera = @import("hedera");
const json = std.json;
const utils = @import("../utils/utils.zig");
pub fn createSchedule(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    if (client == null) {
        return json.Value{ .object = try utils.createErrorMap(allocator, "Client not configured") };
    }
    const p = params orelse return json.Value{ .object = try utils.createErrorMap(allocator, "Invalid parameters") };
    const transaction_bytes = try utils.getStringParam(p, "transactionBytes");
    const memo = try utils.getOptionalStringParam(p, "memo");
    const admin_key = try utils.getOptionalStringParam(p, "adminKey");
    const payer_account_id = try utils.getOptionalStringParam(p, "payerAccountId");
    const expiration_time = try utils.getOptionalNumberParam(p, "expirationTime");
    const wait_for_expiry = try utils.getOptionalBoolParam(p, "waitForExpiry");
    var tx = hedera.ScheduleCreateTransaction.init(allocator);
    defer tx.deinit();
    const decoded_size = std.base64.standard.Decoder.calcSizeForSlice(transaction_bytes) catch return error.InvalidBase64;
    const decoded = try allocator.alloc(u8, decoded_size);
    defer allocator.free(decoded);
    _ = try std.base64.standard.Decoder.decode(decoded, transaction_bytes);
    if (memo) |m| {
        _ = try tx.setScheduleMemo(m);
    }
    if (admin_key) |key_str| {
        const key = try utils.parseKey(allocator, key_str);
        _ = try tx.setAdminKey(key);
    }
    if (payer_account_id) |payer_str| {
        const payer = try hedera.AccountId.fromString(allocator, payer_str);
        _ = try tx.setPayerAccountId(payer);
    }
    if (expiration_time) |exp_time| {
        const timestamp = hedera.Timestamp{ .seconds = @intCast(exp_time), .nanos = 0 };
        _ = try tx.setExpirationTime(timestamp);
    }
    if (wait_for_expiry) |wait| {
        _ = try tx.setWaitForExpiry(wait);
    }
    var response = try tx.execute(client.?);
    defer response.deinit();
    var receipt = try response.getReceipt(client.?);
    defer receipt.deinit();
    if (receipt.schedule_id) |schedule_id| {
        var result = std.json.ObjectMap.init(allocator);
        try result.put("scheduleId", json.Value{ .string = try schedule_id.toString(allocator) });
        try result.put("status", json.Value{ .string = @tagName(receipt.status) });
        return json.Value{ .object = result };
    }
    return json.Value{ .object = try utils.createErrorMap(allocator, "Failed to create schedule") };
}
pub fn signSchedule(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    if (client == null) {
        return json.Value{ .object = try utils.createErrorMap(allocator, "Client not configured") };
    }
    const p = params orelse return json.Value{ .object = try utils.createErrorMap(allocator, "Invalid parameters") };
    const schedule_id = try utils.getStringParam(p, "scheduleId");
    var tx = hedera.ScheduleSignTransaction.init(allocator);
    defer tx.deinit();
    const sid = try hedera.ScheduleId.fromString(allocator, schedule_id);
    _ = try tx.setScheduleId(sid);
    var response = try tx.execute(client.?);
    defer response.deinit();
    var receipt = try response.getReceipt(client.?);
    defer receipt.deinit();
    var result = std.json.ObjectMap.init(allocator);
    try result.put("status", json.Value{ .string = @tagName(receipt.status) });
    return json.Value{ .object = result };
}
pub fn deleteSchedule(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    if (client == null) {
        return json.Value{ .object = try utils.createErrorMap(allocator, "Client not configured") };
    }
    const p = params orelse return json.Value{ .object = try utils.createErrorMap(allocator, "Invalid parameters") };
    const schedule_id = try utils.getStringParam(p, "scheduleId");
    var tx = hedera.ScheduleDeleteTransaction.init(allocator);
    defer tx.deinit();
    const sid = try hedera.ScheduleId.fromString(allocator, schedule_id);
    _ = try tx.setScheduleId(sid);
    var response = try tx.execute(client.?);
    defer response.deinit();
    var receipt = try response.getReceipt(client.?);
    defer receipt.deinit();
    var result = std.json.ObjectMap.init(allocator);
    try result.put("status", json.Value{ .string = @tagName(receipt.status) });
    return json.Value{ .object = result };
}
pub fn getScheduleInfo(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    if (client == null) {
        return json.Value{ .object = try utils.createErrorMap(allocator, "Client not configured") };
    }
    const p = params orelse return json.Value{ .object = try utils.createErrorMap(allocator, "Invalid parameters") };
    const schedule_id = try utils.getStringParam(p, "scheduleId");
    var query = hedera.ScheduleInfoQuery.init(allocator);
    defer query.deinit();
    const sid = try hedera.ScheduleId.fromString(allocator, schedule_id);
    _ = try query.setScheduleId(sid);
    var info = try query.execute(client.?);
    defer info.deinit();
    var result = std.json.ObjectMap.init(allocator);
    try result.put("scheduleId", json.Value{ .string = try info.schedule_id.toString(allocator) });
    if (info.memo.len > 0) {
        try result.put("memo", json.Value{ .string = info.memo });
    }
    try result.put("creatorAccountId", json.Value{ .string = try info.creator_account_id.toString(allocator) });
    try result.put("payerAccountId", json.Value{ .string = try info.payer_account_id.toString(allocator) });
    if (info.admin_key) |key| {
        try result.put("adminKey", json.Value{ .string = try key.toString(allocator) });
    }
    if (info.executed_at) |exec_time| {
        try result.put("executedAt", json.Value{ .integer = @intCast(exec_time.seconds) });
    }
    if (info.deleted_at) |del_time| {
        try result.put("deletedAt", json.Value{ .integer = @intCast(del_time.seconds) });
    }
    try result.put("expirationTime", json.Value{ .integer = @intCast(info.expiration_time.seconds) });
    return json.Value{ .object = result };
}
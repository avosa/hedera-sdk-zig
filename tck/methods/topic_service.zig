const std = @import("std");
const hedera = @import("hedera");
const json = std.json;
const utils = @import("../utils/utils.zig");
const log = std.log.scoped(.topic_service);
pub fn createTopic(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    const c = client orelse return error.ClientNotConfigured;
    const p = params orelse return error.MissingParams;
    var tx = try hedera.topicCreateTransaction(allocator);
    defer tx.deinit();
    if (utils.getString(p, "adminKey")) |key_str| {
        var private_key = try utils.parsePrivateKey(allocator, key_str);
        defer private_key.deinit();
        const key = hedera.Key.fromPublicKey(private_key.getPublicKey());
        _ = try tx.setAdminKey(key);
    }
    if (utils.getString(p, "submitKey")) |key_str| {
        var private_key = try utils.parsePrivateKey(allocator, key_str);
        defer private_key.deinit();
        const key = hedera.Key.fromPublicKey(private_key.getPublicKey());
        _ = try tx.setSubmitKey(key);
    }
    if (utils.getString(p, "memo")) |memo| {
        _ = try tx.setTopicMemo(memo);
    }
    if (utils.getString(p, "autoRenewPeriod")) |period_str| {
        const duration = try utils.parseDuration(period_str);
        _ = try tx.setAutoRenewPeriod(duration);
    }
    if (utils.getString(p, "autoRenewAccount")) |account_str| {
        const account = try utils.parseAccountId(allocator, account_str);
        _ = try tx.setAutoRenewAccountId(account);
    }
    _ = try tx.freezeWith(c);
    var tx_response = try tx.execute(c);
    const receipt = try tx_response.getReceipt(c);
    var response_fields = json.ObjectMap.init(allocator);
    defer response_fields.deinit();
    if (receipt.topic_id) |topic_id| {
        const topic_id_str = try std.fmt.allocPrint(allocator, "{}", .{topic_id});
        try response_fields.put("topicId", json.Value{ .string = try allocator.dupe(u8, topic_id_str) });
        allocator.free(topic_id_str);
    }
    return try utils.createResponse(allocator, "SUCCESS", response_fields);
}
pub fn updateTopic(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    const c = client orelse return error.ClientNotConfigured;
    const p = params orelse return error.MissingParams;
    
    const topic_id_str = utils.getString(p, "topicId") orelse return error.MissingTopicId;
    const topic_id = try utils.parseTopicId(allocator, topic_id_str);
    
    var tx = try hedera.topicUpdateTransaction(allocator);
    defer tx.deinit();
    
    _ = try tx.setTopicId(topic_id);
    
    if (utils.getString(p, "adminKey")) |key_str| {
        var private_key = try utils.parsePrivateKey(allocator, key_str);
        defer private_key.deinit();
        const key = hedera.Key.fromPublicKey(private_key.getPublicKey());
        _ = try tx.setAdminKey(key);
    }
    
    if (utils.getString(p, "submitKey")) |key_str| {
        var private_key = try utils.parsePrivateKey(allocator, key_str);
        defer private_key.deinit();
        const key = hedera.Key.fromPublicKey(private_key.getPublicKey());
        _ = try tx.setSubmitKey(key);
    }
    
    if (utils.getString(p, "memo")) |memo| {
        _ = try tx.setTopicMemo(memo);
    }
    
    if (utils.getString(p, "expirationTime")) |exp_str| {
        const timestamp = try utils.parseTimestamp(exp_str);
        _ = try tx.setExpirationTime(timestamp);
    }
    
    if (utils.getString(p, "autoRenewPeriod")) |period_str| {
        const duration = try utils.parseDuration(period_str);
        _ = try tx.setAutoRenewPeriod(duration);
    }
    
    if (utils.getString(p, "autoRenewAccountId")) |account_str| {
        const account = try utils.parseAccountId(allocator, account_str);
        _ = try tx.setAutoRenewAccountId(account);
    }
    
    _ = try tx.freezeWith(c);
    var tx_response = try tx.execute(c);
    _ = try tx_response.getReceipt(c);
    
    return try utils.createResponse(allocator, "SUCCESS", null);
}
pub fn deleteTopic(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    const c = client orelse return error.ClientNotConfigured;
    const p = params orelse return error.MissingParams;
    
    const topic_id_str = utils.getString(p, "topicId") orelse return error.MissingTopicId;
    const topic_id = try utils.parseTopicId(allocator, topic_id_str);
    
    var tx = try hedera.topicDeleteTransaction(allocator);
    defer tx.deinit();
    
    _ = try tx.setTopicId(topic_id);
    
    _ = try tx.freezeWith(c);
    var tx_response = try tx.execute(c);
    _ = try tx_response.getReceipt(c);
    
    return try utils.createResponse(allocator, "SUCCESS", null);
}
pub fn submitTopicMessage(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    const c = client orelse return error.ClientNotConfigured;
    const p = params orelse return error.MissingParams;
    
    const topic_id_str = utils.getString(p, "topicId") orelse return error.MissingTopicId;
    const topic_id = try utils.parseTopicId(allocator, topic_id_str);
    
    var tx = hedera.topicMessageSubmitTransaction(allocator);
    defer tx.deinit();
    
    _ = try tx.setTopicId(topic_id);
    
    if (utils.getString(p, "message")) |message_base64| {
        const decoder = std.base64.standard.Decoder;
        const decoded_len = try decoder.calcSizeForSlice(message_base64);
        const decoded = try allocator.alloc(u8, decoded_len);
        defer allocator.free(decoded);
        _ = try decoder.decode(decoded, message_base64);
        _ = try tx.setMessage(decoded);
    }
    
    _ = try tx.freezeWith(c);
    var tx_response = try tx.execute(c);
    const receipt = try tx_response.getReceipt(c);
    
    var response_fields = json.ObjectMap.init(allocator);
    defer response_fields.deinit();
    
    if (receipt.topic_sequence_number > 0) {
        try response_fields.put("sequenceNumber", json.Value{ .integer = @intCast(receipt.topic_sequence_number) });
    }
    
    return try utils.createResponse(allocator, "SUCCESS", response_fields);
}
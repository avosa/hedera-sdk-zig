const std = @import("std");
const hedera = @import("hedera");
const json = std.json;
const utils = @import("../utils/utils.zig");
const log = std.log.scoped(.file_service);
pub fn createFile(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    const c = client orelse return error.ClientNotConfigured;
    const p = params orelse return error.MissingParams;
    var tx = hedera.fileCreateTransaction(allocator);
    defer tx.deinit();
    if (utils.getString(p, "keys")) |key_str| {
        var private_key = try utils.parsePrivateKey(allocator, key_str);
        defer private_key.deinit();
        const key = hedera.Key.fromPublicKey(private_key.getPublicKey());
        _ = try tx.setKeys(key);
    }
    if (utils.getString(p, "contents")) |contents_base64| {
        const decoder = std.base64.standard.Decoder;
        const decoded_len = try decoder.calcSizeForSlice(contents_base64);
        const decoded = try allocator.alloc(u8, decoded_len);
        defer allocator.free(decoded);
        _ = try decoder.decode(decoded, contents_base64);
        _ = try tx.setContents(decoded);
    }
    if (utils.getString(p, "expirationTime")) |exp_str| {
        const timestamp = try utils.parseTimestamp(exp_str);
        _ = try tx.setExpirationTime(timestamp);
    }
    if (utils.getString(p, "memo")) |memo| {
        _ = try tx.setMemo(memo);
    }
    _ = try tx.freezeWith(c);
    var tx_response = try tx.execute(c);
    const receipt = try tx_response.getReceipt(c);
    var response_fields = json.ObjectMap.init(allocator);
    defer response_fields.deinit();
    if (receipt.file_id) |file_id| {
        const file_id_str = try std.fmt.allocPrint(allocator, "{}", .{file_id});
        try response_fields.put("fileId", json.Value{ .string = try allocator.dupe(u8, file_id_str) });
        allocator.free(file_id_str);
    }
    return try utils.createResponse(allocator, "SUCCESS", response_fields);
}
pub fn updateFile(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    const c = client orelse return error.ClientNotConfigured;
    const p = params orelse return error.MissingParams;
    
    const file_id_str = utils.getString(p, "fileId") orelse return error.MissingFileId;
    const file_id = try utils.parseFileId(allocator, file_id_str);
    
    var tx = hedera.fileUpdateTransaction(allocator);
    defer tx.deinit();
    
    _ = try tx.setFileId(file_id);
    
    if (utils.getString(p, "keys")) |key_str| {
        var private_key = try utils.parsePrivateKey(allocator, key_str);
        defer private_key.deinit();
        const key = hedera.Key.fromPublicKey(private_key.getPublicKey());
        _ = try tx.setKeys(key);
    }
    
    if (utils.getString(p, "contents")) |contents_base64| {
        const decoder = std.base64.standard.Decoder;
        const decoded_len = try decoder.calcSizeForSlice(contents_base64);
        const decoded = try allocator.alloc(u8, decoded_len);
        defer allocator.free(decoded);
        _ = try decoder.decode(decoded, contents_base64);
        _ = try tx.setContents(decoded);
    }
    
    if (utils.getString(p, "expirationTime")) |exp_str| {
        const timestamp = try utils.parseTimestamp(exp_str);
        _ = try tx.setExpirationTime(timestamp);
    }
    
    if (utils.getString(p, "memo")) |memo| {
        _ = try tx.setMemo(memo);
    }
    
    _ = try tx.base.freezeWith(c);
    var tx_response = try tx.execute(c);
    _ = try tx_response.getReceipt(c);
    
    return try utils.createResponse(allocator, "SUCCESS", null);
}
pub fn deleteFile(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    const c = client orelse return error.ClientNotConfigured;
    const p = params orelse return error.MissingParams;
    
    const file_id_str = utils.getString(p, "fileId") orelse return error.MissingFileId;
    const file_id = try utils.parseFileId(allocator, file_id_str);
    
    var tx = hedera.fileDeleteTransaction(allocator);
    defer tx.deinit();
    
    _ = try tx.setFileId(file_id);
    
    _ = try tx.base.freezeWith(c);
    var tx_response = try tx.execute(c);
    _ = try tx_response.getReceipt(c);
    
    return try utils.createResponse(allocator, "SUCCESS", null);
}
pub fn appendFile(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    const c = client orelse return error.ClientNotConfigured;
    const p = params orelse return error.MissingParams;
    
    const file_id_str = utils.getString(p, "fileId") orelse return error.MissingFileId;
    const file_id = try utils.parseFileId(allocator, file_id_str);
    
    var tx = hedera.fileAppendTransaction(allocator);
    defer tx.deinit();
    
    _ = try tx.setFileId(file_id);
    
    if (utils.getString(p, "contents")) |contents_base64| {
        const decoder = std.base64.standard.Decoder;
        const decoded_len = try decoder.calcSizeForSlice(contents_base64);
        const decoded = try allocator.alloc(u8, decoded_len);
        defer allocator.free(decoded);
        _ = try decoder.decode(decoded, contents_base64);
        _ = try tx.setContents(decoded);
    }
    
    _ = try tx.base.freezeWith(c);
    var tx_response = try tx.execute(c);
    _ = try tx_response.getReceipt(c);
    
    return try utils.createResponse(allocator, "SUCCESS", null);
}
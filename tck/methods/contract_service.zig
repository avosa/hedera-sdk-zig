const std = @import("std");
const hedera = @import("hedera");
const json = std.json;
const utils = @import("../utils/utils.zig");
const log = std.log.scoped(.contract_service);
pub fn createContract(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    const c = client orelse return error.ClientNotConfigured;
    const p = params orelse return error.MissingParams;
    var tx = hedera.ContractCreateTransaction.init(allocator);
    defer tx.deinit();
    if (utils.getString(p, "bytecodeFileId")) |file_id_str| {
        const file_id = try utils.parseFileId(allocator, file_id_str);
        _ = try tx.setBytecodeFileId(file_id);
    } else if (utils.getString(p, "bytecode")) |bytecode_hex| {
        const bytecode_len = bytecode_hex.len / 2;
        const bytecode = try allocator.alloc(u8, bytecode_len);
        defer allocator.free(bytecode);
        _ = try std.fmt.hexToBytes(bytecode, bytecode_hex);
        _ = try tx.setBytecode(bytecode);
    }
    if (utils.getString(p, "adminKey")) |key_str| {
        var private_key = try utils.parsePrivateKey(allocator, key_str);
        defer private_key.deinit();
        const key = hedera.Key.fromPublicKey(private_key.getPublicKey());
        _ = try tx.setAdminKey(key);
    }
    if (utils.getInt(p, "gas")) |gas| {
        _ = try tx.setGas(@intCast(gas));
    }
    if (utils.getString(p, "initialBalance")) |balance_str| {
        const hbar = try utils.parseHbar(balance_str);
        _ = try tx.setInitialBalance(hbar);
    }
    if (utils.getString(p, "constructorParameters")) |params_hex| {
        const params_len = params_hex.len / 2;
        const params_bytes = try allocator.alloc(u8, params_len);
        defer allocator.free(params_bytes);
        _ = try std.fmt.hexToBytes(params_bytes, params_hex);
        _ = try tx.setConstructorParameters(params_bytes);
    }
    if (utils.getString(p, "memo")) |memo| {
        _ = try tx.setContractMemo(memo);
    }
    if (utils.getString(p, "autoRenewPeriod")) |period_str| {
        const duration = try utils.parseDuration(period_str);
        _ = try tx.setAutoRenewPeriod(duration);
    }
    _ = try tx.freezeWith(c);
    var tx_response = try tx.execute(c);
    const receipt = try tx_response.getReceipt(c);
    var response_fields = json.ObjectMap.init(allocator);
    defer response_fields.deinit();
    if (receipt.contract_id) |contract_id| {
        const contract_id_str = try std.fmt.allocPrint(allocator, "{}", .{contract_id});
        try response_fields.put("contractId", json.Value{ .string = try allocator.dupe(u8, contract_id_str) });
        allocator.free(contract_id_str);
    }
    return try utils.createResponse(allocator, "SUCCESS", response_fields);
}
pub fn updateContract(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    _ = client;
    _ = params;
    return try utils.createResponse(allocator, "NOT_IMPLEMENTED", null);
}
pub fn deleteContract(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    _ = client;
    _ = params;
    return try utils.createResponse(allocator, "NOT_IMPLEMENTED", null);
}
pub fn executeContract(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    _ = client;
    _ = params;
    return try utils.createResponse(allocator, "NOT_IMPLEMENTED", null);
}
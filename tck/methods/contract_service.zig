const std = @import("std");
const hedera = @import("hedera");
const json = std.json;
const utils = @import("../utils/utils.zig");

const log = std.log.scoped(.contract_service);

pub fn createContract(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    const c = client orelse return error.ClientNotConfigured;
    const p = params orelse return error.MissingParams;
    
    // Create transaction
    var tx = hedera.newContractCreateTransaction(allocator);
    defer tx.deinit();
    
    // Set bytecode (from file or direct)
    if (utils.getString(p, "bytecodeFileId")) |file_id_str| {
        const file_id = try utils.parseFileId(allocator, file_id_str);
        _ = try tx.setBytecodeFileId(file_id);
    } else if (utils.getString(p, "bytecode")) |bytecode_hex| {
        // Convert hex string to bytes
        const bytecode_len = bytecode_hex.len / 2;
        const bytecode = try allocator.alloc(u8, bytecode_len);
        defer allocator.free(bytecode);
        _ = try std.fmt.hexToBytes(bytecode, bytecode_hex);
        _ = try tx.setBytecode(bytecode);
    }
    
    // Set admin key
    if (utils.getString(p, "adminKey")) |key_str| {
        var private_key = try utils.parsePrivateKey(allocator, key_str);
        defer private_key.deinit();
        const key = hedera.Key.fromPublicKey(private_key.getPublicKey());
        _ = try tx.setAdminKey(key);
    }
    
    // Set gas
    if (utils.getInt(p, "gas")) |gas| {
        _ = try tx.setGas(@intCast(gas));
    }
    
    // Set initial balance
    if (utils.getString(p, "initialBalance")) |balance_str| {
        const hbar = try utils.parseHbar(balance_str);
        _ = try tx.setInitialBalance(hbar);
    }
    
    // Set constructor parameters
    if (utils.getString(p, "constructorParameters")) |params_hex| {
        // Convert hex string to bytes
        const params_len = params_hex.len / 2;
        const params_bytes = try allocator.alloc(u8, params_len);
        defer allocator.free(params_bytes);
        _ = try std.fmt.hexToBytes(params_bytes, params_hex);
        _ = try tx.setConstructorParameters(params_bytes);
    }
    
    // Set memo
    if (utils.getString(p, "memo")) |memo| {
        _ = try tx.setMemo(memo);
    }
    
    // Set auto renew period
    if (utils.getString(p, "autoRenewPeriod")) |period_str| {
        const duration = try utils.parseDuration(period_str);
        _ = try tx.setAutoRenewPeriod(duration);
    }
    
    // Execute transaction
    try tx.freezeWith(c);
    const tx_response = try tx.execute(c);
    const receipt = try tx_response.getReceipt(c);
    
    // Build response
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
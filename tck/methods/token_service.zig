const std = @import("std");
const hedera = @import("hedera");
const json = std.json;
const utils = @import("../utils/utils.zig");
const log = std.log.scoped(.token_service);
pub fn createToken(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    const c = client orelse return error.ClientNotConfigured;
    const p = params orelse return error.MissingParams;
    var tx = hedera.tokenCreateTransaction(allocator);
    defer tx.deinit();
    if (utils.getString(p, "name")) |name| {
        _ = try tx.setTokenName(name);
    }
    if (utils.getString(p, "symbol")) |symbol| {
        _ = try tx.setTokenSymbol(symbol);
    }
    if (utils.getInt(p, "decimals")) |decimals| {
        _ = try tx.setDecimals(@intCast(decimals));
    }
    if (utils.getInt(p, "initialSupply")) |supply| {
        _ = try tx.setInitialSupply(@intCast(supply));
    }
    if (utils.getString(p, "treasuryAccountId")) |treasury_str| {
        const treasury = try utils.parseAccountId(allocator, treasury_str);
        _ = try tx.setTreasuryAccountId(treasury);
    }
    if (utils.getString(p, "adminKey")) |key_str| {
        var private_key = try utils.parsePrivateKey(allocator, key_str);
        defer private_key.deinit();
        const key = hedera.Key.fromPublicKey(private_key.getPublicKey());
        _ = try tx.setAdminKey(key);
    }
    if (utils.getString(p, "kycKey")) |key_str| {
        var private_key = try utils.parsePrivateKey(allocator, key_str);
        defer private_key.deinit();
        const key = hedera.Key.fromPublicKey(private_key.getPublicKey());
        _ = try tx.setKycKey(key);
    }
    if (utils.getString(p, "freezeKey")) |key_str| {
        var private_key = try utils.parsePrivateKey(allocator, key_str);
        defer private_key.deinit();
        const key = hedera.Key.fromPublicKey(private_key.getPublicKey());
        _ = try tx.setFreezeKey(key);
    }
    if (utils.getString(p, "wipeKey")) |key_str| {
        var private_key = try utils.parsePrivateKey(allocator, key_str);
        defer private_key.deinit();
        const key = hedera.Key.fromPublicKey(private_key.getPublicKey());
        _ = try tx.setWipeKey(key);
    }
    if (utils.getString(p, "supplyKey")) |key_str| {
        var private_key = try utils.parsePrivateKey(allocator, key_str);
        defer private_key.deinit();
        const key = hedera.Key.fromPublicKey(private_key.getPublicKey());
        _ = try tx.setSupplyKey(key);
    }
    if (utils.getBool(p, "freezeDefault")) |freeze_default| {
        _ = try tx.setFreezeDefault(freeze_default);
    }
    if (utils.getString(p, "autoRenewPeriod")) |period_str| {
        const duration = try utils.parseDuration(period_str);
        _ = try tx.setAutoRenewPeriod(duration);
    }
    if (utils.getString(p, "memo")) |memo| {
        _ = try tx.setTokenMemo(memo);
    }
    if (utils.getString(p, "tokenType")) |type_str| {
        const token_type = if (std.mem.eql(u8, type_str, "nft")) 
            hedera.TokenType.non_fungible_unique 
        else 
            hedera.TokenType.fungible_common;
        _ = try tx.setTokenType(token_type);
    }
    if (utils.getString(p, "supplyType")) |type_str| {
        const supply_type = if (std.mem.eql(u8, type_str, "finite"))
            hedera.TokenSupplyType.finite
        else
            hedera.TokenSupplyType.infinite;
        _ = try tx.setSupplyType(supply_type);
    }
    if (utils.getInt(p, "maxSupply")) |max_supply| {
        _ = try tx.setMaxSupply(max_supply);
    }
    _ = try tx.freezeWith(c);
    var tx_response = try tx.execute(c);
    const receipt = try tx_response.getReceipt(c);
    
    var response_fields = json.ObjectMap.init(allocator);
    defer response_fields.deinit();
    
    if (receipt.token_id) |token_id| {
        const token_id_str = try std.fmt.allocPrint(allocator, "{}", .{token_id});
        defer allocator.free(token_id_str);
        try response_fields.put("tokenId", json.Value{ .string = try allocator.dupe(u8, token_id_str) });
    }
    
    try response_fields.put("status", json.Value{ .string = @tagName(receipt.status) });
    
    return try utils.createResponse(allocator, "SUCCESS", response_fields);
}
pub fn updateToken(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    _ = client;
    _ = params;
    return try utils.createResponse(allocator, "NOT_IMPLEMENTED", null);
}
pub fn deleteToken(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    _ = client;
    _ = params;
    return try utils.createResponse(allocator, "NOT_IMPLEMENTED", null);
}
pub fn updateTokenFeeSchedule(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    _ = client;
    _ = params;
    return try utils.createResponse(allocator, "NOT_IMPLEMENTED", null);
}
pub fn associateToken(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    _ = client;
    _ = params;
    return try utils.createResponse(allocator, "NOT_IMPLEMENTED", null);
}
pub fn dissociateToken(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    _ = client;
    _ = params;
    return try utils.createResponse(allocator, "NOT_IMPLEMENTED", null);
}
pub fn pauseToken(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    _ = client;
    _ = params;
    return try utils.createResponse(allocator, "NOT_IMPLEMENTED", null);
}
pub fn unpauseToken(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    _ = client;
    _ = params;
    return try utils.createResponse(allocator, "NOT_IMPLEMENTED", null);
}
pub fn freezeToken(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    _ = client;
    _ = params;
    return try utils.createResponse(allocator, "NOT_IMPLEMENTED", null);
}
pub fn unfreezeToken(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    _ = client;
    _ = params;
    return try utils.createResponse(allocator, "NOT_IMPLEMENTED", null);
}
pub fn grantTokenKyc(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    _ = client;
    _ = params;
    return try utils.createResponse(allocator, "NOT_IMPLEMENTED", null);
}
pub fn revokeTokenKyc(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    _ = client;
    _ = params;
    return try utils.createResponse(allocator, "NOT_IMPLEMENTED", null);
}
pub fn mintToken(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    _ = client;
    _ = params;
    return try utils.createResponse(allocator, "NOT_IMPLEMENTED", null);
}
pub fn burnToken(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    _ = client;
    _ = params;
    return try utils.createResponse(allocator, "NOT_IMPLEMENTED", null);
}
pub fn wipeToken(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    _ = client;
    _ = params;
    return try utils.createResponse(allocator, "NOT_IMPLEMENTED", null);
}
pub fn claimToken(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    _ = client;
    _ = params;
    return try utils.createResponse(allocator, "NOT_IMPLEMENTED", null);
}
pub fn airdropToken(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    _ = client;
    _ = params;
    return try utils.createResponse(allocator, "NOT_IMPLEMENTED", null);
}
pub fn cancelAirdrop(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    _ = client;
    _ = params;
    return try utils.createResponse(allocator, "NOT_IMPLEMENTED", null);
}
pub fn rejectToken(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    _ = client;
    _ = params;
    return try utils.createResponse(allocator, "NOT_IMPLEMENTED", null);
}
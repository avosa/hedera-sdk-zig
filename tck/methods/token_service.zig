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
    
    // Apply common transaction parameters
    if (utils.getString(p, "transactionMemo")) |memo| {
        _ = tx.setTransactionMemo(memo) catch {};
    }
    if (utils.getString(p, "maxTransactionFee")) |fee_str| {
        const fee = utils.parseHbar(fee_str) catch hedera.Hbar.zero();
        _ = tx.setMaxTransactionFee(fee) catch {};
    }
    if (utils.getString(p, "grpcDeadline")) |deadline_str| {
        const deadline = utils.parseDuration(deadline_str) catch hedera.Duration.fromSeconds(30);
        _ = tx.setGrpcDeadline(deadline) catch {};
    }
    if (utils.getBool(p, "regenerateTransactionId")) |regenerate| {
        _ = tx.setRegenerateTransactionId(regenerate) catch {};
    }
    
    _ = try tx.base.freezeWith(c);
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
    const c = client orelse return error.ClientNotConfigured;
    const p = params orelse return error.MissingParams;
    
    const token_id_str = utils.getString(p, "tokenId") orelse return error.MissingTokenId;
    const token_id = try utils.parseTokenId(allocator, token_id_str);
    
    var tx = hedera.tokenUpdateTransaction(allocator);
    defer tx.deinit();
    
    _ = try tx.setTokenId(token_id);
    
    if (utils.getString(p, "symbol")) |symbol| {
        _ = try tx.setTokenSymbol(symbol);
    }
    
    if (utils.getString(p, "name")) |name| {
        _ = try tx.setTokenName(name);
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
    
    if (utils.getString(p, "autoRenewAccountId")) |auto_renew_str| {
        const auto_renew = try utils.parseAccountId(allocator, auto_renew_str);
        _ = try tx.setAutoRenewAccount(auto_renew);
    }
    
    if (utils.getString(p, "autoRenewPeriod")) |period_str| {
        const duration = try utils.parseDuration(period_str);
        _ = try tx.setAutoRenewPeriod(duration);
    }
    
    if (utils.getString(p, "expirationTime")) |exp_str| {
        const timestamp = try utils.parseTimestamp(exp_str);
        _ = try tx.setExpirationTime(timestamp);
    }
    
    if (utils.getString(p, "memo")) |memo| {
        _ = try tx.setTokenMemo(memo);
    }
    
    if (utils.getString(p, "feeScheduleKey")) |key_str| {
        var private_key = try utils.parsePrivateKey(allocator, key_str);
        defer private_key.deinit();
        const key = hedera.Key.fromPublicKey(private_key.getPublicKey());
        _ = try tx.setFeeScheduleKey(key);
    }
    
    if (utils.getString(p, "pauseKey")) |key_str| {
        var private_key = try utils.parsePrivateKey(allocator, key_str);
        defer private_key.deinit();
        const key = hedera.Key.fromPublicKey(private_key.getPublicKey());
        _ = try tx.setPauseKey(key);
    }
    
    if (utils.getString(p, "metadata")) |metadata| {
        _ = try tx.setMetadata(metadata);
    }
    
    if (utils.getString(p, "metadataKey")) |key_str| {
        var private_key = try utils.parsePrivateKey(allocator, key_str);
        defer private_key.deinit();
        const key = hedera.Key.fromPublicKey(private_key.getPublicKey());
        _ = try tx.setMetadataKey(key);
    }
    
    _ = try tx.base.freezeWith(c);
    var tx_response = try tx.execute(c);
    _ = try tx_response.getReceipt(c);
    
    return try utils.createResponse(allocator, "SUCCESS", null);
}
pub fn deleteToken(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    const c = client orelse return error.ClientNotConfigured;
    const p = params orelse return error.MissingParams;
    
    const token_id_str = utils.getString(p, "tokenId") orelse return error.MissingTokenId;
    const token_id = try utils.parseTokenId(allocator, token_id_str);
    
    var tx = hedera.tokenDeleteTransaction(allocator);
    defer tx.deinit();
    
    _ = try tx.setTokenId(token_id);
    
    _ = try tx.base.freezeWith(c);
    var tx_response = try tx.execute(c);
    _ = try tx_response.getReceipt(c);
    
    return try utils.createResponse(allocator, "SUCCESS", null);
}
pub fn updateTokenFeeSchedule(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    const c = client orelse return error.ClientNotConfigured;
    const p = params orelse return error.MissingParams;
    
    const token_id_str = utils.getString(p, "tokenId") orelse return error.MissingTokenId;
    const token_id = try utils.parseTokenId(allocator, token_id_str);
    
    var tx = hedera.tokenFeeScheduleUpdateTransaction(allocator);
    defer tx.deinit();
    
    _ = try tx.setTokenId(token_id);
    
    if (p.object.get("customFees")) |custom_fees| {
        for (custom_fees.array.items) |fee| {
            const fee_collector_str = utils.getString(fee, "feeCollectorAccountId") orelse continue;
            const fee_collector = try utils.parseAccountId(allocator, fee_collector_str);
            
            if (fee.object.get("fixedFee")) |fixed| {
                const amount = utils.getInt(fixed, "amount") orelse 0;
                const hbar_amount = try hedera.Hbar.fromTinybars(amount);
                var custom_fee = hedera.CustomFixedFee.init();
                _ = try custom_fee.setAmount(@intCast(hbar_amount.toTinybars()));
                _ = try custom_fee.setFeeCollectorAccountId(fee_collector);
                _ = try tx.addCustomFee(hedera.CustomFee{ .fixed = custom_fee });
            } else if (fee.object.get("fractionalFee")) |fractional| {
                const numerator = utils.getInt(fractional, "numerator") orelse 0;
                const denominator = utils.getInt(fractional, "denominator") orelse 1;
                const min = utils.getInt(fractional, "minimumAmount") orelse 0;
                const max = utils.getInt(fractional, "maximumAmount") orelse 0;
                var custom_fee = hedera.CustomFractionalFee.init();
                _ = try custom_fee.setNumerator(@intCast(numerator));
                _ = try custom_fee.setDenominator(@intCast(denominator));
                _ = try custom_fee.setMinimumAmount(@intCast(min));
                _ = try custom_fee.setMaximumAmount(@intCast(max));
                _ = try custom_fee.setFeeCollectorAccountId(fee_collector);
                _ = try tx.addCustomFee(hedera.CustomFee{ .fractional = custom_fee });
            }
        }
    }
    
    _ = try tx.base.freezeWith(c);
    var tx_response = try tx.execute(c);
    _ = try tx_response.getReceipt(c);
    
    return try utils.createResponse(allocator, "SUCCESS", null);
}
pub fn associateToken(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    const c = client orelse return error.ClientNotConfigured;
    const p = params orelse return error.MissingParams;
    
    const account_id_str = utils.getString(p, "accountId") orelse return error.MissingAccountId;
    const account_id = try utils.parseAccountId(allocator, account_id_str);
    
    var tx = hedera.tokenAssociateTransaction(allocator);
    defer tx.deinit();
    
    _ = try tx.setAccountId(account_id);
    
    if (p.object.get("tokenIds")) |token_ids| {
        for (token_ids.array.items) |token_str| {
            const token_id = try utils.parseTokenId(allocator, token_str.string);
            _ = try tx.addTokenId(token_id);
        }
    }
    
    _ = try tx.base.freezeWith(c);
    var tx_response = try tx.execute(c);
    _ = try tx_response.getReceipt(c);
    
    return try utils.createResponse(allocator, "SUCCESS", null);
}
pub fn dissociateToken(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    const c = client orelse return error.ClientNotConfigured;
    const p = params orelse return error.MissingParams;
    
    const account_id_str = utils.getString(p, "accountId") orelse return error.MissingAccountId;
    const account_id = try utils.parseAccountId(allocator, account_id_str);
    
    var tx = hedera.tokenDissociateTransaction(allocator);
    defer tx.deinit();
    
    _ = try tx.setAccountId(account_id);
    
    if (p.object.get("tokenIds")) |token_ids| {
        for (token_ids.array.items) |token_str| {
            const token_id = try utils.parseTokenId(allocator, token_str.string);
            _ = try tx.addTokenId(token_id);
        }
    }
    
    _ = try tx.base.freezeWith(c);
    var tx_response = try tx.execute(c);
    _ = try tx_response.getReceipt(c);
    
    return try utils.createResponse(allocator, "SUCCESS", null);
}
pub fn pauseToken(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    const c = client orelse return error.ClientNotConfigured;
    const p = params orelse return error.MissingParams;
    
    const token_id_str = utils.getString(p, "tokenId") orelse return error.MissingTokenId;
    const token_id = try utils.parseTokenId(allocator, token_id_str);
    
    var tx = hedera.tokenPauseTransaction(allocator);
    defer tx.deinit();
    
    _ = try tx.setTokenId(token_id);
    
    _ = try tx.base.freezeWith(c);
    var tx_response = try tx.execute(c);
    _ = try tx_response.getReceipt(c);
    
    return try utils.createResponse(allocator, "SUCCESS", null);
}
pub fn unpauseToken(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    const c = client orelse return error.ClientNotConfigured;
    const p = params orelse return error.MissingParams;
    
    const token_id_str = utils.getString(p, "tokenId") orelse return error.MissingTokenId;
    const token_id = try utils.parseTokenId(allocator, token_id_str);
    
    var tx = hedera.tokenUnpauseTransaction(allocator);
    defer tx.deinit();
    
    _ = try tx.setTokenId(token_id);
    
    _ = try tx.base.freezeWith(c);
    var tx_response = try tx.execute(c);
    _ = try tx_response.getReceipt(c);
    
    return try utils.createResponse(allocator, "SUCCESS", null);
}
pub fn freezeToken(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    const c = client orelse return error.ClientNotConfigured;
    const p = params orelse return error.MissingParams;
    
    const token_id_str = utils.getString(p, "tokenId") orelse return error.MissingTokenId;
    const token_id = try utils.parseTokenId(allocator, token_id_str);
    
    const account_id_str = utils.getString(p, "accountId") orelse return error.MissingAccountId;
    const account_id = try utils.parseAccountId(allocator, account_id_str);
    
    var tx = hedera.tokenFreezeTransaction(allocator);
    defer tx.deinit();
    
    _ = try tx.setTokenId(token_id);
    _ = try tx.setAccountId(account_id);
    
    _ = try tx.base.freezeWith(c);
    var tx_response = try tx.execute(c);
    _ = try tx_response.getReceipt(c);
    
    return try utils.createResponse(allocator, "SUCCESS", null);
}
pub fn unfreezeToken(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    const c = client orelse return error.ClientNotConfigured;
    const p = params orelse return error.MissingParams;
    
    const token_id_str = utils.getString(p, "tokenId") orelse return error.MissingTokenId;
    const token_id = try utils.parseTokenId(allocator, token_id_str);
    
    const account_id_str = utils.getString(p, "accountId") orelse return error.MissingAccountId;
    const account_id = try utils.parseAccountId(allocator, account_id_str);
    
    var tx = hedera.tokenUnfreezeTransaction(allocator);
    defer tx.deinit();
    
    _ = try tx.setTokenId(token_id);
    _ = try tx.setAccountId(account_id);
    
    _ = try tx.base.freezeWith(c);
    var tx_response = try tx.execute(c);
    _ = try tx_response.getReceipt(c);
    
    return try utils.createResponse(allocator, "SUCCESS", null);
}
pub fn grantTokenKyc(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    const c = client orelse return error.ClientNotConfigured;
    const p = params orelse return error.MissingParams;
    
    const token_id_str = utils.getString(p, "tokenId") orelse return error.MissingTokenId;
    const token_id = try utils.parseTokenId(allocator, token_id_str);
    
    const account_id_str = utils.getString(p, "accountId") orelse return error.MissingAccountId;
    const account_id = try utils.parseAccountId(allocator, account_id_str);
    
    var tx = hedera.tokenGrantKycTransaction(allocator);
    defer tx.deinit();
    
    _ = try tx.setTokenId(token_id);
    _ = try tx.setAccountId(account_id);
    
    _ = try tx.base.freezeWith(c);
    var tx_response = try tx.execute(c);
    _ = try tx_response.getReceipt(c);
    
    return try utils.createResponse(allocator, "SUCCESS", null);
}
pub fn revokeTokenKyc(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    const c = client orelse return error.ClientNotConfigured;
    const p = params orelse return error.MissingParams;
    
    const token_id_str = utils.getString(p, "tokenId") orelse return error.MissingTokenId;
    const token_id = try utils.parseTokenId(allocator, token_id_str);
    
    const account_id_str = utils.getString(p, "accountId") orelse return error.MissingAccountId;
    const account_id = try utils.parseAccountId(allocator, account_id_str);
    
    var tx = hedera.tokenRevokeKycTransaction(allocator);
    defer tx.deinit();
    
    _ = try tx.setTokenId(token_id);
    _ = try tx.setAccountId(account_id);
    
    _ = try tx.base.freezeWith(c);
    var tx_response = try tx.execute(c);
    _ = try tx_response.getReceipt(c);
    
    return try utils.createResponse(allocator, "SUCCESS", null);
}
pub fn mintToken(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    const c = client orelse return error.ClientNotConfigured;
    const p = params orelse return error.MissingParams;
    
    const token_id_str = utils.getString(p, "tokenId") orelse return error.MissingTokenId;
    const token_id = try utils.parseTokenId(allocator, token_id_str);
    
    var tx = hedera.tokenMintTransaction(allocator);
    defer tx.deinit();
    
    _ = try tx.setTokenId(token_id);
    
    if (utils.getInt(p, "amount")) |amount| {
        _ = try tx.setAmount(@intCast(amount));
    }
    
    if (p.object.get("metadata")) |metadata_array| {
        for (metadata_array.array.items) |metadata| {
            _ = try tx.addMetadata(metadata.string);
        }
    }
    
    _ = try tx.base.freezeWith(c);
    var tx_response = try tx.execute(c);
    const receipt = try tx_response.getReceipt(c);
    
    var response_fields = json.ObjectMap.init(allocator);
    defer response_fields.deinit();
    
    if (receipt.serial_numbers.len > 0) {
        var serial_array = std.ArrayList(json.Value).init(allocator);
        defer serial_array.deinit();
        for (receipt.serial_numbers) |serial| {
            try serial_array.append(json.Value{ .integer = @intCast(serial) });
        }
        try response_fields.put("serialNumbers", json.Value{ .array = serial_array });
    }
    
    return try utils.createResponse(allocator, "SUCCESS", response_fields);
}
pub fn burnToken(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    const c = client orelse return error.ClientNotConfigured;
    const p = params orelse return error.MissingParams;
    
    const token_id_str = utils.getString(p, "tokenId") orelse return error.MissingTokenId;
    const token_id = try utils.parseTokenId(allocator, token_id_str);
    
    var tx = hedera.tokenBurnTransaction(allocator);
    defer tx.deinit();
    
    _ = try tx.setTokenId(token_id);
    
    if (utils.getInt(p, "amount")) |amount| {
        _ = try tx.setAmount(@intCast(amount));
    }
    
    if (p.object.get("serialNumbers")) |serial_array| {
        for (serial_array.array.items) |serial| {
            _ = try tx.addSerialNumber(@intCast(serial.integer));
        }
    }
    
    _ = try tx.base.freezeWith(c);
    var tx_response = try tx.execute(c);
    _ = try tx_response.getReceipt(c);
    
    return try utils.createResponse(allocator, "SUCCESS", null);
}
pub fn wipeToken(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    const c = client orelse return error.ClientNotConfigured;
    const p = params orelse return error.MissingParams;
    
    const token_id_str = utils.getString(p, "tokenId") orelse return error.MissingTokenId;
    const token_id = try utils.parseTokenId(allocator, token_id_str);
    
    const account_id_str = utils.getString(p, "accountId") orelse return error.MissingAccountId;
    const account_id = try utils.parseAccountId(allocator, account_id_str);
    
    var tx = hedera.tokenWipeTransaction(allocator);
    defer tx.deinit();
    
    _ = try tx.setTokenId(token_id);
    _ = try tx.setAccountId(account_id);
    
    if (utils.getInt(p, "amount")) |amount| {
        _ = try tx.setAmount(@intCast(amount));
    }
    
    if (p.object.get("serialNumbers")) |serial_array| {
        for (serial_array.array.items) |serial| {
            _ = try tx.addSerialNumber(@intCast(serial.integer));
        }
    }
    
    _ = try tx.base.freezeWith(c);
    var tx_response = try tx.execute(c);
    _ = try tx_response.getReceipt(c);
    
    return try utils.createResponse(allocator, "SUCCESS", null);
}
pub fn claimToken(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    _ = client;
    _ = params;
    return try utils.createResponse(allocator, "METHOD_NOT_FULLY_IMPLEMENTED", null);
}
pub fn airdropToken(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    const c = client orelse return error.ClientNotConfigured;
    const p = params orelse return error.MissingParams;
    
    var tx = hedera.tokenAirdropTransaction(allocator);
    defer tx.deinit();
    
    if (p.object.get("tokenTransfers")) |transfers| {
        for (transfers.array.items) |transfer| {
            const token_str = utils.getString(transfer, "tokenId") orelse continue;
            const account_str = utils.getString(transfer, "accountId") orelse continue;
            const amount_int = utils.getInt(transfer, "amount") orelse continue;
            _ = utils.getInt(transfer, "expectedDecimals");
            
            const token_id = try utils.parseTokenId(allocator, token_str);
            const account_id = try utils.parseAccountId(allocator, account_str);
            
            _ = try tx.addTokenTransfer(token_id, account_id, @as(i64, @intCast(amount_int)));
        }
    }
    
    if (p.object.get("nftTransfers")) |transfers| {
        for (transfers.array.items) |transfer| {
            const token_str = utils.getString(transfer, "tokenId") orelse continue;
            const sender_str = utils.getString(transfer, "senderAccountId") orelse continue;
            const receiver_str = utils.getString(transfer, "receiverAccountId") orelse continue;
            const serial_int = utils.getInt(transfer, "serialNumber") orelse continue;
            
            const token_id = try utils.parseTokenId(allocator, token_str);
            _ = try utils.parseAccountId(allocator, sender_str);
            const receiver = try utils.parseAccountId(allocator, receiver_str);
            const nft_id = hedera.NftId.init(token_id, @intCast(serial_int));
            
            _ = try tx.addNftTransfer(nft_id, receiver);
        }
    }
    
    _ = try tx.base.freezeWith(c);
    var tx_response = try tx.execute(c);
    _ = try tx_response.getReceipt(c);
    
    return try utils.createResponse(allocator, "SUCCESS", null);
}
pub fn cancelAirdrop(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    _ = client;
    _ = params;
    return try utils.createResponse(allocator, "METHOD_NOT_FULLY_IMPLEMENTED", null);
}
pub fn rejectToken(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    const c = client orelse return error.ClientNotConfigured;
    const p = params orelse return error.MissingParams;
    
    var tx = hedera.tokenRejectTransaction(allocator);
    defer tx.deinit();
    
    const owner_str = utils.getString(p, "ownerId");
    if (owner_str) |owner| {
        const owner_id = try utils.parseAccountId(allocator, owner);
        _ = try tx.setOwnerId(owner_id);
    }
    
    if (p.object.get("tokenIds")) |token_ids| {
        for (token_ids.array.items) |token_str| {
            const token_id = try utils.parseTokenId(allocator, token_str.string);
            _ = try tx.addTokenId(token_id);
        }
    }
    
    if (p.object.get("nftIds")) |nft_ids| {
        for (nft_ids.array.items) |nft| {
            const token_str = utils.getString(nft, "tokenId") orelse continue;
            const serial = utils.getInt(nft, "serialNumber") orelse continue;
            const token_id = try utils.parseTokenId(allocator, token_str);
            const nft_id = hedera.NftId.init(token_id, @intCast(serial));
            _ = try tx.addNftId(nft_id);
        }
    }
    
    _ = try tx.base.freezeWith(c);
    var tx_response = try tx.execute(c);
    _ = try tx_response.getReceipt(c);
    
    return try utils.createResponse(allocator, "SUCCESS", null);
}
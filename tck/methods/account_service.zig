const std = @import("std");
const hedera = @import("hedera");
const json = std.json;
const utils = @import("../utils/utils.zig");
const log = std.log.scoped(.account_service);
pub fn createAccount(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    const c = client orelse return error.ClientNotConfigured;
    const p = params orelse return error.MissingParams;
    var tx = hedera.accountCreateTransaction(allocator);
    defer tx.deinit();
    if (utils.getString(p, "key")) |key_str| {
        if (utils.parsePublicKey(allocator, key_str)) |_public_key| {
            var public_key = _public_key;
            defer public_key.deinit(allocator);
            const key = hedera.Key.fromPublicKey(public_key);
            _ = try tx.setKey(key);
        } else |_| {
            var private_key = try utils.parsePrivateKey(allocator, key_str);
            defer private_key.deinit();
            const key = hedera.Key.fromPublicKey(private_key.getPublicKey());
            _ = try tx.setKey(key);
        }
    }
    if (utils.getString(p, "initialBalance")) |balance_str| {
        const hbar = try utils.parseHbar(balance_str);
        _ = try tx.setInitialBalance(hbar);
    }
    if (utils.getBool(p, "receiverSignatureRequired")) |required| {
        _ = try tx.setReceiverSignatureRequired(required);
    }
    if (utils.getInt(p, "maxAutomaticTokenAssociations")) |max_associations| {
        _ = try tx.setMaxAutomaticTokenAssociations(@intCast(max_associations));
    }
    if (utils.getString(p, "stakedAccountId")) |staked_account_str| {
        const staked_account = try utils.parseAccountId(allocator, staked_account_str);
        _ = try tx.setStakedAccountId(staked_account);
    }
    if (utils.getInt(p, "stakedNodeId")) |staked_node| {
        _ = try tx.setStakedNodeId(@intCast(staked_node));
    }
    if (utils.getBool(p, "declineStakingReward")) |decline| {
        _ = try tx.setDeclineStakingReward(decline);
    }
    if (utils.getString(p, "memo")) |memo| {
        _ = try tx.setAccountMemo(memo);
    }
    if (utils.getString(p, "autoRenewPeriod")) |period_str| {
        const duration = try utils.parseDuration(period_str);
        _ = try tx.setAutoRenewPeriod(duration);
    }
    if (utils.getString(p, "alias")) |alias_str| {
        _ = try tx.setAlias(alias_str);
    }
    _ = try tx.freezeWith(c);
    var tx_response = try tx.execute(c);
    const receipt = try tx_response.getReceipt(c);
    var response_fields = json.ObjectMap.init(allocator);
    defer response_fields.deinit();
    if (receipt.account_id) |account_id| {
        const account_id_str = try std.fmt.allocPrint(allocator, "{}", .{account_id});
        defer allocator.free(account_id_str);
        try response_fields.put("accountId", json.Value{ .string = try allocator.dupe(u8, account_id_str) });
    }
    return try utils.createResponse(allocator, "SUCCESS", response_fields);
}
pub fn updateAccount(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    const c = client orelse return error.ClientNotConfigured;
    const p = params orelse return error.MissingParams;
    const account_id_str = utils.getString(p, "accountId") orelse return error.MissingAccountId;
    const account_id = try utils.parseAccountId(allocator, account_id_str);
    var tx = hedera.accountUpdateTransaction(allocator);
    defer tx.deinit();
    _ = try tx.setAccountId(account_id);
    if (utils.getString(p, "key")) |key_str| {
        var private_key = try utils.parsePrivateKey(allocator, key_str);
        defer private_key.deinit();
        const key = hedera.Key.fromPublicKey(private_key.getPublicKey());
        _ = try tx.setKey(key);
    }
    if (utils.getString(p, "expirationTime")) |exp_str| {
        const timestamp = try utils.parseTimestamp(exp_str);
        _ = try tx.setExpirationTime(timestamp);
    }
    if (utils.getBool(p, "receiverSignatureRequired")) |required| {
        _ = try tx.setReceiverSignatureRequired(required);
    }
    if (utils.getInt(p, "maxAutomaticTokenAssociations")) |max_associations| {
        _ = try tx.setMaxAutomaticTokenAssociations(@intCast(max_associations));
    }
    if (utils.getString(p, "stakedAccountId")) |staked_account_str| {
        const staked_account = try utils.parseAccountId(allocator, staked_account_str);
        _ = try tx.setStakedAccountId(staked_account);
    }
    if (utils.getInt(p, "stakedNodeId")) |staked_node| {
        _ = try tx.setStakedNodeId(@intCast(staked_node));
    }
    if (utils.getBool(p, "declineStakingReward")) |decline| {
        _ = try tx.setDeclineStakingReward(decline);
    }
    if (utils.getString(p, "memo")) |memo| {
        _ = try tx.setAccountMemo(memo);
    }
    if (utils.getString(p, "autoRenewPeriod")) |period_str| {
        const duration = try utils.parseDuration(period_str);
        _ = try tx.setAutoRenewPeriod(duration);
    }
    _ = try tx.freezeWith(c);
    var tx_response = try tx.execute(c);
    _ = try tx_response.getReceipt(c);
    return try utils.createResponse(allocator, "SUCCESS", null);
}
pub fn deleteAccount(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    const c = client orelse return error.ClientNotConfigured;
    const p = params orelse return error.MissingParams;
    const account_id_str = utils.getString(p, "deleteAccountId") orelse return error.MissingAccountId;
    const account_id = try utils.parseAccountId(allocator, account_id_str);
    const transfer_id_str = utils.getString(p, "transferAccountId") orelse return error.MissingTransferAccountId;
    const transfer_id = try utils.parseAccountId(allocator, transfer_id_str);
    var tx = hedera.accountDeleteTransaction(allocator);
    defer tx.deinit();
    _ = try tx.setAccountId(account_id);
    _ = try tx.setTransferAccountId(transfer_id);
    _ = try tx.freezeWith(c);
    var tx_response = try tx.execute(c);
    _ = try tx_response.getReceipt(c);
    return try utils.createResponse(allocator, "SUCCESS", null);
}
pub fn approveAllowance(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    const c = client orelse return error.ClientNotConfigured;
    const p = params orelse return error.MissingParams;
    var tx = hedera.accountAllowanceApproveTransaction(allocator);
    defer tx.deinit();
    if (p.object.get("hbarAllowances")) |allowances| {
        for (allowances.array.items) |allowance| {
            const owner_str = utils.getString(allowance, "owner") orelse continue;
            const spender_str = utils.getString(allowance, "spender") orelse continue;
            const amount_str = utils.getString(allowance, "amount") orelse continue;
            const owner = try utils.parseAccountId(allocator, owner_str);
            const spender = try utils.parseAccountId(allocator, spender_str);
            const amount = try utils.parseHbar(amount_str);
            _ = try tx.approveHbarAllowance(owner, spender, amount);
        }
    }
    if (p.object.get("tokenAllowances")) |allowances| {
        for (allowances.array.items) |allowance| {
            const token_str = utils.getString(allowance, "tokenId") orelse continue;
            const owner_str = utils.getString(allowance, "owner") orelse continue;
            const spender_str = utils.getString(allowance, "spender") orelse continue;
            const amount_int = utils.getInt(allowance, "amount") orelse continue;
            const token_id = try utils.parseTokenId(allocator, token_str);
            const owner = try utils.parseAccountId(allocator, owner_str);
            const spender = try utils.parseAccountId(allocator, spender_str);
            _ = try tx.approveTokenAllowance(token_id, owner, spender, @intCast(amount_int));
        }
    }
    if (p.object.get("nftAllowances")) |allowances| {
        for (allowances.array.items) |allowance| {
            const token_str = utils.getString(allowance, "tokenId") orelse continue;
            const owner_str = utils.getString(allowance, "owner") orelse continue;
            const spender_str = utils.getString(allowance, "spender") orelse continue;
            const token_id = try utils.parseTokenId(allocator, token_str);
            const owner = try utils.parseAccountId(allocator, owner_str);
            const spender = try utils.parseAccountId(allocator, spender_str);
            if (allowance.object.get("serialNumbers")) |serial_nums| {
                for (serial_nums.array.items) |serial| {
                    const nft_id = hedera.NftId.init(token_id, @intCast(serial.integer));
                    _ = try tx.addNftAllowance(nft_id, owner, spender);
                }
            } else {
                _ = try tx.approveNftAllowanceAllSerials(token_id, owner, spender);
            }
        }
    }
    _ = try tx.freezeWith(c);
    var tx_response = try tx.execute(c);
    _ = try tx_response.getReceipt(c);
    return try utils.createResponse(allocator, "SUCCESS", null);
}
pub fn deleteAllowance(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    const c = client orelse return error.ClientNotConfigured;
    const p = params orelse return error.MissingParams;
    var tx = hedera.accountAllowanceDeleteTransaction(allocator);
    defer tx.deinit();
    if (p.object.get("nftAllowances")) |allowances| {
        for (allowances.array.items) |allowance| {
            const token_str = utils.getString(allowance, "tokenId") orelse continue;
            const owner_str = utils.getString(allowance, "owner") orelse continue;
            const token_id = try utils.parseTokenId(allocator, token_str);
            const owner = try utils.parseAccountId(allocator, owner_str);
            if (allowance.object.get("serialNumbers")) |serial_nums| {
                for (serial_nums.array.items) |serial| {
                    const nft_id = hedera.NftId.init(token_id, @intCast(serial.integer));
                    _ = try tx.deleteNftAllowance(nft_id, owner);
                }
            }
        }
    }
    _ = try tx.freezeWith(c);
    var tx_response = try tx.execute(c);
    _ = try tx_response.getReceipt(c);
    return try utils.createResponse(allocator, "SUCCESS", null);
}
pub fn transferCrypto(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    const c = client orelse return error.ClientNotConfigured;
    const p = params orelse return error.MissingParams;
    var tx = hedera.transferTransaction(allocator);
    defer tx.deinit();
    if (p.object.get("hbarTransfers")) |transfers| {
        for (transfers.array.items) |transfer| {
            const account_str = utils.getString(transfer, "accountId") orelse continue;
            const amount_str = utils.getString(transfer, "amount") orelse continue;
            const account_id = try utils.parseAccountId(allocator, account_str);
            const amount = try utils.parseHbar(amount_str);
            _ = try tx.addHbarTransfer(account_id, amount);
        }
    }
    if (p.object.get("tokenTransfers")) |transfers| {
        for (transfers.array.items) |transfer| {
            const token_str = utils.getString(transfer, "tokenId") orelse continue;
            const account_str = utils.getString(transfer, "accountId") orelse continue;
            const amount_int = utils.getInt(transfer, "amount") orelse continue;
            const token_id = try utils.parseTokenId(allocator, token_str);
            const account_id = try utils.parseAccountId(allocator, account_str);
            _ = try tx.addTokenTransfer(token_id, account_id, amount_int);
        }
    }
    if (p.object.get("nftTransfers")) |transfers| {
        for (transfers.array.items) |transfer| {
            const token_str = utils.getString(transfer, "tokenId") orelse continue;
            const sender_str = utils.getString(transfer, "senderAccountId") orelse continue;
            const receiver_str = utils.getString(transfer, "receiverAccountId") orelse continue;
            const serial_int = utils.getInt(transfer, "serialNumber") orelse continue;
            const token_id = try utils.parseTokenId(allocator, token_str);
            const sender = try utils.parseAccountId(allocator, sender_str);
            const receiver = try utils.parseAccountId(allocator, receiver_str);
            const nft_id = hedera.NftId.init(token_id, @intCast(serial_int));
            _ = try tx.addNftTransfer(nft_id, sender, receiver);
        }
    }
    _ = try tx.freezeWith(c);
    var tx_response = try tx.execute(c);
    _ = try tx_response.getReceipt(c);
    return try utils.createResponse(allocator, "SUCCESS", null);
}
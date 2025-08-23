const std = @import("std");
const hedera = @import("hedera");
const json = std.json;
const utils = @import("../utils/utils.zig");

const log = std.log.scoped(.account_service);

// Create account method
pub fn createAccount(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    const c = client orelse return error.ClientNotConfigured;
    
    const p = params orelse return error.MissingParams;
    
    // Create transaction
    var tx = hedera.newAccountCreateTransaction(allocator);
    defer tx.deinit();
    
    // Set key if provided
    if (utils.getString(p, "key")) |key_str| {
        var private_key = try utils.parsePrivateKey(allocator, key_str);
        defer private_key.deinit();
        const key = hedera.Key.fromPublicKey(private_key.getPublicKey());
        _ = try tx.setKey(key);
    }
    
    // Set initial balance if provided
    if (utils.getString(p, "initialBalance")) |balance_str| {
        const hbar = try utils.parseHbar(balance_str);
        _ = try tx.setInitialBalance(hbar);
    }
    
    // Set receiver signature required if provided
    if (utils.getBool(p, "receiverSignatureRequired")) |required| {
        _ = try tx.setReceiverSignatureRequired(required);
    }
    
    // Set max automatic token associations if provided
    if (utils.getInt(p, "maxAutomaticTokenAssociations")) |max_associations| {
        _ = try tx.setMaxAutomaticTokenAssociations(@intCast(max_associations));
    }
    
    // Set staked account ID if provided
    if (utils.getString(p, "stakedAccountId")) |staked_account_str| {
        const staked_account = try utils.parseAccountId(allocator, staked_account_str);
        _ = try tx.setStakedAccountId(staked_account);
    }
    
    // Set staked node ID if provided
    if (utils.getInt(p, "stakedNodeId")) |staked_node| {
        _ = try tx.setStakedNodeId(@intCast(staked_node));
    }
    
    // Set decline staking reward if provided
    if (utils.getBool(p, "declineStakingReward")) |decline| {
        _ = try tx.setDeclineStakingReward(decline);
    }
    
    // Set account memo if provided
    if (utils.getString(p, "memo")) |memo| {
        _ = try tx.setAccountMemo(memo);
    }
    
    // Set auto renew period if provided
    if (utils.getString(p, "autoRenewPeriod")) |period_str| {
        const duration = try utils.parseDuration(period_str);
        _ = try tx.setAutoRenewPeriod(duration);
    }
    
    // Set alias if provided
    if (utils.getString(p, "alias")) |alias_str| {
        // For now, just convert string to bytes
        _ = try tx.setAlias(alias_str);
    }
    
    // Execute transaction
    try tx.freezeWith(c);
    const tx_response = try tx.execute(c);
    const receipt = try tx_response.getReceipt(c);
    
    // Build response
    var response_fields = json.ObjectMap.init(allocator);
    defer response_fields.deinit();
    
    if (receipt.account_id) |account_id| {
        const account_id_str = try std.fmt.allocPrint(allocator, "{}", .{account_id});
        defer allocator.free(account_id_str);
        try response_fields.put("accountId", json.Value{ .string = try allocator.dupe(u8, account_id_str) });
    }
    
    return try utils.createResponse(allocator, "SUCCESS", response_fields);
}

// Update account method
pub fn updateAccount(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    const c = client orelse return error.ClientNotConfigured;
    const p = params orelse return error.MissingParams;
    
    // Get account ID to update
    const account_id_str = utils.getString(p, "accountId") orelse return error.MissingAccountId;
    const account_id = try utils.parseAccountId(allocator, account_id_str);
    
    // Create transaction
    var tx = hedera.newAccountUpdateTransaction(allocator);
    defer tx.deinit();
    
    _ = try tx.setAccountId(account_id);
    
    // Set key if provided
    if (utils.getString(p, "key")) |key_str| {
        var private_key = try utils.parsePrivateKey(allocator, key_str);
        defer private_key.deinit();
        const key = hedera.Key.fromPublicKey(private_key.getPublicKey());
        _ = try tx.setKey(key);
    }
    
    // Set expiration time if provided
    if (utils.getString(p, "expirationTime")) |exp_str| {
        const timestamp = try utils.parseTimestamp(exp_str);
        _ = try tx.setExpirationTime(timestamp);
    }
    
    // Set receiver signature required if provided
    if (utils.getBool(p, "receiverSignatureRequired")) |required| {
        _ = try tx.setReceiverSignatureRequired(required);
    }
    
    // Set max automatic token associations if provided
    if (utils.getInt(p, "maxAutomaticTokenAssociations")) |max_associations| {
        _ = try tx.setMaxAutomaticTokenAssociations(@intCast(max_associations));
    }
    
    // Set staked account ID if provided
    if (utils.getString(p, "stakedAccountId")) |staked_account_str| {
        const staked_account = try utils.parseAccountId(allocator, staked_account_str);
        _ = try tx.setStakedAccountId(staked_account);
    }
    
    // Set staked node ID if provided
    if (utils.getInt(p, "stakedNodeId")) |staked_node| {
        _ = try tx.setStakedNodeId(@intCast(staked_node));
    }
    
    // Set decline staking reward if provided
    if (utils.getBool(p, "declineStakingReward")) |decline| {
        _ = try tx.setDeclineStakingReward(decline);
    }
    
    // Set account memo if provided
    if (utils.getString(p, "memo")) |memo| {
        _ = try tx.setAccountMemo(memo);
    }
    
    // Set auto renew period if provided
    if (utils.getString(p, "autoRenewPeriod")) |period_str| {
        const duration = try utils.parseDuration(period_str);
        _ = try tx.setAutoRenewPeriod(duration);
    }
    
    // Execute transaction
    try tx.freezeWith(c);
    const tx_response = try tx.execute(c);
    _ = try tx_response.getReceipt(c);
    
    return try utils.createResponse(allocator, "SUCCESS", null);
}

// Delete account method
pub fn deleteAccount(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    const c = client orelse return error.ClientNotConfigured;
    const p = params orelse return error.MissingParams;
    
    // Get account ID to delete
    const account_id_str = utils.getString(p, "deleteAccountId") orelse return error.MissingAccountId;
    const account_id = try utils.parseAccountId(allocator, account_id_str);
    
    // Get transfer account ID
    const transfer_id_str = utils.getString(p, "transferAccountId") orelse return error.MissingTransferAccountId;
    const transfer_id = try utils.parseAccountId(allocator, transfer_id_str);
    
    // Create transaction
    var tx = hedera.newAccountDeleteTransaction(allocator);
    defer tx.deinit();
    
    _ = try tx.setAccountId(account_id);
    _ = try tx.setTransferAccountId(transfer_id);
    
    // Execute transaction
    try tx.freezeWith(c);
    const tx_response = try tx.execute(c);
    _ = try tx_response.getReceipt(c);
    
    return try utils.createResponse(allocator, "SUCCESS", null);
}

// Approve allowance method
pub fn approveAllowance(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    const c = client orelse return error.ClientNotConfigured;
    const p = params orelse return error.MissingParams;
    
    // Create transaction
    var tx = hedera.newAccountAllowanceApproveTransaction(allocator);
    defer tx.deinit();
    
    // Handle HBAR allowances
    if (p.object.get("hbarAllowances")) |allowances| {
        for (allowances.array.items) |allowance| {
            const owner_str = utils.getString(allowance, "owner") orelse continue;
            const spender_str = utils.getString(allowance, "spender") orelse continue;
            const amount_str = utils.getString(allowance, "amount") orelse continue;
            
            const owner = try utils.parseAccountId(allocator, owner_str);
            const spender = try utils.parseAccountId(allocator, spender_str);
            const amount = try utils.parseHbar(amount_str);
            
            try tx.approveHbarAllowance(owner, spender, amount);
        }
    }
    
    // Handle token allowances
    if (p.object.get("tokenAllowances")) |allowances| {
        for (allowances.array.items) |allowance| {
            const token_str = utils.getString(allowance, "tokenId") orelse continue;
            const owner_str = utils.getString(allowance, "owner") orelse continue;
            const spender_str = utils.getString(allowance, "spender") orelse continue;
            const amount_int = utils.getInt(allowance, "amount") orelse continue;
            
            const token_id = try utils.parseTokenId(allocator, token_str);
            const owner = try utils.parseAccountId(allocator, owner_str);
            const spender = try utils.parseAccountId(allocator, spender_str);
            
            try tx.approveTokenAllowance(token_id, owner, spender, @intCast(amount_int));
        }
    }
    
    // Handle NFT allowances
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
                    try tx.addNftAllowance(nft_id, owner, spender);
                }
            } else {
                try tx.approveNftAllowanceAllSerials(token_id, owner, spender);
            }
        }
    }
    
    // Execute transaction
    try tx.freezeWith(c);
    const tx_response = try tx.execute(c);
    _ = try tx_response.getReceipt(c);
    
    return try utils.createResponse(allocator, "SUCCESS", null);
}

// Delete allowance method
pub fn deleteAllowance(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    const c = client orelse return error.ClientNotConfigured;
    const p = params orelse return error.MissingParams;
    
    // Create transaction
    var tx = hedera.newAccountAllowanceDeleteTransaction(allocator);
    defer tx.deinit();
    
    // Handle NFT allowance deletions
    if (p.object.get("nftAllowances")) |allowances| {
        for (allowances.array.items) |allowance| {
            const token_str = utils.getString(allowance, "tokenId") orelse continue;
            const owner_str = utils.getString(allowance, "owner") orelse continue;
            
            const token_id = try utils.parseTokenId(allocator, token_str);
            const owner = try utils.parseAccountId(allocator, owner_str);
            
            if (allowance.object.get("serialNumbers")) |serial_nums| {
                for (serial_nums.array.items) |serial| {
                    const nft_id = hedera.NftId.init(token_id, @intCast(serial.integer));
                    try tx.deleteNftAllowance(nft_id, owner);
                }
            }
        }
    }
    
    // Execute transaction
    try tx.freezeWith(c);
    const tx_response = try tx.execute(c);
    _ = try tx_response.getReceipt(c);
    
    return try utils.createResponse(allocator, "SUCCESS", null);
}

// Transfer crypto method
pub fn transferCrypto(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    const c = client orelse return error.ClientNotConfigured;
    const p = params orelse return error.MissingParams;
    
    // Create transaction
    var tx = hedera.newTransferTransaction(allocator);
    defer tx.deinit();
    
    // Handle HBAR transfers
    if (p.object.get("hbarTransfers")) |transfers| {
        for (transfers.array.items) |transfer| {
            const account_str = utils.getString(transfer, "accountId") orelse continue;
            const amount_str = utils.getString(transfer, "amount") orelse continue;
            
            const account_id = try utils.parseAccountId(allocator, account_str);
            const amount = try utils.parseHbar(amount_str);
            
            try tx.addHbarTransfer(account_id, amount);
        }
    }
    
    // Handle token transfers
    if (p.object.get("tokenTransfers")) |transfers| {
        for (transfers.array.items) |transfer| {
            const token_str = utils.getString(transfer, "tokenId") orelse continue;
            const account_str = utils.getString(transfer, "accountId") orelse continue;
            const amount_int = utils.getInt(transfer, "amount") orelse continue;
            
            const token_id = try utils.parseTokenId(allocator, token_str);
            const account_id = try utils.parseAccountId(allocator, account_str);
            
            try tx.addTokenTransfer(token_id, account_id, amount_int);
        }
    }
    
    // Handle NFT transfers
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
            try tx.addNftTransfer(nft_id, sender, receiver);
        }
    }
    
    // Execute transaction
    try tx.freezeWith(c);
    const tx_response = try tx.execute(c);
    _ = try tx_response.getReceipt(c);
    
    return try utils.createResponse(allocator, "SUCCESS", null);
}
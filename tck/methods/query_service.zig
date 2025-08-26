const std = @import("std");
const hedera = @import("hedera");
const json = std.json;
const utils = @import("../utils/utils.zig");
pub fn getAccountInfo(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    if (client == null) {
        return json.Value{ .object = (try utils.createErrorMap(allocator, "Client not configured")) };
    }
    const p = params orelse return json.Value{ .object = (try utils.createErrorMap(allocator, "Invalid parameters")) };
    const account_id = try utils.getStringParam(p, "accountId");
    var query = hedera.AccountInfoQuery.init(allocator);
    defer query.deinit();
    const acc_id = try hedera.AccountId.fromString(allocator, account_id);
    _ = try query.setAccountId(acc_id);
    var info = try query.execute(client.?);
    defer info.deinit();
    var result = std.json.ObjectMap.init(allocator);
    try result.put("accountId", json.Value{ .string = try info.account_id.toString(allocator) });
    try result.put("balance", json.Value{ .integer = @intCast(info.balance.tinybars) });
    try result.put("ethereumNonce", json.Value{ .integer = @intCast(info.ethereum_nonce) });
    try result.put("maxAutoTokenAssociations", json.Value{ .integer = @intCast(info.max_automatic_token_associations) });
    try result.put("key", json.Value{ .string = try info.key.toString(allocator) });
    if (info.alias.len > 0) {
        const encoded = try allocator.alloc(u8, std.base64.standard.Encoder.calcSize(info.alias.len));
        _ = std.base64.standard.Encoder.encode(encoded, info.alias);
        try result.put("alias", json.Value{ .string = encoded });
    }
    if (info.memo.len > 0) {
        try result.put("memo", json.Value{ .string = info.memo });
    }
    try result.put("receiverSignatureRequired", json.Value{ .bool = info.receiver_signature_required });
    try result.put("deleted", json.Value{ .bool = info.deleted });
    try result.put("expirationTime", json.Value{ .integer = @intCast(info.expiration_time.seconds) });
    if (info.staking_info) |staking| {
        var staking_map = std.json.ObjectMap.init(allocator);
        try staking_map.put("declineReward", json.Value{ .bool = staking.decline_reward });
        try staking_map.put("stakedToMe", json.Value{ .integer = @intCast(staking.staked_to_me) });
        if (staking.staked_node_id) |node_id| {
            try staking_map.put("stakedNodeId", json.Value{ .integer = @intCast(node_id) });
        }
        if (staking.staked_account_id) |acc_id_staked| {
            try staking_map.put("stakedAccountId", json.Value{ .string = try acc_id_staked.toString(allocator) });
        }
        try result.put("stakingInfo", json.Value{ .object = staking_map });
    }
    return json.Value{ .object = result };
}
pub fn getAccountBalance(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    if (client == null) {
        return json.Value{ .object = (try utils.createErrorMap(allocator, "Client not configured")) };
    }
    const p = params orelse return json.Value{ .object = (try utils.createErrorMap(allocator, "Invalid parameters")) };
    const account_id = try utils.getStringParam(p, "accountId");
    var query = hedera.AccountBalanceQuery.init(allocator);
    defer query.deinit();
    const acc_id = try hedera.AccountId.fromString(allocator, account_id);
    _ = try query.setAccountId(acc_id);
    var balance = try query.execute(client.?);
    defer balance.deinit();
    var result = std.json.ObjectMap.init(allocator);
    try result.put("balance", json.Value{ .integer = @intCast(balance.hbars.tinybars) });
    if (balance.tokens.count() > 0) {
        var tokens_array = std.json.Array.init(allocator);
        var token_iter = balance.tokens.iterator();
        while (token_iter.next()) |entry| {
            var token_map = std.json.ObjectMap.init(allocator);
            try token_map.put("tokenId", json.Value{ .string = try entry.key_ptr.*.toString(allocator) });
            try token_map.put("balance", json.Value{ .integer = @intCast(entry.value_ptr.*) });
            try tokens_array.append(json.Value{ .object = token_map });
        }
        try result.put("tokens", json.Value{ .array = tokens_array });
    }
    return json.Value{ .object = result };
}
pub fn getTokenInfo(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    if (client == null) {
        return json.Value{ .object = (try utils.createErrorMap(allocator, "Client not configured")) };
    }
    const p = params orelse return json.Value{ .object = (try utils.createErrorMap(allocator, "Invalid parameters")) };
    const token_id = try utils.getStringParam(p, "tokenId");
    var query = hedera.TokenInfoQuery.init(allocator);
    defer query.deinit();
    const tid = try hedera.TokenId.fromString(allocator, token_id);
    _ = try query.setTokenId(tid);
    var info = try query.execute(client.?);
    defer info.deinit();
    var result = std.json.ObjectMap.init(allocator);
    try result.put("tokenId", json.Value{ .string = try info.token_id.toString(allocator) });
    try result.put("name", json.Value{ .string = info.name });
    try result.put("symbol", json.Value{ .string = info.symbol });
    try result.put("decimals", json.Value{ .integer = @intCast(info.decimals) });
    try result.put("totalSupply", json.Value{ .integer = @intCast(info.total_supply) });
    if (info.treasury_account_id) |treasury| {
        try result.put("treasuryAccountId", json.Value{ .string = try treasury.toString(allocator) });
    }
    if (info.admin_key) |key| {
        try result.put("adminKey", json.Value{ .string = try key.toString(allocator) });
    }
    if (info.supply_key) |key| {
        try result.put("supplyKey", json.Value{ .string = try key.toString(allocator) });
    }
    if (info.freeze_key) |key| {
        try result.put("freezeKey", json.Value{ .string = try key.toString(allocator) });
    }
    if (info.wipe_key) |key| {
        try result.put("wipeKey", json.Value{ .string = try key.toString(allocator) });
    }
    if (info.kyc_key) |key| {
        try result.put("kycKey", json.Value{ .string = try key.toString(allocator) });
    }
    if (info.pause_key) |key| {
        try result.put("pauseKey", json.Value{ .string = try key.toString(allocator) });
    }
    if (info.metadata_key) |key| {
        try result.put("metadataKey", json.Value{ .string = try key.toString(allocator) });
    }
    if (info.fee_schedule_key) |key| {
        try result.put("feeScheduleKey", json.Value{ .string = try key.toString(allocator) });
    }
    try result.put("tokenType", json.Value{ .string = @tagName(info.token_type) });
    try result.put("supplyType", json.Value{ .string = @tagName(info.supply_type) });
    if (info.memo.len > 0) {
        try result.put("memo", json.Value{ .string = info.memo });
    }
    try result.put("deleted", json.Value{ .bool = info.deleted });
    try result.put("paused", json.Value{ .bool = info.pause_status });
    if (info.auto_renew_account) |renew_acc| {
        try result.put("autoRenewAccount", json.Value{ .string = try renew_acc.toString(allocator) });
    }
    try result.put("autoRenewPeriod", json.Value{ .integer = @intCast(info.auto_renew_period.seconds) });
    if (info.expiry) |expiry| {
        try result.put("expirationTime", json.Value{ .integer = @intCast(expiry.seconds) });
    }
    return json.Value{ .object = result };
}
pub fn getTokenBalance(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    if (client == null) {
        return json.Value{ .object = (try utils.createErrorMap(allocator, "Client not configured")) };
    }
    const p = params orelse return json.Value{ .object = (try utils.createErrorMap(allocator, "Invalid parameters")) };
    const token_id = try utils.getStringParam(p, "tokenId");
    const account_id = try utils.getStringParam(p, "accountId");
    var query = hedera.AccountBalanceQuery.init(allocator);
    defer query.deinit();
    const acc_id = try hedera.AccountId.fromString(allocator, account_id);
    _ = try query.setAccountId(acc_id);
    var balance = try query.execute(client.?);
    defer balance.deinit();
    const tid = try hedera.TokenId.fromString(allocator, token_id);
    var result = std.json.ObjectMap.init(allocator);
    if (balance.tokens.get(tid)) |token_balance| {
        try result.put("balance", json.Value{ .integer = @intCast(token_balance) });
    } else {
        try result.put("balance", json.Value{ .integer = 0 });
    }
    return json.Value{ .object = result };
}
pub fn getFileInfo(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    if (client == null) {
        return json.Value{ .object = (try utils.createErrorMap(allocator, "Client not configured")) };
    }
    const p = params orelse return json.Value{ .object = (try utils.createErrorMap(allocator, "Invalid parameters")) };
    const file_id = try utils.getStringParam(p, "fileId");
    var query = hedera.FileInfoQuery.init(allocator);
    defer query.deinit();
    const fid = try hedera.FileId.fromString(allocator, file_id);
    _ = try query.setFileId(fid);
    var info = try query.execute(client.?);
    defer info.deinit();
    var result = std.json.ObjectMap.init(allocator);
    try result.put("fileId", json.Value{ .string = try info.file_id.toString(allocator) });
    try result.put("size", json.Value{ .integer = @intCast(info.size) });
    try result.put("expirationTime", json.Value{ .integer = @intCast(info.expiration_time.seconds) });
    try result.put("deleted", json.Value{ .bool = info.deleted });
    if (info.memo.len > 0) {
        try result.put("memo", json.Value{ .string = info.memo });
    }
    if (info.keys.items.len > 0) {
        try result.put("adminKey", json.Value{ .string = try info.keys.items[0].toString(allocator) });
    }
    return json.Value{ .object = result };
}
pub fn getFileContents(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    if (client == null) {
        return json.Value{ .object = (try utils.createErrorMap(allocator, "Client not configured")) };
    }
    const p = params orelse return json.Value{ .object = (try utils.createErrorMap(allocator, "Invalid parameters")) };
    const file_id = try utils.getStringParam(p, "fileId");
    var query = hedera.FileContentsQuery.init(allocator);
    defer query.deinit();
    const fid = try hedera.FileId.fromString(allocator, file_id);
    _ = try query.setFileId(fid);
    var file_contents = try query.execute(client.?);
    defer file_contents.deinit();
    var result = std.json.ObjectMap.init(allocator);
    const encoded = try allocator.alloc(u8, std.base64.standard.Encoder.calcSize(file_contents.contents.len));
    _ = std.base64.standard.Encoder.encode(encoded, file_contents.contents);
    try result.put("contents", json.Value{ .string = encoded });
    return json.Value{ .object = result };
}
pub fn getTopicInfo(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    if (client == null) {
        return json.Value{ .object = (try utils.createErrorMap(allocator, "Client not configured")) };
    }
    const p = params orelse return json.Value{ .object = (try utils.createErrorMap(allocator, "Invalid parameters")) };
    const topic_id = try utils.getStringParam(p, "topicId");
    var query = hedera.TopicInfoQuery.init(allocator);
    defer query.deinit();
    const tid = try hedera.TopicId.fromString(allocator, topic_id);
    _ = try query.setTopicId(tid);
    var info = try query.execute(client.?);
    defer info.deinit();
    var result = std.json.ObjectMap.init(allocator);
    try result.put("topicId", json.Value{ .string = try info.topic_id.toString(allocator) });
    if (info.memo.len > 0) {
        try result.put("memo", json.Value{ .string = info.memo });
    }
    if (info.admin_key) |key| {
        try result.put("adminKey", json.Value{ .string = try key.toString(allocator) });
    }
    if (info.submit_key) |key| {
        try result.put("submitKey", json.Value{ .string = try key.toString(allocator) });
    }
    if (info.auto_renew_account) |acc| {
        try result.put("autoRenewAccount", json.Value{ .string = try acc.toString(allocator) });
    }
    try result.put("autoRenewPeriod", json.Value{ .integer = @intCast(info.auto_renew_period.seconds) });
    try result.put("expirationTime", json.Value{ .integer = @intCast(info.expiration_time.seconds) });
    try result.put("sequenceNumber", json.Value{ .integer = @intCast(info.sequence_number) });
    return json.Value{ .object = result };
}
pub fn getContractInfo(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    if (client == null) {
        return json.Value{ .object = (try utils.createErrorMap(allocator, "Client not configured")) };
    }
    const p = params orelse return json.Value{ .object = (try utils.createErrorMap(allocator, "Invalid parameters")) };
    const contract_id = try utils.getStringParam(p, "contractId");
    var query = hedera.ContractInfoQuery.init(allocator);
    defer query.deinit();
    const cid = try hedera.ContractId.fromString(allocator, contract_id);
    _ = try query.setContractId(cid);
    var info = try query.execute(client.?);
    defer info.deinit();
    var result = std.json.ObjectMap.init(allocator);
    try result.put("contractId", json.Value{ .string = try info.contract_id.toString(allocator) });
    try result.put("accountId", json.Value{ .string = try info.account_id.toString(allocator) });
    if (info.contract_account_id.len > 0) {
        try result.put("contractAccountId", json.Value{ .string = info.contract_account_id });
    }
    if (info.admin_key) |key| {
        try result.put("adminKey", json.Value{ .string = try key.toString(allocator) });
    }
    try result.put("storage", json.Value{ .integer = @intCast(info.storage) });
    if (info.memo.len > 0) {
        try result.put("memo", json.Value{ .string = info.memo });
    }
    try result.put("balance", json.Value{ .integer = @intCast(info.balance) });
    try result.put("deleted", json.Value{ .bool = info.deleted });
    try result.put("autoRenewPeriod", json.Value{ .integer = @intCast(info.auto_renew_period.seconds) });
    if (info.auto_renew_account_id) |acc| {
        try result.put("autoRenewAccountId", json.Value{ .string = try acc.toString(allocator) });
    }
    try result.put("maxAutoTokenAssociations", json.Value{ .integer = @intCast(info.max_automatic_token_associations) });
    return json.Value{ .object = result };
}
pub fn getTransactionRecord(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    if (client == null) {
        return json.Value{ .object = (try utils.createErrorMap(allocator, "Client not configured")) };
    }
    const p = params orelse return json.Value{ .object = (try utils.createErrorMap(allocator, "Invalid parameters")) };
    const transaction_id = try utils.getStringParam(p, "transactionId");
    var query = hedera.TransactionRecordQuery.init(allocator);
    defer query.deinit();
    const tx_id = try hedera.TransactionId.fromString(allocator, transaction_id);
    _ = try query.setTransactionId(tx_id);
    var record = try query.execute(client.?);
    defer record.deinit();
    var result = std.json.ObjectMap.init(allocator);
    if (record.transaction_id) |tid| {
        try result.put("transactionId", json.Value{ .string = try tid.toString(allocator) });
    }
    if (record.receipt) |receipt| {
        try result.put("status", json.Value{ .string = @tagName(receipt.status) });
    }
    if (record.transaction_hash) |hash| {
        const encoded = try allocator.alloc(u8, std.base64.standard.Encoder.calcSize(hash.len));
        _ = std.base64.standard.Encoder.encode(encoded, hash);
        try result.put("transactionHash", json.Value{ .string = encoded });
    }
    if (record.transaction_fee) |fee| {
        try result.put("transactionFee", json.Value{ .integer = @intCast(fee) });
    }
    if (record.consensus_timestamp) |timestamp| {
        try result.put("consensusTimestamp", json.Value{ .integer = @intCast(timestamp.seconds) });
    }
    if (record.memo) |memo| {
        try result.put("memo", json.Value{ .string = memo });
    }
    if (record.transfers) |transfers| {
        var transfers_array = std.json.Array.init(allocator);
        for (transfers) |transfer| {
            var transfer_map = std.json.ObjectMap.init(allocator);
            try transfer_map.put("accountId", json.Value{ .string = try transfer.account_id.toString(allocator) });
            try transfer_map.put("amount", json.Value{ .integer = @intCast(transfer.amount) });
            try transfers_array.append(json.Value{ .object = transfer_map });
        }
        try result.put("transfers", json.Value{ .array = transfers_array });
    }
    return json.Value{ .object = result };
}
pub fn getTransactionReceipt(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    if (client == null) {
        return json.Value{ .object = (try utils.createErrorMap(allocator, "Client not configured")) };
    }
    const p = params orelse return json.Value{ .object = (try utils.createErrorMap(allocator, "Invalid parameters")) };
    const transaction_id = try utils.getStringParam(p, "transactionId");
    var query = hedera.TransactionReceiptQuery.init(allocator);
    defer query.deinit();
    const tx_id = try hedera.TransactionId.fromString(allocator, transaction_id);
    _ = try query.setTransactionId(tx_id);
    var receipt = try query.execute(client.?);
    defer receipt.deinit();
    var result = std.json.ObjectMap.init(allocator);
    try result.put("status", json.Value{ .string = @tagName(receipt.status) });
    if (receipt.account_id) |acc_id| {
        try result.put("accountId", json.Value{ .string = try acc_id.toString(allocator) });
    }
    if (receipt.token_id) |tid| {
        try result.put("tokenId", json.Value{ .string = try tid.toString(allocator) });
    }
    if (receipt.file_id) |fid| {
        try result.put("fileId", json.Value{ .string = try fid.toString(allocator) });
    }
    if (receipt.contract_id) |cid| {
        try result.put("contractId", json.Value{ .string = try cid.toString(allocator) });
    }
    if (receipt.topic_id) |tid| {
        try result.put("topicId", json.Value{ .string = try tid.toString(allocator) });
    }
    if (receipt.schedule_id) |sid| {
        try result.put("scheduleId", json.Value{ .string = try sid.toString(allocator) });
    }
    if (receipt.topic_sequence_number) |seq| {
        try result.put("topicSequenceNumber", json.Value{ .integer = @intCast(seq) });
    }
    if (receipt.topic_running_hash) |hash| {
        const encoded = try allocator.alloc(u8, std.base64.standard.Encoder.calcSize(hash.len));
        _ = std.base64.standard.Encoder.encode(encoded, hash);
        try result.put("topicRunningHash", json.Value{ .string = encoded });
    }
    if (receipt.serials) |serials| {
        var serials_array = std.json.Array.init(allocator);
        for (serials) |serial| {
            try serials_array.append(json.Value{ .integer = @intCast(serial) });
        }
        try result.put("serials", json.Value{ .array = serials_array });
    }
    if (receipt.total_supply) |supply| {
        try result.put("totalSupply", json.Value{ .integer = @intCast(supply) });
    }
    if (receipt.exchange_rate) |rate| {
        var rate_map = std.json.ObjectMap.init(allocator);
        try rate_map.put("hbars", json.Value{ .integer = @intCast(rate.hbars) });
        try rate_map.put("cents", json.Value{ .integer = @intCast(rate.cents) });
        try result.put("exchangeRate", json.Value{ .object = rate_map });
    }
    return json.Value{ .object = result };
}
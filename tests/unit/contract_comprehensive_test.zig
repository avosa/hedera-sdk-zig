const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectEqualSlices = std.testing.expectEqualSlices;
const allocator = std.testing.allocator;

const ContractId = @import("../../src/core/id.zig").ContractId;
const AccountId = @import("../../src/core/id.zig").AccountId;
const FileId = @import("../../src/core/id.zig").FileId;
const Hbar = @import("../../src/core/hbar.zig").Hbar;
const Duration = @import("../../src/core/duration.zig").Duration;
const Timestamp = @import("../../src/core/timestamp.zig").Timestamp;
const Key = @import("../../src/crypto/key.zig").Key;
const PrivateKey = @import("../../src/crypto/private_key.zig").PrivateKey;

const ContractCreateTransaction = @import("../../src/contract/contract_create.zig").ContractCreateTransaction;
const ContractExecuteTransaction = @import("../../src/contract/contract_execute.zig").ContractExecuteTransaction;
const ContractFunctionParameters = @import("../../src/contract/contract_execute.zig").ContractFunctionParameters;
const ContractFunctionResult = @import("../../src/contract/contract_execute.zig").ContractFunctionResult;
const ContractCallQuery = @import("../../src/contract/contract_call_query.zig").ContractCallQuery;
const ContractInfo = @import("../../src/contract/contract_info_query.zig").ContractInfo;
const ContractInfoQuery = @import("../../src/contract/contract_info_query.zig").ContractInfoQuery;
const StakingInfo = @import("../../src/contract/contract_info_query.zig").StakingInfo;
const ContractUpdateTransaction = @import("../../src/contract/contract_update_transaction.zig").ContractUpdateTransaction;
const ContractDeleteTransaction = @import("../../src/contract/contract_delete.zig").ContractDeleteTransaction;

// ContractId Tests
test "ContractId initialization and basic operations" {
    const contract_id = ContractId.init(0, 0, 1001);
    
    try expectEqual(@as(u64, 0), contract_id.shard());
    try expectEqual(@as(u64, 0), contract_id.realm());
    try expectEqual(@as(u64, 1001), contract_id.num());
}

test "ContractId with EVM address" {
    var contract_id = ContractId.init(0, 0, 1001);
    const evm_address = "0x1234567890abcdef1234567890abcdef12345678";
    contract_id.evm_address = evm_address;
    
    try expectEqual(@as(u64, 1001), contract_id.num());
    try expectEqualSlices(u8, evm_address, contract_id.evm_address.?);
}

test "ContractId string representation" {
    const contract_id = ContractId.init(1, 2, 3);
    const result = try contract_id.toString(allocator);
    defer allocator.free(result);
    
    try expectEqualSlices(u8, "1.2.3", result);
}

test "ContractId parsing from string" {
    const contract_id = try ContractId.fromString("0.0.1001");
    
    try expectEqual(@as(u64, 0), contract_id.shard());
    try expectEqual(@as(u64, 0), contract_id.realm());
    try expectEqual(@as(u64, 1001), contract_id.num());
}

test "ContractId equality comparison" {
    const contract1 = ContractId.init(0, 0, 1001);
    const contract2 = ContractId.init(0, 0, 1001);
    const contract3 = ContractId.init(0, 0, 1002);
    
    try expect(contract1.equals(contract2));
    try expect(!contract1.equals(contract3));
}

// ContractCreateTransaction Tests
test "ContractCreateTransaction initialization and basic setters" {
    var tx = ContractCreateTransaction.init(allocator);
    defer tx.deinit();
    
    const file_id = FileId.init(0, 0, 1001);
    _ = try tx.setBytecodeFileId(file_id);
    try expectEqual(file_id, tx.getBytecodeFileID());
    
    const admin_key = Key{ .ed25519_public_key = "test_key" };
    _ = try tx.setAdminKey(admin_key);
    try expectEqual(admin_key, tx.getAdminKey().?);
    
    _ = try tx.setGas(250000);
    try expectEqual(@as(u64, 250000), tx.getGas());
    
    const balance = try Hbar.from(10);
    _ = try tx.setInitialBalance(balance);
    try expectEqual(balance, tx.getInitialBalance());
    
    _ = try tx.setMemo("Test contract");
    try expectEqualSlices(u8, "Test contract", tx.getContractMemo());
    
    _ = try tx.setMaxAutomaticTokenAssociations(100);
    try expectEqual(@as(i32, 100), tx.getMaxAutomaticTokenAssociations());
    
    _ = try tx.setDeclineStakingReward(true);
    try expect(tx.getDeclineStakingReward());
}

test "ContractCreateTransaction with bytecode instead of file ID" {
    var tx = ContractCreateTransaction.init(allocator);
    defer tx.deinit();
    
    const bytecode = "608060405234801561001057600080fd5b50";
    _ = try tx.setBytecode(bytecode);
    try expectEqualSlices(u8, bytecode, tx.getBytecode());
    
    // Setting bytecode should clear file ID
    try expectEqual(FileId{}, tx.getBytecodeFileID());
}

test "ContractCreateTransaction auto renew period" {
    var tx = ContractCreateTransaction.init(allocator);
    defer tx.deinit();
    
    const period = Duration{ .seconds = 7890000, .nanos = 0 };
    _ = try tx.setAutoRenewPeriod(period);
    try expectEqual(period, tx.getAutoRenewPeriod());
}

test "ContractCreateTransaction staking configuration" {
    var tx = ContractCreateTransaction.init(allocator);
    defer tx.deinit();
    
    const account_id = AccountId.init(0, 0, 500);
    _ = try tx.setStakedAccountID(account_id);
    try expectEqual(account_id, tx.getStakedAccountID());
    try expectEqual(@as(i64, 0), tx.getStakedNodeID());
    
    _ = try tx.setStakedNodeId(3);
    try expectEqual(@as(i64, 3), tx.getStakedNodeID());
    try expectEqual(AccountId{}, tx.getStakedAccountID());
}

test "ContractCreateTransaction auto renew account" {
    var tx = ContractCreateTransaction.init(allocator);
    defer tx.deinit();
    
    const auto_renew_account = AccountId.init(0, 0, 600);
    _ = try tx.setAutoRenewAccountId(auto_renew_account);
    try expectEqual(auto_renew_account, tx.getAutoRenewAccountID());
}

test "ContractCreateTransaction constructor parameters" {
    var tx = ContractCreateTransaction.init(allocator);
    defer tx.deinit();
    
    const params = "constructor_params_data";
    _ = try tx.setConstructorParameters(params);
    try expectEqualSlices(u8, params, tx.getConstructorParameters());
}

test "ContractCreateTransaction frozen state validation" {
    var tx = ContractCreateTransaction.init(allocator);
    defer tx.deinit();
    
    tx.base.frozen = true;
    
    try expectError(error.TransactionFrozen, tx.setBytecodeFileId(FileId.init(0, 0, 1001)));
    try expectError(error.TransactionFrozen, tx.setAdminKey(Key{ .ed25519_public_key = "test" }));
    try expectError(error.TransactionFrozen, tx.setGas(100000));
}

// ContractFunctionParameters Tests
test "ContractFunctionParameters basic types" {
    var params = ContractFunctionParameters.init(allocator);
    defer params.deinit();
    
    try params.addUint256(12345);
    try params.addInt64(9876543210);
    try params.addUint32(4294967295);
    try params.addInt32(-2147483648);
    try params.addUint8(255);
    try params.addInt8(-128);
    try params.addBool(true);
    
    try expectEqual(@as(usize, 7), params.arguments.items.len);
}

test "ContractFunctionParameters string and bytes" {
    var params = ContractFunctionParameters.init(allocator);
    defer params.deinit();
    
    try params.addString("Hello, world!");
    try params.addBytes(&[_]u8{ 0x01, 0x02, 0x03, 0x04 });
    
    const bytes32 = [_]u8{0xFF} ** 32;
    try params.addBytes32(bytes32);
    
    try expectEqual(@as(usize, 3), params.arguments.items.len);
}

test "ContractFunctionParameters address handling" {
    var params = ContractFunctionParameters.init(allocator);
    defer params.deinit();
    
    // Test hex address with 0x prefix
    try params.addAddress("0x1234567890abcdef1234567890abcdef12345678");
    
    // Test hex address without 0x prefix
    try params.addAddress("1234567890abcdef1234567890abcdef12345678");
    
    // Test raw 20-byte address
    const raw_addr = [_]u8{0x12} ** 20;
    try params.addAddress(&raw_addr);
    
    try expectEqual(@as(usize, 3), params.arguments.items.len);
}

test "ContractFunctionParameters invalid address formats" {
    var params = ContractFunctionParameters.init(allocator);
    defer params.deinit();
    
    // Invalid length
    try expectError(error.InvalidAddressLength, params.addAddress("0x1234"));
    
    // Invalid hex characters
    try expectError(error.InvalidAddressFormat, params.addAddress("0x1234567890abcdef1234567890abcdef1234567g"));
}

test "ContractFunctionParameters function selector" {
    var params = ContractFunctionParameters.init(allocator);
    defer params.deinit();
    
    _ = try params.setFunction("transfer(address,uint256)");
    
    // Function selector should be set (first 4 bytes of Keccak256)
    try expect(params.function_selector[0] != 0 or params.function_selector[1] != 0 or 
               params.function_selector[2] != 0 or params.function_selector[3] != 0);
}

test "ContractFunctionParameters encoding" {
    var params = ContractFunctionParameters.init(allocator);
    defer params.deinit();
    
    _ = try params.setFunction("test()");
    try params.addUint256(42);
    try params.addBool(true);
    
    const encoded = try params.build();
    defer allocator.free(encoded);
    
    // Should have function selector (4 bytes) + encoded parameters
    try expect(encoded.len >= 4);
    
    // First 4 bytes should be function selector
    try expectEqualSlices(u8, &params.function_selector, encoded[0..4]);
}

// ContractExecuteTransaction Tests
test "ContractExecuteTransaction initialization and basic setters" {
    var tx = ContractExecuteTransaction.init(allocator);
    defer tx.deinit();
    
    const contract_id = ContractId.init(0, 0, 1001);
    _ = try tx.setContractId(contract_id);
    try expectEqual(contract_id, tx.getContractId());
    
    _ = try tx.setGas(300000);
    try expectEqual(@as(u64, 300000), tx.getGas());
    
    const payable_amount = try Hbar.from(5);
    _ = try tx.setPayableAmount(payable_amount);
    try expectEqual(payable_amount, tx.getPayableAmount());
}

test "ContractExecuteTransaction with function parameters" {
    var tx = ContractExecuteTransaction.init(allocator);
    defer tx.deinit();
    
    const contract_id = ContractId.init(0, 0, 1001);
    _ = try tx.setContractId(contract_id);
    
    var params = ContractFunctionParameters.init(allocator);
    defer params.deinit();
    
    try params.addUint256(100);
    try params.addString("test");
    
    _ = try tx.setFunction("testFunction(uint256,string)", &params);
    
    const function_params = tx.getFunctionParameters();
    try expect(function_params.len > 0);
}

test "ContractExecuteTransaction direct parameter setting" {
    var tx = ContractExecuteTransaction.init(allocator);
    defer tx.deinit();
    
    const params = "direct_parameter_bytes";
    _ = try tx.setFunctionParameters(params);
    try expectEqualSlices(u8, params, tx.getFunctionParameters());
}

test "ContractExecuteTransaction execution validation" {
    var tx = ContractExecuteTransaction.init(allocator);
    defer tx.deinit();
    
    // Should fail without contract ID
    var client = @import("../../src/network/client.zig").Client.init(allocator);
    defer client.deinit();
    
    try expectError(error.ContractIdRequired, tx.execute(&client));
}

// ContractCallQuery Tests
test "ContractCallQuery initialization and basic setters" {
    var query = ContractCallQuery.init(allocator);
    defer query.deinit();
    
    const contract_id = ContractId.init(0, 0, 1001);
    _ = try query.setContractId(contract_id);
    
    _ = try query.setGas(100000);
    _ = try query.setMaxResultSize(2048);
    
    const sender_id = AccountId.init(0, 0, 500);
    _ = try query.setSenderId(sender_id);
    
    const payment = try Hbar.fromTinybars(1000000);
    _ = try query.setQueryPayment(payment);
}

test "ContractCallQuery with function parameters" {
    var query = ContractCallQuery.init(allocator);
    defer query.deinit();
    
    const contract_id = ContractId.init(0, 0, 1001);
    _ = try query.setContractId(contract_id);
    
    var params = ContractFunctionParameters.init(allocator);
    defer params.deinit();
    
    try params.addUint256(42);
    try params.addAddress("0x1234567890abcdef1234567890abcdef12345678");
    
    _ = try query.setFunction("balanceOf(address)", params);
}

test "ContractCallQuery direct parameter setting" {
    var query = ContractCallQuery.init(allocator);
    defer query.deinit();
    
    const params = "query_parameter_bytes";
    _ = try query.setFunctionParameters(params);
}

test "ContractCallQuery gas validation" {
    var query = ContractCallQuery.init(allocator);
    defer query.deinit();
    
    try expectError(error.InvalidParameter, query.setGas(-100));
}

// ContractFunctionResult Tests
test "ContractFunctionResult parsing uint values" {
    const result_bytes = [_]u8{0} ** 32 ++ [_]u8{0} ** 28 ++ [_]u8{ 0, 0, 0, 42 }; // uint256 = 42
    
    const result = ContractFunctionResult{
        .contract_id = ContractId.init(0, 0, 1001),
        .contract_call_result = &result_bytes,
        .error_message = "",
        .bloom = "",
        .gas_used = 50000,
        .logs = &[_]ContractFunctionResult.ContractLogInfo{},
        .created_contract_ids = &[_]ContractId{},
        .evm_address = null,
        .gas = 100000,
        .amount = 0,
        .function_parameters = "",
        .sender_id = null,
    };
    
    const uint256_result = try result.getUint256(0);
    try expectEqual(@as(u32, 42), std.mem.readInt(u32, uint256_result[28..32], .big));
    
    const uint64_result = try result.getUint64(0);
    try expectEqual(@as(u64, 42), uint64_result);
    
    const uint32_result = try result.getUint32(0);
    try expectEqual(@as(u32, 42), uint32_result);
}

test "ContractFunctionResult parsing boolean" {
    const result_bytes = [_]u8{0} ** 31 ++ [_]u8{1}; // bool = true
    
    const result = ContractFunctionResult{
        .contract_id = ContractId.init(0, 0, 1001),
        .contract_call_result = &result_bytes,
        .error_message = "",
        .bloom = "",
        .gas_used = 50000,
        .logs = &[_]ContractFunctionResult.ContractLogInfo{},
        .created_contract_ids = &[_]ContractId{},
        .evm_address = null,
        .gas = 100000,
        .amount = 0,
        .function_parameters = "",
        .sender_id = null,
    };
    
    const bool_result = try result.getBool(0);
    try expect(bool_result);
}

test "ContractFunctionResult parsing address" {
    var result_bytes = [_]u8{0} ** 32;
    const address_bytes = [_]u8{0x12} ** 20;
    @memcpy(result_bytes[12..32], &address_bytes);
    
    const result = ContractFunctionResult{
        .contract_id = ContractId.init(0, 0, 1001),
        .contract_call_result = &result_bytes,
        .error_message = "",
        .bloom = "",
        .gas_used = 50000,
        .logs = &[_]ContractFunctionResult.ContractLogInfo{},
        .created_contract_ids = &[_]ContractId{},
        .evm_address = null,
        .gas = 100000,
        .amount = 0,
        .function_parameters = "",
        .sender_id = null,
    };
    
    const address_result = try result.getAddress(0);
    try expectEqualSlices(u8, &address_bytes, &address_result);
}

test "ContractFunctionResult index out of bounds" {
    const result_bytes = [_]u8{0} ** 32; // Only one 32-byte word
    
    const result = ContractFunctionResult{
        .contract_id = ContractId.init(0, 0, 1001),
        .contract_call_result = &result_bytes,
        .error_message = "",
        .bloom = "",
        .gas_used = 50000,
        .logs = &[_]ContractFunctionResult.ContractLogInfo{},
        .created_contract_ids = &[_]ContractId{},
        .evm_address = null,
        .gas = 100000,
        .amount = 0,
        .function_parameters = "",
        .sender_id = null,
    };
    
    try expectError(error.IndexOutOfBounds, result.getUint256(1));
    try expectError(error.IndexOutOfBounds, result.getUint64(1));
    try expectError(error.IndexOutOfBounds, result.getBool(1));
}

// ContractInfo and ContractInfoQuery Tests
test "ContractInfo initialization" {
    var info = ContractInfo.init(allocator);
    defer info.deinit();
    
    const contract_id = ContractId.init(0, 0, 1001);
    info.contract_id = contract_id;
    
    const account_id = AccountId.init(0, 0, 1001);
    info.account_id = account_id;
    
    info.storage = 1024;
    info.balance = 50000000; // 0.5 Hbar in tinybars
    info.deleted = false;
    
    try expectEqual(contract_id, info.contract_id);
    try expectEqual(account_id, info.account_id);
    try expectEqual(@as(i64, 1024), info.storage);
    try expectEqual(@as(u64, 50000000), info.balance);
    try expect(!info.deleted);
}

test "ContractInfo with admin key and expiration" {
    var info = ContractInfo.init(allocator);
    defer info.deinit();
    
    const admin_key = Key{ .ed25519_public_key = "admin_key_data" };
    info.admin_key = admin_key;
    
    const expiration = Timestamp{ .seconds = 1234567890, .nanos = 123456789 };
    info.expiration_time = expiration;
    
    const auto_renew = Duration{ .seconds = 7890000, .nanos = 0 };
    info.auto_renew_period = auto_renew;
    
    try expectEqual(admin_key, info.admin_key.?);
    try expectEqual(expiration, info.expiration_time);
    try expectEqual(auto_renew, info.auto_renew_period);
}

test "ContractInfo with staking information" {
    var info = ContractInfo.init(allocator);
    defer info.deinit();
    
    const staking_info = StakingInfo{
        .decline_reward = true,
        .stake_period_start = Timestamp{ .seconds = 1000000000, .nanos = 0 },
        .pending_reward = 10000000, // 0.1 Hbar
        .staked_to_me = 50000000, // 0.5 Hbar
        .staked_account_id = AccountId.init(0, 0, 500),
        .staked_node_id = null,
    };
    
    info.staking_info = staking_info;
    
    try expect(info.staking_info.?.decline_reward);
    try expectEqual(@as(i64, 10000000), info.staking_info.?.pending_reward);
    try expectEqual(@as(i64, 50000000), info.staking_info.?.staked_to_me);
    try expectEqual(AccountId.init(0, 0, 500), info.staking_info.?.staked_account_id.?);
}

test "ContractInfo with automatic token associations" {
    var info = ContractInfo.init(allocator);
    defer info.deinit();
    
    info.max_automatic_token_associations = 1000;
    
    const auto_renew_account = AccountId.init(0, 0, 700);
    info.auto_renew_account_id = auto_renew_account;
    
    try expectEqual(@as(i32, 1000), info.max_automatic_token_associations);
    try expectEqual(auto_renew_account, info.auto_renew_account_id.?);
}

test "ContractInfoQuery initialization and configuration" {
    var query = ContractInfoQuery.init(allocator);
    defer query.deinit();
    
    const contract_id = ContractId.init(0, 0, 1001);
    _ = try query.setContractId(contract_id);
    
    const payment = try Hbar.fromTinybars(2000000);
    _ = try query.setQueryPayment(payment);
}

test "ContractInfoQuery execution validation" {
    var query = ContractInfoQuery.init(allocator);
    defer query.deinit();
    
    var client = @import("../../src/network/client.zig").Client.init(allocator);
    defer client.deinit();
    
    // Should fail without contract ID
    try expectError(error.ContractIdRequired, query.execute(&client));
}

// ContractUpdateTransaction Tests
test "ContractUpdateTransaction initialization and setters" {
    var tx = ContractUpdateTransaction.init(allocator);
    defer tx.deinit();
    
    const contract_id = ContractId.init(0, 0, 1001);
    _ = try tx.SetContractID(contract_id);
    try expectEqual(contract_id, tx.GetContractID());
    
    const expiration = Timestamp{ .seconds = 2000000000, .nanos = 0 };
    _ = try tx.SetExpirationTime(expiration);
    try expectEqual(expiration, tx.GetExpirationTime());
    
    const admin_key = Key{ .ed25519_public_key = "new_admin_key" };
    _ = try tx.SetAdminKey(admin_key);
    try expectEqual(admin_key, tx.GetAdminKey().?);
    
    const auto_renew_period = Duration{ .seconds = 8640000, .nanos = 0 };
    _ = try tx.SetAutoRenewPeriod(auto_renew_period);
    try expectEqual(auto_renew_period, tx.GetAutoRenewPeriod());
}

test "ContractUpdateTransaction memo operations" {
    var tx = ContractUpdateTransaction.init(allocator);
    defer tx.deinit();
    
    _ = try tx.SetContractMemo("Updated contract memo");
    try expectEqualSlices(u8, "Updated contract memo", tx.GetContractMemo());
    
    _ = try tx.ClearContractMemo();
    try expectEqualSlices(u8, "", tx.GetContractMemo());
}

test "ContractUpdateTransaction auto renew account operations" {
    var tx = ContractUpdateTransaction.init(allocator);
    defer tx.deinit();
    
    const auto_renew_account = AccountId.init(0, 0, 800);
    _ = try tx.SetAutoRenewAccountID(auto_renew_account);
    try expectEqual(auto_renew_account, tx.GetAutoRenewAccountID());
    
    _ = try tx.ClearAutoRenewAccountID();
    try expectEqual(AccountId{}, tx.GetAutoRenewAccountID());
}

test "ContractUpdateTransaction staking operations" {
    var tx = ContractUpdateTransaction.init(allocator);
    defer tx.deinit();
    
    const staked_account = AccountId.init(0, 0, 900);
    _ = try tx.SetStakedAccountID(staked_account);
    try expectEqual(staked_account, tx.GetStakedAccountID());
    try expectEqual(@as(i64, 0), tx.GetStakedNodeID());
    
    _ = try tx.SetStakedNodeID(5);
    try expectEqual(@as(i64, 5), tx.GetStakedNodeID());
    try expectEqual(AccountId{}, tx.GetStakedAccountID());
    
    _ = try tx.ClearStakedAccountID();
    _ = try tx.ClearStakedNodeID();
    try expectEqual(@as(i64, -1), tx.GetStakedNodeID());
}

test "ContractUpdateTransaction automatic token associations" {
    var tx = ContractUpdateTransaction.init(allocator);
    defer tx.deinit();
    
    _ = try tx.SetMaxAutomaticTokenAssociations(500);
    try expectEqual(@as(i32, 500), tx.GetMaxAutomaticTokenAssociations());
}

test "ContractUpdateTransaction decline staking reward" {
    var tx = ContractUpdateTransaction.init(allocator);
    defer tx.deinit();
    
    _ = try tx.SetDeclineStakingReward(true);
    try expect(tx.GetDeclineStakingReward());
    
    _ = try tx.SetDeclineStakingReward(false);
    try expect(!tx.GetDeclineStakingReward());
}

test "ContractUpdateTransaction proxy account (deprecated)" {
    var tx = ContractUpdateTransaction.init(allocator);
    defer tx.deinit();
    
    const proxy_account = AccountId.init(0, 0, 1000);
    _ = try tx.SetProxyAccountID(proxy_account);
    try expectEqual(proxy_account, tx.GetProxyAccountID());
}

test "ContractUpdateTransaction bytecode file (deprecated)" {
    var tx = ContractUpdateTransaction.init(allocator);
    defer tx.deinit();
    
    const file_id = FileId.init(0, 0, 2001);
    _ = try tx.SetBytecodeFileID(file_id);
    try expectEqual(file_id, tx.GetBytecodeFileID());
}

// ContractDeleteTransaction Tests
test "ContractDeleteTransaction initialization and basic setters" {
    var tx = ContractDeleteTransaction.init(allocator);
    defer tx.deinit();
    
    const contract_id = ContractId.init(0, 0, 1001);
    _ = try tx.SetContractID(contract_id);
    try expectEqual(contract_id, tx.GetContractID());
    
    const transfer_account = AccountId.init(0, 0, 500);
    _ = try tx.SetTransferAccountID(transfer_account);
    try expectEqual(transfer_account, tx.GetTransferAccountID());
    try expectEqual(ContractId{}, tx.GetTransferContractID());
}

test "ContractDeleteTransaction transfer to contract" {
    var tx = ContractDeleteTransaction.init(allocator);
    defer tx.deinit();
    
    const contract_id = ContractId.init(0, 0, 1001);
    _ = try tx.SetContractID(contract_id);
    
    const transfer_contract = ContractId.init(0, 0, 1002);
    _ = try tx.SetTransferContractID(transfer_contract);
    try expectEqual(transfer_contract, tx.GetTransferContractID());
    try expectEqual(AccountId{}, tx.GetTransferAccountID());
}

test "ContractDeleteTransaction permanent removal flag" {
    var tx = ContractDeleteTransaction.init(allocator);
    defer tx.deinit();
    
    _ = try tx.SetPermanentRemoval(true);
    try expect(tx.GetPermanentRemoval());
    
    _ = try tx.SetPermanentRemoval(false);
    try expect(!tx.GetPermanentRemoval());
}

test "ContractDeleteTransaction execution validation" {
    var tx = ContractDeleteTransaction.init(allocator);
    defer tx.deinit();
    
    var client = @import("../../src/network/client.zig").Client.init(allocator);
    defer client.deinit();
    
    // Should fail without contract ID
    try expectError(error.ContractIdRequired, tx.execute(&client));
    
    const contract_id = ContractId.init(0, 0, 1001);
    _ = try tx.SetContractID(contract_id);
    
    // Should fail without transfer target
    try expectError(error.TransferTargetRequired, tx.execute(&client));
}

// Contract Log Info Tests
test "ContractLogInfo structure" {
    const log_info = ContractFunctionResult.ContractLogInfo{
        .contract_id = ContractId.init(0, 0, 1001),
        .bloom = "bloom_filter_data",
        .topics = &[_][]const u8{ "topic1", "topic2", "topic3" },
        .data = "log_event_data",
    };
    
    try expectEqual(ContractId.init(0, 0, 1001), log_info.contract_id);
    try expectEqualSlices(u8, "bloom_filter_data", log_info.bloom);
    try expectEqual(@as(usize, 3), log_info.topics.len);
    try expectEqualSlices(u8, "topic1", log_info.topics[0]);
    try expectEqualSlices(u8, "log_event_data", log_info.data);
}

// Error Handling Tests
test "Contract operations with invalid parameters" {
    // Test invalid gas values
    var create_tx = ContractCreateTransaction.init(allocator);
    defer create_tx.deinit();
    
    // Gas should be reasonable
    _ = try create_tx.setGas(0);
    try expectEqual(@as(u64, 0), create_tx.getGas());
    
    var execute_tx = ContractExecuteTransaction.init(allocator);
    defer execute_tx.deinit();
    
    _ = try execute_tx.setGas(15000000); // Max gas
    try expectEqual(@as(u64, 15000000), execute_tx.getGas());
}

test "Contract parameter encoding edge cases" {
    var params = ContractFunctionParameters.init(allocator);
    defer params.deinit();
    
    // Test empty string
    try params.addString("");
    
    // Test empty bytes
    try params.addBytes(&[_]u8{});
    
    // Test maximum uint values
    try params.addUint8(255);
    try params.addUint16(65535);
    try params.addUint32(4294967295);
    try params.addUint64(18446744073709551615);
    
    // Test minimum int values
    try params.addInt8(-128);
    try params.addInt16(-32768);
    try params.addInt32(-2147483648);
    try params.addInt64(-9223372036854775808);
    
    try expectEqual(@as(usize, 10), params.arguments.items.len);
}

// Integration Tests
test "Complete contract creation flow" {
    var create_tx = ContractCreateTransaction.init(allocator);
    defer create_tx.deinit();
    
    // Set up contract creation transaction
    const bytecode_file = FileId.init(0, 0, 2001);
    _ = try create_tx.setBytecodeFileId(bytecode_file);
    
    const private_key = try PrivateKey.generateEd25519();
    defer private_key.deinit();
    const admin_key = Key{ .ed25519_public_key = private_key.public_key.toStringRaw() };
    _ = try create_tx.setAdminKey(admin_key);
    
    _ = try create_tx.setGas(300000);
    _ = try create_tx.setInitialBalance(try Hbar.from(10));
    _ = try create_tx.setMemo("Integration test contract");
    _ = try create_tx.setMaxAutomaticTokenAssociations(1000);
    
    const auto_renew_period = Duration{ .seconds = 7890000, .nanos = 0 };
    _ = try create_tx.setAutoRenewPeriod(auto_renew_period);
    
    // Verify all properties are set correctly
    try expectEqual(bytecode_file, create_tx.getBytecodeFileID());
    try expectEqual(admin_key, create_tx.getAdminKey().?);
    try expectEqual(@as(u64, 300000), create_tx.getGas());
    try expectEqualSlices(u8, "Integration test contract", create_tx.getContractMemo());
    try expectEqual(@as(i32, 1000), create_tx.getMaxAutomaticTokenAssociations());
    try expectEqual(auto_renew_period, create_tx.getAutoRenewPeriod());
}

test "Contract execution with complex parameters" {
    var execute_tx = ContractExecuteTransaction.init(allocator);
    defer execute_tx.deinit();
    
    const contract_id = ContractId.init(0, 0, 1001);
    _ = try execute_tx.setContractId(contract_id);
    _ = try execute_tx.setGas(500000);
    _ = try execute_tx.setPayableAmount(try Hbar.from(1));
    
    // Create complex function parameters
    var params = ContractFunctionParameters.init(allocator);
    defer params.deinit();
    
    // Simulate a complex function call: transferFrom(address,address,uint256)
    try params.addAddress("0x1234567890abcdef1234567890abcdef12345678");
    try params.addAddress("0xfedcba0987654321fedcba0987654321fedcba09");
    try params.addUint256(1000000000); // 1 billion tokens
    
    _ = try execute_tx.setFunction("transferFrom(address,address,uint256)", &params);
    
    try expectEqual(contract_id, execute_tx.getContractId());
    try expectEqual(@as(u64, 500000), execute_tx.getGas());
    
    const function_params = execute_tx.getFunctionParameters();
    try expect(function_params.len > 4); // Should have function selector + parameters
}

test "Contract query with result parsing" {
    var query = ContractCallQuery.init(allocator);
    defer query.deinit();
    
    const contract_id = ContractId.init(0, 0, 1001);
    _ = try query.setContractId(contract_id);
    _ = try query.setGas(100000);
    _ = try query.setMaxResultSize(4096);
    
    // Set up balance query parameters
    var params = ContractFunctionParameters.init(allocator);
    defer params.deinit();
    
    try params.addAddress("0x1234567890abcdef1234567890abcdef12345678");
    _ = try query.setFunction("balanceOf(address)", params);
    
    const sender_id = AccountId.init(0, 0, 500);
    _ = try query.setSenderId(sender_id);
}

test "Contract update with comprehensive changes" {
    var update_tx = ContractUpdateTransaction.init(allocator);
    defer update_tx.deinit();
    
    const contract_id = ContractId.init(0, 0, 1001);
    _ = try update_tx.SetContractID(contract_id);
    
    // Update expiration time
    const new_expiration = Timestamp{ .seconds = 2000000000, .nanos = 0 };
    _ = try update_tx.SetExpirationTime(new_expiration);
    
    // Update admin key
    const private_key = try PrivateKey.generateEd25519();
    defer private_key.deinit();
    const new_admin_key = Key{ .ed25519_public_key = private_key.public_key.toStringRaw() };
    _ = try update_tx.SetAdminKey(new_admin_key);
    
    // Update memo
    _ = try update_tx.SetContractMemo("Updated contract memo");
    
    // Update auto-renew settings
    const new_auto_renew_period = Duration{ .seconds = 8640000, .nanos = 0 };
    _ = try update_tx.SetAutoRenewPeriod(new_auto_renew_period);
    
    const auto_renew_account = AccountId.init(0, 0, 700);
    _ = try update_tx.SetAutoRenewAccountID(auto_renew_account);
    
    // Update staking
    const staked_account = AccountId.init(0, 0, 800);
    _ = try update_tx.SetStakedAccountID(staked_account);
    _ = try update_tx.SetDeclineStakingReward(true);
    
    // Update token associations
    _ = try update_tx.SetMaxAutomaticTokenAssociations(2000);
    
    // Verify all updates
    try expectEqual(contract_id, update_tx.GetContractID());
    try expectEqual(new_expiration, update_tx.GetExpirationTime());
    try expectEqual(new_admin_key, update_tx.GetAdminKey().?);
    try expectEqualSlices(u8, "Updated contract memo", update_tx.GetContractMemo());
    try expectEqual(new_auto_renew_period, update_tx.GetAutoRenewPeriod());
    try expectEqual(auto_renew_account, update_tx.GetAutoRenewAccountID());
    try expectEqual(staked_account, update_tx.GetStakedAccountID());
    try expect(update_tx.GetDeclineStakingReward());
    try expectEqual(@as(i32, 2000), update_tx.GetMaxAutomaticTokenAssociations());
}

test "Contract deletion with balance transfer scenarios" {
    // Test deletion with account transfer
    var delete_tx1 = ContractDeleteTransaction.init(allocator);
    defer delete_tx1.deinit();
    
    const contract_to_delete = ContractId.init(0, 0, 1001);
    _ = try delete_tx1.SetContractID(contract_to_delete);
    
    const beneficiary_account = AccountId.init(0, 0, 500);
    _ = try delete_tx1.SetTransferAccountID(beneficiary_account);
    _ = try delete_tx1.SetPermanentRemoval(true);
    
    try expectEqual(contract_to_delete, delete_tx1.GetContractID());
    try expectEqual(beneficiary_account, delete_tx1.GetTransferAccountID());
    try expect(delete_tx1.GetPermanentRemoval());
    
    // Test deletion with contract transfer
    var delete_tx2 = ContractDeleteTransaction.init(allocator);
    defer delete_tx2.deinit();
    
    _ = try delete_tx2.SetContractID(contract_to_delete);
    
    const beneficiary_contract = ContractId.init(0, 0, 1002);
    _ = try delete_tx2.SetTransferContractID(beneficiary_contract);
    
    try expectEqual(beneficiary_contract, delete_tx2.GetTransferContractID());
    try expectEqual(AccountId{}, delete_tx2.GetTransferAccountID());
}
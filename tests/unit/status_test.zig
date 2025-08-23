const std = @import("std");
const testing = std.testing;
const hedera.Status = @import("../../src/core/status.zig").hedera.Status;

test "hedera.Status values" {
    const ok = Status.OK;
    const invalid_transaction = Status.INVALID_TRANSACTION;
    const payer_account_not_found = Status.PAYER_ACCOUNT_NOT_FOUND;
    
    try testing.expectEqual(Status.OK, ok);
    try testing.expect(ok != invalid_transaction);
    try testing.expect(invalid_transaction != payer_account_not_found);
}

test "hedera.Status toString" {
    const allocator = testing.allocator;
    
    const str_ok = try Status.toString(allocator, Status.OK);
    defer allocator.free(str_ok);
    try testing.expectEqualStrings("OK", str_ok);
    
    const str_invalid = try Status.toString(allocator, Status.INVALID_TRANSACTION);
    defer allocator.free(str_invalid);
    try testing.expectEqualStrings("INVALID_TRANSACTION", str_invalid);
}

test "hedera.Status fromString" {
    const ok = try Status.fromString("OK");
    try testing.expectEqual(Status.OK, ok);
    
    const invalid = try Status.fromString("INVALID_TRANSACTION");
    try testing.expectEqual(Status.INVALID_TRANSACTION, invalid);
    
    // Test invalid string
    const result = Status.fromString("INVALID_STATUS_NAME");
    try testing.expectError(error.UnknownStatus, result);
}

test "hedera.Status isSuccess" {
    try testing.expect(Status.isSuccess(Status.OK));
    try testing.expect(Status.isSuccess(Status.SUCCESS));
    try testing.expect(!Status.isSuccess(Status.INVALID_TRANSACTION));
    try testing.expect(!Status.isSuccess(Status.PAYER_ACCOUNT_NOT_FOUND));
}

test "hedera.Status isError" {
    try testing.expect(!Status.isError(Status.OK));
    try testing.expect(!Status.isError(Status.SUCCESS));
    try testing.expect(Status.isError(Status.INVALID_TRANSACTION));
    try testing.expect(Status.isError(Status.INSUFFICIENT_ACCOUNT_BALANCE));
}

test "hedera.Status code values" {
    // Test specific status code values match expected protocol values
    try testing.expectEqual(@as(i32, 0), @intFromEnum(Status.OK));
    try testing.expectEqual(@as(i32, 1), @intFromEnum(Status.INVALID_TRANSACTION));
    try testing.expectEqual(@as(i32, 2), @intFromEnum(Status.PAYER_ACCOUNT_NOT_FOUND));
    try testing.expectEqual(@as(i32, 3), @intFromEnum(Status.INVALID_TRANSACTION_START));
    try testing.expectEqual(@as(i32, 4), @intFromEnum(Status.INSUFFICIENT_ACCOUNT_BALANCE));
}

test "hedera.Status from code" {
    const ok = Status.fromCode(0);
    try testing.expectEqual(Status.OK, ok);
    
    const invalid = Status.fromCode(1);
    try testing.expectEqual(Status.INVALID_TRANSACTION, invalid);
    
    const insufficient = Status.fromCode(4);
    try testing.expectEqual(Status.INSUFFICIENT_ACCOUNT_BALANCE, insufficient);
}

test "hedera.Status to code" {
    try testing.expectEqual(@as(i32, 0), Status.toCode(Status.OK));
    try testing.expectEqual(@as(i32, 1), Status.toCode(Status.INVALID_TRANSACTION));
    try testing.expectEqual(@as(i32, 4), Status.toCode(Status.INSUFFICIENT_ACCOUNT_BALANCE));
}

test "hedera.Status protobuf serialization" {
    const allocator = testing.allocator;
    var writer = @import("../../src/protobuf/writer.zig").ProtoWriter.init(allocator);
    defer writer.deinit();
    
    try Status.toProtobuf(&writer, Status.OK);
    
    const bytes = try writer.finalize();
    defer allocator.free(bytes);
    
    try testing.expect(bytes.len > 0);
}

test "hedera.Status protobuf deserialization" {
    const allocator = testing.allocator;
    
    // Create serialized data
    var writer = @import("../../src/protobuf/writer.zig").ProtoWriter.init(allocator);
    defer writer.deinit();
    
    const original = Status.INVALID_TRANSACTION;
    try Status.toProtobuf(&writer, original);
    
    const bytes = try writer.finalize();
    defer allocator.free(bytes);
    
    // Deserialize
    const deserialized = try Status.fromProtobuf(bytes);
    
    try testing.expectEqual(original, deserialized);
}

test "hedera.Status error conversion" {
    const err = Status.toError(Status.INSUFFICIENT_ACCOUNT_BALANCE);
    try testing.expectError(error.InsufficientAccountBalance, err);
    
    const err2 = Status.toError(Status.INVALID_TRANSACTION);
    try testing.expectError(error.InvalidTransaction, err2);
}

test "hedera.Status all known codes" {
    // Test that all common status codes are defined
    _ = Status.OK;
    _ = Status.INVALID_TRANSACTION;
    _ = Status.PAYER_ACCOUNT_NOT_FOUND;
    _ = Status.INVALID_TRANSACTION_START;
    _ = Status.INSUFFICIENT_ACCOUNT_BALANCE;
    _ = Status.INVALID_SIGNATURE;
    _ = Status.KEY_NOT_PROVIDED;
    _ = Status.INVALID_ACCOUNT_ID;
    _ = Status.DUPLICATE_TRANSACTION;
    _ = Status.BUSY;
    _ = Status.NOT_SUPPORTED;
    _ = Status.INVALID_FILE_ID;
    _ = Status.INVALID_CONTRACT_ID;
    _ = Status.INVALID_TRANSACTION_ID;
    _ = Status.RECEIPT_NOT_FOUND;
    _ = Status.RECORD_NOT_FOUND;
    _ = Status.INVALID_SOLIDITY_ADDRESS;
    _ = Status.CONTRACT_EXECUTION_EXCEPTION;
    _ = Status.CONTRACT_REVERT_EXECUTED;
    _ = Status.INVALID_RECEIVING_NODE_ACCOUNT;
    _ = Status.MISSING_QUERY_HEADER;
    _ = Status.ACCOUNT_UPDATE_FAILED;
    _ = Status.INVALID_KEY_ENCODING;
    _ = Status.NULL_SOLIDITY_ADDRESS;
    _ = Status.CONTRACT_UPDATE_FAILED;
    _ = Status.INVALID_QUERY_HEADER;
    _ = Status.INVALID_FEE_SUBMITTED;
    _ = Status.INVALID_PAYER_SIGNATURE;
    _ = Status.KEY_PREFIX_MISMATCH;
    _ = Status.PLATFORM_TRANSACTION_NOT_CREATED;
    _ = Status.INVALID_RENEWAL_PERIOD;
    _ = Status.INVALID_PAYER_ACCOUNT_ID;
    _ = Status.ACCOUNT_DELETED;
    _ = Status.FILE_DELETED;
    _ = Status.ACCOUNT_REPEATED_IN_ACCOUNT_AMOUNTS;
    _ = Status.SETTING_NEGATIVE_ACCOUNT_BALANCE;
    _ = Status.OBTAINER_REQUIRED;
    _ = Status.OBTAINER_SAME_CONTRACT_ID;
    _ = Status.OBTAINER_DOES_NOT_EXIST;
    _ = Status.MODIFYING_IMMUTABLE_CONTRACT;
    _ = Status.FILE_SYSTEM_EXCEPTION;
    _ = Status.AUTORENEW_DURATION_NOT_IN_RANGE;
    _ = Status.ERROR_DECODING_BYTESTRING;
    _ = Status.CONTRACT_FILE_EMPTY;
    _ = Status.CONTRACT_BYTECODE_EMPTY;
    _ = Status.INVALID_INITIAL_BALANCE;
    _ = Status.INVALID_RECEIVE_RECORD_THRESHOLD;
    _ = Status.INVALID_SEND_RECORD_THRESHOLD;
    _ = Status.ACCOUNT_IS_NOT_GENESIS_ACCOUNT;
    _ = Status.PAYER_ACCOUNT_UNAUTHORIZED;
    _ = Status.INVALID_FREEZE_TRANSACTION_BODY;
    _ = Status.FREEZE_TRANSACTION_BODY_NOT_FOUND;
    _ = Status.TRANSFER_LIST_SIZE_LIMIT_EXCEEDED;
    _ = Status.RESULT_SIZE_LIMIT_EXCEEDED;
    _ = Status.NOT_SPECIAL_ACCOUNT;
    _ = Status.CONTRACT_NEGATIVE_GAS;
    _ = Status.CONTRACT_NEGATIVE_VALUE;
    _ = Status.INVALID_FEE_FILE;
    _ = Status.INVALID_EXCHANGE_RATE_FILE;
    _ = Status.INSUFFICIENT_LOCAL_CALL_GAS;
    _ = Status.ENTITY_NOT_ALLOWED_TO_DELETE;
    _ = Status.AUTHORIZATION_FAILED;
    _ = Status.FILE_UPLOADED_PROTO_INVALID;
    _ = Status.FILE_UPLOADED_PROTO_NOT_SAVED_TO_DISK;
    _ = Status.FEE_SCHEDULE_FILE_PART_UPLOADED;
    _ = Status.EXCHANGE_RATE_CHANGE_LIMIT_EXCEEDED;

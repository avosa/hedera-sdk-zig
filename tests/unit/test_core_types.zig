const std = @import("std");
const testing = std.testing;
const hedera = @import("hedera");

test "AccountId creation and validation" {
    // Test basic account ID creation
    const account = hedera.AccountId.init(0, 0, 3);
    try testing.expectEqual(@as(u64, 0), account.shard);
    try testing.expectEqual(@as(u64, 0), account.realm);
    try testing.expectEqual(@as(u64, 3), account.num());
    
    // Test checksum calculation
    const checksum = account.calculateChecksum();
    try testing.expect(checksum.len > 0);
    
    // Test string parsing
    const parsed = try hedera.AccountId.fromString("0.0.3");
    try testing.expect(parsed.equals(account));
    
    // Test invalid string parsing
    try testing.expectError(error.InvalidAccountId, hedera.AccountId.fromString("invalid"));
    try testing.expectError(error.InvalidAccountId, hedera.AccountId.fromString("0.0"));
    try testing.expectError(error.InvalidAccountId, hedera.AccountId.fromString("0.0.a"));
}

test "ContractId creation and validation" {
    const contract = hedera.ContractId.init(0, 0, 1001);
    try testing.expectEqual(@as(u64, 0), contract.shard);
    try testing.expectEqual(@as(u64, 0), contract.realm);
    try testing.expectEqual(@as(u64, 1001), contract.num());
    
    const parsed = try hedera.ContractId.fromString("0.0.1001");
    try testing.expect(parsed.equals(contract));
}

test "FileId creation and validation" {
    const file = hedera.FileId.init(0, 0, 150);
    try testing.expectEqual(@as(u64, 0), file.shard);
    try testing.expectEqual(@as(u64, 0), file.realm);
    try testing.expectEqual(@as(u64, 150), file.num());
    
    const parsed = try hedera.FileId.fromString("0.0.150");
    try testing.expect(parsed.equals(file));
}

test "TokenId creation and validation" {
    const token = hedera.TokenId.init(0, 0, 2000);
    try testing.expectEqual(@as(u64, 0), token.shard);
    try testing.expectEqual(@as(u64, 0), token.realm);
    try testing.expectEqual(@as(u64, 2000), token.num());
    
    const parsed = try hedera.TokenId.fromString("0.0.2000");
    try testing.expect(parsed.equals(token));
}

test "TopicId creation and validation" {
    const topic = hedera.TopicId.init(0, 0, 5000);
    try testing.expectEqual(@as(u64, 0), topic.shard);
    try testing.expectEqual(@as(u64, 0), topic.realm);
    try testing.expectEqual(@as(u64, 5000), topic.num());
    
    const parsed = try hedera.TopicId.fromString("0.0.5000");
    try testing.expect(parsed.equals(topic));
}

test "ScheduleId creation and validation" {
    const schedule = hedera.ScheduleId.init(0, 0, 3000);
    try testing.expectEqual(@as(u64, 0), schedule.shard);
    try testing.expectEqual(@as(u64, 0), schedule.realm);
    try testing.expectEqual(@as(u64, 3000), schedule.num());
    
    const parsed = try hedera.ScheduleId.fromString("0.0.3000");
    try testing.expect(parsed.equals(schedule));
}

test "NftId creation and validation" {
    const nft = hedera.NftId.init(hedera.TokenId.init(0, 0, 1000), 123);
    try testing.expect(nft.token_id.equals(hedera.TokenId.init(0, 0, 1000)));
    try testing.expectEqual(@as(u64, 123), nft.serial_number);
    
    const parsed = try hedera.NftId.fromString("0.0.1000/123");
    try testing.expect(parsed.equals(nft));
    
    try testing.expectError(error.InvalidNftId, hedera.NftId.fromString("0.0.1000"));
    try testing.expectError(error.InvalidNftId, hedera.NftId.fromString("invalid/123"));
}

test "Hbar creation and conversion" {
    // Test creation from different units
    const hbar_from_hbar = try hedera.Hbar.from(100);
    try testing.expectEqual(@as(i64, 10_000_000_000), hbar_from_hbar.toTinybars());
    try testing.expectEqual(@as(f64, 100.0), hbar_from_hbar.toHbars());
    
    const hbar_from_tinybars = hedera.Hbar.fromTinybars(50_000_000_000);
    try testing.expectEqual(@as(i64, 50_000_000_000), hbar_from_tinybars.toTinybars());
    try testing.expectEqual(@as(f64, 500.0), hbar_from_tinybars.toHbars());
    
    // Test unit conversions
    const one_hbar = try hedera.Hbar.from(1);
    try testing.expectEqual(@as(i64, 100_000_000), one_hbar.toMicrobars());
    try testing.expectEqual(@as(i64, 100_000), one_hbar.toMillibars());
    try testing.expectEqual(@as(i64, 100_000_000_000), one_hbar.toTinybars());
    
    // Test arithmetic operations
    const hbar1 = try hedera.Hbar.from(10);
    const hbar2 = try hedera.Hbar.from(5);
    
    const sum = hbar1.add(hbar2);
    try testing.expectEqual(@as(f64, 15.0), sum.toHbars());
    
    const diff = hbar1.subtract(hbar2);
    try testing.expectEqual(@as(f64, 5.0), diff.toHbars());
    
    const negative = hbar2.subtract(hbar1);
    try testing.expectEqual(@as(f64, -5.0), negative.toHbars());
    
    // Test comparison
    try testing.expect(hbar1.greaterThan(hbar2));
    try testing.expect(hbar2.lessThan(hbar1));
    try testing.expect(hbar1.equals(hbar1));
    
    // Test zero and constants
    const zero = hedera.Hbar.ZERO;
    try testing.expectEqual(@as(i64, 0), zero.toTinybars());
    
    const max_hbar = hedera.Hbar.MAX;
    try testing.expect(max_hbar.greaterThan(zero));
    
    const min_hbar = hedera.Hbar.MIN;
    try testing.expect(min_hbar.lessThan(zero));
}

test "Timestamp creation and conversion" {
    const timestamp = hedera.Timestamp.init(1640995200, 123456789);
    try testing.expectEqual(@as(i64, 1640995200), timestamp.seconds);
    try testing.expectEqual(@as(i32, 123456789), timestamp.nanos);
    
    // Test Unix timestamp conversion
    const from_unix = hedera.Timestamp.fromUnixSeconds(1640995200);
    try testing.expectEqual(@as(i64, 1640995200), from_unix.seconds);
    try testing.expectEqual(@as(i32, 0), from_unix.nanos);
    
    const unix_millis = hedera.Timestamp.fromUnixMilliseconds(1640995200123);
    try testing.expectEqual(@as(i64, 1640995200), unix_millis.seconds);
    try testing.expectEqual(@as(i32, 123_000_000), unix_millis.nanos);
    
    // Test conversion back to Unix
    try testing.expectEqual(@as(i64, 1640995200), timestamp.toUnixSeconds());
    try testing.expectEqual(@as(i64, 1640995200123), unix_millis.toUnixMilliseconds());
    
    // Test arithmetic
    const duration = hedera.Duration.init(3600, 0); // 1 hour
    const later = timestamp.add(duration);
    try testing.expectEqual(@as(i64, 1640998800), later.seconds);
    
    const earlier = timestamp.subtract(duration);
    try testing.expectEqual(@as(i64, 1640991600), earlier.seconds);
    
    // Test comparison
    try testing.expect(later.after(timestamp));
    try testing.expect(earlier.before(timestamp));
    try testing.expect(timestamp.equals(timestamp));
}

test "Duration creation and conversion" {
    const duration = hedera.Duration.init(3661, 500_000_000); // 1h 1m 1s 500ms
    try testing.expectEqual(@as(i64, 3661), duration.seconds);
    try testing.expectEqual(@as(i32, 500_000_000), duration.nanos);
    
    // Test conversion methods
    try testing.expectEqual(@as(i64, 3661500), duration.toMilliseconds());
    try testing.expectEqual(@as(i64, 3661), duration.toSeconds());
    try testing.expectEqual(@as(f64, 60.0 + 1.0/60.0 + 1.0/3600.0 + 500.0/3600000.0), duration.toMinutes());
    try testing.expectEqual(@as(f64, 1.0 + 1.0/60.0 + 1.0/3600.0 + 500.0/3600000.0), duration.toHours());
    
    // Test creation from different units
    const from_seconds = hedera.Duration.fromSeconds(3600);
    try testing.expectEqual(@as(i64, 3600), from_seconds.seconds);
    try testing.expectEqual(@as(i32, 0), from_seconds.nanos);
    
    const from_minutes = hedera.Duration.fromMinutes(60);
    try testing.expectEqual(@as(i64, 3600), from_minutes.seconds);
    
    const from_hours = hedera.Duration.fromHours(24);
    try testing.expectEqual(@as(i64, 86400), from_hours.seconds);
    
    const from_days = hedera.Duration.fromDays(7);
    try testing.expectEqual(@as(i64, 604800), from_days.seconds);
    
    // Test arithmetic
    const duration1 = hedera.Duration.fromMinutes(30);
    const duration2 = hedera.Duration.fromMinutes(45);
    
    const sum = duration1.add(duration2);
    try testing.expectEqual(@as(i64, 4500), sum.seconds); // 75 minutes
    
    const diff = duration2.subtract(duration1);
    try testing.expectEqual(@as(i64, 900), diff.seconds); // 15 minutes
    
    // Test comparison
    try testing.expect(duration2.greaterThan(duration1));
    try testing.expect(duration1.lessThan(duration2));
    try testing.expect(duration1.equals(duration1));
}

test "TransactionId creation and validation" {
    const allocator = testing.allocator;
    const account = hedera.AccountId.init(0, 0, 3);
    
    // Test basic TransactionId generation
    const tx_id = hedera.TransactionId.generate(account);
    try testing.expect(tx_id.isValid());
    try testing.expect(tx_id.account_id.equals(account));
    try testing.expect(tx_id.valid_start.seconds > 0);
    
    // Test TransactionId with specific timestamp
    const timestamp = hedera.Timestamp.fromUnixSeconds(1640995200);
    const tx_id_with_time = hedera.TransactionId.initWithTimestamp(account, timestamp);
    try testing.expect(tx_id_with_time.isValid());
    try testing.expect(tx_id_with_time.account_id.equals(account));
    try testing.expectEqual(@as(i64, 1640995200), tx_id_with_time.valid_start.seconds);
    
    // Test TransactionId with nonce
    const tx_id_with_nonce = hedera.TransactionId.initWithNonce(account, 12345);
    try testing.expect(tx_id_with_nonce.isValid());
    try testing.expectEqual(@as(u32, 12345), tx_id_with_nonce.nonce.?);
    
    // Test string conversion and parsing
    const tx_id_str = try tx_id.toString(allocator);
    defer allocator.free(tx_id_str);
    
    const parsed_tx_id = try hedera.TransactionId.fromString(tx_id_str, allocator);
    defer parsed_tx_id.deinit();
    
    try testing.expect(parsed_tx_id.account_id.equals(tx_id.account_id));
    try testing.expectEqual(tx_id.valid_start.seconds, parsed_tx_id.valid_start.seconds);
    
    // Test invalid string parsing
    try testing.expectError(error.InvalidTransactionId, hedera.TransactionId.fromString("invalid", allocator));
    try testing.expectError(error.InvalidTransactionId, hedera.TransactionId.fromString("0.0.3", allocator));
}

test "Status codes and error handling" {
    // Test status code conversion
    try testing.expectEqual(hedera.HederaError.Success, hedera.StatusCode.fromCode(0));
    try testing.expectEqual(hedera.HederaError.InvalidTransaction, hedera.StatusCode.fromCode(1));
    try testing.expectEqual(hedera.HederaError.PayerAccountNotFound, hedera.StatusCode.fromCode(2));
    try testing.expectEqual(hedera.HederaError.InvalidSignature, hedera.StatusCode.fromCode(7));
    try testing.expectEqual(hedera.HederaError.InsufficientTxFee, hedera.StatusCode.fromCode(9));
    
    // Test unknown status code
    try testing.expectEqual(hedera.HederaError.Unknown, hedera.StatusCode.fromCode(99999));
    
    // Test status descriptions
    const success_desc = hedera.StatusCode.getDescription(hedera.HederaError.Success);
    try testing.expect(success_desc.len > 0);
    
    const invalid_tx_desc = hedera.StatusCode.getDescription(hedera.HederaError.InvalidTransaction);
    try testing.expect(invalid_tx_desc.len > 0);
    
    const unknown_desc = hedera.StatusCode.getDescription(hedera.HederaError.Unknown);
    try testing.expect(unknown_desc.len > 0);
    
    // Test that descriptions are different
    try testing.expect(!std.mem.eql(u8, success_desc, invalid_tx_desc));
}

test "Result type operations" {
    const allocator = testing.allocator;
    
    // Test successful result
    const success_result: hedera.Result(i32) = .{ .success = 42 };
    try testing.expect(success_result.isSuccess());
    try testing.expect(!success_result.isError());
    try testing.expectEqual(@as(i32, 42), success_result.success);
    
    // Test error result
    const error_result: hedera.Result(i32) = .{ .err = hedera.HederaError.InvalidTransaction };
    try testing.expect(!error_result.isSuccess());
    try testing.expect(error_result.isError());
    try testing.expectEqual(hedera.HederaError.InvalidTransaction, error_result.err);
    
    // Test unwrap operations
    try testing.expectEqual(@as(i32, 42), try success_result.unwrap());
    try testing.expectError(hedera.HederaError.InvalidTransaction, error_result.unwrap());
    
    // Test unwrap with default
    try testing.expectEqual(@as(i32, 42), success_result.unwrapOr(0));
    try testing.expectEqual(@as(i32, 0), error_result.unwrapOr(0));
}

test "Entity ID format validation" {
    // Test various valid formats
    const valid_ids = [_][]const u8{
        "0.0.3",
        "1.2.3",
        "999.999.999999",
        "0.0.1234567890",
    };
    
    for (valid_ids) |id_str| {
        const account = hedera.AccountId.fromString(id_str) catch |err| {
            std.log.err("Failed to parse valid AccountId '{s}': {}", .{ id_str, err });
            return err;
        };
        const reconstructed = account.toString();
        defer std.testing.allocator.free(reconstructed);
        try testing.expect(std.mem.eql(u8, id_str, reconstructed));
    }
    
    // Test invalid formats
    const invalid_ids = [_][]const u8{
        "",
        "0",
        "0.0",
        "0.0.3.4",
        "a.b.c",
        "0.0.a",
        "0.a.3",
        "a.0.3",
        "-1.0.3",
        "0.-1.3",
        "0.0.-3",
    };
    
    for (invalid_ids) |invalid_id| {
        try testing.expectError(error.InvalidAccountId, hedera.AccountId.fromString(invalid_id));
    }
}


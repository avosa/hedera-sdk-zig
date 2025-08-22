const std = @import("std");
const testing = std.testing;
const hedera = @import("hedera");

test "AccountId parsing and formatting" {
    const allocator = testing.allocator;
    
    // Test fromString
    const account_id = try hedera.AccountId.fromString(allocator, "0.0.1234");
    try testing.expectEqual(@as(u64, 0), account_id.entity.shard);
    try testing.expectEqual(@as(u64, 0), account_id.entity.realm);
    try testing.expectEqual(@as(u64, 1234), account_id.entity.num);
    
    // Test Go SDK compatible function
    const account_id2 = try hedera.account_id_from_string(allocator, "0.0.5678");
    try testing.expectEqual(@as(u64, 5678), account_id2.entity.num);
    
    // Test toString
    const str = try account_id.toString(allocator);
    defer allocator.free(str);
    try testing.expectEqualStrings("0.0.1234", str);
    
    // Test with checksum
    const account_with_checksum = try hedera.AccountId.fromString(allocator, "0.0.1234-abcde");
    try testing.expectEqual(@as(u64, 1234), account_with_checksum.entity.num);
    try testing.expectEqualStrings("abcde", account_with_checksum.entity.checksum.?);
    if (account_with_checksum.entity.checksum) |cs| {
        allocator.free(cs);
    }
    
    // Test EVM address
    const evm_account = try hedera.AccountId.fromString(allocator, "0x1234567890123456789012345678901234567890");
    try testing.expect(evm_account.evm_address != null);
    if (evm_account.evm_address) |addr| {
        allocator.free(addr);
    }
}

test "Hbar conversions" {
    // Test from different units
    const hbar1 = try hedera.Hbar.from(100);
    try testing.expectEqual(@as(i64, 10_000_000_000), hbar1.tinybars);
    
    const hbar2 = try hedera.Hbar.fromTinybars(50_000_000);
    try testing.expectEqual(@as(i64, 50_000_000), hbar2.tinybars);
    
    // Test arithmetic
    const sum = try hbar1.add(hbar2);
    try testing.expectEqual(@as(i64, 10_050_000_000), sum.tinybars);
    
    const diff = try hbar1.subtract(hbar2);
    try testing.expectEqual(@as(i64, 9_950_000_000), diff.tinybars);
    
    const product = try hbar2.multiply(2);
    try testing.expectEqual(@as(i64, 100_000_000), product.tinybars);
    
    // Test comparison
    try testing.expect(hbar1.compare(hbar2) == .gt);
    try testing.expect(hbar2.compare(hbar1) == .lt);
    try testing.expect(hbar1.compare(hbar1) == .eq);
    
    // Test zero and max
    const zero = hedera.Hbar.zero();
    try testing.expectEqual(@as(i64, 0), zero.tinybars);
    
    const max = hedera.Hbar.max();
    try testing.expectEqual(@as(i64, 5_000_000_000_000_000_000), max.tinybars);
}

test "TransactionId generation and parsing" {
    const allocator = testing.allocator;
    
    const account_id = hedera.AccountId.init(0, 0, 100);
    const tx_id = hedera.TransactionId.generate(account_id);
    
    try testing.expectEqual(account_id.entity.num, tx_id.account_id.entity.num);
    try testing.expect(tx_id.valid_start.seconds > 0);
    
    // Test toString
    const str = try tx_id.toString(allocator);
    defer allocator.free(str);
    try testing.expect(std.mem.indexOf(u8, str, "0.0.100@") != null);
    
    // Test with nonce
    var tx_id_with_nonce = tx_id;
    tx_id_with_nonce.nonce = 42;
    try testing.expectEqual(@as(u32, 42), tx_id_with_nonce.nonce.?);
    
    // Test scheduled flag
    var scheduled_tx_id = tx_id;
    scheduled_tx_id.scheduled = true;
    try testing.expect(scheduled_tx_id.scheduled);
}

test "Duration operations" {
    const duration1 = hedera.Duration.fromDays(7);
    try testing.expectEqual(@as(i64, 604800), duration1.seconds);
    
    const duration2 = hedera.Duration.fromHours(24);
    try testing.expectEqual(@as(i64, 86400), duration2.seconds);
    
    const duration3 = hedera.Duration.fromMinutes(60);
    try testing.expectEqual(@as(i64, 3600), duration3.seconds);
    
    const duration4 = hedera.Duration.fromSeconds(3600);
    try testing.expectEqual(@as(i64, 3600), duration4.seconds);
    
    // Test conversions
    try testing.expectEqual(@as(f64, 7), duration1.toDays());
    try testing.expectEqual(@as(f64, 168), duration1.toHours());
    try testing.expectEqual(@as(f64, 10080), duration1.toMinutes());
}

test "Timestamp operations" {
    const now = hedera.Timestamp.now();
    try testing.expect(now.seconds > 0);
    
    const from_seconds = hedera.Timestamp{ .seconds = 1234567890, .nanos = 0 };
    try testing.expectEqual(@as(i64, 1234567890), from_seconds.seconds);
    try testing.expectEqual(@as(i32, 0), from_seconds.nanos);
    
    const with_nanos = hedera.Timestamp{
        .seconds = 1000,
        .nanos = 500000000,
    };
    try testing.expectEqual(@as(i64, 1000), with_nanos.seconds);
    try testing.expectEqual(@as(i32, 500000000), with_nanos.nanos);
    
    // Test comparison
    const t1 = hedera.Timestamp{ .seconds = 100, .nanos = 0 };
    const t2 = hedera.Timestamp{ .seconds = 200, .nanos = 0 };
    const t3 = hedera.Timestamp{ .seconds = 100, .nanos = 500 };
    
    try testing.expect(t1.compare(t2) == .lt);
    try testing.expect(t2.compare(t1) == .gt);
    try testing.expect(t1.compare(t1) == .eq);
    try testing.expect(t1.compare(t3) == .lt);
}

test "Status codes" {
    // Test status code mapping
    const ok_error = hedera.StatusCode.fromCode(0);
    try testing.expectEqual(hedera.HederaError.Ok, ok_error);
    
    const success_error = hedera.StatusCode.fromCode(22);
    try testing.expectEqual(hedera.HederaError.Success, success_error);
    
    const invalid_tx_error = hedera.StatusCode.fromCode(1);
    try testing.expectEqual(hedera.HederaError.InvalidTransaction, invalid_tx_error);
}

test "EntityId operations" {
    const allocator = testing.allocator;
    
    // Test ContractId
    const contract_id = hedera.ContractId.init(0, 0, 5000);
    try testing.expectEqual(@as(u64, 5000), contract_id.entity.num);
    
    const contract_str = try contract_id.toString(allocator);
    defer allocator.free(contract_str);
    try testing.expectEqualStrings("0.0.5000", contract_str);
    
    // Test FileId
    const file_id = hedera.FileId.init(0, 0, 111);
    try testing.expectEqual(@as(u64, 111), file_id.entity.num);
    
    // Test TokenId
    const token_id = hedera.TokenId.init(0, 0, 999);
    try testing.expectEqual(@as(u64, 999), token_id.entity.num);
    
    // Test TopicId
    const topic_id = hedera.TopicId.init(0, 0, 777);
    try testing.expectEqual(@as(u64, 777), topic_id.entity.num);
    
    // Test ScheduleId
    const schedule_id = hedera.ScheduleId.init(0, 0, 333);
    try testing.expectEqual(@as(u64, 333), schedule_id.entity.num);
    
    // Test NftId
    const nft_id = hedera.NftId{
        .token_id = token_id,
        .serial_number = 42,
    };
    try testing.expectEqual(@as(u64, 999), nft_id.token_id.entity.num);
    try testing.expectEqual(@as(u64, 42), nft_id.serial_number);
}
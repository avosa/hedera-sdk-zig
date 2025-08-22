const std = @import("std");
const testing = std.testing;
const hedera.AccountId = @import("../../src/core/id.zig").hedera.AccountId;
const hedera.ContractId = @import("../../src/core/id.zig").hedera.ContractId;
const hedera.FileId = @import("../../src/core/id.zig").hedera.FileId;
const hedera.TokenId = @import("../../src/core/id.zig").hedera.TokenId;
const hedera.TopicId = @import("../../src/core/id.zig").hedera.TopicId;
const hedera.ScheduleId = @import("../../src/core/id.zig").hedera.ScheduleId;
const hedera.NftId = @import("../../src/core/id.zig").hedera.NftId;

test "hedera.AccountId creation and comparison" {
    const id1 = AccountId.init(0, 0, 100);
    const id2 = AccountId.init(0, 0, 100);
    const id3 = AccountId.init(0, 0, 200);
    
    try testing.expect(id1.equals(id2));
    try testing.expect(!id1.equals(id3));
}

test "hedera.AccountId from string parsing" {
    const allocator = testing.allocator;
    
    const id = try AccountId.fromString(allocator, "0.0.100");
    try testing.expectEqual(@as(u64, 0), id.shard);
    try testing.expectEqual(@as(u64, 0), id.realm);
    try testing.expectEqual(@as(u64, 100), id.account);
}

test "hedera.AccountId to string conversion" {
    const allocator = testing.allocator;
    
    const id = AccountId.init(0, 0, 100);
    const str = try id.toString(allocator);
    defer allocator.free(str);
    
    try testing.expectEqualStrings("0.0.100", str);
}

test "hedera.AccountId EVM address conversion" {
    const allocator = testing.allocator;
    
    const id = AccountId.init(0, 0, 100);
    const evm_address = try id.toEvmAddress(allocator);
    defer allocator.free(evm_address);
    
    try testing.expect(evm_address.len == 40); // 20 bytes hex = 40 chars
}

test "hedera.AccountId from EVM address" {
    const allocator = testing.allocator;
    
    const evm_address = "0000000000000000000000000000000000000064"; // 100 in hex
    const id = try AccountId.fromEvmAddress(allocator, evm_address);
    
    try testing.expectEqual(@as(u64, 100), id.account);
}

test "hedera.ContractId creation and comparison" {
    const id1 = ContractId.init(0, 0, 300);
    const id2 = ContractId.init(0, 0, 300);
    const id3 = ContractId.init(0, 0, 400);
    
    try testing.expect(id1.equals(id2));
    try testing.expect(!id1.equals(id3));
}

test "hedera.ContractId from string parsing" {
    const allocator = testing.allocator;
    
    const id = try ContractId.fromString(allocator, "0.0.300");
    try testing.expectEqual(@as(u64, 300), id.contract);
}

test "hedera.ContractId to string conversion" {
    const allocator = testing.allocator;
    
    const id = ContractId.init(0, 0, 300);
    const str = try id.toString(allocator);
    defer allocator.free(str);
    
    try testing.expectEqualStrings("0.0.300", str);
}

test "hedera.FileId creation and comparison" {
    const id1 = FileId.init(0, 0, 600);
    const id2 = FileId.init(0, 0, 600);
    const id3 = FileId.init(0, 0, 700);
    
    try testing.expect(id1.equals(id2));
    try testing.expect(!id1.equals(id3));
}

test "hedera.FileId from string parsing" {
    const allocator = testing.allocator;
    
    const id = try FileId.fromString(allocator, "0.0.600");
    try testing.expectEqual(@as(u64, 600), id.file);
}

test "hedera.TokenId creation and comparison" {
    const id1 = TokenId.init(0, 0, 500);
    const id2 = TokenId.init(0, 0, 500);
    const id3 = TokenId.init(0, 0, 501);
    
    try testing.expect(id1.equals(id2));
    try testing.expect(!id1.equals(id3));
}

test "hedera.TokenId from string parsing" {
    const allocator = testing.allocator;
    
    const id = try TokenId.fromString(allocator, "0.0.500");
    try testing.expectEqual(@as(u64, 500), id.token);
}

test "hedera.TopicId creation and comparison" {
    const id1 = TopicId.init(0, 0, 700);
    const id2 = TopicId.init(0, 0, 700);
    const id3 = TopicId.init(0, 0, 800);
    
    try testing.expect(id1.equals(id2));
    try testing.expect(!id1.equals(id3));
}

test "hedera.TopicId from string parsing" {
    const allocator = testing.allocator;
    
    const id = try TopicId.fromString(allocator, "0.0.700");
    try testing.expectEqual(@as(u64, 700), id.topic);
}

test "hedera.ScheduleId creation and comparison" {
    const id1 = ScheduleId.init(0, 0, 800);
    const id2 = ScheduleId.init(0, 0, 800);
    const id3 = ScheduleId.init(0, 0, 900);
    
    try testing.expect(id1.equals(id2));
    try testing.expect(!id1.equals(id3));
}

test "hedera.ScheduleId from string parsing" {
    const allocator = testing.allocator;
    
    const id = try ScheduleId.fromString(allocator, "0.0.800");
    try testing.expectEqual(@as(u64, 800), id.schedule);
}

test "hedera.NftId creation and comparison" {
    const token_id = TokenId.init(0, 0, 500);
    const id1 = hedera.NftId{ .token_id = token_id, .serial_number = 1 };
    const id2 = hedera.NftId{ .token_id = token_id, .serial_number = 1 };
    const id3 = hedera.NftId{ .token_id = token_id, .serial_number = 2 };
    
    try testing.expect(id1.equals(id2));
    try testing.expect(!id1.equals(id3));
}

test "hedera.NftId to string conversion" {
    const allocator = testing.allocator;
    
    const token_id = TokenId.init(0, 0, 500);
    const id = hedera.NftId{ .token_id = token_id, .serial_number = 42 };
    const str = try id.toString(allocator);
    defer allocator.free(str);
    
    try testing.expectEqualStrings("0.0.500/42", str);
}

test "ID protobuf serialization" {
    const allocator = testing.allocator;
    var writer = @import("../../src/protobuf/writer.zig").ProtoWriter.init(allocator);
    defer writer.deinit();
    
    const account_id = AccountId.init(0, 0, 100);
    try delete_account_id.toProtobuf(&writer);
    
    const bytes = try writer.finalize();
    defer allocator.free(bytes);
    
    try testing.expect(bytes.len > 0);
}

test "ID protobuf deserialization" {
    const allocator = testing.allocator;
    
    // Create serialized data
    var writer = @import("../../src/protobuf/writer.zig").ProtoWriter.init(allocator);
    defer writer.deinit();
    
    const original = AccountId.init(0, 0, 100);
    try original.toProtobuf(&writer);
    
    const bytes = try writer.finalize();
    defer allocator.free(bytes);
    
    // Deserialize
    const deserialized = try AccountId.fromProtobuf(bytes);
    
    try testing.expect(original.equals(deserialized));
}
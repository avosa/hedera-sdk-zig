const std = @import("std");
const testing = std.testing;
const FileId = @import("../file/file_id.zig").FileId;
const ContractId = @import("../contract/contract_id.zig").ContractId;
const Timestamp = @import("../core/timestamp.zig").Timestamp;
const AccountId = @import("../account/delete_account_id.zig").AccountId;

test "SystemDeleteTransaction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = @import("system_delete.zig").SystemDeleteTransaction.init(allocator);
    defer tx.deinit();
    
    // Delete file
    const file_id = FileId.init(0, 0, 150);
    _ = tx.setFileId(file_id);
    tx.setExpirationTime(Timestamp.fromSeconds(1234567890));
    
    try testing.expectEqual(file_id.num(), tx.file_id.?.num());
    try testing.expectEqual(@as(i64, 1234567890), tx.expiration_time.?.getSeconds());
    
    // Can't set both file and contract
    const contract_id = ContractId.init(0, 0, 200);
    _ = tx.setContractId(contract_id);
    
    try testing.expect(tx.file_id == null);
    try testing.expectEqual(contract_id.num(), tx.contract_id.?.num());
}

test "SystemUndeleteTransaction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = @import("system_undelete.zig").SystemUndeleteTransaction.init(allocator);
    defer tx.deinit();
    
    // Undelete file
    const file_id = FileId.init(0, 0, 150);
    _ = tx.setFileId(file_id);
    
    try testing.expectEqual(file_id.num(), tx.file_id.?.num());
    
    // Switch to contract
    const contract_id = ContractId.init(0, 0, 200);
    _ = tx.setContractId(contract_id);
    
    try testing.expect(tx.file_id == null);
    try testing.expectEqual(contract_id.num(), tx.contract_id.?.num());
}

test "FreezeTransaction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tx = @import("freeze.zig").FreezeTransaction.init(allocator);
    defer tx.deinit();
    
    // Set freeze type
    _ = tx.setFreezeType(.FREEZE_UPGRADE);
    
    // Set start and end time
    const start_time = Timestamp.fromSeconds(1234567890);
    const end_time = Timestamp.fromSeconds(1234567900);
    
    _ = tx.setStartTime(start_time);
    _ = tx.setEndTime(end_time);
    
    // Set update file
    const update_file = FileId.init(0, 0, 150);
    _ = tx.setUpdateFile(update_file);
    
    // Set file hash
    const file_hash = try allocator.alloc(u8, 48);
    defer allocator.free(file_hash);
    @memset(file_hash, 0xAB);
    _ = tx.setFileHash(file_hash);
    
    try testing.expectEqual(@as(u8, @intFromEnum(@import("freeze.zig").FreezeType.FREEZE_UPGRADE)), @intFromEnum(tx.freeze_type));
    try testing.expectEqual(start_time.toNanos(), tx.start_time.?.toNanos());
    try testing.expectEqual(end_time.toNanos(), tx.end_time.?.toNanos());
    try testing.expectEqual(update_file.num(), tx.update_file.?.num());
    try testing.expectEqual(@as(usize, 48), tx.file_hash.?.len);
}

test "NetworkVersionInfo" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var info = @import("../network/network_version_info.zig").NetworkVersionInfo.init(allocator);
    defer info.deinit();
    
    info.protobuf_version = @import("../network/network_version_info.zig").SemanticVersion{
        .major = 0,
        .minor = 30,
        .patch = 0,
        .pre = try allocator.dupe(u8, ""),
        .build = try allocator.dupe(u8, ""),
    };
    
    info.services_version = @import("../network/network_version_info.zig").SemanticVersion{
        .major = 0,
        .minor = 30,
        .patch = 0,
        .pre = try allocator.dupe(u8, ""),
        .build = try allocator.dupe(u8, ""),
    };
    
    try testing.expectEqual(@as(u32, 30), info.protobuf_version.?.minor);
    try testing.expectEqual(@as(u32, 30), info.services_version.?.minor);
}

test "GetByKeyQuery" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var query = @import("../query/get_by_key_query.zig").GetByKeyQuery.init(allocator);
    defer query.deinit();
    
    // Set key
    const key = try @import("../crypto/key.zig").Ed25519PublicKey.fromBytes(&[_]u8{1} ** 32);
    _ = query.setKey(key);
    
    try testing.expect(query.key != null);
}

test "SystemInfo" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Test exchange rates
    const rate = @import("../core/exchange_rate.zig").ExchangeRate{
        .hbar_equiv = 30000,
        .cent_equiv = 1,
        .expiration_time = Timestamp.fromSeconds(1234567890),
    };
    
    try testing.expectEqual(@as(i32, 30000), rate.hbar_equiv);
    try testing.expectEqual(@as(i32, 1), rate.cent_equiv);
    
    // Calculate exchange
    const usd_amount = 100; // $1.00 in cents
    const hbars = rate.convert(usd_amount);
    try testing.expectEqual(@as(i64, 3000000), hbars);
    
    // Test current and next exchange rates
    var rates = @import("../core/exchange_rate.zig").ExchangeRateSet{
        .current_rate = rate,
        .next_rate = @import("../core/exchange_rate.zig").ExchangeRate{
            .hbar_equiv = 25000,
            .cent_equiv = 1,
            .expiration_time = Timestamp.fromSeconds(1234567900),
        },
    };
    
    try testing.expectEqual(@as(i32, 30000), rates.current_rate.hbar_equiv);
    try testing.expectEqual(@as(i32, 25000), rates.next_rate.hbar_equiv);
}


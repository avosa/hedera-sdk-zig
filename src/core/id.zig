const std = @import("std");
const errors = @import("errors.zig");
const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;

// Hedera network shard and realm constants
pub const MAINNET_SHARD: u64 = 0;
pub const MAINNET_REALM: u64 = 0;

// Base ID structure used by all entity IDs
pub const EntityId = struct {
    shard: u64,
    realm: u64,
    num: u64,
    checksum: ?[]const u8 = null,
    
    // Parse entity ID from string format: "shard.realm.num" or "shard.realm.num-checksum"
    pub fn fromString(allocator: std.mem.Allocator, str: []const u8) !EntityId {
        var parts = std.mem.tokenizeScalar(u8, str, '-');
        const id_part = parts.next() orelse return error.InvalidParameter;
        const checksum_part = parts.next();
        
        var id_parts = std.mem.tokenizeScalar(u8, id_part, '.');
        
        const shard_str = id_parts.next() orelse return error.InvalidParameter;
        const realm_str = id_parts.next() orelse return error.InvalidParameter;
        const num_str = id_parts.next() orelse return error.InvalidParameter;
        
        const shard = std.fmt.parseInt(u64, shard_str, 10) catch return error.InvalidParameter;
        const realm = std.fmt.parseInt(u64, realm_str, 10) catch return error.InvalidParameter;
        const num = std.fmt.parseInt(u64, num_str, 10) catch return error.InvalidParameter;
        
        var checksum: ?[]const u8 = null;
        if (checksum_part) |cs| {
            checksum = try allocator.dupe(u8, cs);
        }
        
        return EntityId{
            .shard = shard,
            .realm = realm,
            .num = num,
            .checksum = checksum,
        };
    }
    
    // Convert to string format
    pub fn toString(self: EntityId, allocator: std.mem.Allocator) ![]u8 {
        if (self.checksum) |cs| {
            return std.fmt.allocPrint(allocator, "{d}.{d}.{d}-{s}", .{ self.shard, self.realm, self.num, cs });
        } else {
            return std.fmt.allocPrint(allocator, "{d}.{d}.{d}", .{ self.shard, self.realm, self.num });
        }
    }
    
    // Validate checksum
    pub fn validateChecksum(self: EntityId, ledger_id: []const u8) !bool {
        if (self.checksum == null) return true;
        
        const computed = try self.computeChecksum(ledger_id);
        defer computed.deinit();
        
        return std.mem.eql(u8, self.checksum.?, computed.items);
    }
    
    // Compute checksum for this ID
    fn computeChecksum(self: EntityId, ledger_id: []const u8) !std.ArrayList(u8) {
        var checksum = std.ArrayList(u8).init(std.heap.page_allocator);
        
        // Checksum calculation algorithm from Hedera
        const h = [6]u32{ 3, 5, 7, 11, 13, 17 };
        const p = [6]u8{ 26, 26, 26, 26, 26, 26 };
        var c = [6]u32{ 0, 0, 0, 0, 0, 0 };
        var d: u64 = 0;
        
        // Process ledger ID
        for (ledger_id) |byte| {
            d = (d * 31 + byte) % 1000003;
        }
        
        // Process entity ID components
        d = (d * 31 + @as(u32, @intCast(self.shard & 0xFF))) % 1000003;
        d = (d * 31 + @as(u32, @intCast((self.shard >> 8) & 0xFF))) % 1000003;
        d = (d * 31 + @as(u32, @intCast((self.shard >> 16) & 0xFF))) % 1000003;
        d = (d * 31 + @as(u32, @intCast((self.shard >> 24) & 0xFF))) % 1000003;
        
        d = (d * 31 + @as(u32, @intCast(self.realm & 0xFF))) % 1000003;
        d = (d * 31 + @as(u32, @intCast((self.realm >> 8) & 0xFF))) % 1000003;
        d = (d * 31 + @as(u32, @intCast((self.realm >> 16) & 0xFF))) % 1000003;
        d = (d * 31 + @as(u32, @intCast((self.realm >> 24) & 0xFF))) % 1000003;
        
        d = (d * 31 + @as(u32, @intCast(self.num & 0xFF))) % 1000003;
        d = (d * 31 + @as(u32, @intCast((self.num >> 8) & 0xFF))) % 1000003;
        d = (d * 31 + @as(u32, @intCast((self.num >> 16) & 0xFF))) % 1000003;
        d = (d * 31 + @as(u32, @intCast((self.num >> 24) & 0xFF))) % 1000003;
        
        // Generate checksum characters
        for (0..5) |i| {
            c[i] = @as(u32, @intCast((d * h[i]) % p[i]));
            try checksum.append(@as(u8, @intCast(c[i] + 'a')));
        }
        
        return checksum;
    }
    
    pub fn equals(self: EntityId, other: EntityId) bool {
        return self.shard == other.shard and
               self.realm == other.realm and
               self.num == other.num;
    }
    
    pub fn fromBytes(bytes: []const u8) !EntityId {
        // Simple parsing assuming bytes are in format: shard(8) + realm(8) + num(8)
        if (bytes.len < 24) return error.InvalidParameter;
        
        const shard = std.mem.readInt(u64, bytes[0..8], .big);
        const realm = std.mem.readInt(u64, bytes[8..16], .big);
        const num = std.mem.readInt(u64, bytes[16..24], .big);
        
        return EntityId{
            .shard = shard,
            .realm = realm,
            .num = num,
            .checksum = null,
        };
    }
};

// AccountId represents a Hedera account
pub const AccountId = struct {
    shard: u64,
    realm: u64,
    account: u64,
    alias_key: ?*const @import("../crypto/key.zig").PublicKey = null,
    alias_evm_address: ?[]const u8 = null,
    checksum: ?[]const u8 = null,
    
    pub fn init(shard: u64, realm: u64, account: u64) AccountId {
        return AccountId{
            .shard = shard,
            .realm = realm,
            .account = account,
            .alias_key = null,
            .alias_evm_address = null,
            .checksum = null,
        };
    }
    
    
    pub fn num(self: AccountId) u64 {
        return self.account;
    }
    
    pub fn fromString(allocator: std.mem.Allocator, str: []const u8) !AccountId {
        // Check if it's an EVM address (starts with 0x)
        if (std.mem.startsWith(u8, str, "0x")) {
            if (str.len != 42) return error.InvalidParameter;
            
            return AccountId{
                .shard = 0,
                .realm = 0,
                .account = 0,
                .alias_key = null,
                .alias_evm_address = try allocator.dupe(u8, str),
                .checksum = null,
            };
        }
        
        const entity = try EntityId.fromString(allocator, str);
        return AccountId{
            .shard = entity.shard,
            .realm = entity.realm,
            .account = entity.num,
            .alias_key = null,
            .alias_evm_address = null,
            .checksum = entity.checksum,
        };
    }
    
    
    pub fn accountIdFromString(allocator: std.mem.Allocator, str: []const u8) !AccountId {
        return fromString(allocator, str);
    }
    
    // Create AccountId from EVM address (20 bytes or hex string)
    pub fn fromEvmAddress(allocator: std.mem.Allocator, evm_address: []const u8) !AccountId {
        var address_str: []u8 = undefined;
        
        if (std.mem.startsWith(u8, evm_address, "0x")) {
            // Already a hex string
            if (evm_address.len != 42) return error.InvalidParameter;
            address_str = try allocator.dupe(u8, evm_address);
        } else if (evm_address.len == 20) {
            // Raw bytes - convert to hex string
            address_str = try std.fmt.allocPrint(allocator, "0x{}", .{std.fmt.fmtSliceHexLower(evm_address)});
        } else {
            return error.InvalidParameter;
        }
        
        return AccountId{
            .shard = 0,
            .realm = 0,
            .account = 0,
            .alias_key = null,
            .alias_evm_address = address_str,
            .checksum = null,
        };
    }
    
    pub fn deinit(self: *AccountId, allocator: std.mem.Allocator) void {
        if (self.alias_evm_address) |addr| {
            allocator.free(addr);
            self.alias_evm_address = null;
        }
        // Note: alias_key is a pointer to PublicKey, not owned by AccountId
        // so we don't free it here
        self.alias_key = null;
        if (self.checksum) |cs| {
            allocator.free(cs);
            self.checksum = null;
        }
    }
    
    pub fn toString(self: AccountId, allocator: std.mem.Allocator) ![]u8 {
        if (self.alias_evm_address) |addr| {
            return allocator.dupe(u8, addr);
        }
        
        if (self.checksum) |cs| {
            return std.fmt.allocPrint(allocator, "{d}.{d}.{d}-{s}", .{ self.shard, self.realm, self.account, cs });
        } else {
            return std.fmt.allocPrint(allocator, "{d}.{d}.{d}", .{ self.shard, self.realm, self.account });
        }
    }
    
    // Alternative toString that uses a fixed buffer - useful when you know the output size
    pub fn toStringBuf(self: AccountId, buf: []u8) ![]u8 {
        if (self.alias_evm_address) |addr| {
            if (buf.len < addr.len) return error.BufferTooSmall;
            @memcpy(buf[0..addr.len], addr);
            return buf[0..addr.len];
        }
        
        if (self.checksum) |cs| {
            const result = std.fmt.bufPrint(buf, "{d}.{d}.{d}-{s}", .{ 
                self.shard, self.realm, self.account, cs 
            }) catch return error.BufferTooSmall;
            return result;
        } else {
            const result = std.fmt.bufPrint(buf, "{d}.{d}.{d}", .{ 
                self.shard, self.realm, self.account 
            }) catch return error.BufferTooSmall;
            return result;
        }
    }
    
    pub fn toBytes(self: AccountId, allocator: std.mem.Allocator) ![]u8 {
        var bytes = try allocator.alloc(u8, 24);
        
        // Write shard (8 bytes)
        std.mem.writeInt(u64, bytes[0..8], self.shard, .big);
        // Write realm (8 bytes)
        std.mem.writeInt(u64, bytes[8..16], self.realm, .big);
        // Write account num (8 bytes)
        std.mem.writeInt(u64, bytes[16..24], self.account, .big);
        
        return bytes;
    }
    
    pub fn fromBytes(bytes: []const u8) !AccountId {
        if (bytes.len != 24) return error.InvalidParameter;
        
        return AccountId{
            .shard = std.mem.readInt(u64, bytes[0..8], .big),
            .realm = std.mem.readInt(u64, bytes[8..16], .big),
            .account = std.mem.readInt(u64, bytes[16..24], .big),
            .alias_key = null,
            .alias_evm_address = null,
            .checksum = null,
        };
    }
    
    pub fn fromProtobufBytes(allocator: std.mem.Allocator, bytes: []const u8) !AccountId {
        return fromProtobuf(allocator, bytes);
    }
    
    pub fn fromProtobuf(allocator: std.mem.Allocator, bytes: []const u8) !AccountId {
        if (bytes.len == 0) {
            return AccountId.init(0, 0, 0);
        }
        
        var reader = ProtoReader.init(bytes);
        var shard: u64 = 0;
        var realm: u64 = 0;
        var account: u64 = 0;
        var alias_bytes: ?[]const u8 = null;
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => {
                    // shard
                    shard = @intCast(try reader.readInt64());
                },
                2 => {
                    // realm
                    realm = @intCast(try reader.readInt64());
                },
                3 => {
                    // account
                    account = @intCast(try reader.readInt64());
                },
                4 => {
                    // alias
                    alias_bytes = try reader.readBytes();
                },
                else => {
                    // Skip unknown fields
                    try reader.skipField(tag.wire_type);
                },
            }
        }
        
        var result = AccountId.init(shard, realm, account);
        
        // Handle alias if present
        if (alias_bytes) |alias| {
            if (alias.len == 20) {
                // EVM address alias
                result.alias_evm_address = try std.fmt.allocPrint(allocator, "0x{}", .{std.fmt.fmtSliceHexLower(alias)});
            }
            // Could also be a key alias, but we'd need to parse that
        }
        
        return result;
    }
    
    pub fn toProtobuf(self: AccountId, allocator: std.mem.Allocator) ![]u8 {
        var writer = ProtoWriter.init(allocator);
        defer writer.deinit();
        
        if (self.shard != 0) {
            try writer.writeInt64(1, @intCast(self.shard));
        }
        if (self.realm != 0) {
            try writer.writeInt64(2, @intCast(self.realm));
        }
        if (self.account != 0) {
            try writer.writeInt64(3, @intCast(self.account));
        }
        
        // Handle alias
        if (self.alias_evm_address) |evm_addr| {
            if (std.mem.startsWith(u8, evm_addr, "0x") and evm_addr.len == 42) {
                var alias_bytes: [20]u8 = undefined;
                _ = try std.fmt.hexToBytes(&alias_bytes, evm_addr[2..]);
                try writer.writeString(4, &alias_bytes);
            }
        }
        
        return writer.toOwnedSlice();
    }
    
    pub fn equals(self: AccountId, other: AccountId) bool {
        if (self.alias_evm_address != null and other.alias_evm_address != null) {
            return std.mem.eql(u8, self.alias_evm_address.?, other.alias_evm_address.?);
        }
        return self.shard == other.shard and
               self.realm == other.realm and
               self.account == other.account;
    }
    
    pub fn isZero(self: AccountId) bool {
        return self.shard == 0 and 
               self.realm == 0 and 
               self.account == 0 and
               self.alias_evm_address == null and
               self.alias_key == null;
    }
    
    // Convert to EntityId when needed  
    pub fn toEntityId(self: AccountId) EntityId {
        return EntityId{
            .shard = self.shard,
            .realm = self.realm,
            .num = self.account,
            .checksum = self.checksum,
        };
    }
};

// ContractId represents a smart contract on Hedera
pub const ContractId = struct {
    entity: EntityId,
    evm_address: ?[]const u8 = null,
    
    
    pub fn shard(self: ContractId) u64 {
        return self.entity.shard;
    }
    
    pub fn realm(self: ContractId) u64 {
        return self.entity.realm;
    }
    
    pub fn num(self: ContractId) u64 {
        return self.entity.num;
    }
    
    pub fn init(shard_val: u64, realm_val: u64, num_val: u64) ContractId {
        return ContractId{
            .entity = EntityId{
                .shard = shard_val,
                .realm = realm_val,
                .num = num_val,
            },
        };
    }
    
    pub fn fromString(allocator: std.mem.Allocator, str: []const u8) !ContractId {
        // Check if it's an EVM address
        if (std.mem.startsWith(u8, str, "0x")) {
            if (str.len != 42) return error.InvalidParameter;
            
            return ContractId{
                .entity = EntityId{
                    .shard = 0,
                    .realm = 0,
                    .num = 0,
                },
                .evm_address = try allocator.dupe(u8, str),
            };
        }
        
        const entity = try EntityId.fromString(allocator, str);
        return ContractId{ .entity = entity };
    }
    
    pub fn toString(self: ContractId, allocator: std.mem.Allocator) ![]u8 {
        if (self.evm_address) |addr| {
            return allocator.dupe(u8, addr);
        }
        return self.entity.toString(allocator);
    }
    
    // Convert to EVM address
    pub fn toEvmAddress(self: ContractId, allocator: std.mem.Allocator) ![]u8 {
        if (self.evm_address) |addr| {
            return allocator.dupe(u8, addr);
        }
        
        // Convert entity ID to EVM address format
        var address_bytes: [20]u8 = undefined;
        
        // Pack shard, realm, and num into 20 bytes
        const shard_bytes = std.mem.toBytes(self.entity.shard);
        const realm_bytes = std.mem.toBytes(self.entity.realm);
        const num_bytes = std.mem.toBytes(self.entity.num);
        
        // Simple packing - first 4 bytes shard, next 8 bytes realm, last 8 bytes num
        @memcpy(address_bytes[0..4], shard_bytes[0..4]);
        @memcpy(address_bytes[4..12], realm_bytes[0..8]);
        @memcpy(address_bytes[12..20], num_bytes[0..8]);
        
        return std.fmt.allocPrint(allocator, "0x{x}", .{std.fmt.fmtSliceHexLower(&address_bytes)});
    }
    
    pub fn toBytes(self: ContractId, allocator: std.mem.Allocator) ![]u8 {
        return self.toAccountId().toBytes(allocator);
    }
    
    pub fn toAccountId(self: ContractId) AccountId {
        return AccountId{
            .shard = self.entity.shard,
            .realm = self.entity.realm,
            .account = self.entity.num,
            .alias_key = null,
            .alias_evm_address = self.evm_address,
            .checksum = self.entity.checksum,
        };
    }
    
    pub fn equals(self: ContractId, other: ContractId) bool {
        if (self.evm_address != null and other.evm_address != null) {
            return std.mem.eql(u8, self.evm_address.?, other.evm_address.?);
        }
        return self.entity.equals(other.entity);
    }
    
    pub fn fromProtobufBytes(allocator: std.mem.Allocator, bytes: []const u8) !ContractId {
        return fromProtobuf(allocator, bytes);
    }
    
    pub fn fromProtobuf(allocator: std.mem.Allocator, bytes: []const u8) !ContractId {
        _ = allocator;
        
        if (bytes.len == 0) {
            return ContractId.init(0, 0, 0);
        }
        
        var reader = ProtoReader.init(bytes);
        var shard_val: u64 = 0;
        var realm_val: u64 = 0;
        var contract_num: u64 = 0;
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => shard_val = @intCast(try reader.readInt64()),
                2 => realm_val = @intCast(try reader.readInt64()),
                3 => contract_num = @intCast(try reader.readInt64()),
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return ContractId.init(shard_val, realm_val, contract_num);
    }
    
    pub fn toProtobuf(self: ContractId, allocator: std.mem.Allocator) ![]u8 {
        var writer = ProtoWriter.init(allocator);
        defer writer.deinit();
        
        if (self.entity.shard != 0) {
            try writer.writeInt64(1, @intCast(self.entity.shard));
        }
        if (self.entity.realm != 0) {
            try writer.writeInt64(2, @intCast(self.entity.realm));
        }
        if (self.entity.num != 0) {
            try writer.writeInt64(3, @intCast(self.entity.num));
        }
        
        return writer.toOwnedSlice();
    }
};

// FileId represents a file on Hedera
pub const FileId = struct {
    entity: EntityId,
    
    pub fn init(shard_num: u64, realm_num: u64, file_num: u64) FileId {
        return FileId{
            .entity = EntityId{
                .shard = shard_num,
                .realm = realm_num,
                .num = file_num,
            },
        };
    }
    
    
    pub fn shard(self: FileId) u64 {
        return self.entity.shard;
    }
    
    pub fn realm(self: FileId) u64 {
        return self.entity.realm;
    }
    
    pub fn num(self: FileId) u64 {
        return self.entity.num;
    }
    
    pub fn fromString(allocator: std.mem.Allocator, str: []const u8) !FileId {
        const entity = try EntityId.fromString(allocator, str);
        return FileId{ .entity = entity };
    }
    
    pub fn toString(self: FileId, allocator: std.mem.Allocator) ![]u8 {
        return self.entity.toString(allocator);
    }
    
    pub fn equals(self: FileId, other: FileId) bool {
        return self.entity.equals(other.entity);
    }
    
    pub fn fromProtobufBytes(allocator: std.mem.Allocator, bytes: []const u8) !FileId {
        return fromProtobuf(allocator, bytes);
    }
    
    pub fn fromProtobuf(allocator: std.mem.Allocator, bytes: []const u8) !FileId {
        _ = allocator;
        
        if (bytes.len == 0) {
            return FileId.init(0, 0, 0);
        }
        
        var reader = ProtoReader.init(bytes);
        var shard_val: u64 = 0;
        var realm_val: u64 = 0;
        var file_num: u64 = 0;
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => shard_val = @intCast(try reader.readInt64()),
                2 => realm_val = @intCast(try reader.readInt64()),
                3 => file_num = @intCast(try reader.readInt64()),
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return FileId.init(shard_val, realm_val, file_num);
    }
    
    pub fn toProtobuf(self: FileId, allocator: std.mem.Allocator) ![]u8 {
        var writer = ProtoWriter.init(allocator);
        defer writer.deinit();
        
        if (self.entity.shard != 0) {
            try writer.writeInt64(1, @intCast(self.entity.shard));
        }
        if (self.entity.realm != 0) {
            try writer.writeInt64(2, @intCast(self.entity.realm));
        }
        if (self.entity.num != 0) {
            try writer.writeInt64(3, @intCast(self.entity.num));
        }
        
        return writer.toOwnedSlice();
    }
    
    // Import system file IDs from config
    const Config = @import("config.zig");
    pub const ADDRESS_BOOK = Config.SystemFiles.ADDRESS_BOOK;
    pub const FEE_SCHEDULE = Config.SystemFiles.FEE_SCHEDULE;
    pub const EXCHANGE_RATES = Config.SystemFiles.EXCHANGE_RATES;
    pub const NODE_DETAILS = Config.SystemFiles.NODE_DETAILS;
    pub const APPLICATION_PROPERTIES = Config.SystemFiles.APPLICATION_PROPERTIES;
    pub const API_PERMISSIONS = Config.SystemFiles.API_PERMISSIONS;
    pub const THROTTLES = Config.SystemFiles.THROTTLES;
};

// TokenId represents a token on Hedera
pub const TokenId = struct {
    entity: EntityId,
    
    pub fn init(shard_num: u64, realm_num: u64, token_num: u64) TokenId {
        return TokenId{
            .entity = EntityId{
                .shard = shard_num,
                .realm = realm_num,
                .num = token_num,
            },
        };
    }
    
    
    pub fn shard(self: TokenId) u64 {
        return self.entity.shard;
    }
    
    pub fn realm(self: TokenId) u64 {
        return self.entity.realm;
    }
    
    pub fn num(self: TokenId) u64 {
        return self.entity.num;
    }
    
    pub fn fromString(allocator: std.mem.Allocator, str: []const u8) !TokenId {
        const entity = try EntityId.fromString(allocator, str);
        return TokenId{ .entity = entity };
    }
    
    pub fn toString(self: TokenId, allocator: std.mem.Allocator) ![]u8 {
        return self.entity.toString(allocator);
    }
    
    pub fn equals(self: TokenId, other: TokenId) bool {
        return self.entity.equals(other.entity);
    }
    
    pub fn fromProtobufBytes(allocator: std.mem.Allocator, bytes: []const u8) !TokenId {
        return fromProtobuf(allocator, bytes);
    }
    
    pub fn fromProtobuf(allocator: std.mem.Allocator, bytes: []const u8) !TokenId {
        _ = allocator;
        
        if (bytes.len == 0) {
            return TokenId.init(0, 0, 0);
        }
        
        var reader = ProtoReader.init(bytes);
        var shard_val: u64 = 0;
        var realm_val: u64 = 0;
        var token_num: u64 = 0;
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => shard_val = @intCast(try reader.readInt64()),
                2 => realm_val = @intCast(try reader.readInt64()),
                3 => token_num = @intCast(try reader.readInt64()),
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return TokenId.init(shard_val, realm_val, token_num);
    }
    
    pub fn toProtobuf(self: TokenId, allocator: std.mem.Allocator) ![]u8 {
        var writer = ProtoWriter.init(allocator);
        defer writer.deinit();
        
        if (self.entity.shard != 0) {
            try writer.writeInt64(1, @intCast(self.entity.shard));
        }
        if (self.entity.realm != 0) {
            try writer.writeInt64(2, @intCast(self.entity.realm));
        }
        if (self.entity.num != 0) {
            try writer.writeInt64(3, @intCast(self.entity.num));
        }
        
        return writer.toOwnedSlice();
    }
    
    // HashContext for use in HashMap
    pub const HashContext = struct {
        pub fn hash(self: @This(), key: TokenId) u64 {
            _ = self;
            var h = std.hash.Wyhash.init(0);
            h.update(std.mem.asBytes(&key.entity.shard));
            h.update(std.mem.asBytes(&key.entity.realm));
            h.update(std.mem.asBytes(&key.entity.num));
            return h.final();
        }
        
        pub fn eql(self: @This(), a: TokenId, b: TokenId) bool {
            _ = self;
            return a.equals(b);
        }
    };
};

// TopicId represents a consensus service topic
pub const TopicId = struct {
    entity: EntityId,
    
    pub fn init(shard_num: u64, realm_num: u64, topic_num: u64) TopicId {
        return TopicId{
            .entity = EntityId{
                .shard = shard_num,
                .realm = realm_num,
                .num = topic_num,
            },
        };
    }
    
    
    pub fn shard(self: TopicId) u64 {
        return self.entity.shard;
    }
    
    pub fn realm(self: TopicId) u64 {
        return self.entity.realm;
    }
    
    pub fn num(self: TopicId) u64 {
        return self.entity.num;
    }
    
    pub fn fromString(allocator: std.mem.Allocator, str: []const u8) !TopicId {
        const entity = try EntityId.fromString(allocator, str);
        return TopicId{ .entity = entity };
    }
    
    pub fn toString(self: TopicId, allocator: std.mem.Allocator) ![]u8 {
        return self.entity.toString(allocator);
    }
    
    pub fn equals(self: TopicId, other: TopicId) bool {
        return self.entity.equals(other.entity);
    }
    
    pub fn fromProtobufBytes(allocator: std.mem.Allocator, bytes: []const u8) !TopicId {
        return fromProtobuf(allocator, bytes);
    }
    
    pub fn fromProtobuf(allocator: std.mem.Allocator, bytes: []const u8) !TopicId {
        _ = allocator;
        
        if (bytes.len == 0) {
            return TopicId.init(0, 0, 0);
        }
        
        var reader = ProtoReader.init(bytes);
        var shard_val: u64 = 0;
        var realm_val: u64 = 0;
        var topic_num: u64 = 0;
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => shard_val = @intCast(try reader.readInt64()),
                2 => realm_val = @intCast(try reader.readInt64()),
                3 => topic_num = @intCast(try reader.readInt64()),
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return TopicId.init(shard_val, realm_val, topic_num);
    }
    
    pub fn toProtobuf(self: TopicId, allocator: std.mem.Allocator) ![]u8 {
        var writer = ProtoWriter.init(allocator);
        defer writer.deinit();
        
        if (self.entity.shard != 0) {
            try writer.writeInt64(1, @intCast(self.entity.shard));
        }
        if (self.entity.realm != 0) {
            try writer.writeInt64(2, @intCast(self.entity.realm));
        }
        if (self.entity.num != 0) {
            try writer.writeInt64(3, @intCast(self.entity.num));
        }
        
        return writer.toOwnedSlice();
    }
};

// ScheduleId represents a scheduled transaction
pub const ScheduleId = struct {
    entity: EntityId,
    
    pub fn init(shard_num: u64, realm_num: u64, schedule_num: u64) ScheduleId {
        return ScheduleId{
            .entity = EntityId{
                .shard = shard_num,
                .realm = realm_num,
                .num = schedule_num,
            },
        };
    }
    
    
    pub fn shard(self: ScheduleId) u64 {
        return self.entity.shard;
    }
    
    pub fn realm(self: ScheduleId) u64 {
        return self.entity.realm;
    }
    
    pub fn num(self: ScheduleId) u64 {
        return self.entity.num;
    }
    
    pub fn fromString(allocator: std.mem.Allocator, str: []const u8) !ScheduleId {
        const entity = try EntityId.fromString(allocator, str);
        return ScheduleId{ .entity = entity };
    }
    
    pub fn toString(self: ScheduleId, allocator: std.mem.Allocator) ![]u8 {
        return self.entity.toString(allocator);
    }
    
    pub fn equals(self: ScheduleId, other: ScheduleId) bool {
        return self.entity.equals(other.entity);
    }
    
    pub fn fromProtobufBytes(allocator: std.mem.Allocator, bytes: []const u8) !ScheduleId {
        return fromProtobuf(allocator, bytes);
    }
    
    pub fn fromProtobuf(allocator: std.mem.Allocator, bytes: []const u8) !ScheduleId {
        _ = allocator;
        
        if (bytes.len == 0) {
            return ScheduleId.init(0, 0, 0);
        }
        
        var reader = ProtoReader.init(bytes);
        var shard_val: u64 = 0;
        var realm_val: u64 = 0;
        var schedule_num: u64 = 0;
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => shard_val = @intCast(try reader.readInt64()),
                2 => realm_val = @intCast(try reader.readInt64()),
                3 => schedule_num = @intCast(try reader.readInt64()),
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return ScheduleId.init(shard_val, realm_val, schedule_num);
    }
    
    pub fn toProtobuf(self: ScheduleId, allocator: std.mem.Allocator) ![]u8 {
        var writer = ProtoWriter.init(allocator);
        defer writer.deinit();
        
        if (self.entity.shard != 0) {
            try writer.writeInt64(1, @intCast(self.entity.shard));
        }
        if (self.entity.realm != 0) {
            try writer.writeInt64(2, @intCast(self.entity.realm));
        }
        if (self.entity.num != 0) {
            try writer.writeInt64(3, @intCast(self.entity.num));
        }
        
        return writer.toOwnedSlice();
    }
};

// NftId represents a specific NFT (token + serial number)
pub const NftId = struct {
    token_id: TokenId,
    serial_number: u64,
    
    pub fn init(token_id: TokenId, serial_number: u64) NftId {
        return NftId{
            .token_id = token_id,
            .serial_number = serial_number,
        };
    }
    
    pub fn toString(self: NftId, allocator: std.mem.Allocator) ![]u8 {
        const token_str = try self.token_id.toString(allocator);
        defer allocator.free(token_str);
        
        return std.fmt.allocPrint(allocator, "{s}@{d}", .{ token_str, self.serial_number });
    }
    
    pub fn equals(self: NftId, other: NftId) bool {
        return self.token_id.equals(other.token_id) and self.serial_number == other.serial_number;
    }
};
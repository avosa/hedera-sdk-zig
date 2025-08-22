const std = @import("std");
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;

// Ledger ID identifying specific Hedera network
pub const LedgerId = struct {
    bytes: [32]u8,

    pub const MAINNET = LedgerId{ .bytes = [_]u8{0x00} ++ [_]u8{0x00} ** 31 };
    pub const TESTNET = LedgerId{ .bytes = [_]u8{0x01} ++ [_]u8{0x00} ** 31 };
    pub const PREVIEWNET = LedgerId{ .bytes = [_]u8{0x02} ++ [_]u8{0x00} ** 31 };
    pub const LOCAL_NODE = LedgerId{ .bytes = [_]u8{0x03} ++ [_]u8{0x00} ** 31 };

    pub fn init(bytes: [32]u8) LedgerId {
        return LedgerId{ .bytes = bytes };
    }

    pub fn initFromBytes(bytes: []const u8) !LedgerId {
        if (bytes.len > 32) return error.LedgerIdTooLong;
        
        var ledger_bytes: [32]u8 = std.mem.zeroes([32]u8);
        @memcpy(ledger_bytes[0..bytes.len], bytes);
        
        return LedgerId{ .bytes = ledger_bytes };
    }

    pub fn fromString(str: []const u8) !LedgerId {
        if (std.ascii.eqlIgnoreCase(str, "mainnet")) {
            return MAINNET;
        } else if (std.ascii.eqlIgnoreCase(str, "testnet")) {
            return TESTNET;
        } else if (std.ascii.eqlIgnoreCase(str, "previewnet")) {
            return PREVIEWNET;
        } else if (std.ascii.eqlIgnoreCase(str, "local")) {
            return LOCAL_NODE;
        } else {
            const trimmed = std.mem.trim(u8, str, " \t\n\r");
            if (trimmed.len == 0) {
                return error.EmptyLedgerId;
            }
            
            if (trimmed.len % 2 != 0) {
                return error.InvalidHexLength;
            }
            
            const bytes_len = trimmed.len / 2;
            if (bytes_len > 32) {
                return error.LedgerIdTooLong;
            }
            
            var bytes: [32]u8 = std.mem.zeroes([32]u8);
            _ = try std.fmt.hexToBytes(bytes[0..bytes_len], trimmed);
            
            return LedgerId{ .bytes = bytes };
        }
    }

    pub fn getBytes(self: *const LedgerId) [32]u8 {
        return self.bytes;
    }

    pub fn toHex(self: *const LedgerId, allocator: std.mem.Allocator) ![]u8 {
        var effective_len: usize = 32;
        while (effective_len > 0 and self.bytes[effective_len - 1] == 0) {
            effective_len -= 1;
        }
        
        if (effective_len == 0) {
            effective_len = 1;
        }
        
        return std.fmt.allocPrint(allocator, "{x}", .{std.fmt.fmtSliceHexLower(self.bytes[0..effective_len])});
    }

    pub fn toString(self: *const LedgerId, allocator: std.mem.Allocator) ![]u8 {
        if (self.equals(MAINNET)) {
            return allocator.dupe(u8, "mainnet");
        } else if (self.equals(TESTNET)) {
            return allocator.dupe(u8, "testnet");
        } else if (self.equals(PREVIEWNET)) {
            return allocator.dupe(u8, "previewnet");
        } else if (self.equals(LOCAL_NODE)) {
            return allocator.dupe(u8, "local");
        } else {
            return self.toHex(allocator);
        }
    }

    pub fn isMainnet(self: *const LedgerId) bool {
        return self.equals(MAINNET);
    }

    pub fn isTestnet(self: *const LedgerId) bool {
        return self.equals(TESTNET);
    }

    pub fn isPreviewnet(self: *const LedgerId) bool {
        return self.equals(PREVIEWNET);
    }

    pub fn isLocalNode(self: *const LedgerId) bool {
        return self.equals(LOCAL_NODE);
    }

    pub fn equals(self: *const LedgerId, other: LedgerId) bool {
        return std.mem.eql(u8, &self.bytes, &other.bytes);
    }

    pub fn clone(self: *const LedgerId) LedgerId {
        return LedgerId{ .bytes = self.bytes };
    }

    pub fn toProtobuf(self: *const LedgerId, allocator: std.mem.Allocator) ![]u8 {
        var writer = ProtoWriter.init(allocator);
        defer writer.deinit();

        try writer.writeBytes(1, &self.bytes);
        return writer.toOwnedSlice();
    }

    pub fn fromProtobuf(data: []const u8, allocator: std.mem.Allocator) !LedgerId {
        _ = allocator;
        var reader = ProtoReader.init(data);
        var ledger_id = LedgerId{ .bytes = std.mem.zeroes([32]u8) };

        while (try reader.next()) |field| {
            switch (field.number) {
                1 => {
                    const len = @min(field.data.len, 32);
                    @memcpy(ledger_id.bytes[0..len], field.data[0..len]);
                },
                else => {},
            }
        }

        return ledger_id;
    }

    // Get network endpoints for this ledger
    pub fn getNetworkEndpoints(self: *const LedgerId, allocator: std.mem.Allocator) ![]NetworkEndpoint {
        if (self.isMainnet()) {
            return getMainnetEndpoints(allocator);
        } else if (self.isTestnet()) {
            return getTestnetEndpoints(allocator);
        } else if (self.isPreviewnet()) {
            return getPreviewnetEndpoints(allocator);
        } else if (self.isLocalNode()) {
            return getLocalEndpoints(allocator);
        } else {
            return allocator.alloc(NetworkEndpoint, 0);
        }
    }

    // Get mirror node URLs for this ledger
    pub fn getMirrorNodeUrls(self: *const LedgerId, allocator: std.mem.Allocator) ![][]const u8 {
        if (self.isMainnet()) {
            const urls = [_][]const u8{"https://mainnet.mirrornode.hedera.com"};
            return allocator.dupe([]const u8, &urls);
        } else if (self.isTestnet()) {
            const urls = [_][]const u8{"https://testnet.mirrornode.hedera.com"};
            return allocator.dupe([]const u8, &urls);
        } else if (self.isPreviewnet()) {
            const urls = [_][]const u8{"https://previewnet.mirrornode.hedera.com"};
            return allocator.dupe([]const u8, &urls);
        } else if (self.isLocalNode()) {
            const urls = [_][]const u8{"http://localhost:5551"};
            return allocator.dupe([]const u8, &urls);
        } else {
            return allocator.alloc([]const u8, 0);
        }
    }

    pub fn getChainId(self: *const LedgerId) u64 {
        if (self.isMainnet()) {
            return 295;
        } else if (self.isTestnet()) {
            return 296;
        } else if (self.isPreviewnet()) {
            return 297;
        } else if (self.isLocalNode()) {
            return 298;
        } else {
            return 0;
        }
    }
};

pub const NetworkEndpoint = struct {
    address: []const u8,
    port: u16,
    account_id: ?[]const u8,

    pub fn init(address: []const u8, port: u16) NetworkEndpoint {
        return NetworkEndpoint{
            .address = address,
            .port = port,
            .account_id = null,
        };
    }

    pub fn initWithAccountId(address: []const u8, port: u16, account_id: []const u8) NetworkEndpoint {
        return NetworkEndpoint{
            .address = address,
            .port = port,
            .account_id = account_id,
        };
    }
};

fn getMainnetEndpoints(allocator: std.mem.Allocator) ![]NetworkEndpoint {
    const endpoints = [_]NetworkEndpoint{
        NetworkEndpoint.initWithAccountId("35.237.200.180", 50211, "0.0.3"),
        NetworkEndpoint.initWithAccountId("35.186.191.247", 50211, "0.0.4"),
        NetworkEndpoint.initWithAccountId("35.192.2.25", 50211, "0.0.5"),
        NetworkEndpoint.initWithAccountId("35.199.161.108", 50211, "0.0.6"),
        NetworkEndpoint.initWithAccountId("35.203.82.240", 50211, "0.0.7"),
        NetworkEndpoint.initWithAccountId("35.236.5.219", 50211, "0.0.8"),
        NetworkEndpoint.initWithAccountId("35.197.192.225", 50211, "0.0.9"),
        NetworkEndpoint.initWithAccountId("35.242.233.154", 50211, "0.0.10"),
        NetworkEndpoint.initWithAccountId("35.240.118.96", 50211, "0.0.11"),
        NetworkEndpoint.initWithAccountId("35.204.86.32", 50211, "0.0.12"),
    };
    return allocator.dupe(NetworkEndpoint, &endpoints);
}

fn getTestnetEndpoints(allocator: std.mem.Allocator) ![]NetworkEndpoint {
    const endpoints = [_]NetworkEndpoint{
        NetworkEndpoint.initWithAccountId("50.18.132.211", 50211, "0.0.3"),
        NetworkEndpoint.initWithAccountId("52.168.76.241", 50211, "0.0.4"),
        NetworkEndpoint.initWithAccountId("52.20.18.86", 50211, "0.0.5"),
        NetworkEndpoint.initWithAccountId("40.114.107.85", 50211, "0.0.6"),
        NetworkEndpoint.initWithAccountId("3.130.52.236", 50211, "0.0.7"),
        NetworkEndpoint.initWithAccountId("52.183.45.65", 50211, "0.0.8"),
        NetworkEndpoint.initWithAccountId("54.70.192.33", 50211, "0.0.9"),
        NetworkEndpoint.initWithAccountId("52.168.136.202", 50211, "0.0.10"),
        NetworkEndpoint.initWithAccountId("34.91.181.183", 50211, "0.0.11"),
        NetworkEndpoint.initWithAccountId("52.14.252.207", 50211, "0.0.12"),
    };
    return allocator.dupe(NetworkEndpoint, &endpoints);
}

fn getPreviewnetEndpoints(allocator: std.mem.Allocator) ![]NetworkEndpoint {
    const endpoints = [_]NetworkEndpoint{
        NetworkEndpoint.initWithAccountId("50.18.132.211", 50211, "0.0.3"),
        NetworkEndpoint.initWithAccountId("52.168.76.241", 50211, "0.0.4"),
        NetworkEndpoint.initWithAccountId("52.20.18.86", 50211, "0.0.5"),
        NetworkEndpoint.initWithAccountId("40.114.107.85", 50211, "0.0.6"),
    };
    return allocator.dupe(NetworkEndpoint, &endpoints);
}

fn getLocalEndpoints(allocator: std.mem.Allocator) ![]NetworkEndpoint {
    const endpoints = [_]NetworkEndpoint{
        NetworkEndpoint.initWithAccountId("127.0.0.1", 50211, "0.0.3"),
    };
    return allocator.dupe(NetworkEndpoint, &endpoints);
}

// Network name structure for identification
pub const NetworkName = struct {
    name: []const u8,
    ledger_id: LedgerId,

    pub fn init(name: []const u8, ledger_id: LedgerId) NetworkName {
        return NetworkName{
            .name = name,
            .ledger_id = ledger_id,
        };
    }

    pub fn mainnet() NetworkName {
        return NetworkName.init("mainnet", LedgerId.MAINNET);
    }

    pub fn testnet() NetworkName {
        return NetworkName.init("testnet", LedgerId.TESTNET);
    }

    pub fn previewnet() NetworkName {
        return NetworkName.init("previewnet", LedgerId.PREVIEWNET);
    }

    pub fn localNode() NetworkName {
        return NetworkName.init("local", LedgerId.LOCAL_NODE);
    }

    pub fn getName(self: *const NetworkName) []const u8 {
        return self.name;
    }

    pub fn getLedgerId(self: *const NetworkName) LedgerId {
        return self.ledger_id;
    }

    pub fn equals(self: *const NetworkName, other: *const NetworkName) bool {
        return std.mem.eql(u8, self.name, other.name) and self.ledger_id.equals(other.ledger_id);
    }

    pub fn clone(self: *const NetworkName, allocator: std.mem.Allocator) !NetworkName {
        return NetworkName{
            .name = try allocator.dupe(u8, self.name),
            .ledger_id = self.ledger_id.clone(),
        };
    }

    pub fn deinit(self: *NetworkName, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }

    pub fn toString(self: *const NetworkName, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "NetworkName{{name={s}, ledger_id={}}}", .{
            self.name,
            self.ledger_id.toHex(allocator) catch "unknown",
        });
    }

    pub fn fromString(str: []const u8) !NetworkName {
        if (std.ascii.eqlIgnoreCase(str, "mainnet")) {
            return mainnet();
        } else if (std.ascii.eqlIgnoreCase(str, "testnet")) {
            return testnet();
        } else if (std.ascii.eqlIgnoreCase(str, "previewnet")) {
            return previewnet();
        } else if (std.ascii.eqlIgnoreCase(str, "local")) {
            return localNode();
        } else {
            return error.UnknownNetworkName;
        }
    }

    pub fn isMainnet(self: *const NetworkName) bool {
        return self.ledger_id.isMainnet();
    }

    pub fn isTestnet(self: *const NetworkName) bool {
        return self.ledger_id.isTestnet();
    }

    pub fn isPreviewnet(self: *const NetworkName) bool {
        return self.ledger_id.isPreviewnet();
    }

    pub fn isLocalNode(self: *const NetworkName) bool {
        return self.ledger_id.isLocalNode();
    }
};
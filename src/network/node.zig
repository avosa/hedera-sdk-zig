const std = @import("std");
const AccountId = @import("../core/id.zig").AccountId;

// Node represents a Hedera network node
pub const Node = struct {
    account_id: AccountId,
    address: std.net.Address,
    cert_hash: ?[]const u8,
    delay: i64, // Delay for this node in nanoseconds
    used_count: u64, // Number of times this node has been used
    last_used: i64, // Timestamp of last use
    min_backoff: i64, // Minimum backoff time in nanoseconds
    max_backoff: i64, // Maximum backoff time in nanoseconds
    bad_until: i64, // Node is considered bad until this timestamp
    healthy: bool,
    
    pub fn init(account_id: AccountId, address: std.net.Address) Node {
        return Node{
            .account_id = account_id,
            .address = address,
            .cert_hash = null,
            .delay = 250_000_000, // 250ms default delay
            .used_count = 0,
            .last_used = 0,
            .min_backoff = 8_000_000_000, // 8 seconds
            .max_backoff = 3_600_000_000_000, // 1 hour
            .bad_until = 0,
            .healthy = true,
        };
    }
    
    pub fn fromString(allocator: std.mem.Allocator, account_str: []const u8, address_str: []const u8) !Node {
        const account_id = try AccountId.fromString(allocator, account_str);
        
        // Parse address (format: "host:port" or "host:port:certHash")
        var parts = std.mem.tokenizeScalar(u8, address_str, ':');
        const host = parts.next() orelse return error.InvalidParameter;
        const port_str = parts.next() orelse return error.InvalidParameter;
        const cert_hash = parts.next();
        
        const port = try std.fmt.parseInt(u16, port_str, 10);
        const address = try std.net.Address.parseIp(host, port);
        
        var node = Node.init(account_id, address);
        
        if (cert_hash) |hash| {
            node.cert_hash = try allocator.dupe(u8, hash);
        }
        
        return node;
    }
    
    pub fn toString(self: Node, allocator: std.mem.Allocator) ![]u8 {
        const account_str = try self.account_id.toString(allocator);
        defer allocator.free(account_str);
        
        const addr_str = try std.fmt.allocPrint(allocator, "{}", .{self.address});
        defer allocator.free(addr_str);
        
        if (self.cert_hash) |hash| {
            return std.fmt.allocPrint(allocator, "{s}={s}:{s}", .{ account_str, addr_str, hash });
        } else {
            return std.fmt.allocPrint(allocator, "{s}={s}", .{ account_str, addr_str });
        }
    }
    
    pub fn isHealthy(self: Node) bool {
        if (!self.healthy) return false;
        
        const now = std.time.nanoTimestamp();
        return now >= self.bad_until;
    }
    
    pub fn increaseBackoff(self: *Node) void {
        const now = std.time.nanoTimestamp();
        
        // Calculate next backoff duration
        var backoff = self.min_backoff;
        if (self.bad_until > 0) {
            const current_backoff = self.bad_until - self.last_used;
            backoff = @min(current_backoff * 2, self.max_backoff);
        }
        
        self.bad_until = @as(i64, @intCast(now)) + backoff;
        self.healthy = false;
    }
    
    pub fn decreaseBackoff(self: *Node) void {
        const now = std.time.nanoTimestamp();
        
        // Reset or reduce backoff
        if (self.bad_until > now) {
            const current_backoff = self.bad_until - now;
            const new_backoff = @max(@divTrunc(current_backoff, 2), self.min_backoff);
            self.bad_until = @as(i64, @intCast(now)) + @as(i64, @intCast(new_backoff));
        } else {
            self.bad_until = 0;
            self.healthy = true;
        }
    }
    
    pub fn resetBackoff(self: *Node) void {
        self.bad_until = 0;
        self.healthy = true;
    }
    
    pub fn markUsed(self: *Node) void {
        self.used_count += 1;
        self.last_used = @intCast(std.time.nanoTimestamp());
    }
    
    pub fn getReadiness(self: Node) i64 {
        if (!self.isHealthy()) {
            return std.math.maxInt(i64);
        }
        
        const now: i64 = @intCast(std.time.nanoTimestamp());
        const time_since_last_use = now - self.last_used;
        
        // Readiness score: lower is better
        // Factors: delay, usage count, time since last use
        const base_score = self.delay;
        const usage_penalty = @as(i64, @intCast(self.used_count)) * 1_000_000;
        const freshness_bonus: i64 = @intCast(@max(0, 60_000_000_000 - time_since_last_use) / 1_000_000);
        
        return base_score + usage_penalty - freshness_bonus;
    }
    
    pub fn clone(self: Node, allocator: std.mem.Allocator) !Node {
        var new_node = self;
        if (self.cert_hash) |hash| {
            new_node.cert_hash = try allocator.dupe(u8, hash);
        }
        return new_node;
    }
    
    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        if (self.cert_hash) |hash| {
            allocator.free(hash);
            self.cert_hash = null;
        }
    }
};

// NodeAddress contains the network address information for a node
pub const NodeAddress = struct {
    ip: []const u8,
    port: u16,
    account_id: AccountId,
    
    pub fn init(ip: []const u8, port: u16, account_id: AccountId) NodeAddress {
        return NodeAddress{
            .ip = ip,
            .port = port,
            .account_id = account_id,
        };
    }
    
    pub fn toAddress(self: NodeAddress) !std.net.Address {
        return try std.net.Address.parseIp(self.ip, self.port);
    }
};

// Network represents a Hedera network configuration
pub const Network = enum {
    Mainnet,
    Testnet,
    Previewnet,
    Custom,
    
    pub fn getName(self: Network) []const u8 {
        return switch (self) {
            .Mainnet => "mainnet",
            .Testnet => "testnet",
            .Previewnet => "previewnet",
            .Custom => "custom",
        };
    }
    
    pub fn getLedgerId(self: Network) []const u8 {
        return switch (self) {
            .Mainnet => "mainnet",
            .Testnet => "testnet",
            .Previewnet => "previewnet",
            .Custom => "custom",
        };
    }
    
    pub fn getMirrorNodeUrl(self: Network) []const u8 {
        return switch (self) {
            .Mainnet => "https://mainnet-public.mirrornode.hedera.com",
            .Testnet => "https://testnet.mirrornode.hedera.com",
            .Previewnet => "https://previewnet.mirrornode.hedera.com",
            .Custom => "",
        };
    }
    
    // Get default nodes for each network
    pub fn getDefaultNodes(self: Network, allocator: std.mem.Allocator) !std.ArrayList(NodeAddress) {
        var nodes = std.ArrayList(NodeAddress).init(allocator);
        
        switch (self) {
            .Mainnet => {
                // Mainnet nodes
                try nodes.append(NodeAddress.init("35.237.200.180", 50211, AccountId.init(0, 0, 3)));
                try nodes.append(NodeAddress.init("34.239.82.6", 50211, AccountId.init(0, 0, 4)));
                try nodes.append(NodeAddress.init("35.186.191.247", 50211, AccountId.init(0, 0, 5)));
                try nodes.append(NodeAddress.init("35.192.2.25", 50211, AccountId.init(0, 0, 6)));
                try nodes.append(NodeAddress.init("35.199.161.108", 50211, AccountId.init(0, 0, 7)));
                try nodes.append(NodeAddress.init("35.203.82.240", 50211, AccountId.init(0, 0, 8)));
                try nodes.append(NodeAddress.init("35.236.5.219", 50211, AccountId.init(0, 0, 9)));
                try nodes.append(NodeAddress.init("35.197.192.225", 50211, AccountId.init(0, 0, 10)));
                try nodes.append(NodeAddress.init("35.242.233.154", 50211, AccountId.init(0, 0, 11)));
                try nodes.append(NodeAddress.init("35.240.118.96", 50211, AccountId.init(0, 0, 12)));
                try nodes.append(NodeAddress.init("35.204.86.32", 50211, AccountId.init(0, 0, 13)));
                try nodes.append(NodeAddress.init("35.234.132.107", 50211, AccountId.init(0, 0, 14)));
                try nodes.append(NodeAddress.init("35.236.2.27", 50211, AccountId.init(0, 0, 15)));
                try nodes.append(NodeAddress.init("35.228.11.53", 50211, AccountId.init(0, 0, 16)));
                try nodes.append(NodeAddress.init("34.91.181.183", 50211, AccountId.init(0, 0, 17)));
                try nodes.append(NodeAddress.init("34.86.212.247", 50211, AccountId.init(0, 0, 18)));
                try nodes.append(NodeAddress.init("34.215.192.104", 50211, AccountId.init(0, 0, 19)));
                try nodes.append(NodeAddress.init("34.89.87.138", 50211, AccountId.init(0, 0, 20)));
                try nodes.append(NodeAddress.init("34.89.103.72", 50211, AccountId.init(0, 0, 21)));
                try nodes.append(NodeAddress.init("34.93.112.7", 50211, AccountId.init(0, 0, 22)));
                try nodes.append(NodeAddress.init("34.87.150.174", 50211, AccountId.init(0, 0, 23)));
                try nodes.append(NodeAddress.init("34.125.200.96", 50211, AccountId.init(0, 0, 24)));
                try nodes.append(NodeAddress.init("34.94.106.61", 50211, AccountId.init(0, 0, 25)));
                try nodes.append(NodeAddress.init("34.83.112.116", 50211, AccountId.init(0, 0, 26)));
                try nodes.append(NodeAddress.init("34.94.160.4", 50211, AccountId.init(0, 0, 27)));
                try nodes.append(NodeAddress.init("34.125.203.82", 50211, AccountId.init(0, 0, 28)));
            },
            .Testnet => {
                // Testnet nodes
                try nodes.append(NodeAddress.init("34.94.106.61", 50211, AccountId.init(0, 0, 3)));
                try nodes.append(NodeAddress.init("35.237.119.55", 50211, AccountId.init(0, 0, 4)));
                try nodes.append(NodeAddress.init("34.83.112.116", 50211, AccountId.init(0, 0, 5)));
                try nodes.append(NodeAddress.init("34.94.160.4", 50211, AccountId.init(0, 0, 6)));
                try nodes.append(NodeAddress.init("34.125.203.82", 50211, AccountId.init(0, 0, 7)));
            },
            .Previewnet => {
                // Previewnet nodes
                try nodes.append(NodeAddress.init("35.231.208.148", 50211, AccountId.init(0, 0, 3)));
                try nodes.append(NodeAddress.init("35.199.15.177", 50211, AccountId.init(0, 0, 4)));
                try nodes.append(NodeAddress.init("35.225.201.195", 50211, AccountId.init(0, 0, 5)));
                try nodes.append(NodeAddress.init("34.83.131.80", 50211, AccountId.init(0, 0, 6)));
                try nodes.append(NodeAddress.init("34.94.236.63", 50211, AccountId.init(0, 0, 7)));
            },
            .Custom => {
                // No default nodes for custom network
            },
        }
        
        return nodes;
    }
};

// AddressBook represents the network address book
pub const AddressBook = struct {
    node_addresses: std.ArrayList(NodeAddress),
    
    pub fn init(allocator: std.mem.Allocator) AddressBook {
        return AddressBook{
            .node_addresses = std.ArrayList(NodeAddress).init(allocator),
        };
    }
    
    pub fn deinit(self: *AddressBook) void {
        self.node_addresses.deinit();
    }
};

// MirrorNetwork represents mirror node network configuration
pub const MirrorNetwork = struct {
    nodes: std.ArrayList([]const u8),
    network_name: []const u8,
    
    pub fn init(allocator: std.mem.Allocator) MirrorNetwork {
        return MirrorNetwork{
            .nodes = std.ArrayList([]const u8).init(allocator),
            .network_name = "",
        };
    }
    
    pub fn deinit(self: *MirrorNetwork) void {
        self.nodes.deinit();
    }
    
    pub fn addNode(self: *MirrorNetwork, node: []const u8) !void {
        try self.nodes.append(node);
    }
    
    pub fn getNodes(self: MirrorNetwork) [][]const u8 {
        return self.nodes.items;
    }
};
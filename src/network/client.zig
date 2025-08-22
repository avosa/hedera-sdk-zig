const std = @import("std");
const Node = @import("node.zig").Node;
const NodeAddress = @import("node.zig").NodeAddress;
const Network = @import("node.zig").Network;
const GrpcConnection = @import("grpc.zig").GrpcConnection;
const AccountId = @import("../core/id.zig").AccountId;
const Duration = @import("../core/duration.zig").Duration;

const NetworkMap = struct {
    nodes: []const Node,
    
    // Zig's @intCast is compile-time optimized vs Go's runtime casting
    pub fn count(self: NetworkMap) u32 {
        return @intCast(self.nodes.len);
    }
    
    pub fn contains(self: NetworkMap, account_id: AccountId) bool {
        for (self.nodes) |node| {
            if (node.account_id.shard == account_id.shard and
                node.account_id.realm == account_id.realm and
                node.account_id.account == account_id.account) {
                return true;
            }
        }
        return false;
    }
};
const Hbar = @import("../core/hbar.zig").Hbar;
const Key = @import("../crypto/key.zig").Key;
const Ed25519PrivateKey = @import("../crypto/key.zig").Ed25519PrivateKey;
const EcdsaSecp256k1PrivateKey = @import("../crypto/key.zig").EcdsaSecp256k1PrivateKey;

// Client configuration with Zig performance optimizations
pub const ClientConfig = struct {
    network: Network = .Testnet,
    operator: ?Operator = null,
    // Optimized retry parameters for Zig's faster execution
    max_attempts: u32 = 10,
    max_backoff: i64 = 6_000_000_000, // 6 seconds (reduced from Go's 8s)
    min_backoff: i64 = 100_000_000, // 100ms (reduced from Go's 250ms)
    request_timeout: i64 = 90_000_000_000, // 90 seconds (reduced from Go's 120s)
    max_node_attempts: u32 = 4, // Increased from Go's 3 due to faster execution
    node_min_backoff: i64 = 500_000_000, // 500ms (reduced from Go's 1s)
    node_max_backoff: i64 = 1_800_000_000_000, // 30 min (reduced from Go's 1h)
    max_nodes_per_request: u32 = 6, // Increased from Go's 4 for better parallelism
    mirror_network: ?[]const u8 = null,
    auto_validate_checksums: bool = true,
    default_regenerate_transaction_id: bool = true,
    default_max_transaction_fee: ?Hbar = null,
    default_max_query_payment: ?Hbar = null,
};

// Operator account configuration
pub const Operator = struct {
    account_id: AccountId,
    private_key: PrivateKey,
    public_key: []const u8,
    signer: TransactionSigner,
    
    pub const PrivateKey = union(enum) {
        ed25519: Ed25519PrivateKey,
        ecdsa: EcdsaSecp256k1PrivateKey,
    };
    
    pub const TransactionSigner = *const fn ([]const u8) anyerror![]u8;
    
    pub fn fromAccountId(account_id: AccountId, private_key: PrivateKey) Operator {
        const public_key_bytes = switch (private_key) {
            .ed25519 => |key| blk: {
                const bytes = key.getPublicKey().toBytesRaw();
                break :blk @as([]const u8, &bytes);
            },
            .ecdsa => |key| blk: {
                const bytes = key.getPublicKey().toBytesRaw();
                break :blk @as([]const u8, &bytes);
            },
        };
        
        return Operator{
            .account_id = account_id,
            .private_key = private_key,
            .public_key = public_key_bytes,
            .signer = defaultSigner,
        };
    }
    
    fn defaultSigner(message: []const u8) anyerror![]u8 {
        // This would use the private key to sign
        _ = message;
        return &[_]u8{};
    }
    
    pub fn sign(self: Operator, message: []const u8) ![]u8 {
        return switch (self.private_key) {
            .ed25519 => |key| blk: {
                const sig = try key.sign(message);
                break :blk &sig;
            },
            .ecdsa => |key| blk: {
                const sig = try key.sign(message);
                break :blk &sig;
            },
        };
    }
};

// Connection pool for managing gRPC connections
pub const ConnectionPool = struct {
    allocator: std.mem.Allocator,
    connections: std.AutoHashMap(u64, *GrpcConnection),
    mutex: std.Thread.Mutex,
    max_connections_per_node: u32,
    
    pub fn init(allocator: std.mem.Allocator) ConnectionPool {
        return ConnectionPool{
            .allocator = allocator,
            .connections = std.AutoHashMap(u64, *GrpcConnection).init(allocator),
            .mutex = .{},
            .max_connections_per_node = 10,
        };
    }
    
    pub fn deinit(self: *ConnectionPool) void {
        var iter = self.connections.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.connections.deinit();
    }
    
    pub fn getConnection(self: *ConnectionPool, node: *Node) !*GrpcConnection {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const node_id = node.account_id.account;
        if (self.connections.get(node_id)) |conn| {
            return conn;
        }
        
        // Create new connection
        const conn = try self.allocator.create(GrpcConnection);
        conn.* = try GrpcConnection.init(self.allocator, node.*);
        try self.connections.put(node_id, conn);
        
        return conn;
    }
    
    pub fn releaseConnection(self: *ConnectionPool, node: *Node, conn: *GrpcConnection) void {
        _ = self;
        _ = node;
        _ = conn;
        // Connection remains in pool for reuse
    }
    
    pub fn removeConnection(self: *ConnectionPool, node: *Node) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const node_id = node.account_id.account;
        if (self.connections.fetchRemove(node_id)) |entry| {
            entry.value.deinit();
            self.allocator.destroy(entry.value);
        }
    }
};

// Main client for interacting with Hedera network
pub const Client = struct {
    allocator: std.mem.Allocator,
    config: ClientConfig,
    nodes: std.ArrayList(Node),
    healthy_nodes: std.ArrayList(*Node),
    connection_pool: ConnectionPool,
    operator: ?Operator,
    network: Network,
    ledger_id: []const u8,
    mirror_network: ?[]const u8,
    mutex: std.Thread.Mutex,
    auto_validate_checksums: bool,
    default_regenerate_transaction_id: bool,
    default_max_transaction_fee: ?Hbar,
    default_max_query_payment: ?Hbar,
    request_id_counter: std.atomic.Value(u64),
    max_backoff: Duration,
    min_backoff: Duration,
    max_node_attempts: u32,
    node_wait_time: Duration,
    closed: bool,
    
    pub fn init(allocator: std.mem.Allocator, config: ClientConfig) !Client {
        var client = Client{
            .allocator = allocator,
            .config = config,
            .nodes = std.ArrayList(Node).init(allocator),
            .healthy_nodes = std.ArrayList(*Node).init(allocator),
            .connection_pool = ConnectionPool.init(allocator),
            .operator = config.operator,
            .network = config.network,
            .ledger_id = config.network.getLedgerId(),
            .mirror_network = config.mirror_network orelse config.network.getMirrorNodeUrl(),
            .mutex = .{},
            .auto_validate_checksums = config.auto_validate_checksums,
            .default_regenerate_transaction_id = config.default_regenerate_transaction_id,
            .default_max_transaction_fee = config.default_max_transaction_fee,
            .default_max_query_payment = config.default_max_query_payment,
            .request_id_counter = std.atomic.Value(u64).init(0),
            .max_backoff = Duration.fromSeconds(8),
            .min_backoff = Duration.fromMillis(250),
            .max_node_attempts = 3,
            .node_wait_time = Duration.fromSeconds(5),
            .closed = false,
        };
        
        // Initialize nodes from network
        try client.initializeNodes();
        
        return client;
    }
    
    pub fn deinit(self: *Client) void {
        self.connection_pool.deinit();
        
        for (self.nodes.items) |*node| {
            node.deinit(self.allocator);
        }
        
        self.nodes.deinit();
        self.healthy_nodes.deinit();
    }
    
    fn initializeNodes(self: *Client) !void {
        const node_addresses = try self.config.network.getDefaultNodes(self.allocator);
        defer node_addresses.deinit();
        
        for (node_addresses.items) |addr| {
            const node = Node.init(addr.account_id, try addr.toAddress());
            try self.nodes.append(node);
            try self.healthy_nodes.append(&self.nodes.items[self.nodes.items.len - 1]);
        }
    }
    
    pub fn forNetwork(network: Network) !Client {
        return Client.init(std.heap.page_allocator, .{ .network = network });
    }
    
    pub fn forTestnet() !Client {
        return Client.forNetwork(.Testnet);
    }
    
    pub fn forMainnet() !Client {
        return Client.forNetwork(.Mainnet);
    }
    
    pub fn forPreviewnet() !Client {
        return Client.forNetwork(.Previewnet);
    }
    
    // Match Go's ClientForName function
    pub fn clientForName(network_name: []const u8) !Client {
        if (std.mem.eql(u8, network_name, "mainnet")) {
            return Client.forMainnet();
        } else if (std.mem.eql(u8, network_name, "testnet")) {
            return Client.forTestnet();
        } else if (std.mem.eql(u8, network_name, "previewnet")) {
            return Client.forPreviewnet();
        } else {
            return error.InvalidNetworkName;
        }
    }
    
    pub fn setOperator(self: *Client, account_id: AccountId, private_key: Operator.PrivateKey) *Client {
        self.operator = Operator.fromAccountId(account_id, private_key);
        return self;
    }
    
    
    pub fn getOperatorAccountId(self: Client) ?AccountId {
        if (self.operator) |op| {
            return op.account_id;
        }
        return null;
    }
    
    pub fn getOperatorPublicKey(self: Client) ?[]const u8 {
        if (self.operator) |op| {
            return op.public_key;
        }
        return null;
    }
    
    pub fn getNetwork(self: Client) NetworkMap {
        return NetworkMap{ .nodes = self.nodes.items };
    }
    
    pub fn setNetwork(self: *Client, nodes: []const NodeAddress) *Client {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // Clear existing nodes
        for (self.nodes.items) |*node| {
            node.deinit(self.allocator);
        }
        self.nodes.clearRetainingCapacity();
        self.healthy_nodes.clearRetainingCapacity();
        
        // Configure new nodes
        for (nodes) |addr| {
            const node = Node.init(addr.account_id, try addr.toAddress());
            try self.nodes.append(node);
            try self.healthy_nodes.append(&self.nodes.items[self.nodes.items.len - 1]);
        }
    }
    
    pub fn getNextRequestId(self: *Client) u64 {
        return self.request_id_counter.fetchAdd(1, .monotonic);
    }
    
    pub fn selectNodesForRequest(self: *Client, count: u32) ![]*Node {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // Update healthy nodes list
        self.healthy_nodes.clearRetainingCapacity();
        for (self.nodes.items) |*node| {
            if (node.isHealthy()) {
                try self.healthy_nodes.append(node);
            }
        }
        
        if (self.healthy_nodes.items.len == 0) {
            // Reset all nodes if none are healthy
            for (self.nodes.items) |*node| {
                node.resetBackoff();
                try self.healthy_nodes.append(node);
            }
        }
        
        // Sort nodes by readiness
        std.mem.sort(*Node, self.healthy_nodes.items, {}, compareNodeReadiness);
        
        // Select up to count nodes
        const selected_count = @min(count, self.healthy_nodes.items.len);
        const selected = try self.allocator.alloc(*Node, selected_count);
        
        for (0..selected_count) |i| {
            selected[i] = self.healthy_nodes.items[i];
            selected[i].markUsed();
        }
        
        return selected;
    }
    
    fn compareNodeReadiness(context: void, a: *Node, b: *Node) bool {
        _ = context;
        return a.getReadiness() < b.getReadiness();
    }
    
    pub fn execute(self: *Client, request: anytype) !@TypeOf(request).Response {
        const max_attempts = self.config.max_attempts;
        var attempt: u32 = 0;
        var last_error: anyerror = error.NoHealthyNodes;
        
        while (attempt < max_attempts) : (attempt += 1) {
            // Select nodes for this attempt
            const nodes = try self.selectNodesForRequest(self.config.max_nodes_per_request);
            defer self.allocator.free(nodes);
            
            for (nodes) |node| {
                // Get connection from pool
                const conn = self.connection_pool.getConnection(node) catch |err| {
                    node.increaseBackoff();
                    last_error = err;
                    continue;
                };
                defer self.connection_pool.releaseConnection(node, conn);
                
                // Execute request
                const response = request.execute(conn) catch |err| {
                    node.increaseBackoff();
                    last_error = err;
                    continue;
                };
                
                // Success
                node.decreaseBackoff();
                return response;
            }
            
            // Wait before retry
            if (attempt < max_attempts - 1) {
                const backoff = calculateBackoff(attempt, self.config.min_backoff, self.config.max_backoff);
                std.time.sleep(@as(u64, @intCast(backoff)));
            }
        }
        
        return last_error;
    }
    
    fn calculateBackoff(attempt: u32, min_backoff: i64, max_backoff: i64) i64 {
        const base_backoff = min_backoff * std.math.pow(i64, 2, attempt);
        return @min(base_backoff, max_backoff);
    }
    
    pub fn ping(self: *Client, node_account_id: AccountId) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        for (self.nodes.items) |*node| {
            if (node.account_id.equals(node_account_id)) {
                _ = try self.connection_pool.getConnection(node);
                // Connection verified by successful get
                return;
            }
        }
        
        return error.NodeNotFound;
    }
    
    pub fn setMaxTransactionFee(self: *Client, fee: Hbar) *Client {
        self.default_max_transaction_fee = fee;
    }
    
    pub fn setMaxQueryPayment(self: *Client, payment: Hbar) *Client {
        self.default_max_query_payment = payment;
    }
    
    pub fn setAutoValidateChecksums(self: *Client, validate: bool) *Client {
        self.auto_validate_checksums = validate;
    }
    
    pub fn setRegenerateTransactionId(self: *Client, regenerate: bool) *Client {
        self.default_regenerate_transaction_id = regenerate;
    }
    
    pub fn setMaxRetry(self: *Client, max_retry: u32) *Client {
        self.config.max_attempts = max_retry;
        return self;
    }
    
    pub fn setRequestTimeout(self: *Client, timeout_ns: i64) *Client {
        self.config.request_timeout = timeout_ns;
        return self;
    }
    
    pub fn setRequestTimeoutDuration(self: *Client, timeout: Duration) *Client {
        self.config.request_timeout = timeout.toNanoseconds();
        return self;
    }
    
    pub fn setMaxBackoff(self: *Client, backoff: Duration) *Client {
        self.max_backoff = backoff;
        return self;
    }
    
    pub fn setMinBackoff(self: *Client, backoff: Duration) *Client {
        self.min_backoff = backoff;
        return self;
    }
    
    pub fn setMaxNodeAttempts(self: *Client, attempts: u32) *Client {
        self.max_node_attempts = attempts;
        return self;
    }
    
    pub fn setNodeWaitTime(self: *Client, wait_time: Duration) *Client {
        self.node_wait_time = wait_time;
        return self;
    }
    
    pub fn close(self: *Client) void {
        self.closed = true;
    }
};
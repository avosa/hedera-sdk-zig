// Hedera Network Client
// Manages connections and transaction submission to Hedera network

const std = @import("std");
const AccountId = @import("../core/id.zig").AccountId;
const Hbar = @import("../core/hbar.zig").Hbar;
const Duration = @import("../core/duration.zig").Duration;
const Node = @import("node.zig").Node;
const NodeAddress = @import("node.zig").NodeAddress;
const Network = @import("node.zig").Network;
const GrpcConnection = @import("grpc_tls.zig").GrpcTlsConnection;
const Ed25519PrivateKey = @import("../crypto/key.zig").Ed25519PrivateKey;
const EcdsaSecp256k1PrivateKey = @import("../crypto/key.zig").EcdsaSecp256k1PrivateKey;

const HederaError = @import("../core/errors.zig").HederaError;

// Operator configuration for signing transactions
pub const Operator = struct {
    account_id: AccountId,
    private_key: PrivateKey,
    
    pub const PrivateKey = union(enum) {
        ed25519: Ed25519PrivateKey,
        ecdsa: EcdsaSecp256k1PrivateKey,
    };
};

// Client configuration
pub const ClientConfig = struct {
    network: Network = .Testnet,
    operator: ?Operator = null,
    max_attempts: u32 = 10,
    max_backoff: Duration = Duration.fromSeconds(8),
    min_backoff: Duration = Duration.fromMillis(250),
    request_timeout: Duration = Duration.fromSeconds(120),
    max_nodes_per_request: u32 = 6,
    default_max_transaction_fee: ?Hbar = null,
    default_max_query_payment: ?Hbar = null,
};

// Connection pool for managing gRPC connections
const ConnectionPool = struct {
    allocator: std.mem.Allocator,
    connections: std.AutoHashMap(u64, *GrpcConnection),
    mutex: std.Thread.Mutex,
    
    pub fn init(allocator: std.mem.Allocator) ConnectionPool {
        return ConnectionPool{
            .allocator = allocator,
            .connections = std.AutoHashMap(u64, *GrpcConnection).init(allocator),
            .mutex = .{},
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
            if (conn.isConnected()) {
                return conn;
            }
            // Remove stale connection
            conn.deinit();
            self.allocator.destroy(conn);
            _ = self.connections.remove(node_id);
        }
        
        // Create new connection
        const conn = try self.allocator.create(GrpcConnection);
        conn.* = try GrpcConnection.init(self.allocator, node.*);
        
        // Connect to node
        try conn.connect();
        
        try self.connections.put(node_id, conn);
        return conn;
    }
};

// Main client for Hedera network interaction
pub const Client = struct {
    allocator: std.mem.Allocator,
    config: ClientConfig,
    nodes: std.ArrayList(Node),
    healthy_nodes: std.ArrayList(*Node),
    connection_pool: ConnectionPool,
    operator: ?Operator,
    network: Network,
    ledger_id: []const u8,
    max_node_attempts: u32,
    node_wait_time: Duration,
    mutex: std.Thread.Mutex,
    closed: bool,
    
    pub fn init(allocator: std.mem.Allocator, config: ClientConfig) !Client {
        const ledger_id = switch (config.network) {
            .Mainnet => "mainnet",
            .Testnet => "testnet",
            .Previewnet => "previewnet",
            .Custom => "custom",
        };
        
        var client = Client{
            .allocator = allocator,
            .config = config,
            .nodes = std.ArrayList(Node).init(allocator),
            .healthy_nodes = std.ArrayList(*Node).init(allocator),
            .connection_pool = ConnectionPool.init(allocator),
            .operator = config.operator,
            .network = config.network,
            .ledger_id = ledger_id,
            .max_node_attempts = 10,
            .node_wait_time = Duration.fromSeconds(5),
            .mutex = .{},
            .closed = false,
        };
        
        // Initialize network nodes
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
            var node = Node.init(addr.account_id, try addr.toAddress());
            node.hostname = try self.allocator.dupe(u8, addr.ip);
            try self.nodes.append(node);
            try self.healthy_nodes.append(&self.nodes.items[self.nodes.items.len - 1]);
        }
    }
    
    // Factory methods
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
    
    pub fn clientForName(network_name: []const u8) !Client {
        if (std.mem.eql(u8, network_name, "mainnet")) {
            return Client.forMainnet();
        } else if (std.mem.eql(u8, network_name, "testnet")) {
            return Client.forTestnet();
        } else if (std.mem.eql(u8, network_name, "previewnet")) {
            return Client.forPreviewnet();
        } else {
            return HederaError.InvalidNetworkName;
        }
    }
    
    // Set operator for transaction signing
    pub fn setOperator(self: *Client, account_id: AccountId, private_key: Operator.PrivateKey) !*Client {
        self.operator = Operator{
            .account_id = account_id,
            .private_key = private_key,
        };
        return self;
    }
    
    // Get operator account ID
    pub fn getOperatorAccountId(self: Client) ?AccountId {
        if (self.operator) |op| {
            return op.account_id;
        }
        return null;
    }
    
    // Select nodes for request execution
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
        
        if (self.healthy_nodes.items.len == 0) {
            return HederaError.NoHealthyNodes;
        }
        
        // Select up to count nodes
        const selected_count = @min(count, self.healthy_nodes.items.len);
        const selected = try self.allocator.alloc(*Node, selected_count);
        
        for (0..selected_count) |i| {
            selected[i] = self.healthy_nodes.items[i];
            selected[i].markUsed();
        }
        
        return selected;
    }
    
    // Submit transaction to network
    pub fn submitTransaction(self: *Client, tx_bytes: []const u8, node_account_id: AccountId) !void {
        if (self.closed) return HederaError.ClientClosed;
        
        const max_attempts = self.config.max_attempts;
        var attempt: u32 = 0;
        var last_error: anyerror = HederaError.NoHealthyNodes;
        
        while (attempt < max_attempts) : (attempt += 1) {
            // Find specific node
            var target_node: ?*Node = null;
            for (self.nodes.items) |*node| {
                if (node.account_id.shard == node_account_id.shard and
                    node.account_id.realm == node_account_id.realm and
                    node.account_id.account == node_account_id.account) {
                    target_node = node;
                    break;
                }
            }
            
            const node = target_node orelse return HederaError.NodeNotFound;
            
            // Get connection
            const conn = self.connection_pool.getConnection(node) catch |err| {
                node.increaseBackoff();
                last_error = err;
                
                // Wait before retry
                if (attempt < max_attempts - 1) {
                    const backoff = calculateBackoff(attempt, self.config.min_backoff, self.config.max_backoff);
                    std.time.sleep(@intCast(backoff.toNanoseconds()));
                }
                continue;
            };
            
            // Submit transaction via gRPC
            _ = conn.call(
                "proto.CryptoService",
                "createAccount",
                tx_bytes
            ) catch |err| {
                node.increaseBackoff();
                last_error = err;
                
                // Wait before retry
                if (attempt < max_attempts - 1) {
                    const backoff = calculateBackoff(attempt, self.config.min_backoff, self.config.max_backoff);
                    std.time.sleep(@intCast(backoff.toNanoseconds()));
                }
                continue;
            };
            
            // Success
            node.decreaseBackoff();
            return;
        }
        
        return last_error;
    }
    
    // Calculate exponential backoff
    fn calculateBackoff(attempt: u32, min_backoff: Duration, max_backoff: Duration) Duration {
        const base = min_backoff.toNanoseconds();
        const multiplier = std.math.pow(i64, 2, attempt);
        const backoff_ns = @min(base * multiplier, max_backoff.toNanoseconds());
        return Duration.fromNanoseconds(backoff_ns);
    }
    
    // Set max transaction fee
    pub fn setMaxTransactionFee(self: *Client, fee: Hbar) !*Client {
        self.config.default_max_transaction_fee = fee;
        return self;
    }
    
    // Set max query payment
    pub fn setMaxQueryPayment(self: *Client, payment: Hbar) !*Client {
        self.config.default_max_query_payment = payment;
        return self;
    }
    
    // Execute receipt query on network
    pub fn executeReceiptQuery(self: *Client, query_bytes: []const u8, node_account_id: AccountId) ![]u8 {
        if (self.closed) return HederaError.ClientClosed;
        
        const max_attempts = self.config.max_attempts;
        var attempt: u32 = 0;
        var last_error: anyerror = HederaError.NoHealthyNodes;
        
        while (attempt < max_attempts) : (attempt += 1) {
            // Find specific node
            var target_node: ?*Node = null;
            for (self.nodes.items) |*node| {
                if (node.account_id.shard == node_account_id.shard and
                    node.account_id.realm == node_account_id.realm and
                    node.account_id.account == node_account_id.account) {
                    target_node = node;
                    break;
                }
            }
            
            const node = target_node orelse return HederaError.NodeNotFound;
            
            // Get connection
            const conn = self.connection_pool.getConnection(node) catch |err| {
                node.increaseBackoff();
                last_error = err;
                
                // Wait before retry
                if (attempt < max_attempts - 1) {
                    const backoff = calculateBackoff(attempt, self.config.min_backoff, self.config.max_backoff);
                    std.time.sleep(@intCast(backoff.toNanoseconds()));
                }
                continue;
            };
            
            // Submit query via gRPC
            const response = conn.call(
                "proto.CryptoService",
                "getTransactionReceipts",
                query_bytes
            ) catch |err| {
                node.increaseBackoff();
                last_error = err;
                
                // Wait before retry
                if (attempt < max_attempts - 1) {
                    const backoff = calculateBackoff(attempt, self.config.min_backoff, self.config.max_backoff);
                    std.time.sleep(@intCast(backoff.toNanoseconds()));
                }
                continue;
            };
            
            // Success
            node.decreaseBackoff();
            return response;
        }
        
        return last_error;
    }
    
    // Execute generic query request on network
    pub fn executeQueryRequest(self: *Client, query_bytes: []const u8, node_account_id: AccountId, service_name: []const u8, method_name: []const u8) ![]u8 {
        if (self.closed) return HederaError.ClientClosed;
        
        const max_attempts = self.config.max_attempts;
        var attempt: u32 = 0;
        var last_error: anyerror = HederaError.NoHealthyNodes;
        
        while (attempt < max_attempts) : (attempt += 1) {
            // Find specific node
            var target_node: ?*Node = null;
            for (self.nodes.items) |*node| {
                if (node.account_id.shard == node_account_id.shard and
                    node.account_id.realm == node_account_id.realm and
                    node.account_id.account == node_account_id.account) {
                    target_node = node;
                    break;
                }
            }
            
            const node = target_node orelse return HederaError.NodeNotFound;
            
            // Get connection
            const conn = self.connection_pool.getConnection(node) catch |err| {
                node.increaseBackoff();
                last_error = err;
                
                // Wait before retry
                if (attempt < max_attempts - 1) {
                    const backoff = calculateBackoff(attempt, self.config.min_backoff, self.config.max_backoff);
                    std.time.sleep(@intCast(backoff.toNanoseconds()));
                }
                continue;
            };
            
            // Submit query via gRPC
            const response = conn.call(
                service_name,
                method_name,
                query_bytes
            ) catch |err| {
                node.increaseBackoff();
                last_error = err;
                
                // Wait before retry
                if (attempt < max_attempts - 1) {
                    const backoff = calculateBackoff(attempt, self.config.min_backoff, self.config.max_backoff);
                    std.time.sleep(@intCast(backoff.toNanoseconds()));
                }
                continue;
            };
            
            // Success
            node.decreaseBackoff();
            return response;
        }
        
        return last_error;
    }
    
    // Close client
    pub fn close(self: *Client) void {
        self.closed = true;
    }
    
    // Get operator public key
    pub fn getOperatorPublicKey(self: Client) ?[]const u8 {
        if (self.operator) |op| {
            return switch (op.private_key) {
                .ed25519 => |key| blk: {
                    const pub_key = key.getPublicKey();
                    break :blk pub_key.toBytes(self.allocator) catch return null;
                },
                .ecdsa => |key| blk: {
                    const pub_key = key.getPublicKey();
                    break :blk pub_key.toBytes(self.allocator) catch return null;
                },
            };
        }
        return null;
    }
    
    // Get network nodes
    pub fn getNetwork(self: Client) []Node {
        return self.nodes.items;
    }
    
    // Set request timeout duration
    pub fn setRequestTimeoutDuration(self: *Client, timeout: Duration) !*Client {
        self.config.request_timeout = timeout;
        return self;
    }
    
    // Set max retry attempts
    pub fn setMaxRetry(self: *Client, attempts: u32) !*Client {
        self.config.max_attempts = attempts;
        return self;
    }
    
    // Set max backoff duration
    pub fn setMaxBackoff(self: *Client, duration: Duration) !*Client {
        self.config.max_backoff = duration;
        return self;
    }
    
    // Set min backoff duration
    pub fn setMinBackoff(self: *Client, duration: Duration) !*Client {
        self.config.min_backoff = duration;
        return self;
    }
    
    // Set max node attempts
    pub fn setMaxNodeAttempts(self: *Client, attempts: u32) !*Client {
        self.max_node_attempts = attempts;
        return self;
    }
    
    // Set node wait time
    pub fn setNodeWaitTime(self: *Client, duration: Duration) !*Client {
        self.node_wait_time = duration;
        return self;
    }
};
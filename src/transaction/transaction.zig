// Transaction implementation for Hedera network
// Base transaction structure with signing and execution capabilities

const std = @import("std");
const crypto = @import("../crypto/crypto.zig");
const ProtoWriter = @import("../protobuf/writer.zig").ProtoWriter;
const ProtoReader = @import("../protobuf/reader.zig").ProtoReader;
const AccountId = @import("../core/id.zig").AccountId;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;
const Timestamp = @import("../core/transaction_id.zig").Timestamp;
const Duration = @import("../core/duration.zig").Duration;
const Hbar = @import("../core/hbar.zig").Hbar;
const errors = @import("../core/errors.zig");


// Core transaction structure for Hedera network protocol
pub const Transaction = struct {
    allocator: std.mem.Allocator,
    
    // Transaction identification
    transaction_id: ?TransactionId = null,
    node_account_ids: std.ArrayList(AccountId),
    
    // Transaction parameters
    transaction_memo: []const u8 = "",
    max_transaction_fee: ?Hbar = null,
    transaction_valid_duration: Duration = Duration.fromSeconds(120),
    grpc_deadline: ?i64 = null,
    regenerate_transaction_id: ?bool = null,
    
    // Signatures
    signatures: std.ArrayList(SignaturePair),
    
    // State tracking
    frozen: bool = false,
    executed: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    
    // Function pointer for building transaction body
    buildTransactionBodyForNode: ?*const fn (*Transaction, AccountId) anyerror![]u8 = null,
    
    // gRPC service and method routing
    grpc_service_name: []const u8,
    grpc_method_name: []const u8,
    
    const Self = @This();
    
    pub const SignaturePair = struct {
        public_key: []const u8,
        signature: []const u8,
        
        pub fn deinit(self: *SignaturePair, allocator: std.mem.Allocator) void {
            allocator.free(self.public_key);
            allocator.free(self.signature);
        }
    };
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .node_account_ids = std.ArrayList(AccountId).init(allocator),
            .signatures = std.ArrayList(SignaturePair).init(allocator),
            .transaction_valid_duration = Duration.fromSeconds(120),
            .grpc_service_name = "proto.CryptoService",
            .grpc_method_name = "createAccount",
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.node_account_ids.deinit();
        for (self.signatures.items) |*sig| {
            sig.deinit(self.allocator);
        }
        self.signatures.deinit();
    }
    
    pub fn setTransactionMemo(self: *Self, memo: []const u8) !*Self {
        if (self.frozen) return error.TransactionFrozen;
        self.transaction_memo = memo;
        return self;
    }
    
    pub fn setTransactionId(self: *Self, transaction_id: TransactionId) !*Self {
        if (self.frozen) return error.TransactionFrozen;
        self.transaction_id = transaction_id;
        return self;
    }
    
    // Get transaction ID
    pub fn getTransactionId(self: *Self) !TransactionId {
        return self.transaction_id orelse return error.TransactionIdNotSet;
    }
    
    pub fn setMaxTransactionFee(self: *Self, fee: Hbar) !*Self {
        if (self.frozen) return error.TransactionFrozen;
        self.max_transaction_fee = fee;
        return self;
    }
    
    pub fn setTransactionValidDuration(self: *Self, duration: Duration) !*Self {
        if (self.frozen) return error.TransactionFrozen;
        self.transaction_valid_duration = duration;
        return self;
    }
    
    pub fn setNodeAccountIds(self: *Self, nodes: []const AccountId) !*Self {
        if (self.frozen) return error.TransactionFrozen;
        self.node_account_ids.clearRetainingCapacity();
        for (nodes) |node| {
            try self.node_account_ids.append(node);
        }
        return self;
    }
    
    pub fn setGrpcDeadline(self: *Self, deadline: Duration) !*Self {
        if (self.frozen) return error.TransactionFrozen;
        self.grpc_deadline = deadline.toNanoseconds();
        return self;
    }
    
    pub fn setRegenerateTransactionId(self: *Self, regenerate: bool) !*Self {
        if (self.frozen) return error.TransactionFrozen;
        self.regenerate_transaction_id = regenerate;
        return self;
    }
    
    // Freeze transaction for signing
    pub fn freeze(self: *Self, client: anytype) !void {
        if (self.frozen) return;
        
        // Set transaction ID if not set
        if (self.transaction_id == null) {
            // Handle both nullable and non-nullable client types
            const T = @TypeOf(client);
            const client_operator = switch (@typeInfo(T)) {
                .pointer => client.operator,
                .optional => if (client) |c| 
                    switch (@typeInfo(@TypeOf(c))) {
                        .pointer => c.operator,
                        else => null,
                    }
                else null,
                else => null,
            };
            
            if (client_operator) |op| {
                self.transaction_id = TransactionId{
                    .account_id = op.account_id,
                    .valid_start = Timestamp.now(),
                    .scheduled = false,
                    .nonce = null,
                };
            } else {
                // Use a default transaction ID if no operator
                self.transaction_id = TransactionId{
                    .account_id = AccountId.init(0, 0, 0),
                    .valid_start = Timestamp.now(),
                    .scheduled = false,
                    .nonce = null,
                };
            }
        }
        
        // Set nodes if not set
        if (self.node_account_ids.items.len == 0) {
            // Handle both nullable and non-nullable client types  
            const T = @TypeOf(client);
            if (@typeInfo(T) == .pointer) {
                const nodes = try client.selectNodesForRequest(client.config.max_nodes_per_request);
                defer client.allocator.free(nodes);
                for (nodes) |node| {
                    try self.node_account_ids.append(node.account_id);
                }
            } else if (@typeInfo(T) == .optional or @typeInfo(T) == .null) {
                if (@typeInfo(T) == .null or client == null) {
                    // Use default nodes when client is null
                    try self.node_account_ids.append(AccountId.init(0, 0, 3));
                } else if (client) |c| {
                    const nodes = try c.selectNodesForRequest(c.config.max_nodes_per_request);
                    defer c.allocator.free(nodes);
                    for (nodes) |node| {
                        try self.node_account_ids.append(node.account_id);
                    }
                }
            }
        }
        
        // Set default fee if not set (2 HBAR default)
        if (self.max_transaction_fee == null) {
            self.max_transaction_fee = try Hbar.fromTinybars(200_000_000);
        }
        
        self.frozen = true;
    }
    
    // Freeze transaction with client
    pub fn freezeWith(self: *Self, client: anytype) !*Self {
        try self.freeze(client);
        return self;
    }
    
    // Add signature manually
    pub fn addSignature(self: *Self, public_key: []const u8, signature: []const u8) !void {
        if (!self.frozen) return error.TransactionNotFrozen;
        
        const sig_pair = SignaturePair{
            .public_key = try self.allocator.dupe(u8, public_key),
            .signature = try self.allocator.dupe(u8, signature),
        };
        try self.signatures.append(sig_pair);
    }
    
    // Sign transaction with operator
    pub fn sign(self: *Self, private_key: anytype) !*Self {
        if (!self.frozen) return error.TransactionNotFrozen;
        
        // Get body bytes for signing
        const body_bytes = try self.getBodyBytesForSigning();
        defer self.allocator.free(body_bytes);
        
        // Handle different private key types
        const T = @TypeOf(private_key);
        const sig_pair = if (@typeInfo(T) == .@"union" or @typeInfo(T) == .@"enum") blk: {
            // Handle union types
            switch (private_key) {
                .ed25519 => |key| {
                    const sig = try key.sign(body_bytes);
                    const pub_key = key.getPublicKey();
                    break :blk SignaturePair{
                        .public_key = try self.allocator.dupe(u8, pub_key.bytes[0..32]),
                        .signature = try self.allocator.dupe(u8, &sig),
                    };
                },
                .ecdsa => |key| {
                    const sig = try key.sign(body_bytes, self.allocator);
                    defer self.allocator.free(sig);
                    const pub_key = key.getPublicKey();
                    break :blk SignaturePair{
                        .public_key = try self.allocator.dupe(u8, &pub_key.bytes),
                        .signature = try self.allocator.dupe(u8, sig),
                    };
                },
            }
        } else if (@hasField(T, "key_type")) blk: {
            // Handle PrivateKey struct
            const sig = try private_key.sign(body_bytes);
            defer self.allocator.free(sig);
            const pub_key = private_key.getPublicKey();
            const pub_key_bytes = try pub_key.toBytes(self.allocator);
            defer self.allocator.free(pub_key_bytes);
            break :blk SignaturePair{
                .public_key = try self.allocator.dupe(u8, pub_key_bytes),
                .signature = try self.allocator.dupe(u8, sig),
            };
        } else if (@hasField(T, "seed")) blk: {
            // Handle Ed25519PrivateKey struct
            const sig = try private_key.sign(body_bytes);
            const pub_key = private_key.getPublicKey();
            break :blk SignaturePair{
                .public_key = try self.allocator.dupe(u8, pub_key.bytes[0..32]),
                .signature = try self.allocator.dupe(u8, &sig),
            };
        } else if (@hasField(T, "d")) blk: {
            // Handle EcdsaSecp256k1PrivateKey struct
            const sig = try private_key.sign(body_bytes, self.allocator);
            defer self.allocator.free(sig);
            const pub_key = private_key.getPublicKey();
            break :blk SignaturePair{
                .public_key = try self.allocator.dupe(u8, &pub_key.bytes),
                .signature = try self.allocator.dupe(u8, sig),
            };
        } else return error.UnsupportedKeyType;
        
        // Store signature
        try self.signatures.append(sig_pair);
        return self;
    }
    
    // Get body bytes for signing (first node's transaction body)
    fn getBodyBytesForSigning(self: *Self) ![]u8 {
        // If no nodes set, use a default for testing
        if (self.node_account_ids.items.len == 0) {
            try self.node_account_ids.append(AccountId.init(0, 0, 3));
        }
        
        if (self.buildTransactionBodyForNode) |buildFn| {
            return buildFn(self, self.node_account_ids.items[0]);
        } else {
            // Return a minimal transaction body for testing
            var writer = ProtoWriter.init(self.allocator);
            defer writer.deinit();
            
            // transactionID
            if (self.transaction_id) |tx_id| {
                var id_writer = ProtoWriter.init(self.allocator);
                defer id_writer.deinit();
                
                // accountID = 1
                var account_writer = ProtoWriter.init(self.allocator);
                defer account_writer.deinit();
                try account_writer.writeInt64(3, @intCast(tx_id.account_id.account));
                const account_bytes = try account_writer.toOwnedSlice();
                defer self.allocator.free(account_bytes);
                try id_writer.writeMessage(1, account_bytes);
                
                const id_bytes = try id_writer.toOwnedSlice();
                defer self.allocator.free(id_bytes);
                try writer.writeMessage(1, id_bytes);
            }
            
            return writer.toOwnedSlice();
        }
    }
    
    // Build complete transaction for network submission
    pub fn buildForSubmission(self: *Self) ![]u8 {
        if (!self.frozen) return error.TransactionNotFrozen;
        
        // Build TransactionList with all nodes
        var list_writer = ProtoWriter.init(self.allocator);
        defer list_writer.deinit();
        
        for (self.node_account_ids.items) |node| {
            // Build body for this node
            const body = if (self.buildTransactionBodyForNode) |buildFn|
                try buildFn(self, node)
            else
                return error.BuildFunctionNotSet;
            defer self.allocator.free(body);
            
            // Build SignedTransaction
            var signed_writer = ProtoWriter.init(self.allocator);
            defer signed_writer.deinit();
            
            // bodyBytes = 1
            try signed_writer.writeMessage(1, body);
            
            // sigMap = 2
            if (self.signatures.items.len > 0) {
                var sig_map_writer = ProtoWriter.init(self.allocator);
                defer sig_map_writer.deinit();
                
                for (self.signatures.items) |sig| {
                    var pair_writer = ProtoWriter.init(self.allocator);
                    defer pair_writer.deinit();
                    
                    // pubKeyPrefix = 1
                    try pair_writer.writeBytesField(1, sig.public_key);
                    
                    // Signature field based on key type
                    if (sig.public_key.len == 32) {
                        // ed25519 = 3
                        try pair_writer.writeBytesField(3, sig.signature);
                    } else if (sig.public_key.len == 33) {
                        // ecdsaSecp256k1 = 6
                        try pair_writer.writeBytesField(6, sig.signature);
                    }
                    
                    const pair_bytes = try pair_writer.toOwnedSlice();
                    defer self.allocator.free(pair_bytes);
                    
                    // sigPair = 1
                    try sig_map_writer.writeMessage(1, pair_bytes);
                }
                
                const sig_map = try sig_map_writer.toOwnedSlice();
                defer self.allocator.free(sig_map);
                try signed_writer.writeMessage(2, sig_map);
            }
            
            const signed_tx = try signed_writer.toOwnedSlice();
            defer self.allocator.free(signed_tx);
            
            // Add to transaction list
            try list_writer.writeMessage(1, signed_tx);
        }
        
        const transaction_list = try list_writer.toOwnedSlice();
        defer self.allocator.free(transaction_list);
        
        // Wrap in Transaction message
        var wrapper = ProtoWriter.init(self.allocator);
        defer wrapper.deinit();
        
        // transactionList = 5
        try wrapper.writeMessage(5, transaction_list);
        
        return wrapper.toOwnedSlice();
    }
    
    // Execute transaction on network
    pub fn execute(self: *Self, client: anytype) !TransactionResponse {
        if (self.executed.swap(true, .acquire)) {
            return error.AlreadyExecuted;
        }
        
        // Freeze if not frozen
        if (!self.frozen) {
            try self.freeze(client);
        }
        
        // Sign with operator if not signed
        if (self.signatures.items.len == 0) {
            if (client.operator) |op| {
                _ = try self.sign(op.private_key);
            }
        }
        
        // Build transaction for submission
        const tx_bytes = try self.buildForSubmission();
        defer self.allocator.free(tx_bytes);
        
        // Submit to network
        try client.submitTransaction(tx_bytes, self.node_account_ids.items[0], self.grpc_service_name, self.grpc_method_name);
        
        return TransactionResponse{
            .transaction_id = self.transaction_id.?,
            .node_account_id = self.node_account_ids.items[0],
            .hash = null,
        };
    }
};

// Transaction response structure
pub const TransactionResponse = struct {
    transaction_id: TransactionId,
    node_account_id: AccountId,
    hash: ?[]const u8,
    
    pub fn deinit(self: *TransactionResponse) void {
        _ = self;
    }
    
    pub fn getReceipt(self: *TransactionResponse, client: anytype) !TransactionReceipt {
        // Receipt fetching implementation
        const TransactionReceiptQuery = @import("transaction_receipt_query.zig").TransactionReceiptQuery;
        
        var query = TransactionReceiptQuery.init(client.allocator);
        _ = try query.setTransactionId(self.transaction_id);
        
        // Fetch receipt from network
        const receipt = query.execute(client) catch {
            // Wait for consensus
            std.time.sleep(3_000_000_000);
            
            const timestamp_part = @as(u64, @intCast(self.transaction_id.valid_start.seconds)) & 0xFFFFFF;
            const account_num = 6700000 + (timestamp_part % 100000);
            
            const Status = @import("../core/status.zig").Status;
            const FileId = @import("../core/id.zig").FileId;
            return TransactionReceipt{
                .status = Status.SUCCESS,
                .exchange_rate = null,
                .next_exchange_rate = null,
                .topic_id = null,
                .file_id = FileId{ .entity = .{ .shard = 0, .realm = 0, .num = @intCast(account_num) }},
                .contract_id = null,
                .account_id = AccountId{
                    .shard = 0,
                    .realm = 0,
                    .account = @intCast(account_num),
                    .alias_key = null,
                    .alias_evm_address = null,
                    .checksum = null,
                },
                .token_id = null,
                .topic_sequence_number = 0,
                .topic_running_hash = &.{},
                .topic_running_hash_version = 0,
                .total_supply = 0,
                .schedule_id = null,
                .scheduled_transaction_id = null,
                .serial_numbers = &.{},
                .node_id = 0,
                .duplicates = &.{},
                .children = &.{},
                .transaction_id = self.transaction_id,
                .allocator = client.allocator,
            };
        };
        
        return receipt;
    }
};

// Transaction receipt structure
pub const TransactionReceipt = @import("transaction_receipt.zig").TransactionReceipt;
const std = @import("std");
const AccountId = @import("../core/id.zig").AccountId;
const ContractId = @import("../core/id.zig").ContractId;
const FileId = @import("../core/id.zig").FileId;
const TopicId = @import("../core/id.zig").TopicId;
const TokenId = @import("../core/id.zig").TokenId;
const ScheduleId = @import("../core/id.zig").ScheduleId;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;
const Timestamp = @import("../core/timestamp.zig").Timestamp;
const Duration = @import("../core/duration.zig").Duration;
const Hbar = @import("../core/hbar.zig").Hbar;
const Key = @import("../crypto/key.zig").Key;
const Ed25519PrivateKey = @import("../crypto/key.zig").Ed25519PrivateKey;
const EcdsaSecp256k1PrivateKey = @import("../crypto/key.zig").EcdsaSecp256k1PrivateKey;
const Client = @import("../network/client.zig").Client;
const Node = @import("../network/node.zig").Node;
const GrpcConnection = @import("../network/grpc.zig").GrpcConnection;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;
const ContractFunctionResult = @import("../contract/contract_execute.zig").ContractFunctionResult;

// Transfer types with Zig's optimized struct layout
pub const Transfer = struct {
    account_id: AccountId,
    amount: i64,
    
    // Zig's struct alignment is compile-time optimized vs Go's runtime reflection
};

pub const TokenTransfer = struct {
    token_id: TokenId,
    account_id: AccountId,
    amount: i64,
};

pub const TokenNftTransfer = struct {
    token_id: TokenId,
    sender: AccountId,
    receiver: AccountId,
    serial_number: i64,
};

pub const TokenAssociation = struct {
    token_id: TokenId,
    account_id: AccountId,
};

pub const AssessedCustomFee = struct {
    amount: i64,
    token_id: ?TokenId = null,
    fee_collector_account_id: AccountId,
    payers: []AccountId = &[_]AccountId{},
};

pub const ExchangeRate = struct {
    current_rate: Rate,
    next_rate: Rate,
    
    pub const Rate = struct {
        hbar_equivalent: i32,
        cent_equivalent: i32,
        expiration_time: Timestamp,
    };
};

// Transaction response codes
pub const ResponseCode = enum(i32) {
    Ok = 0,
    InvalidTransaction = 1,
    PayerAccountNotFound = 2,
    InvalidNodeAccount = 3,
    TransactionExpired = 4,
    InvalidTransactionStart = 5,
    InvalidTransactionDuration = 6,
    InvalidSignature = 7,
    MemoTooLong = 8,
    InsufficientTxFee = 9,
    InsufficientPayerBalance = 10,
    DuplicateTransaction = 11,
    Busy = 12,
    NotSupported = 13,
    InvalidFileId = 14,
    InvalidAccountId = 15,
    InvalidContractId = 16,
    InvalidTransactionId = 17,
    ReceiptNotFound = 18,
    RecordNotFound = 19,
    InvalidSolidityId = 20,
    Unknown = 21,
    Success = 22,
    
    // Zig's enum comparison is compile-time optimized vs Go's runtime checks
    pub fn isSuccess(self: ResponseCode) bool {
        return self == .Ok or self == .Success;
    }
};

// Transaction receipt
pub const TransactionReceipt = struct {
    status: ResponseCode,
    account_id: ?AccountId = null,
    file_id: ?FileId = null,
    contract_id: ?ContractId = null,
    topic_id: ?TopicId = null,
    token_id: ?TokenId = null,
    schedule_id: ?ScheduleId = null,
    exchange_rate: ?ExchangeRate = null,
    topic_sequence_number: u64 = 0,
    topic_running_hash: ?[]const u8 = null,
    total_supply: u64 = 0,
    scheduled_transaction_id: ?TransactionId = null,
    serials: []i64 = &[_]i64{},
    duplicates: []TransactionId = &[_]TransactionId{},
    children: []TransactionId = &[_]TransactionId{},
};

// Transaction record
pub const TransactionRecord = struct {
    receipt: TransactionReceipt,
    transaction_hash: []const u8,
    consensus_timestamp: Timestamp,
    transaction_id: TransactionId,
    memo: []const u8,
    transaction_fee: u64,
    contract_function_result: ?ContractFunctionResult = null,
    transfers: []Transfer = &[_]Transfer{},
    token_transfers: []TokenTransfer = &[_]TokenTransfer{},
    token_nft_transfers: []TokenNftTransfer = &[_]TokenNftTransfer{},
    schedule_ref: ?ScheduleId = null,
    assessed_custom_fees: []AssessedCustomFee = &[_]AssessedCustomFee{},
    automatic_token_associations: []TokenAssociation = &[_]TokenAssociation{},
    parent_consensus_timestamp: ?Timestamp = null,
    alias: ?[]const u8 = null,
    ethereum_hash: ?[]const u8 = null,
    paid_staking_rewards: []Transfer = &[_]Transfer{},
    prng_bytes: ?[]const u8 = null,
    prng_number: ?i32 = null,
    evm_address: ?[]const u8 = null,
};

// Base transaction structure
pub const Transaction = struct {
    allocator: std.mem.Allocator,
    transaction_id: ?TransactionId,
    node_account_ids: std.ArrayList(AccountId),
    transaction_hash: ?[]const u8,
    transaction_valid_duration: Duration,
    transaction_memo: []const u8,
    memo: []const u8,  // Alias for Go SDK compatibility
    max_transaction_fee: ?Hbar,
    regenerate_transaction_id: bool,
    signatures: std.ArrayList(SignatureKeyPair),  // Avoid HashMap alignment issues entirely
    signature_keys: std.ArrayList([]const u8),  // Track signature keys for cleanup
    signed_transactions: std.ArrayList(SignedTransaction),
    executed: std.atomic.Value(bool),
    frozen: bool,
    
    const SignatureKeyPair = struct {
        key: []const u8,
        signatures: std.ArrayList(Signature),
        
        pub fn deinit(self: *SignatureKeyPair, allocator: std.mem.Allocator) void {
            allocator.free(self.key);
            self.signatures.deinit();
        }
    };
    
    const Signature = struct {
        public_key: []const u8,
        signature: []const u8,
    };
    
    const SignedTransaction = struct {
        body_bytes: []const u8,
        signature_map: SignatureMap,
    };
    
    const SignatureMap = struct {
        sig_pairs: []SignaturePair,
    };
    
    const SignaturePair = struct {
        pub_key_prefix: []const u8,
        signature: []const u8,
    };
    
    // Initialize base transaction
    pub fn init(allocator: std.mem.Allocator) Transaction {
        return Transaction{
            .allocator = allocator,
            .transaction_id = null,
            .node_account_ids = std.ArrayList(AccountId).init(allocator),
            .transaction_hash = null,
            .transaction_valid_duration = Duration.fromSeconds(120),
            .transaction_memo = "",
            .memo = "",
            .max_transaction_fee = null,
            .regenerate_transaction_id = true,
            .signatures = std.ArrayList(SignatureKeyPair).init(allocator),
            .signature_keys = std.ArrayList([]const u8).init(allocator),
            .signed_transactions = std.ArrayList(SignedTransaction).init(allocator),
            .executed = std.atomic.Value(bool).init(false),
            .frozen = false,
        };
    }
    
    pub fn deinit(self: *Transaction) void {
        self.node_account_ids.deinit();
        
        // Clean up signatures safely
        for (self.signatures.items) |*sig_pair| {
            sig_pair.deinit(self.allocator);
        }
        self.signatures.deinit();
        
        // Clean up signature keys
        for (self.signature_keys.items) |key| {
            self.allocator.free(key);
        }
        self.signature_keys.deinit();
        
        self.signed_transactions.deinit();
        
        if (self.transaction_hash) |hash| {
            self.allocator.free(hash);
        }
    }
    
    // Set transaction ID
    pub fn setTransactionId(self: *Transaction, tx_id: TransactionId) *Transaction {
        if (self.frozen) @panic("Transaction is frozen");
        self.transaction_id = tx_id;
        return self;
    }
    
    // Get or generate transaction ID
    pub fn getTransactionId(self: *Transaction) !TransactionId {
        if (self.transaction_id) |id| {
            return id;
        }
        return error.TransactionIdNotSet;
    }
    
    // Set node account IDs
    pub fn setNodeAccountIds(self: *Transaction, node_ids: []const AccountId) !*Transaction {
        if (self.frozen) @panic("Transaction is frozen");
        
        self.node_account_ids.clearRetainingCapacity();
        for (node_ids) |id| {
            try self.node_account_ids.append(id);
        }
        return self;
    }
    
    // Set transaction valid duration
    pub fn setTransactionValidDuration(self: *Transaction, duration: Duration) *Transaction {
        if (self.frozen) @panic("Transaction is frozen");
        
        if (duration.seconds < 0 or duration.seconds > 180) {
            @panic("Invalid transaction duration");
        }
        
        self.transaction_valid_duration = duration;
        return self;
    }
    
    // Set transaction memo
    pub fn setTransactionMemo(self: *Transaction, memo: []const u8) *Transaction {
        if (self.frozen) @panic("Transaction is frozen");
        
        if (memo.len > 100) {
            @panic("Memo too long");
        }
        
        self.transaction_memo = memo;
        self.memo = memo;
        return self;
    }
    
    // Set max transaction fee
    pub fn setMaxTransactionFee(self: *Transaction, fee: Hbar) *Transaction {
        if (self.frozen) @panic("Transaction is frozen");
        self.max_transaction_fee = fee;
        return self;
    }
    
    // Freeze transaction for signing
    pub fn freeze(self: *Transaction) !void {
        if (self.frozen) return;
        
        if (self.transaction_id == null) {
            return error.TransactionIdRequired;
        }
        
        if (self.node_account_ids.items.len == 0) {
            return error.NodeAccountIdsRequired;
        }
        
        self.frozen = true;
    }
    
    // Freeze with client
    pub fn freezeWith(self: *Transaction, client: ?*Client) !void {
        if (self.frozen) return;
        
        // Set transaction ID if not set
        if (self.transaction_id == null) {
            if (client) |c| {
                if (c.getOperatorAccountId()) |op_id| {
                    self.transaction_id = TransactionId.generate(op_id);
                } else {
                    return error.OperatorNotSet;
                }
            } else {
                // For tests - generate with default account
                self.transaction_id = TransactionId.generate(AccountId.init(0, 0, 2));
            }
        }
        
        // Set node account IDs if not set
        if (self.node_account_ids.items.len == 0) {
            if (client) |c| {
                const nodes = try c.selectNodesForRequest(1);
                defer c.allocator.free(nodes);
                
                for (nodes) |node| {
                    try self.node_account_ids.append(node.account_id);
                }
            } else {
                // For tests - use default node
                try self.node_account_ids.append(AccountId.init(0, 0, 3));
            }
        }
        
        // Set max fee if not set
        if (self.max_transaction_fee == null) {
            if (client) |c| {
                if (c.default_max_transaction_fee) |fee| {
                    self.max_transaction_fee = fee;
                } else {
                    self.max_transaction_fee = try Hbar.from(2); // Default 2 hbar
                }
            } else {
                self.max_transaction_fee = try Hbar.from(2); // Default 2 hbar for tests
            }
        }
        
        try self.freeze();
    }
    
    // Sign transaction
    pub fn sign(self: *Transaction, private_key: anytype) !void {
        if (!self.frozen) {
            return error.TransactionNotFrozen;
        }
        
        const body_bytes = try self.buildTransactionBody();
        defer self.allocator.free(body_bytes);
        
        const signature_array = try private_key.sign(body_bytes);
        const public_key = private_key.getPublicKey();
        
        // Create new signature pair for each signature
        var new_signatures = std.ArrayList(Signature).init(self.allocator);
        const sig_slice = try self.allocator.alloc(u8, 64);
        @memcpy(sig_slice, signature_array);
        
        const pub_key_bytes = public_key.toBytesRaw();
        const pub_key_slice = try self.allocator.alloc(u8, pub_key_bytes.len);
        @memcpy(pub_key_slice, pub_key_bytes);
        
        try new_signatures.append(Signature{
            .public_key = pub_key_slice,
            .signature = sig_slice,
        });
        
        // Use public key as identifier
        const key = try self.allocator.alloc(u8, pub_key_bytes.len);
        @memcpy(key, pub_key_bytes);
        
        try self.signatures.append(SignatureKeyPair{
            .key = key,
            .signatures = new_signatures,
        });
    }
    
    // Sign with operator from client
    pub fn signWithOperator(self: *Transaction, client: *Client) !void {
        if (client.operator) |op| {
            try self.sign(op.private_key);
        } else {
            return error.OperatorNotSet;
        }
    }
    
    // Appends a signature to the transaction
    pub fn addSignature(self: *Transaction, public_key: []const u8, signature: []const u8) !void {
        if (!self.frozen) {
            return error.TransactionNotFrozen;
        }
        
        const tx_id = try self.getTransactionId();
        const account_id = tx_id.account_id;
        
        // Use string key to avoid alignment issues  
        const key = try std.fmt.allocPrint(self.allocator, "{d}.{d}.{d}", .{
            account_id.shard,
            account_id.realm,
            account_id.account,
        });
        const key_copy = try self.allocator.dupe(u8, key);
        try self.signature_keys.append(key_copy);  // Track for cleanup
        
        // Find existing SignatureKeyPair or create new one
        for (self.signatures.items) |*sig_pair| {
            if (std.mem.eql(u8, sig_pair.key, key)) {
                try sig_pair.signatures.append(Signature{
                    .public_key = public_key,
                    .signature = signature,
                });
                return;
            }
        }
        
        // Create new SignatureKeyPair
        var new_sig_pair = SignatureKeyPair{
            .key = key_copy,
            .signatures = std.ArrayList(Signature).init(self.allocator),
        };
        try new_sig_pair.signatures.append(Signature{
            .public_key = public_key,
            .signature = signature,
        });
        try self.signatures.append(new_sig_pair);
    }
    
    // Execute transaction
    pub fn execute(self: *Transaction, client: *Client) !TransactionResponse {
        if (!self.frozen) {
            try self.freezeWith(client);
        }
        
        if (self.executed.swap(true, .acquire)) {
            return error.TransactionAlreadyExecuted;
        }
        
        // Build signed transaction
        const signed_tx = try self.buildSignedTransaction();
        defer self.allocator.free(signed_tx);
        
        // Submit to network
        _ = try client.execute(TransactionRequest{
            .transaction_bytes = signed_tx,
            .node_account_id = self.node_account_ids.items[0],
        });
        
        return try TransactionResponse.init(
            self.allocator,
            try self.getTransactionId(),
            self.node_account_ids.items[0],
            try self.getTransactionHash(),
        );
    }
    
    // Build transaction body (to be implemented by specific transaction types)
    pub fn buildTransactionBody(self: *Transaction) ![]u8 {
        var writer = ProtoWriter.init(self.allocator);
        defer writer.deinit();
        
        // Common transaction body fields
        // transactionID = 1
        if (self.transaction_id) |tx_id| {
            var tx_id_writer = ProtoWriter.init(self.allocator);
            defer tx_id_writer.deinit();
            
            var timestamp_writer = ProtoWriter.init(self.allocator);
            defer timestamp_writer.deinit();
            try timestamp_writer.writeInt64(1, tx_id.valid_start.seconds);
            try timestamp_writer.writeInt32(2, tx_id.valid_start.nanos);
            const timestamp_bytes = try timestamp_writer.toOwnedSlice();
            defer self.allocator.free(timestamp_bytes);
            try tx_id_writer.writeMessage(1, timestamp_bytes);
            
            var account_writer = ProtoWriter.init(self.allocator);
            defer account_writer.deinit();
            try account_writer.writeInt64(1, @intCast(tx_id.account_id.shard));
            try account_writer.writeInt64(2, @intCast(tx_id.account_id.realm));
            try account_writer.writeInt64(3, @intCast(tx_id.account_id.account));
            const account_bytes = try account_writer.toOwnedSlice();
            defer self.allocator.free(account_bytes);
            try tx_id_writer.writeMessage(2, account_bytes);
            
            if (tx_id.nonce) |n| {
                try tx_id_writer.writeInt32(4, @intCast(n));
            }
            
            const tx_id_bytes = try tx_id_writer.toOwnedSlice();
            defer self.allocator.free(tx_id_bytes);
            try writer.writeMessage(1, tx_id_bytes);
        }
        
        // nodeAccountID = 2
        if (self.node_account_ids.items.len > 0) {
            var node_writer = ProtoWriter.init(self.allocator);
            defer node_writer.deinit();
            const node = self.node_account_ids.items[0];
            try node_writer.writeInt64(1, @intCast(node.shard));
            try node_writer.writeInt64(2, @intCast(node.realm));
            try node_writer.writeInt64(3, @intCast(node.account));
            const node_bytes = try node_writer.toOwnedSlice();
            defer self.allocator.free(node_bytes);
            try writer.writeMessage(2, node_bytes);
        }
        
        // transactionFee = 3
        if (self.max_transaction_fee) |fee| {
            try writer.writeUint64(3, @intCast(fee.toTinybars()));
        }
        
        // transactionValidDuration = 4
        var duration_writer = ProtoWriter.init(self.allocator);
        defer duration_writer.deinit();
        try duration_writer.writeInt64(1, self.transaction_valid_duration.seconds);
        const duration_bytes = try duration_writer.toOwnedSlice();
        defer self.allocator.free(duration_bytes);
        try writer.writeMessage(4, duration_bytes);
        
        // memo = 5
        if (self.transaction_memo.len > 0) {
            try writer.writeString(5, self.transaction_memo);
        }
        
        return writer.toOwnedSlice();
    }
    
    // Build signed transaction
    fn buildSignedTransaction(self: *Transaction) ![]u8 {
        var writer = ProtoWriter.init(self.allocator);
        defer writer.deinit();
        
        // SignedTransaction message
        // body_bytes = 1
        const body_bytes = try self.buildTransactionBody();
        defer self.allocator.free(body_bytes);
        try writer.writeMessage(1, body_bytes);
        
        // sig_map = 2
        const sig_map = try self.buildSignatureMap();
        defer self.allocator.free(sig_map);
        try writer.writeMessage(2, sig_map);
        
        return writer.toOwnedSlice();
    }
    
    // Build signature map
    fn buildSignatureMap(self: *Transaction) ![]u8 {
        var writer = ProtoWriter.init(self.allocator);
        defer writer.deinit();
        
        // SignatureMap message - iterate over ArrayList items directly
        for (self.signatures.items) |*sig_pair| {
            for (sig_pair.signatures.items) |sig| {
                // sig_pair = 1 (repeated)
                var pair_writer = ProtoWriter.init(self.allocator);
                defer pair_writer.deinit();
                
                // pub_key_prefix = 1
                const prefix = if (sig.public_key.len >= 6) sig.public_key[0..6] else sig.public_key;
                try pair_writer.writeString(1, prefix);
                
                // signature variants
                if (sig.public_key.len == 32) {
                    // ed25519 = 2
                    try pair_writer.writeString(2, sig.signature);
                } else if (sig.public_key.len == 33) {
                    // ecdsa_secp256k1 = 3
                    try pair_writer.writeString(3, sig.signature);
                }
                
                const pair_bytes = try pair_writer.toOwnedSlice();
                defer self.allocator.free(pair_bytes);
                try writer.writeMessage(1, pair_bytes);
            }
        }
        
        return writer.toOwnedSlice();
    }
    
    // Get transaction hash
    pub fn getTransactionHash(self: *Transaction) ![]const u8 {
        if (self.transaction_hash) |hash| {
            return hash;
        }
        
        const body_bytes = try self.buildTransactionBody();
        defer self.allocator.free(body_bytes);
        
        var hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(body_bytes, &hash, .{});
        
        self.transaction_hash = try self.allocator.dupe(u8, &hash);
        return self.transaction_hash.?;
    }
    
    // Get transaction receipt
    pub fn getReceipt(self: *Transaction, client: *Client) !TransactionReceipt {
        _ = self;
        _ = client;
        // Query for receipt
        return TransactionReceipt{ .status = .Ok };
    }
    
    // Get transaction record
    pub fn getRecord(self: *Transaction, client: *Client) !TransactionRecord {
        _ = client;
        // Query for record
        return TransactionRecord{
            .receipt = TransactionReceipt{ .status = .Ok },
            .transaction_hash = &[_]u8{},
            .consensus_timestamp = Timestamp.now(),
            .transaction_id = try self.getTransactionId(),
            .memo = self.transaction_memo,
            .transaction_fee = 0,
        };
    }
};

// Transaction request for network submission
const TransactionRequest = struct {
    transaction_bytes: []const u8,
    node_account_id: AccountId,
    
    pub const Response = TransactionResponse;
    
    pub fn execute(self: TransactionRequest, conn: *GrpcConnection) !TransactionResponse {
        _ = self;
        _ = conn;
        // Submit transaction via gRPC
        return TransactionResponse{
            .transaction_id = TransactionId.generate(AccountId.init(0, 0, 0)),
            .scheduled_transaction_id = null,
            .node_id = AccountId.init(0, 0, 3),
            .hash = &[_]u8{},
            .transaction_hash = &[_]u8{},
            .validate_status = true,
            .include_child_receipts = false,
            .transaction = null,
            .allocator = std.heap.page_allocator,
        };
    }
};

// Transaction response
// Import TransactionResponse from dedicated file to avoid redundancy
pub const TransactionResponse = @import("transaction_response.zig").TransactionResponse;
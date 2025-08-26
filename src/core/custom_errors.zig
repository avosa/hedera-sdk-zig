// Custom error types for specific scenarios
// Provides detailed error handling for various SDK operations

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const HederaError = @import("errors.zig").HederaError;

// Network-specific errors with detailed context
pub const NetworkError = struct {
    base_error: HederaError,
    node_endpoint: ?[]const u8,
    attempt_count: u32,
    last_attempt_time: i64,
    connection_details: ?ConnectionDetails,
    
    pub const ConnectionDetails = struct {
        connection_time_ms: u64,
        bytes_sent: u64,
        bytes_received: u64,
        tls_version: ?[]const u8,
        cipher_suite: ?[]const u8,
        certificate_errors: []const []const u8,
        
        pub fn init(_: Allocator) ConnectionDetails {
            return ConnectionDetails{
                .connection_time_ms = 0,
                .bytes_sent = 0,
                .bytes_received = 0,
                .tls_version = null,
                .cipher_suite = null,
                .certificate_errors = &[_][]const u8{},
            };
        }
        
        pub fn deinit(self: ConnectionDetails, allocator: Allocator) void {
            if (self.tls_version) |version| {
                allocator.free(version);
            }
            if (self.cipher_suite) |cipher| {
                allocator.free(cipher);
            }
            for (self.certificate_errors) |err| {
                allocator.free(err);
            }
            allocator.free(self.certificate_errors);
        }
    };
    
    pub fn init(
        allocator: Allocator,
        base_error: HederaError,
        node_endpoint: ?[]const u8,
        attempt_count: u32,
    ) !NetworkError {
        return NetworkError{
            .base_error = base_error,
            .node_endpoint = if (node_endpoint) |endpoint| try allocator.dupe(u8, endpoint) else null,
            .attempt_count = attempt_count,
            .last_attempt_time = std.time.milliTimestamp(),
            .connection_details = null,
        };
    }
    
    pub fn deinit(self: NetworkError, allocator: Allocator) void {
        if (self.node_endpoint) |endpoint| {
            allocator.free(endpoint);
        }
        if (self.connection_details) |details| {
            details.deinit(allocator);
        }
    }
    
    pub fn withConnectionDetails(self: *NetworkError, details: ConnectionDetails) void {
        self.connection_details = details;
    }
    
    pub fn formatError(self: NetworkError, allocator: Allocator) ![]u8 {
        var message = std.ArrayList(u8).init(allocator);
        const writer = message.writer();
        
        try writer.print("Network Error: {s}", .{@tagName(self.base_error)});
        
        if (self.node_endpoint) |endpoint| {
            try writer.print(" (endpoint: {s})", .{endpoint});
        }
        
        try writer.print(" (attempt: {})", .{self.attempt_count});
        
        if (self.connection_details) |details| {
            if (details.connection_time_ms > 0) {
                try writer.print(" (connection_time: {}ms)", .{details.connection_time_ms});
            }
            
            if (details.certificate_errors.len > 0) {
                try writer.writeAll(" (cert_errors: [");
                for (details.certificate_errors, 0..) |err, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try writer.print("\"{s}\"", .{err});
                }
                try writer.writeAll("])");
            }
        }
        
        return message.toOwnedSlice();
    }
    
    pub fn isRetryable(self: NetworkError) bool {
        return switch (self.base_error) {
            HederaError.NetworkTimeout, 
            HederaError.ConnectionFailed, 
            HederaError.Busy,
            HederaError.RequestTimeout => true,
            else => false,
        };
    }
    
    pub fn shouldBackoff(self: NetworkError) bool {
        return self.attempt_count > 1 and self.isRetryable();
    }
    
    pub fn getRecommendedDelayMs(self: NetworkError) u64 {
        if (!self.isRetryable()) return 0;
        
        // Exponential backoff: 2^attempt * 1000ms, capped at 30 seconds
        const base_delay = std.math.pow(u64, 2, @min(self.attempt_count - 1, 5)) * 1000;
        return @min(base_delay, 30000);
    }
};

// Transaction-specific errors with transaction context
pub const TransactionError = struct {
    base_error: HederaError,
    transaction_id: ?[]const u8,
    transaction_type: ?[]const u8,
    node_account_id: ?[]const u8,
    validation_failures: []const ValidationFailure,
    execution_context: ?ExecutionContext,
    
    pub const ValidationFailure = struct {
        field_name: []const u8,
        expected_value: ?[]const u8,
        actual_value: ?[]const u8,
        constraint_violated: []const u8,
        
        pub fn init(
            allocator: Allocator,
            field_name: []const u8,
            expected_value: ?[]const u8,
            actual_value: ?[]const u8,
            constraint_violated: []const u8,
        ) !ValidationFailure {
            return ValidationFailure{
                .field_name = try allocator.dupe(u8, field_name),
                .expected_value = if (expected_value) |val| try allocator.dupe(u8, val) else null,
                .actual_value = if (actual_value) |val| try allocator.dupe(u8, val) else null,
                .constraint_violated = try allocator.dupe(u8, constraint_violated),
            };
        }
        
        pub fn deinit(self: ValidationFailure, allocator: Allocator) void {
            allocator.free(self.field_name);
            if (self.expected_value) |val| allocator.free(val);
            if (self.actual_value) |val| allocator.free(val);
            allocator.free(self.constraint_violated);
        }
    };
    
    pub const ExecutionContext = struct {
        gas_used: ?u64,
        gas_limit: ?u64,
        fee_charged: ?u64,
        consensus_timestamp: ?i64,
        transaction_hash: ?[]const u8,
        receipt_status: ?HederaError,
        
        pub fn init() ExecutionContext {
            return ExecutionContext{
                .gas_used = null,
                .gas_limit = null,
                .fee_charged = null,
                .consensus_timestamp = null,
                .transaction_hash = null,
                .receipt_status = null,
            };
        }
        
        pub fn deinit(self: ExecutionContext, allocator: Allocator) void {
            if (self.transaction_hash) |hash| {
                allocator.free(hash);
            }
        }
        
        pub fn withGas(self: *ExecutionContext, used: u64, limit: u64) void {
            self.gas_used = used;
            self.gas_limit = limit;
        }
        
        pub fn withFee(self: *ExecutionContext, fee: u64) void {
            self.fee_charged = fee;
        }
        
        pub fn withConsensusTimestamp(self: *ExecutionContext, timestamp: i64) void {
            self.consensus_timestamp = timestamp;
        }
        
        pub fn withTransactionHash(self: *ExecutionContext, allocator: Allocator, hash: []const u8) !void {
            self.transaction_hash = try allocator.dupe(u8, hash);
        }
        
        pub fn withReceiptStatus(self: *ExecutionContext, status: HederaError) void {
            self.receipt_status = status;
        }
    };
    
    pub fn init(
        allocator: Allocator,
        base_error: HederaError,
        transaction_id: ?[]const u8,
        transaction_type: ?[]const u8,
    ) !TransactionError {
        return TransactionError{
            .base_error = base_error,
            .transaction_id = if (transaction_id) |id| try allocator.dupe(u8, id) else null,
            .transaction_type = if (transaction_type) |tx_type| try allocator.dupe(u8, tx_type) else null,
            .node_account_id = null,
            .validation_failures = &[_]ValidationFailure{},
            .execution_context = null,
        };
    }
    
    pub fn deinit(self: TransactionError, allocator: Allocator) void {
        if (self.transaction_id) |id| allocator.free(id);
        if (self.transaction_type) |tx_type| allocator.free(tx_type);
        if (self.node_account_id) |node_id| allocator.free(node_id);
        
        for (self.validation_failures) |failure| {
            failure.deinit(allocator);
        }
        allocator.free(self.validation_failures);
        
        if (self.execution_context) |context| {
            context.deinit(allocator);
        }
    }
    
    pub fn addValidationFailure(self: *TransactionError, allocator: Allocator, failure: ValidationFailure) !void {
        const new_failures = try allocator.alloc(ValidationFailure, self.validation_failures.len + 1);
        std.mem.copy(ValidationFailure, new_failures, self.validation_failures);
        new_failures[self.validation_failures.len] = failure;
        
        allocator.free(self.validation_failures);
        self.validation_failures = new_failures;
    }
    
    pub fn withExecutionContext(self: *TransactionError, context: ExecutionContext) void {
        self.execution_context = context;
    }
    
    pub fn formatError(self: TransactionError, allocator: Allocator) ![]u8 {
        var message = std.ArrayList(u8).init(allocator);
        const writer = message.writer();
        
        try writer.print("Transaction Error: {s}", .{@tagName(self.base_error)});
        
        if (self.transaction_type) |tx_type| {
            try writer.print(" (type: {s})", .{tx_type});
        }
        
        if (self.transaction_id) |tx_id| {
            try writer.print(" (id: {s})", .{tx_id});
        }
        
        if (self.validation_failures.len > 0) {
            try writer.writeAll(" (validation_failures: [");
            for (self.validation_failures, 0..) |failure, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.print("{s}: {s}", .{ failure.field_name, failure.constraint_violated });
            }
            try writer.writeAll("])");
        }
        
        if (self.execution_context) |context| {
            if (context.gas_used) |gas_used| {
                try writer.print(" (gas_used: {})", .{gas_used});
                if (context.gas_limit) |gas_limit| {
                    try writer.print("/{}", .{gas_limit});
                }
            }
            
            if (context.fee_charged) |fee| {
                try writer.print(" (fee: {} tinybar)", .{fee});
            }
        }
        
        return message.toOwnedSlice();
    }
    
    pub fn isValidationError(self: TransactionError) bool {
        return self.validation_failures.len > 0 or switch (self.base_error) {
            HederaError.InvalidTransaction,
            HederaError.InvalidTransactionBody,
            HederaError.EmptyTransactionBody,
            HederaError.InvalidTransactionDuration,
            HederaError.InvalidTransactionStart,
            HederaError.InvalidSignature => true,
            else => false,
        };
    }
    
    pub fn isFeeRelated(self: TransactionError) bool {
        return switch (self.base_error) {
            HederaError.InsufficientTxFee,
            HederaError.InsufficientPayerBalance,
            HederaError.InvalidFeeSubmitted,
            HederaError.FailFee => true,
            else => false,
        };
    }
    
    pub fn hasExecutionFailure(self: TransactionError) bool {
        if (self.execution_context) |context| {
            if (context.receipt_status) |status| {
                return status != HederaError.Success;
            }
        }
        return false;
    }
};

// Query-specific errors with query context
pub const QueryError = struct {
    base_error: HederaError,
    query_type: ?[]const u8,
    target_id: ?[]const u8,
    node_account_id: ?[]const u8,
    payment_details: ?PaymentDetails,
    response_details: ?ResponseDetails,
    
    pub const PaymentDetails = struct {
        payment_amount: u64,
        payment_account_id: []const u8,
        query_payment_transaction_id: ?[]const u8,
        
        pub fn init(allocator: Allocator, amount: u64, account_id: []const u8, tx_id: ?[]const u8) !PaymentDetails {
            return PaymentDetails{
                .payment_amount = amount,
                .payment_account_id = try allocator.dupe(u8, account_id),
                .query_payment_transaction_id = if (tx_id) |id| try allocator.dupe(u8, id) else null,
            };
        }
        
        pub fn deinit(self: PaymentDetails, allocator: Allocator) void {
            allocator.free(self.payment_account_id);
            if (self.query_payment_transaction_id) |tx_id| {
                allocator.free(tx_id);
            }
        }
    };
    
    pub const ResponseDetails = struct {
        response_size_bytes: usize,
        node_response_time_ms: u64,
        cost_estimate: ?u64,
        precheck_status: ?HederaError,
        
        pub fn init() ResponseDetails {
            return ResponseDetails{
                .response_size_bytes = 0,
                .node_response_time_ms = 0,
                .cost_estimate = null,
                .precheck_status = null,
            };
        }
        
        pub fn withSize(self: *ResponseDetails, size: usize) void {
            self.response_size_bytes = size;
        }
        
        pub fn withResponseTime(self: *ResponseDetails, time_ms: u64) void {
            self.node_response_time_ms = time_ms;
        }
        
        pub fn withCostEstimate(self: *ResponseDetails, cost: u64) void {
            self.cost_estimate = cost;
        }
        
        pub fn withPrecheckStatus(self: *ResponseDetails, status: HederaError) void {
            self.precheck_status = status;
        }
    };
    
    pub fn init(
        allocator: Allocator,
        base_error: HederaError,
        query_type: ?[]const u8,
        target_id: ?[]const u8,
    ) !QueryError {
        return QueryError{
            .base_error = base_error,
            .query_type = if (query_type) |qtype| try allocator.dupe(u8, qtype) else null,
            .target_id = if (target_id) |id| try allocator.dupe(u8, id) else null,
            .node_account_id = null,
            .payment_details = null,
            .response_details = null,
        };
    }
    
    pub fn deinit(self: QueryError, allocator: Allocator) void {
        if (self.query_type) |qtype| allocator.free(qtype);
        if (self.target_id) |id| allocator.free(id);
        if (self.node_account_id) |node_id| allocator.free(node_id);
        
        if (self.payment_details) |details| {
            details.deinit(allocator);
        }
    }
    
    pub fn withPaymentDetails(self: *QueryError, details: PaymentDetails) void {
        self.payment_details = details;
    }
    
    pub fn withResponseDetails(self: *QueryError, details: ResponseDetails) void {
        self.response_details = details;
    }
    
    pub fn formatError(self: QueryError, allocator: Allocator) ![]u8 {
        var message = std.ArrayList(u8).init(allocator);
        const writer = message.writer();
        
        try writer.print("Query Error: {s}", .{@tagName(self.base_error)});
        
        if (self.query_type) |qtype| {
            try writer.print(" (type: {s})", .{qtype});
        }
        
        if (self.target_id) |id| {
            try writer.print(" (target: {s})", .{id});
        }
        
        if (self.payment_details) |payment| {
            try writer.print(" (payment: {} tinybar from {s})", .{ payment.payment_amount, payment.payment_account_id });
        }
        
        if (self.response_details) |response| {
            if (response.cost_estimate) |cost| {
                try writer.print(" (estimated_cost: {} tinybar)", .{cost});
            }
            if (response.node_response_time_ms > 0) {
                try writer.print(" (response_time: {}ms)", .{response.node_response_time_ms});
            }
        }
        
        return message.toOwnedSlice();
    }
    
    pub fn isPaymentError(self: QueryError) bool {
        return switch (self.base_error) {
            HederaError.InsufficientTxFee,
            HederaError.InsufficientPayerBalance,
            HederaError.InvalidFeeSubmitted => true,
            else => false,
        };
    }
    
    pub fn isPrecheckFailure(self: QueryError) bool {
        if (self.response_details) |details| {
            if (details.precheck_status) |status| {
                return status != HederaError.Ok and status != HederaError.Success;
            }
        }
        return false;
    }
};

// Cryptography-specific errors
pub const CryptographyError = struct {
    base_error: HederaError,
    operation_type: CryptoOperation,
    key_type: ?KeyType,
    algorithm_details: ?[]const u8,
    input_size: ?usize,
    
    pub const CryptoOperation = enum {
        key_generation,
        signing,
        verification,
        encryption,
        decryption,
        key_derivation,
        hash_computation,
        
        pub fn toString(self: CryptoOperation) []const u8 {
            return switch (self) {
                .key_generation => "key_generation",
                .signing => "signing",
                .verification => "verification",
                .encryption => "encryption",
                .decryption => "decryption",
                .key_derivation => "key_derivation",
                .hash_computation => "hash_computation",
            };
        }
    };
    
    pub const KeyType = enum {
        ed25519,
        ecdsa_secp256k1,
        rsa,
        
        pub fn toString(self: KeyType) []const u8 {
            return switch (self) {
                .ed25519 => "ED25519",
                .ecdsa_secp256k1 => "ECDSA_secp256k1",
                .rsa => "RSA",
            };
        }
    };
    
    pub fn init(
        allocator: Allocator,
        base_error: HederaError,
        operation_type: CryptoOperation,
        key_type: ?KeyType,
        algorithm_details: ?[]const u8,
    ) !CryptographyError {
        return CryptographyError{
            .base_error = base_error,
            .operation_type = operation_type,
            .key_type = key_type,
            .algorithm_details = if (algorithm_details) |details| try allocator.dupe(u8, details) else null,
            .input_size = null,
        };
    }
    
    pub fn deinit(self: CryptographyError, allocator: Allocator) void {
        if (self.algorithm_details) |details| {
            allocator.free(details);
        }
    }
    
    pub fn withInputSize(self: *CryptographyError, size: usize) void {
        self.input_size = size;
    }
    
    pub fn formatError(self: CryptographyError, allocator: Allocator) ![]u8 {
        var message = std.ArrayList(u8).init(allocator);
        const writer = message.writer();
        
        try writer.print("Cryptography Error: {s} during {s}", .{
            @tagName(self.base_error),
            self.operation_type.toString(),
        });
        
        if (self.key_type) |ktype| {
            try writer.print(" (key_type: {s})", .{ktype.toString()});
        }
        
        if (self.algorithm_details) |details| {
            try writer.print(" (algorithm: {s})", .{details});
        }
        
        if (self.input_size) |size| {
            try writer.print(" (input_size: {} bytes)", .{size});
        }
        
        return message.toOwnedSlice();
    }
    
    pub fn isKeyError(self: CryptographyError) bool {
        return switch (self.base_error) {
            HederaError.KeyRequired,
            HederaError.InvalidKeyEncoding,
            HederaError.KeyNotProvided,
            HederaError.BadEncoding => true,
            else => false,
        };
    }
    
    pub fn isSignatureError(self: CryptographyError) bool {
        return switch (self.base_error) {
            HederaError.InvalidSignature,
            HederaError.InvalidPayerSignature,
            HederaError.InvalidSignatureTypeMismatchingKey => true,
            else => false,
        };
    }
};

// Configuration-specific errors
pub const ConfigurationError = struct {
    base_error: HederaError,
    config_section: ?[]const u8,
    config_key: ?[]const u8,
    expected_type: ?[]const u8,
    actual_value: ?[]const u8,
    suggested_fix: ?[]const u8,
    
    pub fn init(
        allocator: Allocator,
        base_error: HederaError,
        config_section: ?[]const u8,
        config_key: ?[]const u8,
    ) !ConfigurationError {
        return ConfigurationError{
            .base_error = base_error,
            .config_section = if (config_section) |section| try allocator.dupe(u8, section) else null,
            .config_key = if (config_key) |key| try allocator.dupe(u8, key) else null,
            .expected_type = null,
            .actual_value = null,
            .suggested_fix = null,
        };
    }
    
    pub fn deinit(self: ConfigurationError, allocator: Allocator) void {
        if (self.config_section) |section| allocator.free(section);
        if (self.config_key) |key| allocator.free(key);
        if (self.expected_type) |etype| allocator.free(etype);
        if (self.actual_value) |value| allocator.free(value);
        if (self.suggested_fix) |fix| allocator.free(fix);
    }
    
    pub fn withTypeError(self: *ConfigurationError, allocator: Allocator, expected: []const u8, actual: []const u8) !void {
        self.expected_type = try allocator.dupe(u8, expected);
        self.actual_value = try allocator.dupe(u8, actual);
    }
    
    pub fn withSuggestedFix(self: *ConfigurationError, allocator: Allocator, fix: []const u8) !void {
        self.suggested_fix = try allocator.dupe(u8, fix);
    }
    
    pub fn formatError(self: ConfigurationError, allocator: Allocator) ![]u8 {
        var message = std.ArrayList(u8).init(allocator);
        const writer = message.writer();
        
        try writer.print("Configuration Error: {s}", .{@tagName(self.base_error)});
        
        if (self.config_section) |section| {
            try writer.print(" in section '{s}'", .{section});
        }
        
        if (self.config_key) |key| {
            try writer.print(" for key '{s}'", .{key});
        }
        
        if (self.expected_type) |expected| {
            try writer.print(" (expected: {s}", .{expected});
            if (self.actual_value) |actual| {
                try writer.print(", got: {s}", .{actual});
            }
            try writer.writeAll(")");
        }
        
        if (self.suggested_fix) |fix| {
            try writer.print(" - Suggestion: {s}", .{fix});
        }
        
        return message.toOwnedSlice();
    }
};

// Unified error context that can contain any specific error type
pub const ErrorContext = union(enum) {
    network: NetworkError,
    transaction: TransactionError,
    query: QueryError,
    cryptography: CryptographyError,
    configuration: ConfigurationError,
    generic: HederaError,
    
    pub fn deinit(self: ErrorContext, allocator: Allocator) void {
        switch (self) {
            .network => |err| err.deinit(allocator),
            .transaction => |err| err.deinit(allocator),
            .query => |err| err.deinit(allocator),
            .cryptography => |err| err.deinit(allocator),
            .configuration => |err| err.deinit(allocator),
            .generic => {},
        }
    }
    
    pub fn getBaseError(self: ErrorContext) HederaError {
        return switch (self) {
            .network => |err| err.base_error,
            .transaction => |err| err.base_error,
            .query => |err| err.base_error,
            .cryptography => |err| err.base_error,
            .configuration => |err| err.base_error,
            .generic => |err| err,
        };
    }
    
    pub fn formatError(self: ErrorContext, allocator: Allocator) ![]u8 {
        return switch (self) {
            .network => |err| err.formatError(allocator),
            .transaction => |err| err.formatError(allocator),
            .query => |err| err.formatError(allocator),
            .cryptography => |err| err.formatError(allocator),
            .configuration => |err| err.formatError(allocator),
            .generic => |err| try std.fmt.allocPrint(allocator, "Generic Error: {s}", .{@tagName(err)}),
        };
    }
    
    pub fn isRetryable(self: ErrorContext) bool {
        return switch (self) {
            .network => |err| err.isRetryable(),
            .transaction => |err| !err.isValidationError(),
            .query => |err| !err.isPrecheckFailure(),
            .cryptography => false,
            .configuration => false,
            .generic => |err| switch (err) {
                HederaError.Busy, HederaError.NetworkTimeout => true,
                else => false,
            },
        };
    }
};

// Error builder for creating detailed error contexts
pub const ErrorBuilder = struct {
    allocator: Allocator,
    
    pub fn init(allocator: Allocator) ErrorBuilder {
        return ErrorBuilder{
            .allocator = allocator,
        };
    }
    
    pub fn networkError(self: ErrorBuilder, base_error: HederaError, endpoint: ?[]const u8, attempts: u32) !ErrorContext {
        const err = try NetworkError.init(self.allocator, base_error, endpoint, attempts);
        return ErrorContext{ .network = err };
    }
    
    pub fn transactionError(self: ErrorBuilder, base_error: HederaError, tx_id: ?[]const u8, tx_type: ?[]const u8) !ErrorContext {
        const err = try TransactionError.init(self.allocator, base_error, tx_id, tx_type);
        return ErrorContext{ .transaction = err };
    }
    
    pub fn queryError(self: ErrorBuilder, base_error: HederaError, query_type: ?[]const u8, target_id: ?[]const u8) !ErrorContext {
        const err = try QueryError.init(self.allocator, base_error, query_type, target_id);
        return ErrorContext{ .query = err };
    }
    
    pub fn cryptographyError(self: ErrorBuilder, base_error: HederaError, operation: CryptographyError.CryptoOperation, key_type: ?CryptographyError.KeyType) !ErrorContext {
        const err = try CryptographyError.init(self.allocator, base_error, operation, key_type, null);
        return ErrorContext{ .cryptography = err };
    }
    
    pub fn configurationError(self: ErrorBuilder, base_error: HederaError, section: ?[]const u8, key: ?[]const u8) !ErrorContext {
        const err = try ConfigurationError.init(self.allocator, base_error, section, key);
        return ErrorContext{ .configuration = err };
    }
    
    pub fn genericError(self: ErrorBuilder, base_error: HederaError) ErrorContext {
        _ = self;
        return ErrorContext{ .generic = base_error };
    }
};

// Test cases
test "NetworkError creation and formatting" {
    const allocator = testing.allocator;
    
    var err = try NetworkError.init(allocator, HederaError.ConnectionFailed, "mainnet.hedera.com:443", 3);
    defer err.deinit(allocator);
    
    const formatted = try err.formatError(allocator);
    defer allocator.free(formatted);
    
    try testing.expect(std.mem.indexOf(u8, formatted, "ConnectionFailed") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "mainnet.hedera.com:443") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "attempt: 3") != null);
    
    try testing.expect(err.isRetryable());
    try testing.expect(err.shouldBackoff());
    try testing.expect(err.getRecommendedDelayMs() > 0);
}

test "TransactionError with validation failures" {
    const allocator = testing.allocator;
    
    var err = try TransactionError.init(allocator, HederaError.InvalidTransaction, "0.0.123@1234567890.000000000", "TokenCreateTransaction");
    defer err.deinit(allocator);
    
    const failure = try TransactionError.ValidationFailure.init(allocator, "memo", null, "very long memo exceeding limit", "maximum length exceeded");
    try err.addValidationFailure(allocator, failure);
    
    const formatted = try err.formatError(allocator);
    defer allocator.free(formatted);
    
    try testing.expect(std.mem.indexOf(u8, formatted, "InvalidTransaction") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "TokenCreateTransaction") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "memo") != null);
    
    try testing.expect(err.isValidationError());
    try testing.expect(!err.isFeeRelated());
}

test "CryptographyError formatting" {
    const allocator = testing.allocator;
    
    var err = try CryptographyError.init(allocator, HederaError.InvalidSignature, .signing, .ed25519, "Ed25519-SHA512");
    defer err.deinit(allocator);
    
    err.withInputSize(1024);
    
    const formatted = try err.formatError(allocator);
    defer allocator.free(formatted);
    
    try testing.expect(std.mem.indexOf(u8, formatted, "InvalidSignature") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "signing") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "ED25519") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "1024 bytes") != null);
    
    try testing.expect(err.isSignatureError());
    try testing.expect(!err.isKeyError());
}

test "ErrorContext unified interface" {
    const allocator = testing.allocator;
    
    const builder = ErrorBuilder.init(allocator);
    var context = try builder.networkError(HederaError.NetworkTimeout, "testnet.hedera.com:443", 2);
    defer context.deinit(allocator);
    
    try testing.expectEqual(HederaError.NetworkTimeout, context.getBaseError());
    try testing.expect(context.isRetryable());
    
    const formatted = try context.formatError(allocator);
    defer allocator.free(formatted);
    
    try testing.expect(std.mem.indexOf(u8, formatted, "Network Error") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "NetworkTimeout") != null);
}
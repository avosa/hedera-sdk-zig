// Extended validation methods
// Provides comprehensive validation utilities for all Hedera types

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const AccountId = @import("../core/id.zig").AccountId;
const ContractId = @import("../core/id.zig").ContractId;
const FileId = @import("../core/id.zig").FileId;
const TokenId = @import("../core/id.zig").TokenId;
const TopicId = @import("../core/id.zig").TopicId;
const PrivateKey = @import("../crypto/private_key.zig").PrivateKey;
const PublicKey = @import("../crypto/key.zig").PublicKey;
const Hbar = @import("../core/hbar.zig").Hbar;
const Timestamp = @import("../core/timestamp.zig").Timestamp;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;

const HederaError = @import("../core/errors.zig").HederaError;

// Validation result with detailed information
pub const ValidationResult = struct {
    valid: bool,
    errors: []const []const u8,
    warnings: []const []const u8,
    
    pub fn init(_: Allocator) ValidationResult {
        return ValidationResult{
            .valid = true,
            .errors = &[_][]const u8{},
            .warnings = &[_][]const u8{},
        };
    }
    
    pub fn addError(self: *ValidationResult, allocator: Allocator, error_msg: []const u8) !void {
        const new_errors = try allocator.alloc([]const u8, self.errors.len + 1);
        std.mem.copy([]const u8, new_errors, self.errors);
        new_errors[self.errors.len] = try allocator.dupe(u8, error_msg);
        self.errors = new_errors;
        self.valid = false;
    }
    
    pub fn addWarning(self: *ValidationResult, allocator: Allocator, warning_msg: []const u8) !void {
        const new_warnings = try allocator.alloc([]const u8, self.warnings.len + 1);
        std.mem.copy([]const u8, new_warnings, self.warnings);
        new_warnings[self.warnings.len] = try allocator.dupe(u8, warning_msg);
        self.warnings = new_warnings;
    }
    
    pub fn deinit(self: ValidationResult, allocator: Allocator) void {
        for (self.errors) |err| {
            allocator.free(err);
        }
        for (self.warnings) |warn| {
            allocator.free(warn);
        }
        allocator.free(self.errors);
        allocator.free(self.warnings);
    }
};

// Account ID validation
pub const AccountIdValidator = struct {
    pub fn validateAccountId(account_id: ?AccountId) HederaError!void {
        if (account_id == null) return HederaError.NullValue;
        
        const id = account_id.?;
        
        // Validate shard range (0-255 for mainnet)
        if (id.shard > 255) return HederaError.OutOfRange;
        
        // Validate realm range (0-255 for mainnet)  
        if (id.realm > 255) return HederaError.OutOfRange;
        
        // Validate account number range
        if (id.account == 0) return HederaError.InvalidFormat;
        
        // Special system accounts validation
        if (isSystemAccount(id) and !isValidSystemAccount(id)) {
            return HederaError.InvalidFormat;
        }
    }
    
    pub fn validateAccountIdString(account_str: []const u8) HederaError!void {
        if (account_str.len == 0) return HederaError.InvalidLength;
        
        // Check format: shard.realm.account or account
        var parts = std.mem.split(u8, account_str, ".");
        var part_count: u8 = 0;
        
        while (parts.next()) |part| {
            part_count += 1;
            if (part.len == 0) return HederaError.InvalidFormat;
            
            // Validate numeric values
            for (part) |c| {
                if (!std.ascii.isDigit(c)) return HederaError.InvalidCharacters;
            }
        }
        
        if (part_count != 1 and part_count != 3) return HederaError.InvalidFormat;
    }
    
    fn isSystemAccount(account_id: AccountId) bool {
        return account_id.account < 1000;
    }
    
    fn isValidSystemAccount(account_id: AccountId) bool {
        // System accounts 1-999 are valid
        return account_id.account >= 1 and account_id.account <= 999;
    }
    
    pub fn validateDetailedAccountId(allocator: Allocator, account_id: ?AccountId) !ValidationResult {
        var result = ValidationResult.init(allocator);
        
        if (account_id == null) {
            try result.addError(allocator, "Account ID cannot be null");
            return result;
        }
        
        const id = account_id.?;
        
        // Validate shard
        if (id.shard > 255) {
            try result.addError(allocator, "Shard value exceeds maximum (255)");
        }
        
        // Validate realm
        if (id.realm > 255) {
            try result.addError(allocator, "Realm value exceeds maximum (255)");
        }
        
        // Validate account
        if (id.account == 0) {
            try result.addError(allocator, "Account number cannot be zero");
        }
        
        // Warning for system accounts
        if (isSystemAccount(id)) {
            try result.addWarning(allocator, "System account detected - ensure proper authorization");
        }
        
        return result;
    }
};

// Transaction ID validation
pub const TransactionIdValidator = struct {
    pub fn validateTransactionId(tx_id: ?TransactionId) HederaError!void {
        if (tx_id == null) return HederaError.NullValue;
        
        const id = tx_id.?;
        
        // Validate account ID
        try AccountIdValidator.validateAccountId(id.account_id);
        
        // Validate timestamp is not in the future
        const now = Timestamp.now();
        if (id.valid_start.seconds > now.seconds) {
            return HederaError.InvalidFormat;
        }
        
        // Validate timestamp is not too old (older than 180 seconds)
        const max_age = 180;
        if (now.seconds - id.valid_start.seconds > max_age) {
            return HederaError.ExpiredTimestamp;
        }
    }
    
    pub fn validateTransactionIdString(tx_str: []const u8) HederaError!void {
        if (tx_str.len == 0) return HederaError.InvalidLength;
        
        // Format: account_id@seconds.nanoseconds
        const at_pos = std.mem.indexOf(u8, tx_str, "@") orelse return HederaError.InvalidFormat;
        
        const account_part = tx_str[0..at_pos];
        const timestamp_part = tx_str[at_pos + 1..];
        
        // Validate account part
        try AccountIdValidator.validateAccountIdString(account_part);
        
        // Validate timestamp part
        const dot_pos = std.mem.indexOf(u8, timestamp_part, ".") orelse return HederaError.InvalidFormat;
        
        const seconds_str = timestamp_part[0..dot_pos];
        const nanos_str = timestamp_part[dot_pos + 1..];
        
        // Validate numeric format
        for (seconds_str) |c| {
            if (!std.ascii.isDigit(c)) return HederaError.InvalidCharacters;
        }
        
        for (nanos_str) |c| {
            if (!std.ascii.isDigit(c)) return HederaError.InvalidCharacters;
        }
        
        // Validate nanoseconds range
        if (nanos_str.len > 9) return HederaError.OutOfRange;
    }
};

// Hbar amount validation
pub const HbarValidator = struct {
    pub const MAX_HBAR: i64 = 50_000_000_000; // 50 billion Hbar
    pub const MIN_HBAR: i64 = -50_000_000_000;
    
    pub fn validateHbarAmount(amount: ?Hbar) HederaError!void {
        if (amount == null) return HederaError.NullValue;
        
        const hbar = amount.?;
        const tinybars = hbar.toTinybars();
        
        // Validate range
        const max_tinybars = MAX_HBAR * 100_000_000;
        const min_tinybars = MIN_HBAR * 100_000_000;
        
        if (tinybars > max_tinybars or tinybars < min_tinybars) {
            return HederaError.OutOfRange;
        }
    }
    
    pub fn validateHbarString(hbar_str: []const u8) HederaError!void {
        if (hbar_str.len == 0) return HederaError.InvalidLength;
        
        var has_decimal = false;
        var decimal_places: u8 = 0;
        var start_idx: usize = 0;
        
        // Check for negative sign
        if (hbar_str[0] == '-') {
            start_idx = 1;
        }
        
        if (start_idx >= hbar_str.len) return HederaError.InvalidFormat;
        
        for (hbar_str[start_idx..]) |c| {
            if (c == '.') {
                if (has_decimal) return HederaError.InvalidFormat;
                has_decimal = true;
            } else if (std.ascii.isDigit(c)) {
                if (has_decimal) {
                    decimal_places += 1;
                    if (decimal_places > 8) return HederaError.OutOfRange; // Max 8 decimal places for tinybars
                }
            } else {
                return HederaError.InvalidCharacters;
            }
        }
    }
};

// Private key validation
pub const PrivateKeyValidator = struct {
    pub fn validatePrivateKeyBytes(key_bytes: []const u8) HederaError!void {
        if (key_bytes.len == 0) return HederaError.InvalidLength;
        
        // ED25519 private keys are 32 bytes
        // ECDSA secp256k1 private keys are 32 bytes
        if (key_bytes.len != 32) return HederaError.InvalidLength;
        
        // Check for all zeros (invalid key)
        var all_zero = true;
        for (key_bytes) |byte| {
            if (byte != 0) {
                all_zero = false;
                break;
            }
        }
        
        if (all_zero) return HederaError.InvalidKey;
    }
    
    pub fn validatePrivateKeyString(key_str: []const u8) HederaError!void {
        if (key_str.len == 0) return HederaError.InvalidLength;
        
        // DER encoding typically starts with specific bytes
        if (key_str.len < 64) return HederaError.InvalidLength; // Minimum hex string length
        
        // Validate hex characters
        for (key_str) |c| {
            if (!std.ascii.isHex(c)) return HederaError.InvalidCharacters;
        }
    }
    
    pub fn validateKeyPair(private_key: PrivateKey, public_key: PublicKey) HederaError!void {
        // Verify that public key matches private key
        const derived_public = private_key.getPublicKey();
        if (!derived_public.equals(public_key)) {
            return HederaError.InvalidKey;
        }
        
        // Test signing and verification
        const test_message = "validation_test";
        const signature = private_key.sign(test_message) catch return HederaError.InvalidSignature;
        
        if (!public_key.verify(test_message, &signature)) {
            return HederaError.InvalidSignature;
        }
    }
};

// Network validation
pub const NetworkValidator = struct {
    pub fn validateNetworkEndpoint(endpoint: []const u8) HederaError!void {
        if (endpoint.len == 0) return HederaError.InvalidLength;
        
        // Basic format validation for host:port
        const colon_pos = std.mem.lastIndexOf(u8, endpoint, ":") orelse return HederaError.InvalidFormat;
        
        const host = endpoint[0..colon_pos];
        const port_str = endpoint[colon_pos + 1..];
        
        // Validate host (basic check)
        if (host.len == 0) return HederaError.InvalidFormat;
        
        // Validate port
        if (port_str.len == 0) return HederaError.InvalidFormat;
        
        for (port_str) |c| {
            if (!std.ascii.isDigit(c)) return HederaError.InvalidCharacters;
        }
        
        const port = std.fmt.parseInt(u16, port_str, 10) catch return HederaError.OutOfRange;
        if (port == 0) return HederaError.OutOfRange;
    }
    
    pub fn validateTlsCertificate(cert_data: []const u8) HederaError!void {
        if (cert_data.len == 0) return HederaError.InvalidLength;
        
        // Basic PEM format validation
        const pem_header = "-----BEGIN CERTIFICATE-----";
        const pem_footer = "-----END CERTIFICATE-----";
        
        if (!std.mem.startsWith(u8, cert_data, pem_header)) {
            return HederaError.InvalidFormat;
        }
        
        if (!std.mem.endsWith(u8, cert_data, pem_footer)) {
            return HederaError.InvalidFormat;
        }
    }
};

// Batch validation utilities
pub const BatchValidator = struct {
    pub fn validateAccountIds(allocator: Allocator, account_ids: []const AccountId) !ValidationResult {
        var result = ValidationResult.init(allocator);
        
        for (account_ids, 0..) |account_id, index| {
            AccountIdValidator.validateAccountId(account_id) catch |err| {
                const error_msg = try std.fmt.allocPrint(allocator, "Account ID at index {}: {}", .{ index, err });
                try result.addError(allocator, error_msg);
                allocator.free(error_msg);
            };
        }
        
        return result;
    }
    
    pub fn validateTransactionIds(allocator: Allocator, tx_ids: []const TransactionId) !ValidationResult {
        var result = ValidationResult.init(allocator);
        
        for (tx_ids, 0..) |tx_id, index| {
            TransactionIdValidator.validateTransactionId(tx_id) catch |err| {
                const error_msg = try std.fmt.allocPrint(allocator, "Transaction ID at index {}: {}", .{ index, err });
                try result.addError(allocator, error_msg);
                allocator.free(error_msg);
            };
        }
        
        return result;
    }
    
    pub fn validateHbarAmounts(allocator: Allocator, amounts: []const Hbar) !ValidationResult {
        var result = ValidationResult.init(allocator);
        
        for (amounts, 0..) |amount, index| {
            HbarValidator.validateHbarAmount(amount) catch |err| {
                const error_msg = try std.fmt.allocPrint(allocator, "Hbar amount at index {}: {}", .{ index, err });
                try result.addError(allocator, error_msg);
                allocator.free(error_msg);
            };
        }
        
        return result;
    }
};

// Comprehensive validation function
pub fn validateAll(allocator: Allocator, comptime T: type, value: T) !ValidationResult {
    var result = ValidationResult.init(allocator);
    
    switch (@typeInfo(T)) {
        .Optional => |optional_info| {
            if (value == null) {
                try result.addWarning(allocator, "Value is null");
                return result;
            }
            
            // Recursively validate the unwrapped value
            const unwrapped_result = try validateAll(allocator, optional_info.child, value.?);
            defer unwrapped_result.deinit(allocator);
            
            // Merge results
            for (unwrapped_result.errors) |err| {
                try result.addError(allocator, err);
            }
            for (unwrapped_result.warnings) |warn| {
                try result.addWarning(allocator, warn);
            }
        },
        .Struct => |_| {
            if (T == AccountId) {
                AccountIdValidator.validateAccountId(value) catch |err| {
                    const error_msg = try std.fmt.allocPrint(allocator, "Account ID validation failed: {}", .{err});
                    try result.addError(allocator, error_msg);
                    allocator.free(error_msg);
                };
            } else if (T == TransactionId) {
                TransactionIdValidator.validateTransactionId(value) catch |err| {
                    const error_msg = try std.fmt.allocPrint(allocator, "Transaction ID validation failed: {}", .{err});
                    try result.addError(allocator, error_msg);
                    allocator.free(error_msg);
                };
            } else if (T == Hbar) {
                HbarValidator.validateHbarAmount(value) catch |err| {
                    const error_msg = try std.fmt.allocPrint(allocator, "Hbar validation failed: {}", .{err});
                    try result.addError(allocator, error_msg);
                    allocator.free(error_msg);
                };
            }
            // Add more type-specific validations as needed
        },
        else => {
            try result.addWarning(allocator, "No specific validation available for this type");
        },
    }
    
    return result;
}

// Test cases
test "AccountIdValidator basic validation" {
    const allocator = testing.allocator;
    
    // Valid account ID
    const valid_account = AccountId.init(0, 0, 123);
    try AccountIdValidator.validateAccountId(valid_account);
    
    // Invalid account ID (zero account number)
    const invalid_account = AccountId.init(0, 0, 0);
    try testing.expectError(HederaError.InvalidFormat, AccountIdValidator.validateAccountId(invalid_account));
    
    // Out of range shard
    const invalid_shard = AccountId.init(256, 0, 123);
    try testing.expectError(HederaError.OutOfRange, AccountIdValidator.validateAccountId(invalid_shard));
    
    // Detailed validation
    var result = try AccountIdValidator.validateDetailedAccountId(allocator, valid_account);
    defer result.deinit(allocator);
    try testing.expect(result.valid);
}

test "TransactionIdValidator validation" {
    _ = testing.allocator;
    
    // Valid transaction ID string
    try TransactionIdValidator.validateTransactionIdString("0.0.123@1640995200.000000000");
    
    // Invalid format (missing @)
    try testing.expectError(HederaError.InvalidFormat, TransactionIdValidator.validateTransactionIdString("0.0.123-1640995200.000000000"));
    
    // Invalid account format
    try testing.expectError(HederaError.InvalidFormat, TransactionIdValidator.validateTransactionIdString("abc.0.123@1640995200.000000000"));
}

test "HbarValidator validation" {
    _ = testing.allocator;
    
    // Valid Hbar amount
    const valid_amount = try Hbar.from(100);
    try HbarValidator.validateHbarAmount(valid_amount);
    
    // Valid Hbar string
    try HbarValidator.validateHbarString("100.50000000");
    
    // Invalid format (too many decimal places)
    try testing.expectError(HederaError.OutOfRange, HbarValidator.validateHbarString("100.123456789"));
    
    // Invalid characters
    try testing.expectError(HederaError.InvalidCharacters, HbarValidator.validateHbarString("100.5abc"));
}

test "NetworkValidator endpoint validation" {
    // Valid endpoint
    try NetworkValidator.validateNetworkEndpoint("mainnet.hedera.com:50211");
    
    // Invalid format (no port)
    try testing.expectError(HederaError.InvalidFormat, NetworkValidator.validateNetworkEndpoint("mainnet.hedera.com"));
    
    // Invalid port
    try testing.expectError(HederaError.InvalidCharacters, NetworkValidator.validateNetworkEndpoint("mainnet.hedera.com:abc"));
}

test "BatchValidator account IDs validation" {
    const allocator = testing.allocator;
    
    const accounts = [_]AccountId{
        AccountId.init(0, 0, 123),
        AccountId.init(0, 0, 456),
        AccountId.init(256, 0, 789), // Invalid shard
    };
    
    var result = try BatchValidator.validateAccountIds(allocator, &accounts);
    defer result.deinit(allocator);
    
    try testing.expect(!result.valid);
    try testing.expect(result.errors.len == 1);
}
const std = @import("std");
const TransactionReceipt = @import("../query/receipt_query.zig").TransactionReceipt;
const TransactionRecord = @import("../query/transaction_record_query.zig").TransactionRecord;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;
const StatusCode = @import("../core/errors.zig").StatusCode;
const HederaError = @import("../core/errors.zig").HederaError;
const AccountId = @import("../core/id.zig").AccountId;
const TokenId = @import("../core/id.zig").TokenId;
const ContractId = @import("../core/id.zig").ContractId;
const FileId = @import("../core/id.zig").FileId;
const TopicId = @import("../core/id.zig").TopicId;
const ScheduleId = @import("../core/id.zig").ScheduleId;

// Comprehensive transaction receipt and record validation
pub const ReceiptValidator = struct {
    allocator: std.mem.Allocator,
    strict_validation: bool = true,
    require_success_status: bool = true,
    validate_timestamps: bool = true,
    validate_ids: bool = true,
    validate_fees: bool = true,
    
    pub fn init(allocator: std.mem.Allocator) ReceiptValidator {
        return ReceiptValidator{
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *ReceiptValidator) void {
        _ = self;
    }
    
    // Configure validation strictness
    pub fn setStrictValidation(self: *ReceiptValidator, strict: bool) *ReceiptValidator {
        self.strict_validation = strict;
        return self;
    }
    
    // Configure whether success status is required
    pub fn setRequireSuccess(self: *ReceiptValidator, require: bool) *ReceiptValidator {
        self.require_success_status = require;
        return self;
    }
    
    // Configure timestamp validation
    pub fn setValidateTimestamps(self: *ReceiptValidator, validate: bool) *ReceiptValidator {
        self.validate_timestamps = validate;
        return self;
    }
    
    // Configure ID validation
    pub fn setValidateIds(self: *ReceiptValidator, validate: bool) *ReceiptValidator {
        self.validate_ids = validate;
        return self;
    }
    
    // Configure fee validation
    pub fn setValidateFees(self: *ReceiptValidator, validate: bool) *ReceiptValidator {
        self.validate_fees = validate;
        return self;
    }
    
    // Validate transaction receipt
    pub fn validateReceipt(self: *ReceiptValidator, receipt: *const TransactionReceipt, expected_tx_id: ?TransactionId) !ValidationResult {
        var result = ValidationResult{
            .is_valid = true,
            .issues = std.ArrayList(ValidationIssue).init(self.allocator),
            .status = receipt.status,
            .transaction_id = receipt.transaction_id,
        };
        
        // Validate status
        try self.validateStatus(receipt.status, &result);
        
        // Validate transaction ID match
        if (expected_tx_id) |expected| {
            try self.validateTransactionId(receipt.transaction_id, expected, &result);
            return self;
        }
        
        // Validate timestamps if enabled
        if (self.validate_timestamps) {
            try self.validateReceiptTimestamps(receipt, &result);
        }
        
        // Validate entity IDs if enabled
        if (self.validate_ids) {
            try self.validateReceiptIds(receipt, &result);
        }
        
        // Set overall validity
        result.is_valid = result.issues.items.len == 0 or !self.strict_validation;
        
        return result;
    }
    
    // Validate transaction record
    pub fn validateRecord(self: *ReceiptValidator, record: *const TransactionRecord, expected_tx_id: ?TransactionId) !ValidationResult {
        var result = ValidationResult{
            .is_valid = true,
            .issues = std.ArrayList(ValidationIssue).init(self.allocator),
            .status = record.receipt.status,
            .transaction_id = record.transaction_id,
        };
        
        // First validate the embedded receipt
        const receipt_result = try self.validateReceipt(&record.receipt, expected_tx_id);
        defer receipt_result.deinit();
        
        // Copy receipt issues to record result
        for (receipt_result.issues.items) |issue| {
            try result.issues.append(issue);
        }
        
        // Validate record-specific fields
        try self.validateRecordTimestamps(record, &result);
        try self.validateRecordFees(record, &result);
        try self.validateRecordTransfers(record, &result);
        
        // Set overall validity
        result.is_valid = result.issues.items.len == 0 or !self.strict_validation;
        
        return result;
    }
    
    // Validate multiple receipts (for batch operations)
    pub fn validateBatchReceipts(self: *ReceiptValidator, receipts: []const TransactionReceipt, expected_tx_ids: ?[]const TransactionId) !BatchValidationResult {
        var batch_result = BatchValidationResult{
            .total_count = receipts.len,
            .valid_count = 0,
            .invalid_count = 0,
            .results = std.ArrayList(ValidationResult).init(self.allocator),
        };
        
        for (receipts, 0..) |receipt, i| {
            const expected_id = if (expected_tx_ids) |ids| (if (i < ids.len) ids[i] else null) else null;
            const result = try self.validateReceipt(&receipt, expected_id);
            
            if (result.is_valid) {
                batch_result.valid_count += 1;
            } else {
                batch_result.invalid_count += 1;
            }
            
            try batch_result.results.append(result);
        }
        
        return batch_result;
    }
    
    // Validate status code
    fn validateStatus(self: *ReceiptValidator, status: HederaError, result: *ValidationResult) !void {
        if (self.require_success_status and status != .Success) {
            try result.issues.append(ValidationIssue{
                .type = .InvalidStatus,
                .severity = .Error,
                .message = try std.fmt.allocPrint(
                    self.allocator,
                    "Transaction failed with status: {s}",
                    .{StatusCode.getDescription(status)}
                ),
                .field = "status",
            });
        } else if (status == .Unknown) {
            try result.issues.append(ValidationIssue{
                .type = .InvalidStatus,
                .severity = .Warning,
                .message = try self.allocator.dupe(u8, "Transaction status is unknown"),
                .field = "status",
            });
        }
    }
    
    // Validate transaction ID match
    fn validateTransactionId(self: *ReceiptValidator, actual: TransactionId, expected: TransactionId, result: *ValidationResult) !void {
        if (!actual.equals(expected)) {
            try result.issues.append(ValidationIssue{
                .type = .MismatchedTransactionId,
                .severity = .Error,
                .message = try std.fmt.allocPrint(
                    self.allocator,
                    "Transaction ID mismatch: expected {d}.{d}.{d}-{d}-{d}, got {d}.{d}.{d}-{d}-{d}",
                    .{
                        expected.account_id.shard,
                        expected.account_id.realm,
                        expected.account_id.account,
                        expected.valid_start.seconds,
                        expected.valid_start.nanos,
                        actual.account_id.shard,
                        actual.account_id.realm,
                        actual.account_id.account,
                        actual.valid_start.seconds,
                        actual.valid_start.nanos,
                    }
                ),
                .field = "transactionId",
            });
        }
    }
    
    // Validate receipt timestamps
    fn validateReceiptTimestamps(self: *ReceiptValidator, receipt: *const TransactionReceipt, result: *ValidationResult) !void {
        // Check if consensus timestamp is reasonable (not too far in past/future)
        const now = std.time.timestamp();
        const consensus_time = receipt.consensus_timestamp.seconds;
        
        // Allow up to 1 hour in the future or 1 day in the past
        const future_threshold = now + 3600; // 1 hour
        const past_threshold = now - 86400; // 1 day
        
        if (consensus_time > future_threshold) {
            try result.issues.append(ValidationIssue{
                .type = .InvalidTimestamp,
                .severity = .Warning,
                .message = try std.fmt.allocPrint(
                    self.allocator,
                    "Consensus timestamp is too far in the future: {d}",
                    .{consensus_time}
                ),
                .field = "consensusTimestamp",
            });
        } else if (consensus_time < past_threshold) {
            try result.issues.append(ValidationIssue{
                .type = .InvalidTimestamp,
                .severity = .Warning,
                .message = try std.fmt.allocPrint(
                    self.allocator,
                    "Consensus timestamp is too far in the past: {d}",
                    .{consensus_time}
                ),
                .field = "consensusTimestamp",
            });
        }
    }
    
    // Validate receipt entity IDs
    fn validateReceiptIds(self: *ReceiptValidator, receipt: *const TransactionReceipt, result: *ValidationResult) !void {
        
        // Validate account ID if present
        if (receipt.account_id) |account_id| {
            if (account_id.shard < 0 or account_id.realm < 0 or account_id.account < 0) {
                try result.issues.append(ValidationIssue{
                    .type = .InvalidEntityId,
                    .severity = .Error,
                    .message = try std.allocator.dupe(u8, "Account ID contains negative values"),
                    .field = "accountId",
                });
            }
        }
        
        // Similar validation for other entity types
        if (receipt.contract_id) |contract_id| {
            if (contract_id.shard < 0 or contract_id.realm < 0 or contract_id.account < 0) {
                try result.issues.append(ValidationIssue{
                    .type = .InvalidEntityId,
                    .severity = .Error,
                    .message = try self.allocator.dupe(u8, "Contract ID contains negative values"),
                    .field = "contractId",
                });
            }
        }
        
        // Validate token serial numbers if present
        if (receipt.serial_numbers) |serials| {
            for (serials, 0..) |serial, i| {
                if (serial <= 0) {
                    try result.issues.append(ValidationIssue{
                        .type = .InvalidSerialNumber,
                        .severity = .Error,
                        .message = try std.fmt.allocPrint(
                            self.allocator,
                            "Invalid serial number at index {d}: {d}",
                            .{ i, serial }
                        ),
                        .field = "serialNumbers",
                    });
                }
            }
        }
    }
    
    // Validate record timestamps
    fn validateRecordTimestamps(self: *ReceiptValidator, record: *const TransactionRecord, result: *ValidationResult) !void {
        
        // Validate consensus timestamp order
        if (record.consensus_timestamp.seconds < record.transaction_id.valid_start.seconds) {
            try result.issues.append(ValidationIssue{
                .type = .InvalidTimestamp,
                .severity = .Error,
                .message = try self.allocator.dupe(u8, "Consensus timestamp is before transaction valid start time"),
                .field = "consensusTimestamp",
            });
        }
    }
    
    // Validate record fees
    fn validateRecordFees(self: *ReceiptValidator, record: *const TransactionRecord, result: *ValidationResult) !void {
        if (!self.validate_fees) return;
        
        // Check for negative fees
        if (record.transaction_fee < 0) {
            try result.issues.append(ValidationIssue{
                .type = .InvalidFee,
                .severity = .Error,
                .message = try std.fmt.allocPrint(
                    self.allocator,
                    "Negative transaction fee: {d}",
                    .{record.transaction_fee}
                ),
                .field = "transactionFee",
            });
        }
        
        // Check for unreasonably high fees (> 100 HBAR)
        const max_reasonable_fee = 100 * 100_000_000; // 100 HBAR in tinybars
        if (record.transaction_fee > max_reasonable_fee) {
            try result.issues.append(ValidationIssue{
                .type = .InvalidFee,
                .severity = .Warning,
                .message = try std.fmt.allocPrint(
                    self.allocator,
                    "Very high transaction fee: {d} tinybars",
                    .{record.transaction_fee}
                ),
                .field = "transactionFee",
            });
        }
    }
    
    // Validate record transfers
    fn validateRecordTransfers(self: *ReceiptValidator, record: *const TransactionRecord, result: *ValidationResult) !void {
        
        // Check that transfers balance to zero
        var total_transfer: i64 = 0;
        
        if (record.transfer_list) |transfers| {
            for (transfers) |transfer| {
                total_transfer += transfer.amount;
            }
        }
        
        // Allow small rounding errors (1 tinybar)
        if (@abs(total_transfer) > 1) {
            try result.issues.append(ValidationIssue{
                .type = .ImbalancedTransfers,
                .severity = .Error,
                .message = try std.fmt.allocPrint(
                    self.allocator,
                    "Transfers do not balance: total = {d} tinybars",
                    .{total_transfer}
                ),
                .field = "transferList",
            });
        }
    }
};

// Validation result for a single receipt/record
pub const ValidationResult = struct {
    is_valid: bool,
    issues: std.ArrayList(ValidationIssue),
    status: HederaError,
    transaction_id: TransactionId,
    
    pub fn deinit(self: *ValidationResult, allocator: std.mem.Allocator) void {
        for (self.issues.items) |*issue| {
            issue.deinit(allocator);
        }
        self.issues.deinit();
    }
    
    pub fn hasErrors(self: ValidationResult) bool {
        for (self.issues.items) |issue| {
            if (issue.severity == .Error) return true;
        }
        return false;
    }
    
    pub fn hasWarnings(self: ValidationResult) bool {
        for (self.issues.items) |issue| {
            if (issue.severity == .Warning) return true;
        }
        return false;
    }
    
    pub fn getErrorCount(self: ValidationResult) u32 {
        var count: u32 = 0;
        for (self.issues.items) |issue| {
            if (issue.severity == .Error) count += 1;
        }
        return count;
    }
    
    pub fn getWarningCount(self: ValidationResult) u32 {
        var count: u32 = 0;
        for (self.issues.items) |issue| {
            if (issue.severity == .Warning) count += 1;
        }
        return count;
    }
};

// Batch validation result
pub const BatchValidationResult = struct {
    total_count: usize,
    valid_count: usize,
    invalid_count: usize,
    results: std.ArrayList(ValidationResult),
    
    pub fn deinit(self: *BatchValidationResult, allocator: std.mem.Allocator) void {
        for (self.results.items) |*result| {
            result.deinit(allocator);
        }
        self.results.deinit();
    }
    
    pub fn getSuccessRate(self: BatchValidationResult) f64 {
        if (self.total_count == 0) return 0.0;
        return @as(f64, @floatFromInt(self.valid_count)) / @as(f64, @floatFromInt(self.total_count));
    }
};

// Individual validation issue
pub const ValidationIssue = struct {
    type: IssueType,
    severity: Severity,
    message: []const u8,
    field: []const u8,
    
    pub fn deinit(self: *ValidationIssue, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
        allocator.free(self.field);
    }
    
    pub const IssueType = enum {
        InvalidStatus,
        MismatchedTransactionId,
        InvalidTimestamp,
        InvalidEntityId,
        InvalidSerialNumber,
        InvalidFee,
        ImbalancedTransfers,
        MissingRequiredField,
        InvalidField,
        Other,
    };
    
    pub const Severity = enum {
        Error,
        Warning,
        Info,
    };
};
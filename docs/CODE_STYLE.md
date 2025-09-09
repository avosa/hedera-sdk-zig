# Hedera SDK Zig - Code Style Guide

This document outlines the coding conventions and style guidelines for the Hedera SDK for Zig. Following these conventions ensures consistency, readability, and maintainability across the codebase.

## Zig Naming Conventions

### Types (Structs, Enums, Unions)
Use **PascalCase** for all type definitions.

```zig
// Structs
pub const AccountId = struct {
    shard: u64,
    realm: u64,
    account: u64,
};

pub const TransactionResponse = struct {
    transaction_id: TransactionId,
    node_id: AccountId,
    hash: []const u8,
};

// Enums
pub const Status = enum {
    Ok,
    InvalidAccount,
    InsufficientFunds,
    InvalidTransaction,
};

pub const NetworkType = enum {
    Mainnet,
    Testnet,
    Previewnet,
    LocalNode,
};

// Unions
pub const Key = union(enum) {
    ed25519: PublicKey,
    ecdsa_secp256k1: PublicKey,
    threshold: ThresholdKey,
    key_list: KeyList,
};
```

### Variables
Use **snake_case** for all variables, including struct fields.

```zig
pub const AccountCreateTransaction = struct {
    base: Transaction,
    account_id: ?AccountId,          // snake_case field
    initial_balance: ?Hbar,          // snake_case field
    auto_renew_period: ?Duration,    // snake_case field
    
    pub fn init(allocator: std.mem.Allocator) AccountCreateTransaction {
        var transaction_id = TransactionId.generate();  // snake_case variable
        const max_fee = Hbar.fromTinybars(100_000_000); // snake_case variable
        
        return AccountCreateTransaction{
            .base = Transaction.init(allocator),
            .account_id = null,
            .initial_balance = null,
            .auto_renew_period = null,
        };
    }
};
```

### Functions
Use **camelCase** for regular functions.

```zig
// Regular functions use camelCase
pub fn createAccount(allocator: std.mem.Allocator) !AccountCreateTransaction {
    return AccountCreateTransaction.init(allocator);
}

pub fn executeTransaction(client: *Client, transaction: *Transaction) !TransactionResponse {
    return transaction.execute(client);
}

pub fn validateSignature(key: PublicKey, signature: []const u8, message: []const u8) bool {
    return key.verify(signature, message);
}

// Method functions also use camelCase
pub fn setAccountId(self: *AccountCreateTransaction, account_id: AccountId) *AccountCreateTransaction {
    self.account_id = account_id;
    return self;
}

pub fn getBalance(self: *const Account) Hbar {
    return self.balance;
}
```

### Functions Returning Types
Use **PascalCase** for functions that return types (compile-time functions).

```zig
// Functions returning types use PascalCase (like @Type(), @TypeOf())
pub fn ArrayList(comptime T: type) type {
    return std.ArrayList(T);
}

pub fn HashMap(comptime K: type, comptime V: type) type {
    return std.HashMap(K, V, std.hash_map.default_hash, std.hash_map.default_eql, std.heap.page_allocator);
}

// Generic transaction builder
pub fn TransactionBuilder(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,
        transaction: T,
        
        pub fn init(allocator: std.mem.Allocator) @This() {
            return @This(){
                .allocator = allocator,
                .transaction = T.init(allocator),
            };
        }
    };
}
```

### Constants
Use **SCREAMING_SNAKE_CASE** for constants.

```zig
// Module-level constants
pub const MAX_TRANSACTION_FEE: u64 = 100_000_000; // 1 HBAR in tinybars
pub const DEFAULT_AUTO_RENEW_PERIOD: u64 = 7890000; // ~3 months in seconds
pub const MAX_MEMO_LENGTH: usize = 100;
pub const DEFAULT_NETWORK_TIMEOUT: u64 = 30_000; // 30 seconds in milliseconds

// Error constants
pub const INSUFFICIENT_BALANCE_ERROR: []const u8 = "Insufficient account balance";
pub const INVALID_SIGNATURE_ERROR: []const u8 = "Invalid transaction signature";

// Network constants
pub const MAINNET_NODES = [_][]const u8{
    "mainnet-public.mirrornode.hedera.com:443",
    "hgraph.io:443",
};

pub const TESTNET_NODES = [_][]const u8{
    "testnet.mirrornode.hedera.com:443",
};
```

## File Organization

### File Naming
Use **snake_case** for file names.

```
src/
├── account/
│   ├── account_create.zig
│   ├── account_delete.zig
│   ├── account_update.zig
│   └── account_balance_query.zig
├── token/
│   ├── token_create.zig
│   ├── token_transfer.zig
│   └── token_associate.zig
└── crypto/
    ├── private_key.zig
    ├── public_key.zig
    └── key_pair.zig
```

### Module Structure
Organize code logically within files:

```zig
// 1. Standard library imports
const std = @import("std");

// 2. Local imports (relative to current module)
const AccountId = @import("../core/id.zig").AccountId;
const Transaction = @import("../transaction/transaction.zig").Transaction;
const Client = @import("../network/client.zig").Client;

// 3. Constants
pub const MAX_ACCOUNTS_PER_TRANSACTION: usize = 10;
pub const DEFAULT_GAS_LIMIT: u64 = 250_000;

// 4. Error definitions
pub const AccountError = error{
    InvalidAccountId,
    InsufficientBalance,
    AccountNotFound,
};

// 5. Type definitions
pub const AccountCreateTransaction = struct {
    // ... struct implementation
};

// 6. Public functions
pub fn createAccount(allocator: std.mem.Allocator) !AccountCreateTransaction {
    // ... function implementation
}

// 7. Tests (at end of file)
test "account creation" {
    // ... test implementation
}
```

## Code Style Guidelines

### Memory Management
Always use proper memory management patterns:

```zig
pub fn processTransaction(allocator: std.mem.Allocator) !TransactionResult {
    // Create arraylist
    var transaction_list = std.ArrayList(Transaction).init(allocator);
    defer transaction_list.deinit(); // Always defer cleanup
    
    // Allocate memory
    const buffer = try allocator.alloc(u8, 1024);
    defer allocator.free(buffer); // Always defer deallocation
    
    // Process transactions
    for (transaction_list.items) |transaction| {
        try processSingleTransaction(transaction, buffer);
    }
    
    return TransactionResult{ .success = true };
}
```

### Error Handling
Use descriptive error types and proper error propagation:

```zig
pub const TransactionError = error{
    InvalidTransactionId,
    InsufficientFee,
    NetworkTimeout,
    SignatureValidationFailed,
};

pub fn validateTransaction(transaction: *const Transaction) TransactionError!void {
    if (transaction.transaction_id == null) {
        return TransactionError.InvalidTransactionId;
    }
    
    if (transaction.max_transaction_fee.toTinybars() < MIN_TRANSACTION_FEE) {
        return TransactionError.InsufficientFee;
    }
    
    // More validation...
}
```

### Documentation Comments
Use doc comments for public APIs:

```zig
/// Creates a new account on the Hedera network.
/// 
/// This transaction requires:
/// - Initial balance (optional, defaults to 0)
/// - Public key for the new account
/// - Auto-renew period (optional, defaults to 3 months)
/// 
/// Example:
/// ```zig
/// var transaction = AccountCreateTransaction.init(allocator);
/// defer transaction.deinit();
/// 
/// _ = try transaction.setKey(public_key);
/// _ = try transaction.setInitialBalance(Hbar.from(10));
/// 
/// const response = try transaction.execute(client);
/// ```
pub const AccountCreateTransaction = struct {
    base: Transaction,
    
    /// The public key for the new account
    key: ?Key,
    
    /// Initial balance to transfer to the new account
    initial_balance: ?Hbar,
    
    /// Auto-renewal period for the account
    auto_renew_period: ?Duration,
    
    /// Initialize a new account creation transaction
    pub fn init(allocator: std.mem.Allocator) AccountCreateTransaction {
        return AccountCreateTransaction{
            .base = Transaction.init(allocator),
            .key = null,
            .initial_balance = null,
            .auto_renew_period = null,
        };
    }
};
```

## Testing Conventions

### Test Naming
Use descriptive test names with snake_case:

```zig
test "account_creation_with_valid_key_succeeds" {
    // Test implementation
}

test "account_creation_with_insufficient_balance_fails" {
    // Test implementation
}

test "token_transfer_between_associated_accounts" {
    // Test implementation
}
```

### Test Structure
Follow the Arrange-Act-Assert pattern:

```zig
test "token_associate_transaction_execution" {
    // Arrange
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const account_id = AccountId{ .shard = 0, .realm = 0, .account = 123 };
    const token_id = TokenId{ .shard = 0, .realm = 0, .num = 456 };
    
    var transaction = TokenAssociateTransaction.init(allocator);
    defer transaction.deinit();
    
    // Act
    _ = try transaction.setAccountId(account_id);
    _ = try transaction.addTokenId(token_id);
    
    // Assert
    try std.testing.expect(transaction.getAccountId().?.equals(account_id));
    try std.testing.expect(transaction.getTokenIds().len == 1);
    try std.testing.expect(transaction.getTokenIds()[0].equals(token_id));
}
```

## Best Practices

### 1. Prefer Explicit Over Implicit
```zig
// Good: Explicit type specification
const account_id: AccountId = AccountId.fromString("0.0.123") catch unreachable;

// Avoid: Implicit type inference when not obvious
const account_id = AccountId.fromString("0.0.123") catch unreachable;
```

### 2. Use Meaningful Variable Names
```zig
// Good: Descriptive names
const transaction_receipt = try response.getReceipt(client);
const operator_account_id = client.getOperatorAccountId();

// Avoid: Abbreviated or unclear names
const receipt = try response.getReceipt(client);
const op_id = client.getOperatorAccountId();
```

### 3. Group Related Functionality
```zig
// Group related methods together
pub const AccountId = struct {
    shard: u64,
    realm: u64,
    account: u64,
    
    // Construction methods
    pub fn init(shard: u64, realm: u64, account: u64) AccountId { ... }
    pub fn fromString(str: []const u8) !AccountId { ... }
    pub fn fromBytes(bytes: []const u8) !AccountId { ... }
    
    // Conversion methods  
    pub fn toString(self: AccountId, allocator: std.mem.Allocator) ![]u8 { ... }
    pub fn toBytes(self: AccountId, allocator: std.mem.Allocator) ![]u8 { ... }
    
    // Utility methods
    pub fn equals(self: AccountId, other: AccountId) bool { ... }
    pub fn isValid(self: AccountId) bool { ... }
};
```

### 4. Handle Errors Appropriately
```zig
// Good: Proper error handling with context
pub fn executeTransaction(client: *Client, transaction: *Transaction) !TransactionResponse {
    const response = client.submitTransaction(transaction) catch |err| switch (err) {
        error.NetworkTimeout => {
            std.log.err("Network timeout while submitting transaction", .{});
            return err;
        },
        error.InsufficientBalance => {
            std.log.err("Insufficient balance for transaction fee", .{});
            return err;
        },
        else => return err,
    };
    
    return response;
}
```

This style guide ensures consistency across the Hedera SDK for Zig codebase and makes it easier for contributors to write maintainable, readable code that follows Zig best practices.
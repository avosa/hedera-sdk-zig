# Hedera SDK for Zig — Examples

This directory contains runnable examples demonstrating major SDK capabilities and recommended usage patterns for Zig applications that integrate with the Hedera network.

## Prerequisites

* Zig compiler 0.14.1(preferred) or later - Use [zigup](https://github.com/marler8997/zigup) to manage zig version eg `zigup 0.14.1`
  
* Hedera testnet account funded with HBAR
* Environment variables:

  ```bash
  export HEDERA_OPERATOR_ID="0.0.YOUR_ACCOUNT_ID"
  export HEDERA_OPERATOR_KEY="YOUR_PRIVATE_KEY"
  export HEDERA_MIRROR_NODE_URL="https://testnet.mirrornode.hedera.com"  # Optional
  ```

## Build and Discover Examples

From the repository root or this directory:

```bash
zig build list
```

## Run an Example

Use the target shown by `zig build list`. For example:

### Account Operations

```bash
zig build run-account_operations
```

Demonstrates:

* Creating accounts
* Balance and info queries
* HBAR transfers
* Property updates
* Transaction record queries
* Deleting accounts

### Token Operations

```bash
zig build run-token_operations
```

Demonstrates:

* Fungible token creation
* Account association/dissociation
* Token transfers
* Mint and burn
* Freeze/unfreeze
* Property updates
* Token info queries

### Smart Contract Operations

```bash
zig build run-smart_contract_operations
```

Demonstrates:

* Contract deployment
* Function calls with arguments
* Read-only state queries
* Bytecode and contract info queries
* Gas estimation and handling
* ABI encoding/decoding

### Consensus Service (HCS)

```bash
zig build run-consensus_service
```

Demonstrates:

* Topic creation and management
* Message submission (with automatic chunking)
* Topic info queries
* Sequencing and running hashes
* Topic updates and deletion

### File Service

```bash
zig build run-file_service
```

Demonstrates:

* File creation with initial contents
* Appends
* Info and content queries
* Text and binary handling
* Expiration management
* Deletion

### Mirror Node Queries

```bash
zig build run-mirror_node_queries
```

Demonstrates:

* REST access to the Mirror Node
* Account info and balances
* Transaction history retrieval
* Token and contract discovery
* Topic message retrieval
* Basic network metrics

### Cryptography Demo

```bash
zig build run-cryptography_demo
```

Demonstrates:

* ED25519 and ECDSA secp256k1 key generation
* Sign/verify flows
* Mnemonics and key derivation
* DER/PEM/hex serialization
* Composite keys (KeyList, ThresholdKey)
* Micro-benchmarks
* Cross-checks with known test vectors

## Common Patterns

### Client Initialization

```zig
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
defer arena.deinit();
const allocator = arena.allocator();

var client = try hedera.Client.forTestnet(allocator);
defer client.deinit();

const operator_id = try hedera.AccountId.fromString(operator_id_str);
const operator_key = try hedera.PrivateKey.fromString(operator_key_str);
try client.setOperator(operator_id, operator_key);
```

### Transaction Pattern

```zig
var tx = hedera.SomeTransaction.init(allocator);
defer tx.deinit();

try tx.setSomeProperty(value);
try tx.setTransactionMemo("example");

const resp = try tx.execute(&client);
const receipt = try resp.getReceipt(&client);

std.log.info("status: {}", .{receipt.status});
```

### Query Pattern

```zig
var q = hedera.SomeQuery.init(allocator);
defer q.deinit();

try q.setSomeParameter(value);
const result = try q.execute(&client);

std.log.info("result: {}", .{result});
```

### Error Handling

```zig
if (performOperation()) |ok| {
    std.log.info("ok: {}", .{ok});
} else |err| {
    std.log.err("failed: {}", .{err});
    return;
}
```

## Testing the Examples

Compile-check and fast-run example targets:

```bash
zig build test-examples
```

## Environment Variables Reference

| Variable                 | Description                                 | Default                                 |
| ------------------------ | ------------------------------------------- | --------------------------------------- |
| `HEDERA_OPERATOR_ID`     | Hedera account ID, for example `0.0.123456` | Required                                |
| `HEDERA_OPERATOR_KEY`    | Private key (DER hex or PEM)                | Required                                |
| `HEDERA_MIRROR_NODE_URL` | Mirror Node REST endpoint                   | `https://testnet.mirrornode.hedera.com` |

## Troubleshooting

* Missing credentials
  Ensure `HEDERA_OPERATOR_ID` and `HEDERA_OPERATOR_KEY` are set in the current shell.
* Invalid key format
  Confirm the key string matches the expected DER hex or PEM format used by the examples.
* Insufficient HBAR
  Fund your testnet account before running transactions that require fees.
* Network or time drift issues
  If transactions consistently fail with consensus or signature errors, verify local clock sync and retry.

## Contributing Examples

When adding or modifying examples:

1. Follow the [established code style and patterns](/docs/CODE_STYLE.md)
2. Include comprehensive error handling
3. Add detailed logging and comments
4. Test thoroughly on testnet
5. Update this README when introducing a new example target

# Hedera SDK for Zig

**Disclaimer:** Hedera SDK for Zig is an independent, community-created SDK. It is **not affiliated with, endorsed, or officially maintained by Hedera Hashgraph, LLC**. Use this library at your own risk and review its behavior carefully before relying on it in production.

## Overview

This project brings Hedera SDK functionality to the Zig programming language. It is under active development and continues to evolve. The SDK is being built with reference to the [Hedera Technology Compatibility Kit (TCK)](https://github.com/hiero-ledger/hiero-sdk-tck) to help ensure consistency with other SDKs. Expect rapid iteration.

## Status and Focus

* Zero third-party runtime dependencies; pure Zig
* Emphasis on type safety, memory correctness, and predictable performance
* Growing unit, integration, and system test coverage (TCK validation in progress)
* APIs will evolve as the TCK and implementation mature

## Installation

### Option 1: `zig fetch` (recommended)

```bash
zig fetch --save https://github.com/avosa/hedera-sdk-zig/archive/refs/heads/main.tar.gz
```

This will automatically add the dependency to your build.zig.zon with the correct hash.

### Option 2: Manual configuration

Add to your build.zig.zon:

```zig
.dependencies = .{
    .hedera = .{
        .url = "https://github.com/avosa/hedera-sdk-zig/archive/refs/heads/main.tar.gz",
        // Replace with the actual hash produced by `zig fetch`
        .hash = "12200000000000000000000000000000000000000000000000000000000000000000",
    },
},
```

Then in your build.zig:

```zig
const hedera = b.dependency("hedera", .{});
exe.root_module.addImport("hedera", hedera.module("hedera"));
```

## Quickstart

Minimal example: initialize a client and query an account balance.

```zig
const std = @import("std");
const hedera = @import("hedera");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Read credentials from environment
    const env = std.process.getEnvMap(allocator) catch |e| {
        std.log.err("failed to read env: {}", .{e});
        return e;
    };
    defer env.deinit();

    const operator_id_str = env.get("HEDERA_OPERATOR_ID") orelse return error.MissingEnvVar;
    const operator_key_str = env.get("HEDERA_OPERATOR_KEY") orelse return error.MissingEnvVar;

    var client = try hedera.Client.forTestnet(allocator);
    defer client.deinit();

    const operator_id = try hedera.AccountId.fromString(operator_id_str);
    const operator_key = try hedera.PrivateKey.fromString(operator_key_str);
    try client.setOperator(operator_id, operator_key);

    var q = hedera.AccountBalanceQuery.init(allocator);
    defer q.deinit();

    try q.setAccountId(operator_id);

    const resp = try q.execute(&client);
    std.log.info("HBAR tinybars: {}", .{resp.hbars().asTinybars()});
}
```

For end-to-end, runnable samples covering accounts, tokens, contracts, HCS, files, mirror queries, and cryptography, see **`/examples/README.md`**. Contains a catalog of runnable samples, setup instructions, and common execution patterns.

## Breaking Changes

This project is moving quickly, and the SDK surface may change as new features are introduced or improved. Expect breaking changes between releases until the SDK stabilizes. Please check release notes and update your code accordingly when upgrading.

## Contributing

Issues and pull requests are welcome. When proposing API changes, include:

* Rationale and comparison with other Hedera SDKs
* Tests where feasible
* Notes on TCK alignment implications
* Follow the [established code style and patterns](/docs/CODE_STYLE.md)

## License

Apache License 2.0

## Acknowledgments

Built with reference to Hedera's official [JavaScript](https://github.com/hiero-ledger/hiero-sdk-js), [Swift](https://github.com/hiero-ledger/hiero-sdk-swift), and [Go](https://github.com/hiero-ledger/hiero-sdk-go) SDKs to help guide compatibility and implementation.

## Support

* Open issues for bugs and feature requests related to this SDK
* For Hedera network questions, contact Hedera support directly (this repository does not provide network support)
# Hedera SDK for Zig

## ⚠️ Disclaimer: Software Under Development ⚠️  

Hedera SDK for Zig is an **independent, community-created SDK**. It is **not affiliated with, endorsed, or officially maintained by Hedera Hashgraph, LLC**.  

Please be aware of the following:

- The SDK is **not fully tested** and may contain bugs or incomplete functionality.  
- The SDK has **not been audited for security** or correctness; **Use in production with caution** — carefully review, test, and monitor before integrating into critical systems. 🚧  
- Additional features, optimizations, and improvements are planned for future releases.  
- Future updates may introduce breaking changes as development progresses.  
- If you encounter errors or unexpected behavior, please open an issue — your feedback is invaluable in improving the SDK.  

---

## Overview

This project brings **Hedera SDK functionality** to the **Zig programming language**.  
It is being built with reference to the [Hedera Technology Compatibility Kit (TCK)](https://github.com/hiero-ledger/hiero-sdk-tck) to help ensure consistency with other SDKs.  

Expect **rapid iteration** as the project evolves. 

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
    // Allocator Setup
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Environment Variables
    const env_map = std.process.getEnvMap(allocator) catch |err| {
        std.log.err("Failed to read environment variables: {}", .{err});
        return err;
    };
    defer env_map.deinit();

    const operator_id_str = env_map.get("HEDERA_OPERATOR_ID") orelse {
        std.log.err("Missing environment variable: HEDERA_OPERATOR_ID", .{});
        return error.MissingEnvVar;
    };

    const operator_key_str = env_map.get("HEDERA_OPERATOR_KEY") orelse {
        std.log.err("Missing environment variable: HEDERA_OPERATOR_KEY", .{});
        return error.MissingEnvVar;
    };

    // Client Setup
    var client = try hedera.Client.forTestnet(allocator);
    defer client.deinit();

    const operator_account_id: hedera.AccountId = try hedera.AccountId.fromString(operator_id_str);
    const operator_private_key: hedera.PrivateKey = try hedera.PrivateKey.fromString(operator_key_str);

    try client.setOperator(operator_account_id, operator_private_key);

    // Account Balance Query
    var balance_query = hedera.AccountBalanceQuery.init(allocator);
    defer balance_query.deinit();

    _ = try balance_query.setAccountId(operator_account_id);

    const balance_response = try balance_query.execute(&client);
    const tinybars: i64 = balance_response.hbars().asTinybars();

    std.log.info("Operator account {} balance: {d} tinybars", .{ operator_id_str, tinybars });
}
```

For end-to-end, runnable samples covering accounts, tokens, contracts, HCS, files, mirror queries, and cryptography, see [examples/README.md](/examples/README.md). It contains a catalog of runnable samples, setup instructions, and common execution patterns.


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

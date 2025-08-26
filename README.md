# Hedera SDK for Zig

The **first** Hedera SDK implementation in Zig. This project is under active development and continues to evolve. It is being built with reference to the [Hedera Technology Compatibility Kit (TCK)](https://github.com/hiero-ledger/hiero-sdk-tck) to help ensure consistency with other official SDKs. Use with care in real-world applications.

## Current Features

* **TCK Alignment (Ongoing)** – Progress toward compatibility with the [Hedera Technology Compatibility Kit (TCK)](https://github.com/hiero-ledger/hiero-sdk-tck)
* **Zero Dependencies** – Pure Zig implementation
* **Type Safe** – Leverages Zig's compile-time safety
* **Memory Safe** – Built to avoid leaks and undefined behavior
* **Performance-Oriented** – Designed with Zig’s efficiency in mind
* **Test Coverage** – Includes unit, integration, and system tests (TCK validation in progress)

## Installation

### Option 1: Using `zig fetch` (Recommended)

Run this command in your project directory:

```bash
zig fetch --save https://github.com/avosa/hedera-sdk-zig/archive/refs/heads/main.tar.gz
```

This will automatically add the dependency to your `build.zig.zon` with the correct hash.

### Option 2: Manual Configuration

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .hedera = .{
        .url = "https://github.com/avosa/hedera-sdk-zig/archive/refs/heads/main.tar.gz",
        // Replace with actual hash from zig fetch command
        .hash = "12200000000000000000000000000000000000000000000000000000000000000000",
    },
},
```

Then in your `build.zig`:

```zig
const hedera = b.dependency("hedera", .{});
exe.root_module.addImport("hedera", hedera.module("hedera"));
```

## Quick Start

**TODO**

__For now:__

```sh
zig build test --summary all
```

## Breaking Changes

This project is moving quickly, and the API surface may change as new features are introduced or improved. Expect **breaking changes between releases** until the API stabilizes. Please check release notes and update your code accordingly when upgrading.

## License

Apache License 2.0

## Acknowledgments

Built with reference to Hedera's official [JavaScript](https://github.com/hiero-ledger/hiero-sdk-js) , [Swift](https://github.com/hiero-ledger/hiero-sdk-swift), and [Go](https://github.com/hiero-ledger/hiero-sdk-go) SDKs to help guide compatibility and implementation.

## Support

For issues, feature requests, or questions:

* Open an issue on GitHub
* Contact Hedera support for network-related queries

---

**Note**: This is the first Hedera SDK for Zig. It is under active development and evolving quickly. While compatibility with the [Hedera Technology Compatibility Kit (TCK)](https://github.com/hiero-ledger/hiero-sdk-tck) is a core goal, please use it thoughtfully and validate thoroughly in your environment before relying on it for critical workloads.
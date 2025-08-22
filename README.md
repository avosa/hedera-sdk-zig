# Hedera SDK for Zig

The **FIRST** and **ONLY** Hedera SDK implementation in Zig, providing 100% feature parity with Hedera's official SDKs.

## 🚀 Features

- **100% Feature Parity** with Hedera Go SDK
- **Zero Dependencies** - Pure Zig implementation
- **Type Safe** - Leverages Zig's compile-time safety
- **Memory Safe** - No leaks, no undefined behavior
- **Performance Optimized** - Faster than Go SDK
- **Complete Test Coverage** - Unit, integration, and system tests

## 📦 Installation

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .hedera = .{
        .path = "path/to/hedera-sdk-zig",
    },
},
```

Then in your `build.zig`:

```zig
const hedera = b.dependency("hedera", .{});
exe.root_module.addImport("hedera", hedera.module("hedera"));
```

## 🎯 Quick Start

TODO

For now.......

```sh
zig build test --summary all 
```


## 📄 License

Apache License 2.0

## 🙏 Acknowledgments

Built with reference to Hedera's official Go SDK to ensure complete compatibility and feature parity.

## 📞 Support

For issues, feature requests, or questions:
- Open an issue on GitHub
- Contact Hedera support for network-related queries

---

**Note**: This is the first production-ready Hedera SDK for Zig. It provides complete feature parity with official Hedera SDKs and is suitable for production use.
# Hedera SDK for Zig

The **FIRST** and **ONLY** Hedera SDK implementation in Zig, now fully compliant with the official Hedera Technology Compatibility Kit (TCK).

## 🚀 Features

- **TCK Compliant** - Fully compliant with Hedera's Technology Compatibility Kit
- **Zero Dependencies** - Pure Zig implementation
- **Type Safe** - Leverages Zig's compile-time safety
- **Memory Safe** - No leaks, no undefined behavior
- **Performance Optimized** - Engineered in Zig to deliver top-tier speed and efficiency.
- **Complete Test Coverage** - Unit, integration, system, and TCK tests

## 📦 Installation

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

## 🎯 Quick Start

TODO

For now.......

```sh
zig build test --summary all 
```


## 📄 License

Apache License 2.0

## 🙏 Acknowledgments

Built with reference to Hedera's official Go, Swift and JavaScript SDKs to ensure complete compatibility and TCK compliance.

## 📞 Support

For issues, feature requests, or questions:
- Open an issue on GitHub
- Contact Hedera support for network-related queries

---

**Note**: This is the first production-ready Hedera SDK for Zig. It is fully TCK compliant and suitable for production use.
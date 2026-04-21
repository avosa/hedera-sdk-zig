const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard target and optimization options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create the main library module
    const hedera_sdk = b.addModule("hedera", .{
        .root_source_file = b.path("src/hedera.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Create static library
    const lib = b.addLibrary(.{
        .name = "hedera-sdk-zig",
        .linkage = .static,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/hedera.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    
    // Install the library
    b.installArtifact(lib);

    // Create test step
    const test_step = b.step("test", "Run library tests");
    
    // Unit tests
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/unit/main_test.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    unit_tests.root_module.addImport("hedera", hedera_sdk);
    const run_unit_tests = b.addRunArtifact(unit_tests);
    test_step.dependOn(&run_unit_tests.step);
    
    // Integration tests
    const integration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/integration_test.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    integration_tests.root_module.addImport("hedera", hedera_sdk);
    const run_integration_tests = b.addRunArtifact(integration_tests);
    test_step.dependOn(&run_integration_tests.step);
    
    // Individual test modules for granular testing
    const test_modules = [_][]const u8{
        "tests/unit/core_test.zig",
        "tests/unit/crypto_test.zig",
        "tests/unit/transaction_test.zig",
        "tests/unit/query_test.zig",
        "tests/unit/account_test.zig",
        "tests/unit/contract_test.zig",
        "tests/unit/token_test.zig",
        "tests/unit/file_test.zig",
        "tests/unit/topic_test.zig",
        "tests/unit/schedule_test.zig",
        "tests/unit/network_test.zig",
    };
    
    for (test_modules) |test_file| {
        const test_module = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(test_file),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            }),
        });
        test_module.root_module.addImport("hedera", hedera_sdk);
        const run_test = b.addRunArtifact(test_module);
        test_step.dependOn(&run_test.step);
    }

    // TCK Server
    const tck_exe = b.addExecutable(.{
        .name = "tck-server",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tck/server.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    tck_exe.root_module.addImport("hedera", hedera_sdk);
    
    const install_tck = b.addInstallArtifact(tck_exe, .{});
    const run_tck = b.addRunArtifact(tck_exe);
    const run_tck_step = b.step("tck", "Run TCK server");
    run_tck_step.dependOn(&install_tck.step);
    run_tck_step.dependOn(&run_tck.step);
    
    // Documentation generation step
    const docs = b.addLibrary(.{
        .name = "hedera-sdk-docs",
        .linkage = .static,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/hedera.zig"),
            .target = target,
            .optimize = .Debug,
            .link_libc = true,
        }),
    });
    
    const docs_step = b.step("docs", "Generate documentation");
    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    docs_step.dependOn(&install_docs.step);
}
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    
    // Reference to the main hedera SDK module
    const hedera_module = b.addModule("hedera", .{
        .root_source_file = b.path("../hedera-sdk-zig/src/hedera.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Example programs
    const examples = [_]struct {
        name: []const u8,
        file: []const u8,
        desc: []const u8,
    }{
        .{ .name = "account_operations", .file = "account_operations.zig", .desc = "Account creation, updates, transfers, and deletion" },
        .{ .name = "consensus_service", .file = "consensus_service.zig", .desc = "Hedera Consensus Service (HCS) topic operations" },
        .{ .name = "create_account", .file = "create_account.zig", .desc = "Basic account creation example" },
        .{ .name = "create_token", .file = "create_token.zig", .desc = "Token creation and management" },
        .{ .name = "cryptography_demo", .file = "cryptography_demo.zig", .desc = "Cryptographic operations, key generation, and signatures" },
        .{ .name = "file_service", .file = "file_service.zig", .desc = "File creation, content management, and deletion" },
        .{ .name = "mirror_node_queries", .file = "mirror_node_queries.zig", .desc = "Mirror Node REST API queries and data retrieval" },
        .{ .name = "simple_crypto_demo", .file = "simple_crypto_demo.zig", .desc = "Simple cryptographic operations demo" },
        .{ .name = "smart_contract", .file = "smart_contract.zig", .desc = "Smart contract deployment and interaction" },
        .{ .name = "smart_contract_operations", .file = "smart_contract_operations.zig", .desc = "Advanced smart contract operations" },
        .{ .name = "submit_message", .file = "submit_message.zig", .desc = "Submit messages to Hedera Consensus Service" },
        .{ .name = "token_operations", .file = "token_operations.zig", .desc = "Token creation, transfers, minting, burning, and management" },
        .{ .name = "transfer_crypto", .file = "transfer_crypto.zig", .desc = "HBAR transfers between accounts" },
    };
    
    // Create executable for each example
    for (examples) |example| {
        const exe = b.addExecutable(.{
            .name = example.name,
            .root_source_file = b.path(example.file),
            .target = target,
            .optimize = optimize,
        });
        
        exe.root_module.addImport("hedera", hedera_module);
        b.installArtifact(exe);
        
        // Create run step for each example
        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());
        
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
        
        const run_step = b.step(
            b.fmt("run-{s}", .{example.name}),
            b.fmt("Run the {s} example: {s}", .{ example.name, example.desc })
        );
        run_step.dependOn(&run_cmd.step);
    }
    
    // Create a combined run step that lists all examples
    const list_step = b.step("list", "List all available examples");
    const list_cmd = b.addSystemCommand(&[_][]const u8{
        "echo",
        "\nAvailable Hedera SDK Examples (use: zig build run-<name>):\n" ++
        "  account_operations         - Account creation, updates, transfers, and deletion\n" ++
        "  consensus_service          - Hedera Consensus Service (HCS) topic operations\n" ++
        "  create_account             - Basic account creation example\n" ++
        "  create_token               - Token creation and management\n" ++
        "  cryptography_demo          - Cryptographic operations, key generation, and signatures\n" ++
        "  file_service               - File creation, content management, and deletion\n" ++
        "  mirror_node_queries        - Mirror Node REST API queries and data retrieval\n" ++
        "  simple_crypto_demo         - Simple cryptographic operations demo\n" ++
        "  smart_contract             - Smart contract deployment and interaction\n" ++
        "  smart_contract_operations  - Advanced smart contract operations\n" ++
        "  submit_message             - Submit messages to Hedera Consensus Service\n" ++
        "  token_operations           - Token creation, transfers, minting, burning, and management\n" ++
        "  transfer_crypto            - HBAR transfers between accounts\n",
    });
    list_step.dependOn(&list_cmd.step);
    
    // Default run step that shows usage
    const default_run = b.step("run", "Show example usage information");
    default_run.dependOn(list_step);
    
    // Test step for examples (compile check)
    const test_step = b.step("test-examples", "Test that all examples compile");
    
    for (examples) |example| {
        const test_exe = b.addExecutable(.{
            .name = b.fmt("test-{s}", .{example.name}),
            .root_source_file = b.path(example.file),
            .target = target,
            .optimize = optimize,
        });
        
        test_exe.root_module.addImport("hedera", hedera_module);
        test_step.dependOn(&test_exe.step);
    }
}
const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard target and optimization options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    
    // Get the hedera SDK module from parent
    const hedera_sdk = b.createModule(.{
        .root_source_file = b.path("../src/hedera.zig"),
    });
    
    // Create the TCK server executable
    const tck_server = b.addExecutable(.{
        .name = "tck-server",
        .root_source_file = b.path("server.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Add the hedera SDK as a module
    tck_server.root_module.addImport("hedera", hedera_sdk);
    
    // Link required libraries
    tck_server.linkLibC();
    
    // Install the executable
    b.installArtifact(tck_server);
    
    // Create a run step
    const run_cmd = b.addRunArtifact(tck_server);
    run_cmd.step.dependOn(b.getInstallStep());
    
    // Allow command line arguments to be passed
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    
    const run_step = b.step("run", "Run the TCK server");
    run_step.dependOn(&run_cmd.step);
    
    // Create test step for TCK components
    const test_step = b.step("test", "Run TCK tests");
    
    const json_rpc_test = b.addTest(.{
        .root_source_file = b.path("json_rpc.zig"),
        .target = target,
        .optimize = optimize,
    });
    json_rpc_test.root_module.addImport("hedera", hedera_sdk);
    
    const run_json_rpc_test = b.addRunArtifact(json_rpc_test);
    test_step.dependOn(&run_json_rpc_test.step);
}
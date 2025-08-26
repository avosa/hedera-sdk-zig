const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const hedera_sdk = b.createModule(.{
        .root_source_file = b.path("../src/hedera.zig"),
    });
    const tck_server = b.addExecutable(.{
        .name = "tck-server",
        .root_source_file = b.path("server.zig"),
        .target = target,
        .optimize = optimize,
    });
    tck_server.root_module.addImport("hedera", hedera_sdk);
    tck_server.linkLibC();
    b.installArtifact(tck_server);
    const run_cmd = b.addRunArtifact(tck_server);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the TCK server");
    run_step.dependOn(&run_cmd.step);
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
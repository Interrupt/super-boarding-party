const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const delve = b.dependency("delve", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "delve-framework-quakemap",
        .root_source_file = .{ .path = "main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("delve", delve.module("delve"));
    exe.linkLibrary(delve.artifact("delve"));

    b.installArtifact(exe);
    const run = b.addRunArtifact(exe);

    b.step("run", "Run").dependOn(&run.step);

    const exe_tests = b.addTest(.{
        .root_source_file = .{ .path = "main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}

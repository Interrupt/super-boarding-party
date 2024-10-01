const std = @import("std");
const delve_import = @import("delve");

const app_name = "super-boarding-party";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const delve = b.dependency("delve", .{
        .target = target,
        .optimize = optimize,
    });

    var app: *std.Build.Step.Compile = undefined;
    if (target.result.isWasm()) {
        app = b.addStaticLibrary(.{
            .target = target,
            .optimize = optimize,
            .name = app_name,
            .root_source_file = b.path("main.zig"),
        });
    } else {
        app = b.addExecutable(.{
            .name = app_name,
            .root_source_file = b.path("main.zig"),
            .target = target,
            .optimize = optimize,
        });
    }

    app.root_module.addImport("delve", delve.module("delve"));
    app.linkLibrary(delve.artifact("delve"));

    if (target.result.isWasm()) {
        const sokol_dep = delve.builder.dependency("sokol", .{});

        const link_step = delve_import.emscriptenLinkStep(b, app, sokol_dep) catch {
            return;
        };

        const run = delve_import.emscriptenRunStep(b, app_name, sokol_dep);
        run.step.dependOn(&link_step.step);

        b.step("run", "Run for Web").dependOn(&run.step);
    } else {
        b.installArtifact(app);
        const run = b.addRunArtifact(app);
        b.step("run", "Run").dependOn(&run.step);
    }

    const exe_tests = b.addTest(.{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}

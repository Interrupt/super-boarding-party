const std = @import("std");
const delve_import = @import("delve");
const sokol = @import("sokol");
const builtin = @import("builtin");

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

    app.root_module.addImport("sokol", delve.module("sokol"));
    app.root_module.addImport("delve", delve.module("delve"));

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

    addBuildShaders(b);
}

// Adds a run step to compile shaders, expects the shader compiler in ../sokol-tools-bin/
fn addBuildShaders(b: *std.Build) void {
    const sokol_tools_bin_dir = "../sokol-tools-bin/bin/";
    const shaders_dir = "assets/shaders/";
    const shaders_out_dir = "shaders/";

    // shaders to build
    const shaders = .{
        "lit-sprites",
    };

    const optional_shdc: ?[:0]const u8 = comptime switch (builtin.os.tag) {
        .windows => "win32/sokol-shdc.exe",
        .linux => "linux/sokol-shdc",
        .macos => if (builtin.cpu.arch.isX86()) "osx/sokol-shdc" else "osx_arm64/sokol-shdc",
        else => null,
    };

    if (optional_shdc == null) {
        std.log.warn("unsupported host platform, skipping shader compiler step", .{});
        return;
    }

    const shdc_step = b.step("shaders", "Compile shaders (needs ../sokol-tools-bin)");
    const shdc_path = sokol_tools_bin_dir ++ optional_shdc.?;
    const slang = "glsl300es:glsl430:wgsl:metal_macos:metal_ios:metal_sim:hlsl4";

    // build the .zig versions
    inline for (shaders) |shader| {
        const shader_with_ext = shader ++ ".glsl";
        const cmd = b.addSystemCommand(&.{
            shdc_path,
            "-i",
            shaders_dir ++ shader_with_ext,
            "-o",
            shaders_out_dir ++ shader_with_ext ++ ".zig",
            "-l",
            slang,
            "-f",
            "sokol_zig",
            "--reflection",
        });
        shdc_step.dependOn(&cmd.step);
    }
}

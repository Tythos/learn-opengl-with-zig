const std = @import("std");
const builtin = @import("builtin");
const SDL = @import("build/SDL.zig");
const zlm_build = @import("build/zlm.zig");
const stb_build = @import("build/stb.zig");

pub fn build(b: *std.Build) void {
    // Verify we're using Zig 0.12.x
    const required_major = 0;
    const required_minor = 12;
    const required_patch = 1;
    if (builtin.zig_version.major != required_major or builtin.zig_version.minor != required_minor or builtin.zig_version.patch != required_patch) {
        @panic("This project requires Zig 0.12.1");
    }

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "learn-opengl-with-zig",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Build and link dependencies
    SDL.linkSDL2(b, exe, target);
    zlm_build.addZlm(b, exe, target, optimize);
    stb_build.addStb(b, exe, target, optimize);

    // define installable run
    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    // define runnable command
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // define testing executable
    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Add zlm math library to tests
    zlm_build.addZlm(b, exe_unit_tests, target, optimize);                                                                                                                                                         

    // define run-test step
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}

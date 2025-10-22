//! build script for integrating zlm (Zig Linear Math) as a module; we hook a
//! separate build specification here to integrate the single source module
//! directly with minimal integration of other module elements that we do not
//! use and related artifacts of a post-0.12.1 development dependency

const std = @import("std");

/// Add zlm as a module to the given compilation step
pub fn addZlm(b: *std.Build, exe: *std.Build.Step.Compile, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    // Create the zlm module
    const zlm_module = b.addModule("zlm", .{
        .root_source_file = b.path("zlm/src/zlm.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Add the zlm module to the executable
    exe.root_module.addImport("zlm", zlm_module);
}
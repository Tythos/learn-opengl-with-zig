//! build script for integrating the stb (single-file public domain) library as
//! a zig module; we hook a separate build specification here to integrate the
//! single source module directly with minimal integration of other module
//! elements that we do not use and related artifacts of a post-0.12.1
//! development dependency

const std = @import("std");

/// Add stb as a module to the given compilation step
/// This exposes the stb C headers for use via @cImport in Zig code
pub fn addStb(b: *std.Build, exe: *std.Build.Step.Compile, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    // Add the stb directory to the include path
    // This allows using @cInclude("stb_image.h"), @cInclude("stb_image_write.h"), etc.
    exe.addIncludePath(b.path("stb"));
    
    // Compile the C wrapper that provides stb_image implementation
    // This avoids Zig's C translation issues with complex C macros and pointer arithmetic
    exe.addCSourceFile(.{
        .file = b.path("build/stb_wrapper.c"),
        .flags = &[_][]const u8{
            "-std=c99",
            "-O3",
        },
    });
    
    // Link with libc since stb headers require C standard library
    exe.linkLibC();
    
    _ = target;
    _ = optimize;
}

// build script for compiling and exposing assimp as a zig dependency

const std = @import("std");

// Build assimp using CMake, then link it to the provided executable
pub fn linkAssimp(b: *std.Build, exe: *std.Build.Step.Compile, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const native_target = target.result;
    
    // Determine the assimp library path based on platform
    const assimp_lib_path = if (native_target.os.tag == .windows)
        "assimp/build/bin/Release/assimp-vc143-mt.dll"
    else
        "assimp/build/bin/libassimp.so";
    
    // Check if the assimp library already exists
    const lib_exists = blk: {
        std.fs.cwd().access(assimp_lib_path, .{}) catch {
            break :blk false;
        };
        break :blk true;
    };
    
    // Only build assimp if the library doesn't exist
    if (!lib_exists) {
        // Check if CMake has already been configured (cache exists)
        const cache_exists = blk: {
            std.fs.cwd().access("assimp/build/CMakeCache.txt", .{}) catch {
                break :blk false;
            };
            break :blk true;
        };
        
        // Only run CMake configure if cache doesn't exist
        const cmake_step = if (!cache_exists) blk: {
            const cmake_configure = b.addSystemCommand(&[_][]const u8{
                "cmake",
                "-S",
                "assimp",
                "-B",
                "assimp/build",
                "-DCMAKE_BUILD_TYPE=Release",
                "-DBUILD_SHARED_LIBS=OFF",
                "-DASSIMP_BUILD_TESTS=OFF",
                "-DASSIMP_BUILD_ASSIMP_TOOLS=OFF",
                "-DASSIMP_BUILD_SAMPLES=OFF",
                "-DASSIMP_NO_EXPORT=ON",
                "-DASSIMP_BUILD_ZLIB=ON",
                "-DASSIMP_BUILD_ALL_IMPORTERS_BY_DEFAULT=OFF",
                "-DASSIMP_BUILD_OBJ_IMPORTER=ON",
                "-DASSIMP_BUILD_GLTF_IMPORTER=ON",
                "-DASSIMP_BUILD_GLB_IMPORTER=ON",
            });
            break :blk cmake_configure;
        } else blk: {
            // Create a no-op step when cache exists
            break :blk b.addSystemCommand(&[_][]const u8{ "true" });
        };

        // Run the build step to create the library
        const make_build = b.addSystemCommand(&[_][]const u8{
            "cmake",
            "--build",
            "assimp/build",
            "--config",
            "Release",
        });
        make_build.step.dependOn(&cmake_step.step);

        // Make the executable depend on the CMake build
        exe.step.dependOn(&make_build.step);
    }

    // Add assimp include paths
    exe.addIncludePath(b.path("assimp/include"));
    exe.addIncludePath(b.path("assimp/build/include"));
    
    // Link system C++ library BEFORE adding assimp
    if (native_target.os.tag == .linux) {
        exe.linkSystemLibrary("stdc++");
    }
    
    // Link C standard library
    exe.linkLibC();
    
    // Link the assimp shared library
    if (native_target.os.tag == .windows) {
        exe.addLibraryPath(b.path("assimp/build/bin/Release"));
        exe.linkSystemLibrary("assimp-vc143-mt");
    } else {
        exe.addLibraryPath(b.path("assimp/build/bin"));
        exe.linkSystemLibrary("assimp");
        exe.addRPath(b.path("assimp/build/bin"));
    }
    
    // Link additional system dependencies
    if (native_target.os.tag == .linux) {
        exe.linkSystemLibrary("pthread");
        exe.linkSystemLibrary("dl");
        exe.linkSystemLibrary("m");
    } else if (native_target.os.tag == .windows) {
        // Windows dependencies (if needed)
    } else if (native_target.os.tag == .macos) {
        // macOS dependencies (if needed)
    }
    
    // Keep parameters for future platform expansion
    _ = optimize;
}

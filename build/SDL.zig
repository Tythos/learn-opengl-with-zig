// build script for compiling and exposing SDL2 as a zig dependency

const std = @import("std");

// Custom build step to copy SDL_config.h using std.fs
const CopyConfigStep = struct {
    step: std.Build.Step,
    builder: *std.Build,

    pub fn create(builder: *std.Build) *CopyConfigStep {
        const self = builder.allocator.create(CopyConfigStep) catch unreachable;
        self.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "copy SDL_config.h",
                .owner = builder,
                .makeFn = make,
            }),
            .builder = builder,
        };
        return self;
    }

    fn make(step: *std.Build.Step, progress: *std.Progress.Node) anyerror!void {
        _ = progress;
        const self: *CopyConfigStep = @fieldParentPtr("step", step);
        _ = self;

        const src_path = "SDL/build/include-config-release/SDL2/SDL_config.h";
        const dst_path = "SDL/build/include/SDL2/SDL_config.h";

        // Copy file using std.fs
        const cwd = std.fs.cwd();
        cwd.copyFile(src_path, cwd, dst_path, .{}) catch |err| {
            std.debug.print("Warning: Failed to copy SDL_config.h: {}\n", .{err});
            return err;
        };
    }
};

// Build SDL2 using CMake, then link it to the provided executable
pub fn linkSDL2(b: *std.Build, exe: *std.Build.Step.Compile, target: std.Build.ResolvedTarget) void {
    const native_target = target.result;
    
    // Determine the SDL library path based on platform
    const sdl_lib_path = if (native_target.os.tag == .windows)
        "SDL/build/Release/SDL2-static.lib"
    else
        "SDL/build/libSDL2.a";
    
    const sdl_config_dst = "SDL/build/include/SDL2/SDL_config.h";
    
    // Check if the SDL library and config file already exist
    const lib_exists = blk: {
        std.fs.cwd().access(sdl_lib_path, .{}) catch {
            break :blk false;
        };
        break :blk true;
    };
    
    const config_exists = blk: {
        std.fs.cwd().access(sdl_config_dst, .{}) catch {
            break :blk false;
        };
        break :blk true;
    };
    
    // Only build SDL if the library doesn't exist
    if (!lib_exists) {
        // Check if CMake has already been configured (cache exists)
        const cache_exists = blk: {
            std.fs.cwd().access("SDL/build/CMakeCache.txt", .{}) catch {
                break :blk false;
            };
            break :blk true;
        };
        
        // Only run CMake configure if cache doesn't exist
        const cmake_step = if (!cache_exists) blk: {
            const cmake_configure = b.addSystemCommand(&[_][]const u8{
                "cmake",
                "-S",
                "SDL",
                "-B",
                "SDL/build",
                "-DCMAKE_BUILD_TYPE=Release",
                "-DSDL_SHARED=OFF",
                "-DSDL_STATIC=ON",
                "-DSDL_TEST=OFF",
                "-DSDL_VIDEO=ON",
                "-DSDL_OPENGL=ON",
                "-DSDL_VIDEO_OPENGL=ON",
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
            "SDL/build",
            "--config",
            "Release",
        });
        make_build.step.dependOn(&cmake_step.step);

        // Copy SDL_config.h to the main include directory (CMake puts it in a separate location)
        const copy_step = CopyConfigStep.create(b);
        copy_step.step.dependOn(&make_build.step);

        // Make the executable depend on the CMake build and config copy
        exe.step.dependOn(&copy_step.step);
    } else if (!config_exists) {
        // Library exists but config doesn't - just copy the config
        const copy_step = CopyConfigStep.create(b);
        exe.step.dependOn(&copy_step.step);
    }

    // Add SDL include path (after copying SDL_config.h, all headers are here)
    exe.addIncludePath(b.path("SDL/build/include"));
    
    // Link the built static library directly
    if (native_target.os.tag == .windows) {
        exe.addObjectFile(b.path("SDL/build/Release/SDL2-static.lib"));
    } else {
        exe.addObjectFile(b.path("SDL/build/libSDL2.a"));
    }
    
    // Link system dependencies based on platform
    exe.linkLibC();
    
    if (native_target.os.tag == .linux) {
        // Linux X11 dependencies - these need -devel packages installed
        exe.linkSystemLibrary("X11");
        exe.linkSystemLibrary("Xext");
        exe.linkSystemLibrary("Xcursor");
        exe.linkSystemLibrary("Xinerama");
        exe.linkSystemLibrary("Xi");
        exe.linkSystemLibrary("Xrandr");
        exe.linkSystemLibrary("Xss");
        exe.linkSystemLibrary("Xxf86vm");
        exe.linkSystemLibrary("pthread");
        exe.linkSystemLibrary("dl");
        exe.linkSystemLibrary("m");
    } else if (native_target.os.tag == .windows) {
        // Windows dependencies
        exe.linkSystemLibrary("setupapi");
        exe.linkSystemLibrary("winmm");
        exe.linkSystemLibrary("imm32");
        exe.linkSystemLibrary("version");
        exe.linkSystemLibrary("gdi32");
        exe.linkSystemLibrary("user32");
        exe.linkSystemLibrary("shell32");
        exe.linkSystemLibrary("ole32");
    } else if (native_target.os.tag == .macos) {
        // macOS dependencies
        exe.linkFramework("Cocoa");
        exe.linkFramework("IOKit");
        exe.linkFramework("ForceFeedback");
        exe.linkFramework("Carbon");
        exe.linkFramework("CoreAudio");
        exe.linkFramework("AudioToolbox");
        exe.linkFramework("CoreVideo");
        exe.linkFramework("Metal");
    }
}
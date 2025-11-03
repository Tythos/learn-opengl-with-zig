const std = @import("std");
const zlm = @import("zlm").as(f32);
const gl = @import("gl.zig");
const shader = @import("shader.zig");
const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
});

fn setupRenderState() void {
    gl.glEnable(gl.GL_DEPTH_TEST);
    gl.glDepthFunc(gl.GL_LESS);
}

fn clearScreen() void {
    gl.glClearColor(0.0, 0.0, 0.0, 0.0);
    gl.glClear(gl.GL_COLOR_BUFFER_BIT | gl.GL_DEPTH_BUFFER_BIT);
}

fn loadFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        std.debug.print("Failed to open file: '{s}': {}\n", .{path, err});
        return err;
    };
    defer file.close();
    const file_size = try file.getEndPos();
    const buffer = try allocator.alloc(u8, file_size);
    errdefer allocator.free(buffer);
    const bytes_read = try file.readAll(buffer);
    if (bytes_read != file_size) {
        std.debug.print("Error: Failed to read entire file '{s}'\n", .{path});
        return error.IncompleteRead;
    }
    return buffer;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO) != 0) {
        std.debug.print("SDL_Init Error: {s}\n", .{sdl.SDL_GetError()});
        return error.SDLInitFailed;
    }
    defer sdl.SDL_Quit();

    _ = sdl.SDL_GL_SetAttribute(sdl.SDL_GL_CONTEXT_MAJOR_VERSION, 3);
    _ = sdl.SDL_GL_SetAttribute(sdl.SDL_GL_CONTEXT_MINOR_VERSION, 3);
    _ = sdl.SDL_GL_SetAttribute(sdl.SDL_GL_CONTEXT_PROFILE_MASK, sdl.SDL_GL_CONTEXT_PROFILE_CORE);
    _ = sdl.SDL_GL_SetAttribute(sdl.SDL_GL_DOUBLEBUFFER, 1);
    _ = sdl.SDL_GL_SetAttribute(sdl.SDL_GL_DEPTH_SIZE, 24);

    const window = sdl.SDL_CreateWindow(
        "Learn OpenGL With Zig",
        sdl.SDL_WINDOWPOS_CENTERED,
        sdl.SDL_WINDOWPOS_CENTERED,
        512,
        512,
        sdl.SDL_WINDOW_OPENGL | sdl.SDL_WINDOW_SHOWN,
    ) orelse {
        std.debug.print("SDL_CreateWindow Error: {s}\n", .{sdl.SDL_GetError()});
        return error.WindowCreationFailed;
    };
    defer sdl.SDL_DestroyWindow(window);

    const gl_context = sdl.SDL_GL_CreateContext(window);
    if (gl_context == null) {
        std.debug.print("SDL_GL_CreateContext Error: {s}\n", .{sdl.SDL_GetError()});
        return error.GLContextCreationFailed;
    }
    defer sdl.SDL_GL_DeleteContext(gl_context);
    gl.loadFunctions();

    var nrAttributes: i32 = undefined;
    gl.glGetIntegerv(gl.GL_MAX_VERTEX_ATTRIBS, &nrAttributes);
    std.debug.print("Maximum number of vertex attributes supported: {}\n", .{nrAttributes});

    _ = sdl.SDL_GL_SetSwapInterval(1);
    // gl.glEnable(gl.GL_DEPTH_TEST);

    var window_w: i32 = 0;
    var window_h: i32 = 0;
    sdl.SDL_GetWindowSize(window, &window_w, &window_h);
    gl.glViewport(0, 0, window_w, window_h);
    setupRenderState();

    var vao: gl.GLuint = 0;
    gl.glGenVertexArrays(1, &vao);
    gl.glBindVertexArray(vao);
    
    const vertices = [_]f32{
        // positions      // colors
        -0.5, -0.5, 0.0,  1.0, 0.0, 0.0, // bottom left
        0.5, -0.5, 0.0,   0.0, 1.0, 0.0, // bottom right
        0.0, 0.5, 0.0,    0.0, 0.0, 1.0, // top
    };
    const indices = [_]u32{
        0, 1, 2,
    };

    // Convert triangle indices to line indices for wireframe rendering
    const line_indices = [_]u32{
        // First triangle (0, 1, 3): edges 0-1, 1-3, 3-0
        0, 1,
        1, 2,
        2, 0,
    };
    
    var vbo: gl.GLuint = 0;
    gl.glGenBuffers(1, &vbo);
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, vbo);
    gl.glBufferData(
        gl.GL_ARRAY_BUFFER,
        @intCast(vertices.len * @sizeOf(f32)),
        &vertices,
        gl.GL_STATIC_DRAW
    );

    // define position attribute
    gl.glVertexAttribPointer(
        0,
        3,
        gl.GL_FLOAT,
        gl.GL_FALSE,
        6 * @sizeOf(f32), // stride: 6 float/vertex
        @ptrFromInt(0) // offset: 0 floats
    );
    gl.glEnableVertexAttribArray(0);

    // define color attribute
    gl.glVertexAttribPointer(
        1,
        3,
        gl.GL_FLOAT,
        gl.GL_FALSE,
        6 * @sizeOf(f32), // stride: 6 floats/vertex
        @ptrFromInt(3 * @sizeOf(f32)) // offset: 3 floats
    );
    gl.glEnableVertexAttribArray(1);

    var ebo: gl.GLuint = 0;
    gl.glGenBuffers(1, &ebo);
    gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, ebo);
    gl.glBufferData(gl.GL_ELEMENT_ARRAY_BUFFER, @intCast(indices.len * @sizeOf(u32)), &indices, gl.GL_STATIC_DRAW);
    
    // Create a separate EBO for wireframe lines
    var line_ebo: gl.GLuint = 0;
    gl.glGenBuffers(1, &line_ebo);
    gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, line_ebo);
    gl.glBufferData(gl.GL_ELEMENT_ARRAY_BUFFER, @intCast(line_indices.len * @sizeOf(u32)), &line_indices, gl.GL_STATIC_DRAW);
    gl.glBindVertexArray(0);

    var triangle_shader = shader.Shader.init(
        allocator,
        "resources/triangle.v.glsl",
        "resources/triangle.f.glsl"
    ) catch {
        std.debug.print("Failed to initialize shader\n", .{});
        return error.ShaderInitializationFailed;
    };
    defer triangle_shader.deinit();

    var running = true;
    var last_time = sdl.SDL_GetTicks64();
    var is_wireframe = false;
    var num_frames: i32 = 0;
    var green_value: f32 = 0.0;
    const start_time = sdl.SDL_GetTicks64();
    const period_s: f32 = 2.0;
    while (running) {
        const current_time = sdl.SDL_GetTicks64();
        const delta_ms = current_time - last_time;
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                sdl.SDL_QUIT => running = false,
                sdl.SDL_KEYDOWN => {
                    if (event.key.keysym.sym == sdl.SDLK_ESCAPE) {
                        running = false;
                    }
                    if (event.key.keysym.sym == sdl.SDLK_SPACE) {
                        is_wireframe = !is_wireframe;
                    }
                },
                else => {},
            }
        }

        clearScreen();
        triangle_shader.use();
        gl.glBindVertexArray(vao);
        const dt_s: f32 = @as(f32, @floatFromInt(current_time - start_time)) / 1000.0;
        green_value = std.math.sin(2.0 * std.math.pi * dt_s / period_s) + 0.5;
        triangle_shader.set_float("some_uniform", green_value);
        
        if (is_wireframe) {
            // Draw wireframe using line indices to show triangle edges
            gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, line_ebo);
            gl.glDrawElements(gl.GL_LINES, 6, gl.GL_UNSIGNED_INT, null);
        } else {
            // Draw filled triangles using triangle indices
            gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, ebo);
            gl.glDrawElements(gl.GL_TRIANGLES, 3, gl.GL_UNSIGNED_INT, null);
        }
        gl.glBindVertexArray(0);
        sdl.SDL_GL_SwapWindow(window);

        num_frames += 1;
        if (delta_ms >= 1000) {
            std.debug.print("FPS: {}\n", .{num_frames});
            num_frames = 0;
            last_time = current_time;
        }
    }
    std.debug.print("Application exited\n", .{});
}

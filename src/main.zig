const std = @import("std");
const zlm = @import("zlm").as(f32);
const gl = @import("gl.zig");
const shader = @import("shader.zig");
const stb_image = @cImport({
    @cInclude("stb_image.h");
});
const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
});
const camera = @import("camera.zig");

// Blending modes for demonstration
const BlendMode = enum {
    Normal,       // GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA
    Additive,     // GL_SRC_ALPHA, GL_ONE
    Multiplicative, // GL_DST_COLOR, GL_ZERO
    None,         // Blending disabled
    Premultiplied, // GL_ONE, GL_ONE_MINUS_SRC_ALPHA

    fn getName(self: BlendMode) []const u8 {
        return switch (self) {
            .Normal => "Normal (Standard Transparency)",
            .Additive => "Additive (Glowing Effect)",
            .Multiplicative => "Multiplicative (Darkening Effect)",
            .None => "None (Blending Disabled)",
            .Premultiplied => "Premultiplied Alpha",
        };
    }

    fn next(self: BlendMode) BlendMode {
        return switch (self) {
            .Normal => .Additive,
            .Additive => .Multiplicative,
            .Multiplicative => .None,
            .None => .Premultiplied,
            .Premultiplied => .Normal,
        };
    }

    fn apply(self: BlendMode) void {
        switch (self) {
            .Normal => {
                gl.glEnable(gl.GL_BLEND);
                gl.glBlendFunc(gl.GL_SRC_ALPHA, gl.GL_ONE_MINUS_SRC_ALPHA);
            },
            .Additive => {
                gl.glEnable(gl.GL_BLEND);
                gl.glBlendFunc(gl.GL_SRC_ALPHA, gl.GL_ONE);
            },
            .Multiplicative => {
                gl.glEnable(gl.GL_BLEND);
                gl.glBlendFunc(gl.GL_DST_COLOR, gl.GL_ZERO);
            },
            .None => {
                gl.glDisable(gl.GL_BLEND);
            },
            .Premultiplied => {
                gl.glEnable(gl.GL_BLEND);
                gl.glBlendFunc(gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA);
            },
        }
    }
};

// Structure to hold window position and calculated distance
const WindowData = struct {
    position: zlm.Vec3,
    distance: f32,
};

fn loadTexture(path: []const u8, use_clamp_to_edge: bool, flip_vertically: bool) !gl.GLuint {
    var width: i32 = 0;
    var height: i32 = 0;
    var nrChannels: i32 = 0;
    var texture_id: gl.GLuint = 0;
    gl.glGenTextures(1, &texture_id);
    
    stb_image.stbi_set_flip_vertically_on_load(if (flip_vertically) 1 else 0);
    const data: ?*u8 = stb_image.stbi_load(path.ptr, &width, &height, &nrChannels, 0);
    if (data != null) {
        defer stb_image.stbi_image_free(data);
        var format: gl.GLenum = undefined;
        if (nrChannels == 1) {
            format = gl.GL_RED;
        } else if (nrChannels == 3) {
            format = gl.GL_RGB;
        } else if (nrChannels == 4) {
            format = gl.GL_RGBA;
        } else {
            return error.UnsupportedTextureFormat;
        }
        
        gl.glBindTexture(gl.GL_TEXTURE_2D, texture_id);
        gl.glTexImage2D(
            gl.GL_TEXTURE_2D, 0, @intCast(format),
            width, height,
            0, format, gl.GL_UNSIGNED_BYTE, data
        );
        gl.glGenerateMipmap(gl.GL_TEXTURE_2D);
        
        // Use GL_CLAMP_TO_EDGE for transparent textures to prevent border artifacts
        const wrap_mode: gl.GLint = if (use_clamp_to_edge) @intCast(gl.GL_CLAMP_TO_EDGE) else @intCast(gl.GL_REPEAT);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, wrap_mode);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, wrap_mode);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR_MIPMAP_LINEAR);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR);
    } else {
        std.debug.print("Failed to load texture: {s}\n", .{path});
        return error.TextureLoadingFailed;
    }
    return texture_id;
}

fn lessThan(_: void, a: WindowData, b: WindowData) bool {
    return a.distance > b.distance; // Sort descending (furthest first)
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

    const window_w: i32 = 800;
    const window_h: i32 = 600;
    const aspect = @as(f32, @floatFromInt(window_w)) / @as(f32, @floatFromInt(window_h));
    
    const window = sdl.SDL_CreateWindow(
        "Learn OpenGL With Zig - Blending Demo",
        sdl.SDL_WINDOWPOS_CENTERED,
        sdl.SDL_WINDOWPOS_CENTERED,
        window_w,
        window_h,
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
    _ = sdl.SDL_GL_SetSwapInterval(1);
    
    gl.glViewport(0, 0, window_w, window_h);
    gl.glEnable(gl.GL_DEPTH_TEST);

    // Initialize shaders
    var blending_shader = shader.Shader.init(
        allocator,
        "resources/blending.v.glsl",
        "resources/blending.f.glsl"
    ) catch {
        std.debug.print("Failed to initialize blending shader\n", .{});
        return error.ShaderInitializationFailed;
    };
    defer blending_shader.deinit();
    
    var grass_shader = shader.Shader.init(
        allocator,
        "resources/grass.v.glsl",
        "resources/grass.f.glsl"
    ) catch {
        std.debug.print("Failed to initialize grass shader\n", .{});
        return error.ShaderInitializationFailed;
    };
    defer grass_shader.deinit();

    // Cube vertices: position (3) + texture coords (2)
    const cube_vertices = [_]f32{
        // positions          // texture coords
        -0.5, -0.5, -0.5,  0.0, 0.0,
         0.5, -0.5, -0.5,  1.0, 0.0,
         0.5,  0.5, -0.5,  1.0, 1.0,
         0.5,  0.5, -0.5,  1.0, 1.0,
        -0.5,  0.5, -0.5,  0.0, 1.0,
        -0.5, -0.5, -0.5,  0.0, 0.0,

        -0.5, -0.5,  0.5,  0.0, 0.0,
         0.5, -0.5,  0.5,  1.0, 0.0,
         0.5,  0.5,  0.5,  1.0, 1.0,
         0.5,  0.5,  0.5,  1.0, 1.0,
        -0.5,  0.5,  0.5,  0.0, 1.0,
        -0.5, -0.5,  0.5,  0.0, 0.0,

        -0.5,  0.5,  0.5,  1.0, 0.0,
        -0.5,  0.5, -0.5,  1.0, 1.0,
        -0.5, -0.5, -0.5,  0.0, 1.0,
        -0.5, -0.5, -0.5,  0.0, 1.0,
        -0.5, -0.5,  0.5,  0.0, 0.0,
        -0.5,  0.5,  0.5,  1.0, 0.0,

         0.5,  0.5,  0.5,  1.0, 0.0,
         0.5,  0.5, -0.5,  1.0, 1.0,
         0.5, -0.5, -0.5,  0.0, 1.0,
         0.5, -0.5, -0.5,  0.0, 1.0,
         0.5, -0.5,  0.5,  0.0, 0.0,
         0.5,  0.5,  0.5,  1.0, 0.0,

        -0.5, -0.5, -0.5,  0.0, 1.0,
         0.5, -0.5, -0.5,  1.0, 1.0,
         0.5, -0.5,  0.5,  1.0, 0.0,
         0.5, -0.5,  0.5,  1.0, 0.0,
        -0.5, -0.5,  0.5,  0.0, 0.0,
        -0.5, -0.5, -0.5,  0.0, 1.0,

        -0.5,  0.5, -0.5,  0.0, 1.0,
         0.5,  0.5, -0.5,  1.0, 1.0,
         0.5,  0.5,  0.5,  1.0, 0.0,
         0.5,  0.5,  0.5,  1.0, 0.0,
        -0.5,  0.5,  0.5,  0.0, 0.0,
        -0.5,  0.5, -0.5,  0.0, 1.0,
    };

    // Floor plane vertices
    const plane_vertices = [_]f32{
        // positions          // texture coords (note we set these higher than 1 to tile the floor)
         5.0, -0.5,  5.0,  2.0, 0.0,
        -5.0, -0.5,  5.0,  0.0, 0.0,
        -5.0, -0.5, -5.0,  0.0, 2.0,

         5.0, -0.5,  5.0,  2.0, 0.0,
        -5.0, -0.5, -5.0,  0.0, 2.0,
         5.0, -0.5, -5.0,  2.0, 2.0,
    };

    // Transparent quad vertices
    const transparent_vertices = [_]f32{
        // positions         // texture coords
        0.0,  0.5,  0.0,  0.0,  0.0,
        0.0, -0.5,  0.0,  0.0,  1.0,
        1.0, -0.5,  0.0,  1.0,  1.0,

        0.0,  0.5,  0.0,  0.0,  0.0,
        1.0, -0.5,  0.0,  1.0,  1.0,
        1.0,  0.5,  0.0,  1.0,  0.0,
    };

    // Cube VAO
    var cube_vao: gl.GLuint = 0;
    var cube_vbo: gl.GLuint = 0;
    gl.glGenVertexArrays(1, &cube_vao);
    gl.glGenBuffers(1, &cube_vbo);
    defer gl.glDeleteVertexArrays(1, &cube_vao);
    defer gl.glDeleteBuffers(1, &cube_vbo);
    
    gl.glBindVertexArray(cube_vao);
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, cube_vbo);
    gl.glBufferData(gl.GL_ARRAY_BUFFER, @intCast(cube_vertices.len * @sizeOf(f32)), &cube_vertices, gl.GL_STATIC_DRAW);
    gl.glEnableVertexAttribArray(0);
    gl.glVertexAttribPointer(0, 3, gl.GL_FLOAT, gl.GL_FALSE, 5 * @sizeOf(f32), @ptrFromInt(0));
    gl.glEnableVertexAttribArray(1);
    gl.glVertexAttribPointer(1, 2, gl.GL_FLOAT, gl.GL_FALSE, 5 * @sizeOf(f32), @ptrFromInt(3 * @sizeOf(f32)));

    // Plane VAO
    var plane_vao: gl.GLuint = 0;
    var plane_vbo: gl.GLuint = 0;
    gl.glGenVertexArrays(1, &plane_vao);
    gl.glGenBuffers(1, &plane_vbo);
    defer gl.glDeleteVertexArrays(1, &plane_vao);
    defer gl.glDeleteBuffers(1, &plane_vbo);
    
    gl.glBindVertexArray(plane_vao);
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, plane_vbo);
    gl.glBufferData(gl.GL_ARRAY_BUFFER, @intCast(plane_vertices.len * @sizeOf(f32)), &plane_vertices, gl.GL_STATIC_DRAW);
    gl.glEnableVertexAttribArray(0);
    gl.glVertexAttribPointer(0, 3, gl.GL_FLOAT, gl.GL_FALSE, 5 * @sizeOf(f32), @ptrFromInt(0));
    gl.glEnableVertexAttribArray(1);
    gl.glVertexAttribPointer(1, 2, gl.GL_FLOAT, gl.GL_FALSE, 5 * @sizeOf(f32), @ptrFromInt(3 * @sizeOf(f32)));

    // Transparent quad VAO
    var transparent_vao: gl.GLuint = 0;
    var transparent_vbo: gl.GLuint = 0;
    gl.glGenVertexArrays(1, &transparent_vao);
    gl.glGenBuffers(1, &transparent_vbo);
    defer gl.glDeleteVertexArrays(1, &transparent_vao);
    defer gl.glDeleteBuffers(1, &transparent_vbo);
    
    gl.glBindVertexArray(transparent_vao);
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, transparent_vbo);
    gl.glBufferData(gl.GL_ARRAY_BUFFER, @intCast(transparent_vertices.len * @sizeOf(f32)), &transparent_vertices, gl.GL_STATIC_DRAW);
    gl.glEnableVertexAttribArray(0);
    gl.glVertexAttribPointer(0, 3, gl.GL_FLOAT, gl.GL_FALSE, 5 * @sizeOf(f32), @ptrFromInt(0));
    gl.glEnableVertexAttribArray(1);
    gl.glVertexAttribPointer(1, 2, gl.GL_FLOAT, gl.GL_FALSE, 5 * @sizeOf(f32), @ptrFromInt(3 * @sizeOf(f32)));

    // Load textures
    const cube_texture = loadTexture("resources/marble.jpg", false, true) catch {
        std.debug.print("Failed to load cube texture\n", .{});
        return error.TextureLoadingFailed;
    };
    const floor_texture = loadTexture("resources/metal.png", false, true) catch {
        std.debug.print("Failed to load floor texture\n", .{});
        return error.TextureLoadingFailed;
    };
    const window_texture = loadTexture("resources/blending_transparent_window.png", true, true) catch {
        std.debug.print("Failed to load window texture\n", .{});
        return error.TextureLoadingFailed;
    };
    const grass_texture = loadTexture("resources/grass.png", true, false) catch {
        std.debug.print("Failed to load grass texture\n", .{});
        return error.TextureLoadingFailed;
    };

    // Window positions (matching the original tutorial)
    const window_positions = [_]zlm.Vec3{
        zlm.vec3(-1.5, 0.0, -0.48),
        zlm.vec3( 1.5, 0.0,  0.51),
        zlm.vec3( 0.0, 0.0,  0.7),
        zlm.vec3(-0.3, 0.0, -2.3),
        zlm.vec3( 0.5, 0.0, -0.6),
    };

    // Grass positions (scattered around the scene at ground level)
    const grass_positions = [_]zlm.Vec3{
        zlm.vec3(-0.5, 0.0, -0.5),
        zlm.vec3( 1.5, 0.0, -0.3),
        zlm.vec3(-1.8, 0.0, -1.2),
        zlm.vec3( 0.8, 0.0,  0.8),
        zlm.vec3(-2.5, 0.0,  0.5),
        zlm.vec3( 2.8, 0.0, -0.8),
        zlm.vec3(-0.2, 0.0,  1.5),
    };

    // Set up shader uniforms
    blending_shader.use();
    blending_shader.set_int("texture1", 0);
    
    grass_shader.use();
    grass_shader.set_int("texture1", 0);

    // Initialize camera and blending mode
    var cam = camera.Camera.init();
    var current_blend_mode = BlendMode.Normal;
    current_blend_mode.apply();
    
    std.debug.print("\n=== BLENDING DEMO ===\n", .{});
    std.debug.print("Controls:\n", .{});
    std.debug.print("  Mouse: Rotate camera (orbit)\n", .{});
    std.debug.print("  Scroll: Zoom in/out\n", .{});
    std.debug.print("  B: Cycle blending modes\n", .{});
    std.debug.print("  ESC: Exit\n", .{});
    std.debug.print("\nCurrent blend mode: {s}\n\n", .{current_blend_mode.getName()});

    // Main loop
    var running = true;
    var last_time = sdl.SDL_GetTicks64();
    var num_frames: i32 = 0;
    var last_x: i32 = 0;
    var last_y: i32 = 0;
    var is_mouse_entered = false;
    
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
                    } else if (event.key.keysym.sym == sdl.SDLK_b) {
                        current_blend_mode = current_blend_mode.next();
                        current_blend_mode.apply();
                        std.debug.print("Blend mode: {s}\n", .{current_blend_mode.getName()});
                    }
                },
                sdl.SDL_MOUSEMOTION => {
                    if (!is_mouse_entered) {
                        is_mouse_entered = true;
                        last_x = event.motion.x;
                        last_y = event.motion.y;
                    }
                    const dx = event.motion.x - last_x;
                    const dy = last_y - event.motion.y;
                    last_x = event.motion.x;
                    last_y = event.motion.y;
                    cam.processMouseMovement(
                        @as(f32, @floatFromInt(dx)),
                        @as(f32, @floatFromInt(dy))
                    );
                },
                sdl.SDL_MOUSEWHEEL => {
                    cam.processMouseScroll(@as(f32, @floatFromInt(event.wheel.y)));
                },
                else => {},
            }
        }

        // Clear buffers
        gl.glClearColor(0.1, 0.1, 0.1, 1.0);
        gl.glClear(gl.GL_COLOR_BUFFER_BIT | gl.GL_DEPTH_BUFFER_BIT);

        // Set up shader
        blending_shader.use();
        const projection = zlm.Mat4.createPerspective(zlm.radians(cam.zoom), aspect, 0.1, 100.0);
        const view = cam.getViewMatrix();
        blending_shader.set_mat4("projection", zlm.value_ptr(&projection));
        blending_shader.set_mat4("view", zlm.value_ptr(&view));

        // Draw cubes (opaque objects first)
        gl.glBindVertexArray(cube_vao);
        gl.glActiveTexture(gl.GL_TEXTURE0);
        gl.glBindTexture(gl.GL_TEXTURE_2D, cube_texture);
        
        var model = zlm.Mat4.identity;
        model = zlm.translate(model, zlm.vec3(-1.0, 0.0, -1.0));
        blending_shader.set_mat4("model", zlm.value_ptr(&model));
        gl.glDrawArrays(gl.GL_TRIANGLES, 0, 36);
        
        model = zlm.Mat4.identity;
        model = zlm.translate(model, zlm.vec3(2.0, 0.0, 0.0));
        blending_shader.set_mat4("model", zlm.value_ptr(&model));
        gl.glDrawArrays(gl.GL_TRIANGLES, 0, 36);

        // Draw floor
        gl.glBindVertexArray(plane_vao);
        gl.glBindTexture(gl.GL_TEXTURE_2D, floor_texture);
        model = zlm.Mat4.identity;
        blending_shader.set_mat4("model", zlm.value_ptr(&model));
        gl.glDrawArrays(gl.GL_TRIANGLES, 0, 6);

        // Draw grass (uses discard, no sorting needed)
        grass_shader.use();
        grass_shader.set_mat4("projection", zlm.value_ptr(&projection));
        grass_shader.set_mat4("view", zlm.value_ptr(&view));
        gl.glBindVertexArray(transparent_vao);
        gl.glBindTexture(gl.GL_TEXTURE_2D, grass_texture);
        
        for (grass_positions) |pos| {
            model = zlm.Mat4.identity;
            model = zlm.translate(model, pos);
            grass_shader.set_mat4("model", zlm.value_ptr(&model));
            gl.glDrawArrays(gl.GL_TRIANGLES, 0, 6);
        }

        // Sort windows by distance from camera
        var windows = std.ArrayList(WindowData).init(allocator);
        defer windows.deinit();
        
        for (window_positions) |pos| {
            const dist = cam.position.sub(pos).length();
            try windows.append(WindowData{ .position = pos, .distance = dist });
        }
        
        std.mem.sort(WindowData, windows.items, {}, lessThan);

        // Draw windows from furthest to nearest
        gl.glBindVertexArray(transparent_vao);
        gl.glBindTexture(gl.GL_TEXTURE_2D, window_texture);
        
        for (windows.items) |window_data| {
            model = zlm.Mat4.identity;
            model = zlm.translate(model, window_data.position);
            blending_shader.set_mat4("model", zlm.value_ptr(&model));
            gl.glDrawArrays(gl.GL_TRIANGLES, 0, 6);
        }

        sdl.SDL_GL_SwapWindow(window);

        // FPS counter
        num_frames += 1;
        if (delta_ms >= 1000) {
            std.debug.print("FPS: {}\n", .{num_frames});
            num_frames = 0;
            last_time = current_time;
        }
    }
}

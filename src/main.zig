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

// Face culling modes for demonstration
const CullingMode = enum {
    Disabled,        // No face culling
    CullBack,        // Cull back faces (most common, default)
    CullFront,       // Cull front faces (shows inside of objects)
    CullBoth,        // Cull both faces (nothing visible)

    fn getName(self: CullingMode) []const u8 {
        return switch (self) {
            .Disabled => "Disabled (All faces visible)",
            .CullBack => "Cull Back Faces (Standard - 50% performance boost)",
            .CullFront => "Cull Front Faces (Shows inside of objects)",
            .CullBoth => "Cull Both Faces (Nothing visible)",
        };
    }

    fn next(self: CullingMode) CullingMode {
        return switch (self) {
            .Disabled => .CullBack,
            .CullBack => .CullFront,
            .CullFront => .CullBoth,
            .CullBoth => .Disabled,
        };
    }

    fn apply(self: CullingMode) void {
        switch (self) {
            .Disabled => {
                gl.glDisable(gl.GL_CULL_FACE);
            },
            .CullBack => {
                gl.glEnable(gl.GL_CULL_FACE);
                gl.glCullFace(gl.GL_BACK);
            },
            .CullFront => {
                gl.glEnable(gl.GL_CULL_FACE);
                gl.glCullFace(gl.GL_FRONT);
            },
            .CullBoth => {
                gl.glEnable(gl.GL_CULL_FACE);
                gl.glCullFace(gl.GL_FRONT_AND_BACK);
            },
        }
    }
};

// Winding order modes
const WindingMode = enum {
    CounterClockwise,  // CCW is front-facing (OpenGL default)
    Clockwise,         // CW is front-facing

    fn getName(self: WindingMode) []const u8 {
        return switch (self) {
            .CounterClockwise => "Counter-Clockwise (CCW - Default)",
            .Clockwise => "Clockwise (CW)",
        };
    }

    fn toggle(self: WindingMode) WindingMode {
        return switch (self) {
            .CounterClockwise => .Clockwise,
            .Clockwise => .CounterClockwise,
        };
    }

    fn apply(self: WindingMode) void {
        switch (self) {
            .CounterClockwise => gl.glFrontFace(gl.GL_CCW),
            .Clockwise => gl.glFrontFace(gl.GL_CW),
        }
    }
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
        "Learn OpenGL With Zig - Face Culling Demo",
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

    // Initialize shader
    var cube_shader = shader.Shader.init(
        allocator,
        "resources/blending.v.glsl",
        "resources/blending.f.glsl"
    ) catch {
        std.debug.print("Failed to initialize shader\n", .{});
        return error.ShaderInitializationFailed;
    };
    defer cube_shader.deinit();

    // Cube vertices with COUNTER-CLOCKWISE winding order (for front faces)
    // This is important for face culling to work correctly!
    const cube_vertices = [_]f32{
        // Back face (CCW when viewed from behind)
        -0.5, -0.5, -0.5,  0.0, 0.0, // Bottom-left
         0.5,  0.5, -0.5,  1.0, 1.0, // top-right
         0.5, -0.5, -0.5,  1.0, 0.0, // bottom-right         
         0.5,  0.5, -0.5,  1.0, 1.0, // top-right
        -0.5, -0.5, -0.5,  0.0, 0.0, // bottom-left
        -0.5,  0.5, -0.5,  0.0, 1.0, // top-left
        // Front face (CCW when viewed from front)
        -0.5, -0.5,  0.5,  0.0, 0.0, // bottom-left
         0.5, -0.5,  0.5,  1.0, 0.0, // bottom-right
         0.5,  0.5,  0.5,  1.0, 1.0, // top-right
         0.5,  0.5,  0.5,  1.0, 1.0, // top-right
        -0.5,  0.5,  0.5,  0.0, 1.0, // top-left
        -0.5, -0.5,  0.5,  0.0, 0.0, // bottom-left
        // Left face (CCW when viewed from left)
        -0.5,  0.5,  0.5,  1.0, 0.0, // top-right
        -0.5,  0.5, -0.5,  1.0, 1.0, // top-left
        -0.5, -0.5, -0.5,  0.0, 1.0, // bottom-left
        -0.5, -0.5, -0.5,  0.0, 1.0, // bottom-left
        -0.5, -0.5,  0.5,  0.0, 0.0, // bottom-right
        -0.5,  0.5,  0.5,  1.0, 0.0, // top-right
        // Right face (CCW when viewed from right)
         0.5,  0.5,  0.5,  1.0, 0.0, // top-left
         0.5, -0.5, -0.5,  0.0, 1.0, // bottom-right
         0.5,  0.5, -0.5,  1.0, 1.0, // top-right         
         0.5, -0.5, -0.5,  0.0, 1.0, // bottom-right
         0.5,  0.5,  0.5,  1.0, 0.0, // top-left
         0.5, -0.5,  0.5,  0.0, 0.0, // bottom-left     
        // Bottom face (CCW when viewed from bottom)
        -0.5, -0.5, -0.5,  0.0, 1.0, // top-right
         0.5, -0.5, -0.5,  1.0, 1.0, // top-left
         0.5, -0.5,  0.5,  1.0, 0.0, // bottom-left
         0.5, -0.5,  0.5,  1.0, 0.0, // bottom-left
        -0.5, -0.5,  0.5,  0.0, 0.0, // bottom-right
        -0.5, -0.5, -0.5,  0.0, 1.0, // top-right
        // Top face (CCW when viewed from top)
        -0.5,  0.5, -0.5,  0.0, 1.0, // top-left
         0.5,  0.5,  0.5,  1.0, 0.0, // bottom-right
         0.5,  0.5, -0.5,  1.0, 1.0, // top-right     
         0.5,  0.5,  0.5,  1.0, 0.0, // bottom-right
        -0.5,  0.5, -0.5,  0.0, 1.0, // top-left
        -0.5,  0.5,  0.5,  0.0, 0.0, // bottom-left        
    };

    // Floor plane vertices
    const plane_vertices = [_]f32{
        // positions          // texture coords
         5.0, -0.5,  5.0,  2.0, 0.0,
        -5.0, -0.5,  5.0,  0.0, 0.0,
        -5.0, -0.5, -5.0,  0.0, 2.0,

         5.0, -0.5,  5.0,  2.0, 0.0,
        -5.0, -0.5, -5.0,  0.0, 2.0,
         5.0, -0.5, -5.0,  2.0, 2.0,
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

    // Load textures
    const cube_texture = loadTexture("resources/container2.png", false, true) catch {
        std.debug.print("Failed to load cube texture\n", .{});
        return error.TextureLoadingFailed;
    };
    const floor_texture = loadTexture("resources/metal.png", false, true) catch {
        std.debug.print("Failed to load floor texture\n", .{});
        return error.TextureLoadingFailed;
    };

    // Set up shader uniforms
    cube_shader.use();
    cube_shader.set_int("texture1", 0);

    // Initialize camera and culling mode
    var cam = camera.Camera.init();
    var current_culling_mode = CullingMode.CullBack;
    var current_winding_mode = WindingMode.CounterClockwise;
    
    // Apply initial settings
    current_culling_mode.apply();
    current_winding_mode.apply();
    
    std.debug.print("\n=== FACE CULLING DEMO ===\n", .{});
    std.debug.print("Face culling is an optimization technique that discards triangles\n", .{});
    std.debug.print("that are facing away from the camera (back-facing).\n", .{});
    std.debug.print("This can save 50%% or more of fragment shader work!\n\n", .{});
    std.debug.print("Controls:\n", .{});
    std.debug.print("  Mouse: Rotate camera (orbit)\n", .{});
    std.debug.print("  Scroll: Zoom in/out\n", .{});
    std.debug.print("  C: Cycle face culling modes\n", .{});
    std.debug.print("  W: Toggle winding order (CCW/CW)\n", .{});
    std.debug.print("  ESC: Exit\n", .{});
    std.debug.print("\nTIP: Try moving inside a cube to see the effect!\n\n", .{});
    std.debug.print("Culling Mode: {s}\n", .{current_culling_mode.getName()});
    std.debug.print("Winding Order: {s}\n\n", .{current_winding_mode.getName()});

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
                    } else if (event.key.keysym.sym == sdl.SDLK_c) {
                        current_culling_mode = current_culling_mode.next();
                        current_culling_mode.apply();
                        std.debug.print("Culling Mode: {s}\n", .{current_culling_mode.getName()});
                    } else if (event.key.keysym.sym == sdl.SDLK_w) {
                        current_winding_mode = current_winding_mode.toggle();
                        current_winding_mode.apply();
                        std.debug.print("Winding Order: {s}\n", .{current_winding_mode.getName()});
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
        cube_shader.use();
        const projection = zlm.Mat4.createPerspective(zlm.radians(cam.zoom), aspect, 0.1, 100.0);
        const view = cam.getViewMatrix();
        cube_shader.set_mat4("projection", zlm.value_ptr(&projection));
        cube_shader.set_mat4("view", zlm.value_ptr(&view));

        // Draw cubes at various positions
        gl.glBindVertexArray(cube_vao);
        gl.glActiveTexture(gl.GL_TEXTURE0);
        gl.glBindTexture(gl.GL_TEXTURE_2D, cube_texture);
        
        // Cube positions to demonstrate culling
        const cube_positions = [_]zlm.Vec3{
            zlm.vec3(-1.0, 0.0, -1.0),
            zlm.vec3(2.0, 0.0, 0.0),
            zlm.vec3(-1.5, 0.5, -2.5),
            zlm.vec3(1.2, 0.8, -1.5),
            zlm.vec3(0.0, 1.2, 0.0),
        };
        
        for (cube_positions) |pos| {
            var model = zlm.Mat4.identity;
            model = zlm.translate(model, pos);
            cube_shader.set_mat4("model", zlm.value_ptr(&model));
            gl.glDrawArrays(gl.GL_TRIANGLES, 0, 36);
        }

        // Draw floor
        gl.glBindVertexArray(plane_vao);
        gl.glBindTexture(gl.GL_TEXTURE_2D, floor_texture);
        var model = zlm.Mat4.identity;
        cube_shader.set_mat4("model", zlm.value_ptr(&model));
        gl.glDrawArrays(gl.GL_TRIANGLES, 0, 6);

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

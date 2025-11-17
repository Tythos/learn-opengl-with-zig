const std = @import("std");
const zlm = @import("zlm").as(f32);
const gl = @import("gl.zig");
const shader = @import("shader.zig");
const camera = @import("camera.zig");
const stb_image = @cImport({
    @cInclude("stb_image.h");
});
const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
});

// Window settings
const SCR_WIDTH: i32 = 800;
const SCR_HEIGHT: i32 = 600;

// Camera near/far planes
const NEAR_PLANE: f32 = 0.1;
const FAR_PLANE: f32 = 100.0;

// Depth testing modes
const DepthMode = enum {
    normal,         // GL_LESS - normal depth testing
    always,         // GL_ALWAYS - simulates no depth testing
    depth_viz,      // Visualize non-linear depth buffer
    depth_linear,   // Visualize linearized depth values
};

fn loadTexture(path: []const u8) !gl.GLuint {
    var width: i32 = 0;
    var height: i32 = 0;
    var nrChannels: i32 = 0;
    var texture_id: gl.GLuint = 0;
    gl.glGenTextures(1, &texture_id);
    
    stb_image.stbi_set_flip_vertically_on_load(1);
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
        }
        
        gl.glBindTexture(gl.GL_TEXTURE_2D, texture_id);
        gl.glTexImage2D(
            gl.GL_TEXTURE_2D, 0, @intCast(format),
            width, height, 0, format, gl.GL_UNSIGNED_BYTE, data
        );
        gl.glGenerateMipmap(gl.GL_TEXTURE_2D);
        
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_REPEAT);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_REPEAT);
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
    
    // Initialize SDL
    if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO) != 0) {
        std.debug.print("SDL_Init Error: {s}\n", .{sdl.SDL_GetError()});
        return error.SDLInitFailed;
    }
    defer sdl.SDL_Quit();
    
    // Set OpenGL attributes
    _ = sdl.SDL_GL_SetAttribute(sdl.SDL_GL_CONTEXT_MAJOR_VERSION, 3);
    _ = sdl.SDL_GL_SetAttribute(sdl.SDL_GL_CONTEXT_MINOR_VERSION, 3);
    _ = sdl.SDL_GL_SetAttribute(sdl.SDL_GL_CONTEXT_PROFILE_MASK, sdl.SDL_GL_CONTEXT_PROFILE_CORE);
    _ = sdl.SDL_GL_SetAttribute(sdl.SDL_GL_DOUBLEBUFFER, 1);
    _ = sdl.SDL_GL_SetAttribute(sdl.SDL_GL_DEPTH_SIZE, 24);
    
    // Create window
    const window = sdl.SDL_CreateWindow(
        "Depth Testing Demo",
        sdl.SDL_WINDOWPOS_CENTERED,
        sdl.SDL_WINDOWPOS_CENTERED,
        SCR_WIDTH,
        SCR_HEIGHT,
        sdl.SDL_WINDOW_OPENGL | sdl.SDL_WINDOW_SHOWN,
    ) orelse {
        std.debug.print("SDL_CreateWindow Error: {s}\n", .{sdl.SDL_GetError()});
        return error.WindowCreationFailed;
    };
    defer sdl.SDL_DestroyWindow(window);
    
    // Create OpenGL context
    const gl_context = sdl.SDL_GL_CreateContext(window);
    if (gl_context == null) {
        std.debug.print("SDL_GL_CreateContext Error: {s}\n", .{sdl.SDL_GetError()});
        return error.GLContextCreationFailed;
    }
    defer sdl.SDL_GL_DeleteContext(gl_context);
    
    gl.loadFunctions();
    _ = sdl.SDL_GL_SetSwapInterval(1);
    
    // Configure OpenGL
    gl.glViewport(0, 0, SCR_WIDTH, SCR_HEIGHT);
    gl.glEnable(gl.GL_DEPTH_TEST);
    gl.glDepthFunc(gl.GL_LESS);
    
    // Build and compile shaders
    var standard_shader = try shader.Shader.init(
        allocator,
        "examples/depth_testing/shaders/standard.v.glsl",
        "examples/depth_testing/shaders/standard.f.glsl"
    );
    defer standard_shader.deinit();
    
    var depth_viz_shader = try shader.Shader.init(
        allocator,
        "examples/depth_testing/shaders/standard.v.glsl",
        "examples/depth_testing/shaders/depth_viz.f.glsl"
    );
    defer depth_viz_shader.deinit();
    
    var depth_linear_shader = try shader.Shader.init(
        allocator,
        "examples/depth_testing/shaders/standard.v.glsl",
        "examples/depth_testing/shaders/depth_linear.f.glsl"
    );
    defer depth_linear_shader.deinit();
    
    // Set up vertex data - cube with position + texture coords
    const cubeVertices = [_]f32{
        // positions          // texture Coords
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
        -0.5,  0.5, -0.5,  0.0, 1.0
    };
    
    // Set up vertex data - plane (larger, with texture coords that repeat)
    const planeVertices = [_]f32{
        // positions          // texture Coords (note: set higher than 1 to repeat)
         5.0, -0.5,  5.0,  2.0, 0.0,
        -5.0, -0.5,  5.0,  0.0, 0.0,
        -5.0, -0.5, -5.0,  0.0, 2.0,

         5.0, -0.5,  5.0,  2.0, 0.0,
        -5.0, -0.5, -5.0,  0.0, 2.0,
         5.0, -0.5, -5.0,  2.0, 2.0
    };
    
    // Cube VAO
    var cubeVAO: gl.GLuint = 0;
    var cubeVBO: gl.GLuint = 0;
    gl.glGenVertexArrays(1, &cubeVAO);
    gl.glGenBuffers(1, &cubeVBO);
    defer gl.glDeleteVertexArrays(1, &cubeVAO);
    defer gl.glDeleteBuffers(1, &cubeVBO);
    
    gl.glBindVertexArray(cubeVAO);
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, cubeVBO);
    gl.glBufferData(
        gl.GL_ARRAY_BUFFER,
        @intCast(cubeVertices.len * @sizeOf(f32)),
        &cubeVertices,
        gl.GL_STATIC_DRAW
    );
    gl.glEnableVertexAttribArray(0);
    gl.glVertexAttribPointer(0, 3, gl.GL_FLOAT, gl.GL_FALSE, 5 * @sizeOf(f32), @ptrFromInt(0));
    gl.glEnableVertexAttribArray(1);
    gl.glVertexAttribPointer(1, 2, gl.GL_FLOAT, gl.GL_FALSE, 5 * @sizeOf(f32), @ptrFromInt(3 * @sizeOf(f32)));
    
    // Plane VAO
    var planeVAO: gl.GLuint = 0;
    var planeVBO: gl.GLuint = 0;
    gl.glGenVertexArrays(1, &planeVAO);
    gl.glGenBuffers(1, &planeVBO);
    defer gl.glDeleteVertexArrays(1, &planeVAO);
    defer gl.glDeleteBuffers(1, &planeVBO);
    
    gl.glBindVertexArray(planeVAO);
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, planeVBO);
    gl.glBufferData(
        gl.GL_ARRAY_BUFFER,
        @intCast(planeVertices.len * @sizeOf(f32)),
        &planeVertices,
        gl.GL_STATIC_DRAW
    );
    gl.glEnableVertexAttribArray(0);
    gl.glVertexAttribPointer(0, 3, gl.GL_FLOAT, gl.GL_FALSE, 5 * @sizeOf(f32), @ptrFromInt(0));
    gl.glEnableVertexAttribArray(1);
    gl.glVertexAttribPointer(1, 2, gl.GL_FLOAT, gl.GL_FALSE, 5 * @sizeOf(f32), @ptrFromInt(3 * @sizeOf(f32)));
    
    // Load textures
    const cubeTexture = try loadTexture("resources/marble.jpg");
    const floorTexture = try loadTexture("resources/metal.png");
    
    // Shader configuration
    standard_shader.use();
    standard_shader.set_int("texture1", 0);
    
    // Initialize camera
    var cam = camera.Camera.init();
    
    // Depth mode state
    var current_mode = DepthMode.normal;
    
    // Main loop
    var running = true;
    var last_time = sdl.SDL_GetTicks64();
    var num_frames: i32 = 0;
    var last_x: i32 = 0;
    var last_y: i32 = 0;
    var is_mouse_entered = false;
    
    std.debug.print("\n=== Depth Testing Demo ===\n", .{});
    std.debug.print("Controls:\n", .{});
    std.debug.print("  1 - Normal depth testing (GL_LESS)\n", .{});
    std.debug.print("  2 - Always pass depth test (GL_ALWAYS)\n", .{});
    std.debug.print("  3 - Visualize depth buffer (non-linear)\n", .{});
    std.debug.print("  4 - Visualize depth buffer (linearized)\n", .{});
    std.debug.print("  Mouse - Rotate camera\n", .{});
    std.debug.print("  Scroll - Zoom in/out\n", .{});
    std.debug.print("  ESC - Quit\n\n", .{});
    
    while (running) {
        const current_time = sdl.SDL_GetTicks64();
        const delta_ms = current_time - last_time;
        
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                sdl.SDL_QUIT => running = false,
                sdl.SDL_KEYDOWN => {
                    switch (event.key.keysym.sym) {
                        sdl.SDLK_ESCAPE => running = false,
                        sdl.SDLK_1 => {
                            current_mode = .normal;
                            gl.glDepthFunc(gl.GL_LESS);
                            std.debug.print("Mode: Normal depth testing (GL_LESS)\n", .{});
                        },
                        sdl.SDLK_2 => {
                            current_mode = .always;
                            gl.glDepthFunc(gl.GL_ALWAYS);
                            std.debug.print("Mode: Always pass depth test (GL_ALWAYS)\n", .{});
                        },
                        sdl.SDLK_3 => {
                            current_mode = .depth_viz;
                            gl.glDepthFunc(gl.GL_LESS); // Use normal depth testing for visualization
                            std.debug.print("Mode: Depth buffer visualization (non-linear)\n", .{});
                        },
                        sdl.SDLK_4 => {
                            current_mode = .depth_linear;
                            gl.glDepthFunc(gl.GL_LESS);
                            std.debug.print("Mode: Depth buffer visualization (linearized)\n", .{});
                        },
                        else => {},
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
        
        // Render
        gl.glClearColor(0.1, 0.1, 0.1, 1.0);
        gl.glClear(gl.GL_COLOR_BUFFER_BIT | gl.GL_DEPTH_BUFFER_BIT);
        
        // Select shader based on mode
        const active_shader = switch (current_mode) {
            .normal, .always => &standard_shader,
            .depth_viz => &depth_viz_shader,
            .depth_linear => &depth_linear_shader,
        };
        
        active_shader.use();
        
        // Set up view/projection matrices
        const aspect = @as(f32, @floatFromInt(SCR_WIDTH)) / @as(f32, @floatFromInt(SCR_HEIGHT));
        const projection = zlm.Mat4.createPerspective(zlm.radians(cam.zoom), aspect, NEAR_PLANE, FAR_PLANE);
        const view = cam.getViewMatrix();
        
        active_shader.set_mat4("projection", zlm.value_ptr(&projection));
        active_shader.set_mat4("view", zlm.value_ptr(&view));
        
        // Set near/far for linear depth visualization
        if (current_mode == .depth_linear) {
            active_shader.set_float("near", NEAR_PLANE);
            active_shader.set_float("far", FAR_PLANE);
        }
        
        // Draw cubes
        gl.glBindVertexArray(cubeVAO);
        gl.glActiveTexture(gl.GL_TEXTURE0);
        gl.glBindTexture(gl.GL_TEXTURE_2D, cubeTexture);
        
        var model = zlm.Mat4.identity;
        model = zlm.translate(model, zlm.vec3(-1.0, 0.0, -1.0));
        active_shader.set_mat4("model", zlm.value_ptr(&model));
        gl.glDrawArrays(gl.GL_TRIANGLES, 0, 36);
        
        model = zlm.Mat4.identity;
        model = zlm.translate(model, zlm.vec3(2.0, 0.0, 0.0));
        active_shader.set_mat4("model", zlm.value_ptr(&model));
        gl.glDrawArrays(gl.GL_TRIANGLES, 0, 36);
        
        // Draw floor
        gl.glBindVertexArray(planeVAO);
        gl.glBindTexture(gl.GL_TEXTURE_2D, floorTexture);
        model = zlm.Mat4.identity;
        active_shader.set_mat4("model", zlm.value_ptr(&model));
        gl.glDrawArrays(gl.GL_TRIANGLES, 0, 6);
        
        // Swap buffers
        sdl.SDL_GL_SwapWindow(window);
        
        // Update FPS counter
        num_frames += 1;
        if (delta_ms >= 1000) {
            std.debug.print("FPS: {}\n", .{num_frames});
            num_frames = 0;
            last_time = current_time;
        }
    }
    
    std.debug.print("Depth Testing Demo exited\n", .{});
}

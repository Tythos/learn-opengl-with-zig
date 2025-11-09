const std = @import("std");
const zlm = @import("zlm").as(f32);
const gl = @import("gl.zig");
const shader = @import("shader.zig");
const stb_image = @cImport({
    // Don't define STB_IMAGE_IMPLEMENTATION here - it's in the C wrapper
    @cInclude("stb_image.h");
});
const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
});
const camera = @import("camera.zig");

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

    const window_w: i32 = 800;
    const window_h: i32 = 600;
    const aspect = @as(f32, @floatFromInt(window_w)) / @as(f32, @floatFromInt(window_h));
    const window = sdl.SDL_CreateWindow(
        "Learn OpenGL With Zig",
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

    var nrAttributes: i32 = undefined;
    gl.glGetIntegerv(gl.GL_MAX_VERTEX_ATTRIBS, &nrAttributes);
    std.debug.print("Maximum number of vertex attributes supported: {}\n", .{nrAttributes});

    _ = sdl.SDL_GL_SetSwapInterval(1);
    // gl.glEnable(gl.GL_DEPTH_TEST);

    // var window_w: i32 = 0;
    // var window_h: i32 = 0;
    // sdl.SDL_GetWindowSize(window, &window_w, &window_h);
    gl.glViewport(0, 0, window_w, window_h);
    setupRenderState();

    // Set up vertex data for a cube
    const vertices = [_]f32{
        // -Z face
        -0.5, -0.5, -0.5, 0.0, 0.0, -1.0,
         0.5, -0.5, -0.5, 0.0, 0.0, -1.0,
         0.5,  0.5, -0.5, 0.0, 0.0, -1.0,
         0.5,  0.5, -0.5, 0.0, 0.0, -1.0,
        -0.5,  0.5, -0.5, 0.0, 0.0, -1.0,
        -0.5, -0.5, -0.5, 0.0, 0.0, -1.0,

        // +Z face
        -0.5, -0.5,  0.5, 0.0, 0.0, 1.0,
         0.5, -0.5,  0.5, 0.0, 0.0, 1.0,
         0.5,  0.5,  0.5, 0.0, 0.0, 1.0,
         0.5,  0.5,  0.5, 0.0, 0.0, 1.0,
        -0.5,  0.5,  0.5, 0.0, 0.0, 1.0,
        -0.5, -0.5,  0.5, 0.0, 0.0, 1.0,

        // -X face
        -0.5,  0.5,  0.5, -1.0, 0.0, 0.0,
        -0.5,  0.5, -0.5, -1.0, 0.0, 0.0,
        -0.5, -0.5, -0.5, -1.0, 0.0, 0.0,
        -0.5, -0.5, -0.5, -1.0, 0.0, 0.0,
        -0.5, -0.5,  0.5, -1.0, 0.0, 0.0,
        -0.5,  0.5,  0.5, -1.0, 0.0, 0.0,

        // +X face
         0.5,  0.5,  0.5, 1.0, 0.0, 0.0,
         0.5,  0.5, -0.5, 1.0, 0.0, 0.0,
         0.5, -0.5, -0.5, 1.0, 0.0, 0.0,
         0.5, -0.5, -0.5, 1.0, 0.0, 0.0,
         0.5, -0.5,  0.5, 1.0, 0.0, 0.0,
         0.5,  0.5,  0.5, 1.0, 0.0, 0.0,

        // -Y face
        -0.5, -0.5, -0.5, 0.0, -1.0, 0.0,
         0.5, -0.5, -0.5, 0.0, -1.0, 0.0,
         0.5, -0.5,  0.5, 0.0, -1.0, 0.0,
         0.5, -0.5,  0.5, 0.0, -1.0, 0.0,
        -0.5, -0.5,  0.5, 0.0, -1.0, 0.0,
        -0.5, -0.5, -0.5, 0.0, -1.0, 0.0,

        // +Y face
        -0.5,  0.5, -0.5, 0.0, 1.0, 0.0,
         0.5,  0.5, -0.5, 0.0, 1.0, 0.0,
         0.5,  0.5,  0.5, 0.0, 1.0, 0.0,
         0.5,  0.5,  0.5, 0.0, 1.0, 0.0,
        -0.5,  0.5,  0.5, 0.0, 1.0, 0.0,
        -0.5,  0.5, -0.5, 0.0, 1.0, 0.0,
    };

    // First, configure the cube's VAO (and VBO)
    var vbo: gl.GLuint = 0;
    gl.glGenBuffers(1, &vbo);
    
    var cube_vao: gl.GLuint = 0;
    gl.glGenVertexArrays(1, &cube_vao);
    
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, vbo);
    gl.glBufferData(
        gl.GL_ARRAY_BUFFER,
        @intCast(vertices.len * @sizeOf(f32)),
        &vertices,
        gl.GL_STATIC_DRAW
    );

    gl.glBindVertexArray(cube_vao);

    // Position, normal1 attributes
    gl.glVertexAttribPointer(0, 3, gl.GL_FLOAT, gl.GL_FALSE, 6 * @sizeOf(f32), @ptrFromInt(0));
    gl.glEnableVertexAttribArray(0);

    // Normal attribute
    gl.glVertexAttribPointer(1, 3, gl.GL_FLOAT, gl.GL_FALSE, 6 * @sizeOf(f32), @ptrFromInt(3 * @sizeOf(f32)));
    gl.glEnableVertexAttribArray(1);

    // Second, configure the light's VAO
    var light_cube_vao: gl.GLuint = 0;
    gl.glGenVertexArrays(1, &light_cube_vao);
    gl.glBindVertexArray(light_cube_vao);

    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, vbo);
    gl.glVertexAttribPointer(0, 3, gl.GL_FLOAT, gl.GL_FALSE, 6 * @sizeOf(f32), @ptrFromInt(0));
    gl.glEnableVertexAttribArray(0);

    // Build and compile shaders
    var lighting_shader = shader.Shader.init(
        allocator,
        "resources/subject.v.glsl",
        "resources/subject.f.glsl"
    ) catch {
        std.debug.print("Failed to initialize lighting shader\n", .{});
        return error.ShaderInitializationFailed;
    };
    defer lighting_shader.deinit();

    var light_cube_shader = shader.Shader.init(
        allocator,
        "resources/light_cube.v.glsl",
        "resources/light_cube.f.glsl"
    ) catch {
        std.debug.print("Failed to initialize light cube shader\n", .{});
        return error.ShaderInitializationFailed;
    };
    defer light_cube_shader.deinit();

    var axis_shader = shader.Shader.init(
        allocator,
        "resources/axis.v.glsl",
        "resources/axis.f.glsl"
    ) catch {
        std.debug.print("Failed to initialize axis shader\n", .{});
        return error.ShaderInitializationFailed;
    };
    defer axis_shader.deinit();

    // Set up coordinate axes (position + color for each vertex)
    const axis_vertices = [_]f32{
        // X axis (red)
        0.0, 0.0, 0.0,  1.0, 0.0, 0.0,  // origin
        1.0, 0.0, 0.0,  1.0, 0.0, 0.0,  // +X
        // Y axis (green)
        0.0, 0.0, 0.0,  0.0, 1.0, 0.0,  // origin
        0.0, 1.0, 0.0,  0.0, 1.0, 0.0,  // +Y
        // Z axis (blue)
        0.0, 0.0, 0.0,  0.0, 0.0, 1.0,  // origin
        0.0, 0.0, 1.0,  0.0, 0.0, 1.0,  // +Z
    };

    var axis_vbo: gl.GLuint = 0;
    gl.glGenBuffers(1, &axis_vbo);
    
    var axis_vao: gl.GLuint = 0;
    gl.glGenVertexArrays(1, &axis_vao);
    
    gl.glBindVertexArray(axis_vao);
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, axis_vbo);
    gl.glBufferData(
        gl.GL_ARRAY_BUFFER,
        @intCast(axis_vertices.len * @sizeOf(f32)),
        &axis_vertices,
        gl.GL_STATIC_DRAW
    );

    // Position attribute
    gl.glVertexAttribPointer(0, 3, gl.GL_FLOAT, gl.GL_FALSE, 6 * @sizeOf(f32), @ptrFromInt(0));
    gl.glEnableVertexAttribArray(0);
    // Color attribute
    gl.glVertexAttribPointer(1, 3, gl.GL_FLOAT, gl.GL_FALSE, 6 * @sizeOf(f32), @ptrFromInt(3 * @sizeOf(f32)));
    gl.glEnableVertexAttribArray(1);

    // Initialize orbit camera
    var cam = camera.Camera.init();

    // Lighting
    const light_pos = zlm.vec3(2.0, 3.0, 5.0);

    // Main loop
    var running = true;
    var last_time = sdl.SDL_GetTicks64();
    var num_frames: i32 = 0;
    const start_time = sdl.SDL_GetTicks64();
    var last_x: i32 = 0;
    var last_y: i32 = 0;
    var is_mouse_entered = false;
    while (running) {
        const current_time = sdl.SDL_GetTicks64();
        const delta_ms = current_time - last_time;
        const dt_s = @as(f32, @floatFromInt(current_time - start_time)) * 1e-3;

        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                sdl.SDL_QUIT => running = false,
                sdl.SDL_KEYDOWN => {
                    if (event.key.keysym.sym == sdl.SDLK_ESCAPE) {
                        running = false;
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

        // set up lighting shader
        lighting_shader.use();
        lighting_shader.set_vec3("objectColor", 1.0, 0.5, 0.31);
        lighting_shader.set_vec3("lightColor", 1.0, 1.0, 1.0);
        lighting_shader.set_vec3("viewPos", cam.position.x, cam.position.y, cam.position.z);
        lighting_shader.set_vec3("material.ambient", 1.0, 0.5, 0.31);
        lighting_shader.set_vec3("material.diffuse", 1.0, 0.5, 0.31);
        lighting_shader.set_vec3("material.specular", 0.5, 0.5, 0.5);
        lighting_shader.set_float("material.shininess", 32.0);
        lighting_shader.set_vec3("light.position", light_pos.x, light_pos.y, light_pos.z);
        lighting_shader.set_vec3("light.specular", 1.0, 1.0, 1.0);

        // time-varying light material properties
        var lightColor = zlm.vec3(1.0, 1.0, 1.0);
        lightColor.x = std.math.sin(dt_s * 2.0);
        lightColor.y = std.math.sin(dt_s * 0.7);
        lightColor.z = std.math.sin(dt_s * 1.3);
        const diffuseColor = lightColor.scale(0.5);
        const ambientColor = diffuseColor.scale(0.2);
        lighting_shader.set_vec3("light.ambient", ambientColor.x, ambientColor.y, ambientColor.z);
        lighting_shader.set_vec3("light.diffuse", diffuseColor.x, diffuseColor.y, diffuseColor.z);

        // View/projection transformations
        const projection = zlm.Mat4.createPerspective(zlm.radians(cam.zoom), aspect, 0.1, 100.0);
        const view = cam.getViewMatrix();
        lighting_shader.set_mat4("projection", zlm.value_ptr(&projection));
        lighting_shader.set_mat4("view", zlm.value_ptr(&view));

        // World transformation
        var model = zlm.Mat4.identity;
        lighting_shader.set_mat4("model", zlm.value_ptr(&model));

        // Render the cube
        gl.glBindVertexArray(cube_vao);
        gl.glDrawArrays(gl.GL_TRIANGLES, 0, 36);

        // Also draw the lamp object
        light_cube_shader.use();
        light_cube_shader.set_mat4("projection", zlm.value_ptr(&projection));
        light_cube_shader.set_mat4("view", zlm.value_ptr(&view));
        model = zlm.Mat4.identity;
        model = zlm.translate(model, light_pos);
        model = zlm.scale(model, zlm.vec3(0.2, 0.2, 0.2)); // smaller cube
        light_cube_shader.set_mat4("model", zlm.value_ptr(&model));

        gl.glBindVertexArray(light_cube_vao);
        gl.glDrawArrays(gl.GL_TRIANGLES, 0, 36);

        // Draw coordinate axes
        axis_shader.use();
        axis_shader.set_mat4("projection", zlm.value_ptr(&projection));
        axis_shader.set_mat4("view", zlm.value_ptr(&view));
        
        gl.glBindVertexArray(axis_vao);
        gl.glDrawArrays(gl.GL_LINES, 0, 6);

        sdl.SDL_GL_SwapWindow(window);

        // Update FPS counter
        num_frames += 1;
        if (delta_ms >= 1000) {
            std.debug.print("FPS={} @ dt={d:.1}s\n", .{num_frames, dt_s});
            std.debug.print("Camera: radius={d:.1}, theta={d:.1}, phi={d:.1}\n", .{
                cam.radius, cam.theta, cam.phi
            });
            num_frames = 0;
            last_time = current_time;
        }
    }
    std.debug.print("Application exited\n", .{});
}

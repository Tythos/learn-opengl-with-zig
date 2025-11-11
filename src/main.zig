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

fn loadTexture(path: []const u8) !gl.GLuint {
    var width: i32 = 0;
    var height: i32 = 0;
    var nrChannels: i32 = 0;
    var texture_id: gl.GLuint = 0;
    gl.glGenTextures(1, &texture_id);
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
            width, height,
            0, format, gl.GL_UNSIGNED_BYTE, data);
        gl.glGenerateMipmap(gl.GL_TEXTURE_2D);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_REPEAT);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_REPEAT);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR_MIPMAP_LINEAR);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR);
    } else {
        std.debug.print("Failed to load texture\n", .{});
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
    gl.glEnable(gl.GL_DEPTH_TEST);
    gl.glDepthFunc(gl.GL_LESS);

    // build/compile shader programs
    var subject_shader = shader.Shader.init(
        allocator,
        "resources/subject.v.glsl",
        "resources/subject.f.glsl"
    ) catch {
        std.debug.print("Failed to initialize lighting shader\n", .{});
        return error.ShaderInitializationFailed;
    };
    defer subject_shader.deinit();
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

    // Set up vertex data for a cube
    const vertices = [_]f32{
        // xyz             norm             uv
        // -Z face
        -0.5, -0.5, -0.5,  0.0, 0.0, -1.0,  0.0, 0.0,
         0.5, -0.5, -0.5,  0.0, 0.0, -1.0,  1.0, 0.0,
         0.5,  0.5, -0.5,  0.0, 0.0, -1.0,  1.0, 1.0,
         0.5,  0.5, -0.5,  0.0, 0.0, -1.0,  1.0, 1.0,
        -0.5,  0.5, -0.5,  0.0, 0.0, -1.0,  0.0, 1.0,
        -0.5, -0.5, -0.5,  0.0, 0.0, -1.0,  0.0, 0.0,

        // +Z face
        -0.5, -0.5,  0.5,  0.0, 0.0, 1.0,  0.0, 0.0,
         0.5, -0.5,  0.5,  0.0, 0.0, 1.0,  1.0, 0.0,
         0.5,  0.5,  0.5,  0.0, 0.0, 1.0,  1.0, 1.0,
         0.5,  0.5,  0.5,  0.0, 0.0, 1.0,  1.0, 1.0,
        -0.5,  0.5,  0.5,  0.0, 0.0, 1.0,  0.0, 1.0,
        -0.5, -0.5,  0.5,  0.0, 0.0, 1.0,  0.0, 0.0,

        // -X face
        -0.5,  0.5,  0.5,  -1.0, 0.0, 0.0,  1.0, 0.0,
        -0.5,  0.5, -0.5,  -1.0, 0.0, 0.0,  1.0, 1.0,
        -0.5, -0.5, -0.5,  -1.0, 0.0, 0.0,  0.0, 1.0,
        -0.5, -0.5, -0.5,  -1.0, 0.0, 0.0,  0.0, 1.0,
        -0.5, -0.5,  0.5,  -1.0, 0.0, 0.0,  0.0, 0.0,
        -0.5,  0.5,  0.5,  -1.0, 0.0, 0.0,  1.0, 0.0,

        // +X face
         0.5,  0.5,  0.5,  1.0, 0.0, 0.0,  1.0, 0.0,
         0.5,  0.5, -0.5,  1.0, 0.0, 0.0,  1.0, 1.0,
         0.5, -0.5, -0.5,  1.0, 0.0, 0.0,  0.0, 1.0,
         0.5, -0.5, -0.5,  1.0, 0.0, 0.0,  0.0, 1.0,
         0.5, -0.5,  0.5,  1.0, 0.0, 0.0,  0.0, 0.0,
         0.5,  0.5,  0.5,  1.0, 0.0, 0.0,  1.0, 0.0,

        // -Y face
        -0.5, -0.5, -0.5,  0.0, -1.0, 0.0,  0.0, 1.0,
         0.5, -0.5, -0.5,  0.0, -1.0, 0.0,  1.0, 1.0,
         0.5, -0.5,  0.5,  0.0, -1.0, 0.0,  1.0, 0.0,
         0.5, -0.5,  0.5,  0.0, -1.0, 0.0,  1.0, 0.0,
        -0.5, -0.5,  0.5,  0.0, -1.0, 0.0,  0.0, 0.0,
        -0.5, -0.5, -0.5,  0.0, -1.0, 0.0,  0.0, 1.0,

        // +Y face
        -0.5,  0.5, -0.5,  0.0, 1.0, 0.0,  0.0, 1.0,
         0.5,  0.5, -0.5,  0.0, 1.0, 0.0,  1.0, 1.0,
         0.5,  0.5,  0.5,  0.0, 1.0, 0.0,  1.0, 0.0,
         0.5,  0.5,  0.5,  0.0, 1.0, 0.0,  1.0, 0.0,
        -0.5,  0.5,  0.5,  0.0, 1.0, 0.0,  0.0, 0.0,
        -0.5,  0.5, -0.5,  0.0, 1.0, 0.0,  0.0, 1.0,
    };

    // define cube positions
    const cube_positions = [_]zlm.Vec3{
        zlm.vec3(0.0, 0.0, 0.0),
        zlm.vec3(2.0, 5.0, -15.0),
        zlm.vec3(-1.5, -2.2, -2.5),
        zlm.vec3(-3.8, -2.0, -12.3),
        zlm.vec3(2.4, -0.4, -3.5),
        zlm.vec3(-1.7, 3.0, -7.5),
        zlm.vec3(1.3, -2.0, -2.5),
        zlm.vec3(1.5, 2.0, -2.5),
        zlm.vec3(1.5, 0.2, -1.5),
        zlm.vec3(-1.3, 1.0, -1.5),
    };

    // First, configure the cube's vertex buffer and array objects
    var vbo: gl.GLuint = 0;
    var cube_vao: gl.GLuint = 0;
    defer gl.glDeleteVertexArrays(1, &cube_vao);
    gl.glGenVertexArrays(1, &cube_vao);
    gl.glGenBuffers(1, &vbo);
    defer gl.glDeleteBuffers(1, &vbo);
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, vbo);
    gl.glBufferData(
        gl.GL_ARRAY_BUFFER,
        @intCast(vertices.len * @sizeOf(f32)),
        &vertices,
        gl.GL_STATIC_DRAW
    );
    gl.glBindVertexArray(cube_vao);

    // define vertex layout
    gl.glVertexAttribPointer(0, 3, gl.GL_FLOAT, gl.GL_FALSE, 8 * @sizeOf(f32), @ptrFromInt(0));
    gl.glEnableVertexAttribArray(0);
    gl.glVertexAttribPointer(1, 3, gl.GL_FLOAT, gl.GL_FALSE, 8 * @sizeOf(f32), @ptrFromInt(3 * @sizeOf(f32)));
    gl.glEnableVertexAttribArray(1);
    gl.glVertexAttribPointer(2, 2, gl.GL_FLOAT, gl.GL_FALSE, 8 * @sizeOf(f32), @ptrFromInt(6 * @sizeOf(f32)));
    gl.glEnableVertexAttribArray(2);

    // configure the light's vertex array object (same buffer object)
    var light_cube_vao: gl.GLuint = 0;
    gl.glGenVertexArrays(1, &light_cube_vao);
    defer gl.glDeleteVertexArrays(1, &light_cube_vao);
    gl.glBindVertexArray(light_cube_vao);
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, vbo);
    gl.glVertexAttribPointer(0, 3, gl.GL_FLOAT, gl.GL_FALSE, 8 * @sizeOf(f32), @ptrFromInt(0));
    gl.glEnableVertexAttribArray(0);

    // load/set texture
    const diffuseMap: gl.GLuint = loadTexture("resources/container2.png") catch {
        std.debug.print("Failed to load texture\n", .{});
        return error.TextureLoadingFailed;
    };
    const specularMap: gl.GLuint = loadTexture("resources/container2_specular.png") catch {
        std.debug.print("Failed to load texture\n", .{});
        return error.TextureLoadingFailed;
    };
    subject_shader.use();
    subject_shader.set_int("material.diffuse", 0);
    subject_shader.set_int("material.specular", 1);

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
 
    // Main loop
    var cam = camera.Camera.init();
    const light_pos = zlm.vec3(1.2, 1.0, 2.0);
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

        // Clear before rendering
        gl.glClearColor(0.1, 0.1, 0.1, 1.0);
        gl.glClear(gl.GL_COLOR_BUFFER_BIT | gl.GL_DEPTH_BUFFER_BIT);

        // set up lighting shader
        subject_shader.use();
        subject_shader.set_vec3("light.position", cam.position.x, cam.position.y, cam.position.z);
        subject_shader.set_vec3("light.direction", cam.front.x, cam.front.y, cam.front.z);
        subject_shader.set_float("light.cutOff", std.math.cos(zlm.radians(12.5)));
        subject_shader.set_float("light.outerCutOff", std.math.cos(zlm.radians(17.5)));
        subject_shader.set_vec3("light.ambient", 0.2, 0.2, 0.2);
        subject_shader.set_vec3("light.diffuse", 0.5, 0.5, 0.5);
        subject_shader.set_vec3("light.specular", 1.0, 1.0, 1.0);
        subject_shader.set_float("light.constant", 1.0);
        subject_shader.set_float("light.linear", 0.7);
        subject_shader.set_float("light.quadratic", 1.8);
        subject_shader.set_vec3("material.specular", 0.5, 0.5, 0.5);
        subject_shader.set_float("material.shininess", 64.0);

        // V/P transformations
        const projection = zlm.Mat4.createPerspective(zlm.radians(cam.zoom), aspect, 0.1, 100.0);
        const view = cam.getViewMatrix();
        subject_shader.set_mat4("projection", zlm.value_ptr(&projection));
        subject_shader.set_mat4("view", zlm.value_ptr(&view));
        subject_shader.set_vec3("viewPos", cam.position.x, cam.position.y, cam.position.z);
        var model = zlm.Mat4.identity;
        subject_shader.set_mat4("model", zlm.value_ptr(&model));

        // bind textures, vertex array
        gl.glActiveTexture(gl.GL_TEXTURE0);
        gl.glBindTexture(gl.GL_TEXTURE_2D, diffuseMap);
        gl.glActiveTexture(gl.GL_TEXTURE1);
        gl.glBindTexture(gl.GL_TEXTURE_2D, specularMap);
        gl.glBindVertexArray(cube_vao);

        // draw cubes
        for (cube_positions, 0..) |pos, i| {
            model = zlm.Mat4.identity;
            model = zlm.translate(model, pos);
            const angle = 20.0 * @as(f32, @floatFromInt(i));
            model = zlm.rotate(model, zlm.radians(angle), zlm.vec3(1.0, 3.0, 0.5));
            subject_shader.set_mat4("model", zlm.value_ptr(&model));
            gl.glDrawArrays(gl.GL_TRIANGLES, 0, 36);
        }

        // Also draw the "lamp" object
        light_cube_shader.use();
        light_cube_shader.set_mat4("projection", zlm.value_ptr(&projection));
        light_cube_shader.set_mat4("view", zlm.value_ptr(&view));
        model = zlm.Mat4.identity;
        model = zlm.scale(model, zlm.vec3(0.2, 0.2, 0.2)); // smaller cube
        model = zlm.translate(model, light_pos);
        light_cube_shader.set_mat4("model", zlm.value_ptr(&model));
        gl.glBindVertexArray(light_cube_vao);
        // gl.glDrawArrays(gl.GL_TRIANGLES, 0, 36);

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

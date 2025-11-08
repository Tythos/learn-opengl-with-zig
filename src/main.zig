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

    var vao: gl.GLuint = 0;
    gl.glGenVertexArrays(1, &vao);
    gl.glBindVertexArray(vao);
    
    const vertices = [_]f32{
        // positions      // colors       // texturre coods
        -0.5, -0.5, 0.0,  1.0, 0.0, 0.0,  0.0, 0.0, // bottom left
        0.5, -0.5, 0.0,   0.0, 1.0, 0.0,  1.0, 0.0, // bottom right
        0.0, 0.5, 0.0,    0.0, 0.0, 1.0,  0.5, 1.0, // top
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

    // load texture1 from resource using stb_image
    var width: c_int = undefined;
    var height: c_int = undefined;
    var channels: c_int = undefined;
    const texture_data = stb_image.stbi_load(
        "resources/wall.jpg",
        &width,
        &height,
        &channels,
        0
    );
    defer stb_image.stbi_image_free(texture_data);
    if (texture_data == null) {
        std.debug.print("Failed to load texture: {s}\n", .{"resources/wall.jpg"});
        return error.TextureLoadFailed;
    }

    // load texture2 from resource using stb_image
    var width2: c_int = undefined;
    var height2: c_int = undefined;
    var channels2: c_int = undefined;
    const texture_data2 = stb_image.stbi_load(
        "resources/awesomeface.png",
        &width2,
        &height2,
        &channels2,
        0
    );
    defer stb_image.stbi_image_free(texture_data2);
    if (texture_data2 == null) {
        std.debug.print("Failed to load texture: {s}\n", .{"resources/awesomeface.png"});
        return error.TextureLoadFailed;
    }

    // create gl texture
    var texture_id: gl.GLuint = 0;
    gl.glGenTextures(1, &texture_id);
    gl.glBindTexture(gl.GL_TEXTURE_2D, texture_id);
    gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, gl.GL_RGB, width, height, 0, gl.GL_RGB, gl.GL_UNSIGNED_BYTE, texture_data);
    gl.glGenerateMipmap(gl.GL_TEXTURE_2D);

    // create gl texture2
    var texture_id2: gl.GLuint = 0;
    gl.glGenTextures(1, &texture_id2);
    gl.glBindTexture(gl.GL_TEXTURE_2D, texture_id2);
    gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, gl.GL_RGB, width2, height2, 0, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, texture_data2);
    gl.glGenerateMipmap(gl.GL_TEXTURE_2D);
    
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
        8 * @sizeOf(f32), // stride: 6 float/vertex
        @ptrFromInt(0) // offset: 0 floats
    );
    gl.glEnableVertexAttribArray(0);

    // define color attribute
    gl.glVertexAttribPointer(
        1,
        3,
        gl.GL_FLOAT,
        gl.GL_FALSE,
        8 * @sizeOf(f32), // stride: 6 floats/vertex
        @ptrFromInt(3 * @sizeOf(f32)) // offset: 3 floats
    );
    gl.glEnableVertexAttribArray(1);

    // define texture coordinate attribute
    gl.glVertexAttribPointer(
        2,
        2,
        gl.GL_FLOAT,
        gl.GL_FALSE,
        8 * @sizeOf(f32), // stride: 6 floats/vertex
        @ptrFromInt(6 * @sizeOf(f32)) // offset: 6 floats
    );
    gl.glEnableVertexAttribArray(2);

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

    // do some camera modeling
    var camera_pos = zlm.vec3(0.0, 0.0, 3.0);
    var camera_front = zlm.vec3(0.0, 0.0, -1.0);
    const camera_up = zlm.vec3(0.0, 1.0, 0.0);

    // create m/v/p matrices
    const fov: f32 = 45.0;
    var model = zlm.rotate(zlm.Mat4.identity, zlm.radians(-55.0), zlm.vec3(1.0, 0.0, 0.0));
    var projection = zlm.Mat4.createPerspective(zlm.radians(fov), aspect, 0.1, 100.0);

    // resolve matrix locations in shader program
    const modelLoc = gl.glGetUniformLocation(triangle_shader.program_id, "model");
    const viewLoc = gl.glGetUniformLocation(triangle_shader.program_id, "view");
    const projectionLoc = gl.glGetUniformLocation(triangle_shader.program_id, "projection");

    // main loop
    var running = true;
    var last_time = sdl.SDL_GetTicks64();
    var is_wireframe = false;
    var num_frames: i32 = 0;
    const start_time = sdl.SDL_GetTicks64();
    var last_x: i32 = 0;
    var last_y: i32 = 0;
    const sensitivity: f32 = 5e-1;
    var yaw: f32 = 0.0;
    var pitch: f32 = 0.0;
    var distance: f32 = 5.0;
    const min_distance = 1.0;
    const max_distance = 10.0;
    var is_mouse_entered = false;
    // var green_value: f32 = 0.0;
    // const start_time = sdl.SDL_GetTicks64();
    // const period_s: f32 = 2.0;
    while (running) {
        const current_time = sdl.SDL_GetTicks64();
        const delta_ms = current_time - last_time;
        const camera_speed: f32 = 1e-4 * @as(f32, @floatFromInt(delta_ms));

        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                sdl.SDL_QUIT => running = false,
                sdl.SDL_KEYDOWN => {
                    const camera_right = camera_front.cross(camera_up).normalize();
                    if (event.key.keysym.sym == sdl.SDLK_ESCAPE) {
                        running = false;
                    }
                    if (event.key.keysym.sym == sdl.SDLK_SPACE) {
                        is_wireframe = !is_wireframe;
                    }
                    if (event.key.keysym.sym == sdl.SDLK_w) {
                        camera_pos = camera_pos.add(camera_front.scale(camera_speed));
                    }
                    if (event.key.keysym.sym == sdl.SDLK_s) {
                        camera_pos = camera_pos.sub(camera_front.scale(camera_speed));
                    }
                    if (event.key.keysym.sym == sdl.SDLK_a) {
                        camera_pos = camera_pos.sub(camera_right.scale(camera_speed));
                    }
                    if (event.key.keysym.sym == sdl.SDLK_d) {
                        camera_pos = camera_pos.add(camera_right.scale(camera_speed));
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
                    yaw += @as(f32, @floatFromInt(dx)) * sensitivity;
                    pitch += @as(f32, @floatFromInt(dy)) * sensitivity;
                    if (pitch > 89.0) { pitch = 89.0; }
                    if (pitch < -89.0) { pitch = -89.0; }
                    // std.debug.print("mouse motion: {}/{}\n", .{dx, dy});
                },
                sdl.SDL_MOUSEWHEEL => {
                    const zoom_delta = @as(f32, @floatFromInt(event.wheel.y));
                    distance -= zoom_delta;
                    distance = std.math.clamp(distance, min_distance, max_distance);
                    camera_pos = camera_pos.normalize().scale(distance);
                },
                else => {},
            }
        }

        // "animate" basic rotation in model matrix
        const dt_s = @as(f32, @floatFromInt(current_time - start_time)) * 1e-3;

        // euler angle camera transform
        var direction = zlm.vec3(0.0, 0.0, 0.0);
        direction.x = std.math.cos(zlm.radians(yaw)) * std.math.cos(zlm.radians(pitch));
        direction.y = std.math.sin(zlm.radians(pitch));
        direction.z = std.math.sin(zlm.radians(yaw)) * std.math.cos(zlm.radians(pitch));
        camera_front = direction.normalize();
        const view = zlm.Mat4.createLookAt(camera_pos, camera_pos.add(camera_front), camera_up);
        projection = zlm.Mat4.createPerspective(zlm.radians(fov), aspect, 0.1, 1000.0);
        
        // clear and map
        clearScreen();
        triangle_shader.use();
        gl.glUniformMatrix4fv(modelLoc, 1, gl.GL_FALSE, zlm.value_ptr(&model));
        gl.glUniformMatrix4fv(viewLoc, 1, gl.GL_FALSE, zlm.value_ptr(&view));
        gl.glUniformMatrix4fv(projectionLoc, 1, gl.GL_FALSE, zlm.value_ptr(&projection));

        // set texture units
        gl.glActiveTexture(gl.GL_TEXTURE0);
        gl.glBindTexture(gl.GL_TEXTURE_2D, texture_id);
        triangle_shader.set_int("texture1", 0);
        gl.glActiveTexture(gl.GL_TEXTURE1);
        gl.glBindTexture(gl.GL_TEXTURE_2D, texture_id2);
        triangle_shader.set_int("texture2", 1);

        // bind and draw (depending on mode)
        gl.glBindVertexArray(vao);
        if (is_wireframe) {
            // Draw wireframe using line indices to show triangle edges
            gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, line_ebo);
            gl.glDrawElements(gl.GL_LINES, 6, gl.GL_UNSIGNED_INT, null);
        } else {
            // Draw filled triangles using triangle indices
            gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, ebo);
            gl.glDrawElements(gl.GL_TRIANGLES, 3, gl.GL_UNSIGNED_INT, null);
        }

        // unbind and swap
        gl.glBindVertexArray(0);
        sdl.SDL_GL_SwapWindow(window);

        // update fps after one second
        num_frames += 1;
        if (delta_ms >= 1000) {
            std.debug.print("FPS={} @ dt={}s\n", .{num_frames, dt_s});
            std.debug.print("yaw={}, pitch={}\n", .{yaw, pitch});
            num_frames = 0;
            last_time = current_time;
        }
    }
    std.debug.print("Application exited\n", .{});
}

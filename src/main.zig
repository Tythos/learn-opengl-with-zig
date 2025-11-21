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

// Post-processing effects
const PostProcessEffect = enum(i32) {
    Normal = 0,
    Inversion = 1,
    Grayscale = 2,
    Sharpen = 3,
    Blur = 4,
    EdgeDetection = 5,

    fn getName(self: PostProcessEffect) []const u8 {
        return switch (self) {
            .Normal => "Normal (No effect)",
            .Inversion => "Inversion",
            .Grayscale => "Grayscale",
            .Sharpen => "Sharpen",
            .Blur => "Blur",
            .EdgeDetection => "Edge Detection",
        };
    }

    fn next(self: PostProcessEffect) PostProcessEffect {
        return switch (self) {
            .Normal => .Inversion,
            .Inversion => .Grayscale,
            .Grayscale => .Sharpen,
            .Sharpen => .Blur,
            .Blur => .EdgeDetection,
            .EdgeDetection => .Normal,
        };
    }
};

fn loadTexture(path: []const u8, flip_vertically: bool) !gl.GLuint {
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
        
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, @intCast(gl.GL_REPEAT));
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, @intCast(gl.GL_REPEAT));
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR_MIPMAP_LINEAR);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR);
    } else {
        std.debug.print("Failed to load texture: {s}\n", .{path});
        return error.TextureLoadingFailed;
    }
    return texture_id;
}

fn loadCubemap(faces: [6][]const u8) !gl.GLuint {
    var texture_id: gl.GLuint = 0;
    gl.glGenTextures(1, &texture_id);
    gl.glBindTexture(gl.GL_TEXTURE_CUBE_MAP, texture_id);
    
    stb_image.stbi_set_flip_vertically_on_load(0);
    
    for (faces, 0..) |face_path, i| {
        var width: i32 = 0;
        var height: i32 = 0;
        var nrChannels: i32 = 0;
        const data: ?*u8 = stb_image.stbi_load(face_path.ptr, &width, &height, &nrChannels, 0);
        
        if (data != null) {
            defer stb_image.stbi_image_free(data);
            gl.glTexImage2D(
                gl.GL_TEXTURE_CUBE_MAP_POSITIVE_X + @as(c_uint, @intCast(i)),
                0,
                gl.GL_RGB,
                width,
                height,
                0,
                gl.GL_RGB,
                gl.GL_UNSIGNED_BYTE,
                data
            );
        } else {
            std.debug.print("Cubemap texture failed to load at path: {s}\n", .{face_path});
            return error.CubemapLoadingFailed;
        }
    }
    
    gl.glTexParameteri(gl.GL_TEXTURE_CUBE_MAP, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR);
    gl.glTexParameteri(gl.GL_TEXTURE_CUBE_MAP, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR);
    gl.glTexParameteri(gl.GL_TEXTURE_CUBE_MAP, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
    gl.glTexParameteri(gl.GL_TEXTURE_CUBE_MAP, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);
    gl.glTexParameteri(gl.GL_TEXTURE_CUBE_MAP, gl.GL_TEXTURE_WRAP_R, gl.GL_CLAMP_TO_EDGE);
    
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
        "Learn OpenGL With Zig - Cubemaps Skybox",
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
    var scene_shader = shader.Shader.init(
        allocator,
        "resources/cubemaps.v.glsl",
        "resources/cubemaps.f.glsl"
    ) catch {
        std.debug.print("Failed to initialize scene shader\n", .{});
        return error.ShaderInitializationFailed;
    };
    defer scene_shader.deinit();

    var skybox_shader = shader.Shader.init(
        allocator,
        "resources/skybox.v.glsl",
        "resources/skybox.f.glsl"
    ) catch {
        std.debug.print("Failed to initialize skybox shader\n", .{});
        return error.ShaderInitializationFailed;
    };
    defer skybox_shader.deinit();

    // Cube vertices (position + texture coords)
    const cube_vertices = [_]f32{
        // Back face
        -0.5, -0.5, -0.5,  0.0, 0.0,
         0.5,  0.5, -0.5,  1.0, 1.0,
         0.5, -0.5, -0.5,  1.0, 0.0,
         0.5,  0.5, -0.5,  1.0, 1.0,
        -0.5, -0.5, -0.5,  0.0, 0.0,
        -0.5,  0.5, -0.5,  0.0, 1.0,
        // Front face
        -0.5, -0.5,  0.5,  0.0, 0.0,
         0.5, -0.5,  0.5,  1.0, 0.0,
         0.5,  0.5,  0.5,  1.0, 1.0,
         0.5,  0.5,  0.5,  1.0, 1.0,
        -0.5,  0.5,  0.5,  0.0, 1.0,
        -0.5, -0.5,  0.5,  0.0, 0.0,
        // Left face
        -0.5,  0.5,  0.5,  1.0, 0.0,
        -0.5,  0.5, -0.5,  1.0, 1.0,
        -0.5, -0.5, -0.5,  0.0, 1.0,
        -0.5, -0.5, -0.5,  0.0, 1.0,
        -0.5, -0.5,  0.5,  0.0, 0.0,
        -0.5,  0.5,  0.5,  1.0, 0.0,
        // Right face
         0.5,  0.5,  0.5,  1.0, 0.0,
         0.5, -0.5, -0.5,  0.0, 1.0,
         0.5,  0.5, -0.5,  1.0, 1.0,
         0.5, -0.5, -0.5,  0.0, 1.0,
         0.5,  0.5,  0.5,  1.0, 0.0,
         0.5, -0.5,  0.5,  0.0, 0.0,
        // Bottom face
        -0.5, -0.5, -0.5,  0.0, 1.0,
         0.5, -0.5, -0.5,  1.0, 1.0,
         0.5, -0.5,  0.5,  1.0, 0.0,
         0.5, -0.5,  0.5,  1.0, 0.0,
        -0.5, -0.5,  0.5,  0.0, 0.0,
        -0.5, -0.5, -0.5,  0.0, 1.0,
        // Top face
        -0.5,  0.5, -0.5,  0.0, 1.0,
         0.5,  0.5,  0.5,  1.0, 0.0,
         0.5,  0.5, -0.5,  1.0, 1.0,
         0.5,  0.5,  0.5,  1.0, 0.0,
        -0.5,  0.5, -0.5,  0.0, 1.0,
        -0.5,  0.5,  0.5,  0.0, 0.0,
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

    // Skybox vertices (only positions, no texture coords)
    const skybox_vertices = [_]f32{
        // positions          
        -1.0,  1.0, -1.0,
        -1.0, -1.0, -1.0,
         1.0, -1.0, -1.0,
         1.0, -1.0, -1.0,
         1.0,  1.0, -1.0,
        -1.0,  1.0, -1.0,

        -1.0, -1.0,  1.0,
        -1.0, -1.0, -1.0,
        -1.0,  1.0, -1.0,
        -1.0,  1.0, -1.0,
        -1.0,  1.0,  1.0,
        -1.0, -1.0,  1.0,

         1.0, -1.0, -1.0,
         1.0, -1.0,  1.0,
         1.0,  1.0,  1.0,
         1.0,  1.0,  1.0,
         1.0,  1.0, -1.0,
         1.0, -1.0, -1.0,

        -1.0, -1.0,  1.0,
        -1.0,  1.0,  1.0,
         1.0,  1.0,  1.0,
         1.0,  1.0,  1.0,
         1.0, -1.0,  1.0,
        -1.0, -1.0,  1.0,

        -1.0,  1.0, -1.0,
         1.0,  1.0, -1.0,
         1.0,  1.0,  1.0,
         1.0,  1.0,  1.0,
        -1.0,  1.0,  1.0,
        -1.0,  1.0, -1.0,

        -1.0, -1.0, -1.0,
        -1.0, -1.0,  1.0,
         1.0, -1.0, -1.0,
         1.0, -1.0, -1.0,
        -1.0, -1.0,  1.0,
         1.0, -1.0,  1.0,
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

    // Skybox VAO
    var skybox_vao: gl.GLuint = 0;
    var skybox_vbo: gl.GLuint = 0;
    gl.glGenVertexArrays(1, &skybox_vao);
    gl.glGenBuffers(1, &skybox_vbo);
    defer gl.glDeleteVertexArrays(1, &skybox_vao);
    defer gl.glDeleteBuffers(1, &skybox_vbo);
    
    gl.glBindVertexArray(skybox_vao);
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, skybox_vbo);
    gl.glBufferData(gl.GL_ARRAY_BUFFER, @intCast(skybox_vertices.len * @sizeOf(f32)), &skybox_vertices, gl.GL_STATIC_DRAW);
    gl.glEnableVertexAttribArray(0);
    gl.glVertexAttribPointer(0, 3, gl.GL_FLOAT, gl.GL_FALSE, 3 * @sizeOf(f32), @ptrFromInt(0));

    // Load textures
    const cube_texture = loadTexture("resources/container2.png", true) catch {
        std.debug.print("Failed to load cube texture\n", .{});
        return error.TextureLoadingFailed;
    };
    
    // Load cubemap
    const skybox_faces = [_][]const u8{
        "resources/skybox/right.jpg",
        "resources/skybox/left.jpg",
        "resources/skybox/top.jpg",
        "resources/skybox/bottom.jpg",
        "resources/skybox/front.jpg",
        "resources/skybox/back.jpg",
    };
    const cubemap_texture = loadCubemap(skybox_faces) catch {
        std.debug.print("Failed to load cubemap texture\n", .{});
        return error.TextureLoadingFailed;
    };

    // Set up shader uniforms
    scene_shader.use();
    scene_shader.set_int("texture1", 0);

    skybox_shader.use();
    skybox_shader.set_int("skybox", 0);

    // Initialize camera
    var cam = camera.Camera.init();
    
    std.debug.print("\n=== CUBEMAPS SKYBOX DEMO ===\n", .{});
    std.debug.print("This demo renders a skybox using a cubemap texture.\n", .{});
    std.debug.print("The skybox appears infinitely distant and surrounds the scene.\n\n", .{});
    std.debug.print("Controls:\n", .{});
    std.debug.print("  Mouse: Rotate camera (orbit)\n", .{});
    std.debug.print("  Scroll: Zoom in/out\n", .{});
    std.debug.print("  ESC: Exit\n\n", .{});

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

        // Clear screen
        gl.glClearColor(0.1, 0.1, 0.1, 1.0);
        gl.glClear(gl.GL_COLOR_BUFFER_BIT | gl.GL_DEPTH_BUFFER_BIT);

        // Draw scene
        scene_shader.use();
        const projection = zlm.Mat4.createPerspective(zlm.radians(cam.zoom), aspect, 0.1, 100.0);
        var view = cam.getViewMatrix();
        scene_shader.set_mat4("projection", zlm.value_ptr(&projection));
        scene_shader.set_mat4("view", zlm.value_ptr(&view));

        // Draw cube
        gl.glBindVertexArray(cube_vao);
        gl.glActiveTexture(gl.GL_TEXTURE0);
        gl.glBindTexture(gl.GL_TEXTURE_2D, cube_texture);
        var model = zlm.Mat4.identity;
        scene_shader.set_mat4("model", zlm.value_ptr(&model));
        gl.glDrawArrays(gl.GL_TRIANGLES, 0, 36);

        // Draw skybox as last
        gl.glDepthFunc(gl.GL_LEQUAL); // Change depth function so depth test passes when values are equal to depth buffer's content
        skybox_shader.use();
        // Remove translation from view matrix
        view = zlm.Mat4{
            .fields = .{
                .{ view.fields[0][0], view.fields[0][1], view.fields[0][2], 0.0 },
                .{ view.fields[1][0], view.fields[1][1], view.fields[1][2], 0.0 },
                .{ view.fields[2][0], view.fields[2][1], view.fields[2][2], 0.0 },
                .{ 0.0, 0.0, 0.0, 1.0 },
            },
        };
        skybox_shader.set_mat4("view", zlm.value_ptr(&view));
        skybox_shader.set_mat4("projection", zlm.value_ptr(&projection));
        // Skybox cube
        gl.glBindVertexArray(skybox_vao);
        gl.glActiveTexture(gl.GL_TEXTURE0);
        gl.glBindTexture(gl.GL_TEXTURE_CUBE_MAP, cubemap_texture);
        gl.glDrawArrays(gl.GL_TRIANGLES, 0, 36);
        gl.glBindVertexArray(0);
        gl.glDepthFunc(gl.GL_LESS); // Set depth function back to default

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

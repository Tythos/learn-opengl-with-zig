const std = @import("std");
const gl = @import("gl.zig");

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

pub const Shader = struct {
    const Self = @This();

    program_id: gl.GLuint,

    pub fn init(allocator: std.mem.Allocator, vertex_path: []const u8, fragment_path: []const u8) !Shader {
        // load vertex shader source from file
        const vertex_glsl = try loadFile(allocator, vertex_path);
        defer allocator.free(vertex_glsl);
        const vertex_shader: gl.GLuint = gl.glCreateShader(gl.GL_VERTEX_SHADER);
        defer gl.glDeleteShader(vertex_shader);

        // load fragment shader source from file
        const fragment_glsl = try loadFile(allocator, fragment_path);
        defer allocator.free(fragment_glsl);
        const fragment_shader: gl.GLuint = gl.glCreateShader(gl.GL_FRAGMENT_SHADER);
        defer gl.glDeleteShader(fragment_shader);

        // compile vertex shader
        const vertex_length: gl.GLint = @intCast(vertex_glsl.len);
        gl.glShaderSource(vertex_shader, 1, &vertex_glsl.ptr, &vertex_length);
        gl.glCompileShader(vertex_shader);
        var compile_status: gl.GLint = undefined;
        gl.glGetShaderiv(vertex_shader, gl.GL_COMPILE_STATUS, &compile_status);
        if (compile_status == gl.GL_FALSE) {
            var log_length: gl.GLint = 0;
            gl.glGetShaderiv(vertex_shader, gl.GL_INFO_LOG_LENGTH, &log_length);
            const info = allocator.alloc(u8, @intCast(log_length)) catch {
                std.debug.print("Error: Failed to allocate memory for shader log\n", .{});
                return error.OutOfMemory;
            };
            defer allocator.free(info);
            gl.glGetShaderInfoLog(vertex_shader, @intCast(log_length), null, info.ptr);
            std.debug.print("Vertex shader compilation failed: {s}\n", .{info});
            return error.VertexShaderCompilationFailed;
        }

        // compile fragment shader
        const fragment_length: gl.GLint = @intCast(fragment_glsl.len);
        gl.glShaderSource(fragment_shader, 1, &fragment_glsl.ptr, &fragment_length);
        gl.glCompileShader(fragment_shader);
        gl.glGetShaderiv(fragment_shader, gl.GL_COMPILE_STATUS, &compile_status);
        if (compile_status == gl.GL_FALSE) {
            var log_length: gl.GLint = 0;
            gl.glGetShaderiv(fragment_shader, gl.GL_INFO_LOG_LENGTH, &log_length);
            const info = allocator.alloc(u8, @intCast(log_length)) catch {
                std.debug.print("Error: Failed to allocate memory for shader log\n", .{});
                return error.OutOfMemory;
            };
            defer allocator.free(info);
            gl.glGetShaderInfoLog(fragment_shader, @intCast(log_length), null, info.ptr);
            std.debug.print("Fragment shader compilation failed: {s}\n", .{info});
            return error.FragmentShaderCompilationFailed;
        }

        // link program
        const program_id = gl.glCreateProgram();
        gl.glAttachShader(program_id, vertex_shader);
        gl.glAttachShader(program_id, fragment_shader);
        gl.glLinkProgram(program_id);
        var link_status: gl.GLint = undefined;
        gl.glGetProgramiv(program_id, gl.GL_LINK_STATUS, &link_status);
        if (link_status == gl.GL_FALSE) {
            var log_length: gl.GLint = 0;
            gl.glGetProgramiv(program_id, gl.GL_INFO_LOG_LENGTH, &log_length);
            const info = allocator.alloc(u8, @intCast(log_length)) catch {
                std.debug.print("Error: Failed to allocate memory for shader log\n", .{});
                return error.OutOfMemory;
            };
            defer allocator.free(info);
            gl.glGetProgramInfoLog(program_id, @intCast(log_length), null, info.ptr);
            std.debug.print("Shader program linking failed: {s}\n", .{info});
            return error.ShaderProgramLinkingFailed;
        }

        return Shader{ .program_id = program_id };
    }

    pub fn deinit(self: Self) void {
        gl.glDeleteProgram(self.program_id);
    }

    pub fn use(self: Self) void {
        gl.glUseProgram(self.program_id);
    }

    pub fn set_bool(self: Self, name: [*c]const u8, value: bool) void {
        gl.glUniform1i(gl.glGetUniformLocation(self.program_id, name), if (value) gl.GL_TRUE else gl.GL_FALSE);
    }

    pub fn set_int(self: Self, name: [*c]const u8, value: i32) void {
        gl.glUniform1i(gl.glGetUniformLocation(self.program_id, name), value);
    }

    pub fn set_float(self: Self, name: [*c]const u8, value: f32) void {
        gl.glUniform1f(gl.glGetUniformLocation(self.program_id, name), value);
    }
};

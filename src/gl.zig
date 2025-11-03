const std = @import("std");
const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
});

// OpenGL types
pub const GLuint = c_uint;
pub const GLint = c_int;
pub const GLsizei = c_int;
pub const GLsizeiptr = isize;
pub const GLenum = c_uint;
pub const GLbitfield = c_uint;
pub const GLboolean = u8;
pub const GLfloat = f32;
pub const GLchar = u8;

// OpenGL constants
pub const GL_FALSE: GLboolean = 0;
pub const GL_TRUE: GLboolean = 1;

pub const GL_COLOR_BUFFER_BIT: GLbitfield = 0x00004000;
pub const GL_DEPTH_BUFFER_BIT: GLbitfield = 0x00000100;

pub const GL_DEPTH_TEST: GLenum = 0x0B71;
pub const GL_LESS: GLenum = 0x0201;

// Error codes
pub const GL_NO_ERROR: GLenum = 0;
pub const GL_INVALID_ENUM: GLenum = 0x0500;
pub const GL_INVALID_VALUE: GLenum = 0x0501;
pub const GL_INVALID_OPERATION: GLenum = 0x0502;
pub const GL_OUT_OF_MEMORY: GLenum = 0x0505;

pub const GL_VERTEX_SHADER: GLenum = 0x8B31;
pub const GL_FRAGMENT_SHADER: GLenum = 0x8B30;

pub const GL_COMPILE_STATUS: GLenum = 0x8B81;
pub const GL_LINK_STATUS: GLenum = 0x8B82;
pub const GL_INFO_LOG_LENGTH: GLenum = 0x8B84;

pub const GL_ARRAY_BUFFER: GLenum = 0x8892;
pub const GL_STATIC_DRAW: GLenum = 0x88E4;

pub const GL_FLOAT: GLenum = 0x1406;
pub const GL_TRIANGLES: GLenum = 0x0004;
pub const GL_LINES: GLenum = 0x0001;
pub const GL_LINE_LOOP: GLenum = 0x0002;
pub const GL_UNSIGNED_INT: GLenum = 0x1405;
pub const GL_ELEMENT_ARRAY_BUFFER: GLenum = 0x8893;

pub const GL_FRONT_AND_BACK: GLenum = 0x0408;
pub const GL_LINE: GLenum = 0x1B01;
pub const GL_FILL: GLenum = 0x1B02;

pub const GL_MAX_VERTEX_ATTRIBS: GLenum = 0x8869;

// OpenGL function pointers
pub var glCreateShader: *const fn (GLenum) callconv(.C) GLuint = undefined;
pub var glShaderSource: *const fn (GLuint, GLsizei, [*c]const [*c]const GLchar, [*c]const GLint) callconv(.C) void = undefined;
pub var glCompileShader: *const fn (GLuint) callconv(.C) void = undefined;
pub var glGetShaderiv: *const fn (GLuint, GLenum, [*c]GLint) callconv(.C) void = undefined;
pub var glGetShaderInfoLog: *const fn (GLuint, GLsizei, [*c]GLsizei, [*c]GLchar) callconv(.C) void = undefined;
pub var glDeleteShader: *const fn (GLuint) callconv(.C) void = undefined;

pub var glCreateProgram: *const fn () callconv(.C) GLuint = undefined;
pub var glAttachShader: *const fn (GLuint, GLuint) callconv(.C) void = undefined;
pub var glLinkProgram: *const fn (GLuint) callconv(.C) void = undefined;
pub var glGetProgramiv: *const fn (GLuint, GLenum, [*c]GLint) callconv(.C) void = undefined;
pub var glGetProgramInfoLog: *const fn (GLuint, GLsizei, [*c]GLsizei, [*c]GLchar) callconv(.C) void = undefined;
pub var glUseProgram: *const fn (GLuint) callconv(.C) void = undefined;
pub var glDeleteProgram: *const fn (GLuint) callconv(.C) void = undefined;
pub var glGetUniformLocation: *const fn (GLuint, [*c]const GLchar) callconv(.C) GLint = undefined;
pub var glUniform1f: *const fn (GLint, GLfloat) callconv(.C) void = undefined;
pub var glUniformMatrix4fv: *const fn (GLint, GLsizei, GLboolean, [*c]const GLfloat) callconv(.C) void = undefined;

pub var glGenVertexArrays: *const fn (GLsizei, [*c]GLuint) callconv(.C) void = undefined;
pub var glBindVertexArray: *const fn (GLuint) callconv(.C) void = undefined;
pub var glDeleteVertexArrays: *const fn (GLsizei, [*c]const GLuint) callconv(.C) void = undefined;

pub var glGenBuffers: *const fn (GLsizei, [*c]GLuint) callconv(.C) void = undefined;
pub var glBindBuffer: *const fn (GLenum, GLuint) callconv(.C) void = undefined;
pub var glBufferData: *const fn (GLenum, GLsizeiptr, ?*const anyopaque, GLenum) callconv(.C) void = undefined;
pub var glDeleteBuffers: *const fn (GLsizei, [*c]const GLuint) callconv(.C) void = undefined;

pub var glVertexAttribPointer: *const fn (GLuint, GLint, GLenum, GLboolean, GLsizei, ?*const anyopaque) callconv(.C) void = undefined;
pub var glEnableVertexAttribArray: *const fn (GLuint) callconv(.C) void = undefined;

pub var glClearColor: *const fn (GLfloat, GLfloat, GLfloat, GLfloat) callconv(.C) void = undefined;
pub var glClear: *const fn (GLbitfield) callconv(.C) void = undefined;
pub var glDrawArrays: *const fn (GLenum, GLint, GLsizei) callconv(.C) void = undefined;
pub var glDrawElements: *const fn (GLenum, GLsizei, GLenum, ?*const anyopaque) callconv(.C) void = undefined;

pub var glViewport: *const fn (GLint, GLint, GLsizei, GLsizei) callconv(.C) void = undefined;
pub var glEnable: *const fn (GLenum) callconv(.C) void = undefined;
pub var glDepthFunc: *const fn (GLenum) callconv(.C) void = undefined;
pub var glGetError: *const fn () callconv(.C) GLenum = undefined;
pub var glPolygonMode: *const fn (GLenum, GLenum) callconv(.C) void = undefined;
pub var glGetIntegerv: *const fn (GLenum, [*c]GLint) callconv(.C) void = undefined;

/// Load an OpenGL function pointer using SDL
fn loadFunction(comptime T: type, name: [*:0]const u8) T {
    const proc = sdl.SDL_GL_GetProcAddress(name);
    if (proc == null) {
        std.debug.print("Warning: Failed to load OpenGL function: {s}\n", .{name});
        @panic("Failed to load required OpenGL function");
    }
    return @ptrCast(@alignCast(proc));
}

/// Initialize OpenGL function pointers
pub fn loadFunctions() void {
    std.debug.print("Loading OpenGL functions...\n", .{});
    
    glCreateShader = loadFunction(@TypeOf(glCreateShader), "glCreateShader");
    glShaderSource = loadFunction(@TypeOf(glShaderSource), "glShaderSource");
    glCompileShader = loadFunction(@TypeOf(glCompileShader), "glCompileShader");
    glGetShaderiv = loadFunction(@TypeOf(glGetShaderiv), "glGetShaderiv");
    glGetShaderInfoLog = loadFunction(@TypeOf(glGetShaderInfoLog), "glGetShaderInfoLog");
    glDeleteShader = loadFunction(@TypeOf(glDeleteShader), "glDeleteShader");
    
    glCreateProgram = loadFunction(@TypeOf(glCreateProgram), "glCreateProgram");
    glAttachShader = loadFunction(@TypeOf(glAttachShader), "glAttachShader");
    glLinkProgram = loadFunction(@TypeOf(glLinkProgram), "glLinkProgram");
    glGetProgramiv = loadFunction(@TypeOf(glGetProgramiv), "glGetProgramiv");
    glGetProgramInfoLog = loadFunction(@TypeOf(glGetProgramInfoLog), "glGetProgramInfoLog");
    glUseProgram = loadFunction(@TypeOf(glUseProgram), "glUseProgram");
    glDeleteProgram = loadFunction(@TypeOf(glDeleteProgram), "glDeleteProgram");
    glGetUniformLocation = loadFunction(@TypeOf(glGetUniformLocation), "glGetUniformLocation");
    glUniform1f = loadFunction(@TypeOf(glUniform1f), "glUniform1f");
    glUniformMatrix4fv = loadFunction(@TypeOf(glUniformMatrix4fv), "glUniformMatrix4fv");
    
    glGenVertexArrays = loadFunction(@TypeOf(glGenVertexArrays), "glGenVertexArrays");
    glBindVertexArray = loadFunction(@TypeOf(glBindVertexArray), "glBindVertexArray");
    glDeleteVertexArrays = loadFunction(@TypeOf(glDeleteVertexArrays), "glDeleteVertexArrays");
    
    glGenBuffers = loadFunction(@TypeOf(glGenBuffers), "glGenBuffers");
    glBindBuffer = loadFunction(@TypeOf(glBindBuffer), "glBindBuffer");
    glBufferData = loadFunction(@TypeOf(glBufferData), "glBufferData");
    glDeleteBuffers = loadFunction(@TypeOf(glDeleteBuffers), "glDeleteBuffers");
    
    glVertexAttribPointer = loadFunction(@TypeOf(glVertexAttribPointer), "glVertexAttribPointer");
    glEnableVertexAttribArray = loadFunction(@TypeOf(glEnableVertexAttribArray), "glEnableVertexAttribArray");
    
    glClearColor = loadFunction(@TypeOf(glClearColor), "glClearColor");
    glClear = loadFunction(@TypeOf(glClear), "glClear");
    glDrawArrays = loadFunction(@TypeOf(glDrawArrays), "glDrawArrays");
    glDrawElements = loadFunction(@TypeOf(glDrawElements), "glDrawElements");
    
    glViewport = loadFunction(@TypeOf(glViewport), "glViewport");
    glEnable = loadFunction(@TypeOf(glEnable), "glEnable");
    
    glEnable = loadFunction(@TypeOf(glEnable), "glEnable");
    glDepthFunc = loadFunction(@TypeOf(glDepthFunc), "glDepthFunc");
    glGetError = loadFunction(@TypeOf(glGetError), "glGetError");
    glPolygonMode = loadFunction(@TypeOf(glPolygonMode), "glPolygonMode");
    glGetIntegerv = loadFunction(@TypeOf(glGetIntegerv), "glGetIntegerv");
    
    std.debug.print("OpenGL functions loaded successfully\n", .{});
}

/// Check for OpenGL errors and print them (useful for debugging)
pub fn checkError(context: []const u8) void {
    const err = glGetError();
    if (err != GL_NO_ERROR) {
        std.debug.print("OpenGL Error in {s}: 0x{X}\n", .{ context, err });
    }
}

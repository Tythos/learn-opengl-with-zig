const std = @import("std");
const gl = @import("gl.zig");
const zlm = @import("zlm");
const Shader = @import("shader.zig").Shader;

pub const MAX_BONE_INFLUENCE = 4;

/// Vertex data structure containing position, normal, texture coordinates,
/// tangent space data, and skeletal animation data
pub const Vertex = struct {
    position: zlm.Vec3,
    normal: zlm.Vec3,
    tex_coords: zlm.Vec2,
    tangent: zlm.Vec3,
    bitangent: zlm.Vec3,
    bone_ids: [MAX_BONE_INFLUENCE]i32,
    bone_weights: [MAX_BONE_INFLUENCE]f32,
};

/// Texture data structure
pub const Texture = struct {
    id: gl.GLuint,
    type_name: []const u8,
    path: []const u8,
};

/// Mesh represents a renderable 3D mesh with vertex data, indices, and textures
pub const Mesh = struct {
    const Self = @This();

    vertices: []const Vertex,
    indices: []const u32,
    textures: []const Texture,
    vao: gl.GLuint,
    vbo: gl.GLuint,
    ebo: gl.GLuint,

    /// Initialize a mesh with vertex data, indices, and textures.
    /// The caller retains ownership of the data slices.
    pub fn init(vertices: []const Vertex, indices: []const u32, textures: []const Texture) !Self {
        var mesh = Self{
            .vertices = vertices,
            .indices = indices,
            .textures = textures,
            .vao = 0,
            .vbo = 0,
            .ebo = 0,
        };

        mesh.setupMesh();
        return mesh;
    }

    /// Clean up OpenGL resources
    pub fn deinit(self: *Self) void {
        gl.glDeleteVertexArrays(1, &self.vao);
        gl.glDeleteBuffers(1, &self.vbo);
        gl.glDeleteBuffers(1, &self.ebo);
    }

    /// Render the mesh using the provided shader
    pub fn draw(self: *const Self, shader: *const Shader) void {
        // Bind appropriate textures
        var diffuse_nr: u32 = 1;
        var specular_nr: u32 = 1;
        var normal_nr: u32 = 1;
        var height_nr: u32 = 1;

        for (self.textures, 0..) |texture, i| {
            gl.glActiveTexture(gl.GL_TEXTURE0 + @as(gl.GLenum, @intCast(i)));

            // Retrieve texture number (the N in diffuse_textureN)
            var number_buf: [32]u8 = undefined;
            const number_str = blk: {
                if (std.mem.eql(u8, texture.type_name, "texture_diffuse")) {
                    const num_str = std.fmt.bufPrint(&number_buf, "{d}", .{diffuse_nr}) catch unreachable;
                    diffuse_nr += 1;
                    break :blk num_str;
                } else if (std.mem.eql(u8, texture.type_name, "texture_specular")) {
                    const num_str = std.fmt.bufPrint(&number_buf, "{d}", .{specular_nr}) catch unreachable;
                    specular_nr += 1;
                    break :blk num_str;
                } else if (std.mem.eql(u8, texture.type_name, "texture_normal")) {
                    const num_str = std.fmt.bufPrint(&number_buf, "{d}", .{normal_nr}) catch unreachable;
                    normal_nr += 1;
                    break :blk num_str;
                } else if (std.mem.eql(u8, texture.type_name, "texture_height")) {
                    const num_str = std.fmt.bufPrint(&number_buf, "{d}", .{height_nr}) catch unreachable;
                    height_nr += 1;
                    break :blk num_str;
                } else {
                    break :blk "1";
                }
            };

            // Build the uniform name (e.g., "texture_diffuse1")
            var uniform_name_buf: [64]u8 = undefined;
            const uniform_name = std.fmt.bufPrintZ(&uniform_name_buf, "{s}{s}", .{ texture.type_name, number_str }) catch unreachable;

            // Set the sampler to the correct texture unit
            shader.set_int(uniform_name.ptr, @intCast(i));

            // Bind the texture
            gl.glBindTexture(gl.GL_TEXTURE_2D, texture.id);
        }

        // Draw mesh
        gl.glBindVertexArray(self.vao);
        gl.glDrawElements(gl.GL_TRIANGLES, @intCast(self.indices.len), gl.GL_UNSIGNED_INT, null);
        gl.glBindVertexArray(0);

        // Set everything back to defaults
        gl.glActiveTexture(gl.GL_TEXTURE0);
    }

    /// Initialize OpenGL buffers and vertex attributes
    fn setupMesh(self: *Self) void {
        // Create buffers/arrays
        gl.glGenVertexArrays(1, &self.vao);
        gl.glGenBuffers(1, &self.vbo);
        gl.glGenBuffers(1, &self.ebo);

        gl.glBindVertexArray(self.vao);

        // Load data into vertex buffers
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vbo);
        const vertices_size = self.vertices.len * @sizeOf(Vertex);
        gl.glBufferData(gl.GL_ARRAY_BUFFER, @intCast(vertices_size), self.vertices.ptr, gl.GL_STATIC_DRAW);

        // Load data into element buffer
        gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, self.ebo);
        const indices_size = self.indices.len * @sizeOf(u32);
        gl.glBufferData(gl.GL_ELEMENT_ARRAY_BUFFER, @intCast(indices_size), self.indices.ptr, gl.GL_STATIC_DRAW);

        // Set vertex attribute pointers
        const stride: gl.GLsizei = @sizeOf(Vertex);

        // Vertex positions
        gl.glEnableVertexAttribArray(0);
        gl.glVertexAttribPointer(0, 3, gl.GL_FLOAT, gl.GL_FALSE, stride, @ptrFromInt(@offsetOf(Vertex, "position")));

        // Vertex normals
        gl.glEnableVertexAttribArray(1);
        gl.glVertexAttribPointer(1, 3, gl.GL_FLOAT, gl.GL_FALSE, stride, @ptrFromInt(@offsetOf(Vertex, "normal")));

        // Vertex texture coords
        gl.glEnableVertexAttribArray(2);
        gl.glVertexAttribPointer(2, 2, gl.GL_FLOAT, gl.GL_FALSE, stride, @ptrFromInt(@offsetOf(Vertex, "tex_coords")));

        // Vertex tangent
        gl.glEnableVertexAttribArray(3);
        gl.glVertexAttribPointer(3, 3, gl.GL_FLOAT, gl.GL_FALSE, stride, @ptrFromInt(@offsetOf(Vertex, "tangent")));

        // Vertex bitangent
        gl.glEnableVertexAttribArray(4);
        gl.glVertexAttribPointer(4, 3, gl.GL_FLOAT, gl.GL_FALSE, stride, @ptrFromInt(@offsetOf(Vertex, "bitangent")));

        // Bone IDs (integer attribute)
        gl.glEnableVertexAttribArray(5);
        gl.glVertexAttribIPointer(5, 4, gl.GL_INT, stride, @ptrFromInt(@offsetOf(Vertex, "bone_ids")));

        // Bone weights
        gl.glEnableVertexAttribArray(6);
        gl.glVertexAttribPointer(6, 4, gl.GL_FLOAT, gl.GL_FALSE, stride, @ptrFromInt(@offsetOf(Vertex, "bone_weights")));

        gl.glBindVertexArray(0);
    }
};

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

pub const Model = struct {
    const Self = @This();

    meshes: []const Mesh,
    directory: []const u8,

    pub fn init(path: []const u8) !Self {
    }

    pub fn Draw(self: *Self, shader: *const Shader) void {
        for (self.meshes) |mesh| {
            mesh.draw(shader);
        }
    }

    fn loadModel(self: *Self, path: []const u8) !void {
        var importer = assimp.Importer.init();
        const scene = importer.importFile(path);
        if (scene == null || scene.mFlags & assimp.aiSceneFlags.INCOMPLETE != 0 || scene.mRootNode == null) {
            std.debug.print("Failed to load model\n", .{});
            return error.ModelLoadingFailed;
        }
        self.directory = std.fs.path.dirname(path).?;d
        self.processNode(scene.mRootNode, scene);
    }

    fn processNode(self: *Self, node: *const aiNode, scene: *const aiScene) !void {
        for (0..node.mNumMeshes) |i| {
            const mesh = scene.mMeshes[node.mMeshes[i]];
            try self.meshes.append(self.processMesh(mesh, scene));
        }
        for (0..node.mNumChildren) |i| {
            try self.processNode(node.mChildren[i], scene);
        }
    }

    fn processMesh(self: *Self, mesh: *const aiMesh, scene: *const aiScene) !Mesh {
        var vertices: []Vertex = undefined;
        var indices: []u32 = undefined;
        var textures: []Texture = undefined;
        for (0..mesh.mNumVertices) |i| {
            if (mesh.mTextureCoords[0] == null) {
                vertices.append(Vertex{
                    .position = zlm.vec3(mesh.mVertices[i].x, mesh.mVertices[i].y, mesh.mVertices[i].z),
                    .normal = zlm.vec3(mesh.mNormals[i].x, mesh.mNormals[i].y, mesh.mNormals[i].z),
                    .tex_coords = zlm.vec2(0.0, 0.0),
                });
            } else {
                vertices.append(Vertex{
                    .position = zlm.vec3(mesh.mVertices[i].x, mesh.mVertices[i].y, mesh.mVertices[i].z),
                    .normal = zlm.vec3(mesh.mNormals[i].x, mesh.mNormals[i].y, mesh.mNormals[i].z),
                    .tex_coords = zlm.vec2(mesh.mTextureCoords[0][i].x, mesh.mTextureCoords[0][i].y),
                });
            }
        }
        if (mesh.mMaterialIndex >= 0) {
            var material = scene.mMaterials[mesh.mMaterialIndex];
            var diffuse_maps = try self.loadMaterialTextures(material, assimp.aiTextureType.DIFFUSE, "texture_diffuse", scene);
            textures.append(textures.end(), diffuse_maps.begin(), diffuse_maps.end());
            var specular_maps = try self.loadMaterialTextures(material, assimp.aiTextureType.SPECULAR, "texture_specular", scene);
            textures.append(textures.end(), specular_maps.begin(), specular_maps.end());
        }
        for (0..mesh.mNumFaces) |i| {
            const face = mesh.mFaces[i];
            for (0..face.mNumIndices) |j| {
                indices.append(face.mIndices[j]);
            }
        }
        return try Mesh.init(vertices, indices, textures);
    }

    fn loadMaterialTextures(self: *Self, mat: *const aiMaterial, type: aiTextureType, type_name: []const u8) ![]Texture {
        var textures: []Texture = undefined;
        for (0..mat.GetTextureCount(type)) |i| {
            const path = mat.GetTexture(type, i);
            if (path == null) {
                continue;
            }
            var texture: Texture = undefined;
            texture.id = TextureFromFile(path.C_Str(), self.directory);
            texture.type = type_name;
            texture.path = str;
            textures.append(texture);
        }
        return textures;
    }
};

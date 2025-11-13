const std = @import("std");
const gl = @import("gl.zig");
const zlm = @import("zlm").as(f32);
const Shader = @import("shader.zig").Shader;

const assimp = @cImport({
    @cInclude("assimp/cimport.h");
    @cInclude("assimp/scene.h");
    @cInclude("assimp/postprocess.h");
});

const stb_image = @cImport({
    @cInclude("stb_image.h");
});

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

    allocator: std.mem.Allocator,
    meshes: std.ArrayList(Mesh),
    textures_loaded: std.ArrayList(Texture),
    directory: []const u8,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) !Self {
        var model = Self{
            .allocator = allocator,
            .meshes = std.ArrayList(Mesh).init(allocator),
            .textures_loaded = std.ArrayList(Texture).init(allocator),
            .directory = "",
        };

        try model.loadModel(path);
        return model;
    }

    pub fn deinit(self: *Self) void {
        for (self.meshes.items) |*mesh| {
            mesh.deinit();
        }
        self.meshes.deinit();
        
        // Free loaded textures
        for (self.textures_loaded.items) |texture| {
            self.allocator.free(texture.path);
        }
        self.textures_loaded.deinit();
        
        if (self.directory.len > 0) {
            self.allocator.free(self.directory);
        }
    }

    pub fn draw(self: *const Self, shader: *const Shader) void {
        for (self.meshes.items) |*mesh| {
            mesh.draw(shader);
        }
    }

    fn loadModel(self: *Self, path: []const u8) !void {
        const path_z = try self.allocator.dupeZ(u8, path);
        defer self.allocator.free(path_z);

        // Import the scene
        const scene = assimp.aiImportFile(
            path_z.ptr,
            assimp.aiProcess_Triangulate | assimp.aiProcess_FlipUVs | assimp.aiProcess_CalcTangentSpace
        );

        if (scene == null or (scene.*.mFlags & assimp.AI_SCENE_FLAGS_INCOMPLETE) != 0 or scene.*.mRootNode == null) {
            const err_str = assimp.aiGetErrorString();
            std.debug.print("Assimp error: {s}\n", .{err_str});
            return error.ModelLoadingFailed;
        }

        // Store directory path
        if (std.fs.path.dirname(path)) |dir| {
            self.directory = try self.allocator.dupe(u8, dir);
        } else {
            self.directory = try self.allocator.dupe(u8, ".");
        }

        // Process the scene
        try self.processNode(scene.*.mRootNode, scene);

        // Clean up the scene
        assimp.aiReleaseImport(scene);
    }

    fn processNode(self: *Self, node: *const assimp.aiNode, scene: *const assimp.aiScene) !void {
        // Process all the node's meshes
        var i: u32 = 0;
        while (i < node.*.mNumMeshes) : (i += 1) {
            const mesh_index = node.*.mMeshes[i];
            const mesh = scene.*.mMeshes[mesh_index];
            const processed_mesh = try self.processMesh(mesh, scene);
            try self.meshes.append(processed_mesh);
        }

        // Process children nodes
        i = 0;
        while (i < node.*.mNumChildren) : (i += 1) {
            try self.processNode(node.*.mChildren[i], scene);
        }
    }

    fn processMesh(self: *Self, mesh: *const assimp.aiMesh, scene: *const assimp.aiScene) !Mesh {
        var vertices = std.ArrayList(Vertex).init(self.allocator);
        defer vertices.deinit();
        
        var indices = std.ArrayList(u32).init(self.allocator);
        defer indices.deinit();
        
        var textures = std.ArrayList(Texture).init(self.allocator);
        defer textures.deinit();

        // Process vertices
        var i: u32 = 0;
        while (i < mesh.*.mNumVertices) : (i += 1) {
            const vertex = Vertex{
                .position = zlm.Vec3.new(
                    mesh.*.mVertices[i].x,
                    mesh.*.mVertices[i].y,
                    mesh.*.mVertices[i].z
                ),
                .normal = if (mesh.*.mNormals != null)
                    zlm.Vec3.new(
                        mesh.*.mNormals[i].x,
                        mesh.*.mNormals[i].y,
                        mesh.*.mNormals[i].z
                    )
                else
                    zlm.Vec3.zero,
                .tex_coords = if (mesh.*.mTextureCoords[0] != null)
                    zlm.Vec2.new(
                        mesh.*.mTextureCoords[0][i].x,
                        mesh.*.mTextureCoords[0][i].y
                    )
                else
                    zlm.Vec2.zero,
                .tangent = if (mesh.*.mTangents != null)
                    zlm.Vec3.new(
                        mesh.*.mTangents[i].x,
                        mesh.*.mTangents[i].y,
                        mesh.*.mTangents[i].z
                    )
                else
                    zlm.Vec3.zero,
                .bitangent = if (mesh.*.mBitangents != null)
                    zlm.Vec3.new(
                        mesh.*.mBitangents[i].x,
                        mesh.*.mBitangents[i].y,
                        mesh.*.mBitangents[i].z
                    )
                else
                    zlm.Vec3.zero,
                .bone_ids = [_]i32{-1} ** MAX_BONE_INFLUENCE,
                .bone_weights = [_]f32{0.0} ** MAX_BONE_INFLUENCE,
            };

            try vertices.append(vertex);
        }

        // Process indices
        i = 0;
        while (i < mesh.*.mNumFaces) : (i += 1) {
            const face = mesh.*.mFaces[i];
            var j: u32 = 0;
            while (j < face.mNumIndices) : (j += 1) {
                try indices.append(face.mIndices[j]);
            }
        }

        // Process material
        if (mesh.*.mMaterialIndex >= 0) {
            const material = scene.*.mMaterials[mesh.*.mMaterialIndex];
            
            // Diffuse maps
            const diffuse_maps = try self.loadMaterialTextures(material, assimp.aiTextureType_DIFFUSE, "texture_diffuse");
            try textures.appendSlice(diffuse_maps);
            self.allocator.free(diffuse_maps);
            
            // Specular maps
            const specular_maps = try self.loadMaterialTextures(material, assimp.aiTextureType_SPECULAR, "texture_specular");
            try textures.appendSlice(specular_maps);
            self.allocator.free(specular_maps);
            
            // Normal maps
            const normal_maps = try self.loadMaterialTextures(material, assimp.aiTextureType_HEIGHT, "texture_normal");
            try textures.appendSlice(normal_maps);
            self.allocator.free(normal_maps);
            
            // Height maps
            const height_maps = try self.loadMaterialTextures(material, assimp.aiTextureType_AMBIENT, "texture_height");
            try textures.appendSlice(height_maps);
            self.allocator.free(height_maps);
        }

        // Convert to owned slices
        const vertices_owned = try vertices.toOwnedSlice();
        const indices_owned = try indices.toOwnedSlice();
        const textures_owned = try textures.toOwnedSlice();

        return try Mesh.init(vertices_owned, indices_owned, textures_owned);
    }

    fn loadMaterialTextures(self: *Self, mat: *const assimp.aiMaterial, texture_type: assimp.aiTextureType, type_name: []const u8) ![]Texture {
        var textures = std.ArrayList(Texture).init(self.allocator);
        
        const texture_count = assimp.aiGetMaterialTextureCount(mat, texture_type);
        var i: u32 = 0;
        while (i < texture_count) : (i += 1) {
            var path: assimp.aiString = undefined;
            if (assimp.aiGetMaterialTexture(mat, texture_type, i, &path, null, null, null, null, null, null) == assimp.aiReturn_SUCCESS) {
                const path_str = std.mem.sliceTo(&path.data, 0);
                
                // Check if texture was already loaded
                var skip = false;
                for (self.textures_loaded.items) |loaded_tex| {
                    if (std.mem.eql(u8, loaded_tex.path, path_str)) {
                        try textures.append(loaded_tex);
                        skip = true;
                        break;
                    }
                }
                
                if (!skip) {
                    const texture_id = try self.textureFromFile(path_str);
                    const path_dupe = try self.allocator.dupe(u8, path_str);
                    const texture = Texture{
                        .id = texture_id,
                        .type_name = type_name,
                        .path = path_dupe,
                    };
                    try textures.append(texture);
                    try self.textures_loaded.append(texture);
                }
            }
        }
        
        return try textures.toOwnedSlice();
    }

    fn textureFromFile(self: *Self, filename: []const u8) !gl.GLuint {
        // Build full path
        var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
        const full_path = try std.fmt.bufPrintZ(&path_buf, "{s}/{s}", .{ self.directory, filename });
        
        var texture_id: gl.GLuint = 0;
        gl.glGenTextures(1, &texture_id);
        
        var width: i32 = 0;
        var height: i32 = 0;
        var nr_components: i32 = 0;
        
        const data = stb_image.stbi_load(full_path.ptr, &width, &height, &nr_components, 0);
        if (data != null) {
            defer stb_image.stbi_image_free(data);
            
            var format: gl.GLenum = gl.GL_RGB;
            if (nr_components == 1) {
                format = gl.GL_RED;
            } else if (nr_components == 3) {
                format = gl.GL_RGB;
            } else if (nr_components == 4) {
                format = gl.GL_RGBA;
            }
            
            gl.glBindTexture(gl.GL_TEXTURE_2D, texture_id);
            gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, @intCast(format), width, height, 0, format, gl.GL_UNSIGNED_BYTE, data);
            gl.glGenerateMipmap(gl.GL_TEXTURE_2D);
            
            gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_REPEAT);
            gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_REPEAT);
            gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR_MIPMAP_LINEAR);
            gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR);
        } else {
            std.debug.print("Failed to load texture: {s}\n", .{full_path});
            return error.TextureLoadFailed;
        }
        
        return texture_id;
    }
};

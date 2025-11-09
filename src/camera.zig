const std = @import("std");
const zlm = @import("zlm").as(f32);
const gl = @import("gl.zig");

/// Movement directions for camera control
pub const CameraMovement = enum {
    forward,
    backward,
    left,
    right,
};

// Default camera values
const DEFAULT_YAW: f32 = -90.0;
const DEFAULT_PITCH: f32 = 0.0;
const DEFAULT_SPEED: f32 = 2.5;
const DEFAULT_SENSITIVITY: f32 = 0.1;
const DEFAULT_ZOOM: f32 = 45.0;

/// A camera system that processes input and calculates corresponding
/// Euler angles, vectors and matrices for use in OpenGL
pub const Camera = struct {
    const Self = @This();

    // Camera attributes
    position: zlm.Vec3,
    front: zlm.Vec3,
    up: zlm.Vec3,
    right: zlm.Vec3,
    world_up: zlm.Vec3,

    // Euler angles
    yaw: f32,
    pitch: f32,

    // Camera options
    movement_speed: f32,
    mouse_sensitivity: f32,
    zoom: f32,

    /// Initialize camera with vector parameters
    pub fn initVectors(
        position: zlm.Vec3,
        world_up: zlm.Vec3,
        yaw: f32,
        pitch: f32,
    ) Camera {
        var camera = Camera{
            .position = position,
            .front = zlm.Vec3.new(0.0, 0.0, -1.0),
            .up = zlm.Vec3.zero,
            .right = zlm.Vec3.zero,
            .world_up = world_up,
            .yaw = yaw,
            .pitch = pitch,
            .movement_speed = DEFAULT_SPEED,
            .mouse_sensitivity = DEFAULT_SENSITIVITY,
            .zoom = DEFAULT_ZOOM,
        };
        camera.updateCameraVectors();
        return camera;
    }

    /// Initialize camera with default values
    pub fn init() Camera {
        return initVectors(
            zlm.Vec3.new(0.0, 0.0, 0.0),
            zlm.Vec3.new(0.0, 1.0, 0.0),
            DEFAULT_YAW,
            DEFAULT_PITCH,
        );
    }

    /// Initialize camera with scalar values
    pub fn initScalars(
        pos_x: f32,
        pos_y: f32,
        pos_z: f32,
        up_x: f32,
        up_y: f32,
        up_z: f32,
        yaw: f32,
        pitch: f32,
    ) Camera {
        return initVectors(
            zlm.Vec3.new(pos_x, pos_y, pos_z),
            zlm.Vec3.new(up_x, up_y, up_z),
            yaw,
            pitch,
        );
    }

    /// Returns the view matrix calculated using Euler angles and the LookAt matrix
    pub fn getViewMatrix(self: Self) zlm.Mat4 {
        return zlm.Mat4.createLookAt(
            self.position,
            self.position.add(self.front),
            self.up,
        );
    }

    /// Processes input received from keyboard-like input system
    pub fn processKeyboard(self: *Self, direction: CameraMovement, delta_time: f32) void {
        const velocity = self.movement_speed * delta_time;
        switch (direction) {
            .forward => {
                self.position = self.position.add(self.front.scale(velocity));
            },
            .backward => {
                self.position = self.position.sub(self.front.scale(velocity));
            },
            .left => {
                self.position = self.position.sub(self.right.scale(velocity));
            },
            .right => {
                self.position = self.position.add(self.right.scale(velocity));
            },
        }
    }

    /// Processes input received from mouse movement
    pub fn processMouseMovement(
        self: *Self,
        xoffset: f32,
        yoffset: f32,
        constrain_pitch: bool,
    ) void {
        const x_adjusted = xoffset * self.mouse_sensitivity;
        const y_adjusted = yoffset * self.mouse_sensitivity;

        self.yaw += x_adjusted;
        self.pitch += y_adjusted;

        // Constrain pitch to prevent screen flip
        if (constrain_pitch) {
            if (self.pitch > 89.0) {
                self.pitch = 89.0;
            }
            if (self.pitch < -89.0) {
                self.pitch = -89.0;
            }
        }

        // Update Front, Right and Up vectors using updated Euler angles
        self.updateCameraVectors();
    }

    /// Processes input received from mouse scroll wheel
    pub fn processMouseScroll(self: *Self, yoffset: f32) void {
        self.zoom -= yoffset;
        if (self.zoom < 1.0) {
            self.zoom = 1.0;
        }
        if (self.zoom > 45.0) {
            self.zoom = 45.0;
        }
    }

    /// Calculates the front vector from the camera's updated Euler angles
    fn updateCameraVectors(self: *Self) void {
        // Calculate the new Front vector
        const yaw_rad = std.math.degreesToRadians(self.yaw);
        const pitch_rad = std.math.degreesToRadians(self.pitch);

        var front: zlm.Vec3 = undefined;
        front.x = @cos(yaw_rad) * @cos(pitch_rad);
        front.y = @sin(pitch_rad);
        front.z = @sin(yaw_rad) * @cos(pitch_rad);

        self.front = front.normalize();

        // Recalculate Right and Up vectors
        // Normalize vectors because their length gets closer to 0 the more you
        // look up or down, which results in slower movement
        self.right = self.front.cross(self.world_up).normalize();
        self.up = self.right.cross(self.front).normalize();
    }
};

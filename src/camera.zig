const std = @import("std");
const zlm = @import("zlm").as(f32);
const gl = @import("gl.zig");

// Default camera values for orbit camera
const DEFAULT_RADIUS: f32 = 5.0;
const DEFAULT_MIN_RADIUS: f32 = 1.0;
const DEFAULT_MAX_RADIUS: f32 = 20.0;
const DEFAULT_THETA: f32 = 0.0; // Azimuth angle (horizontal rotation)
const DEFAULT_PHI: f32 = 45.0;  // Elevation angle (vertical rotation)
const DEFAULT_SENSITIVITY: f32 = 0.5;
const DEFAULT_ZOOM_SENSITIVITY: f32 = 0.5;
const DEFAULT_ZOOM: f32 = 45.0;

/// Orbit camera that rotates around a fixed target point
pub const Camera = struct {
    const Self = @This();

    // Orbit parameters
    target: zlm.Vec3,
    radius: f32,
    theta: f32,  // Azimuth (horizontal angle in degrees)
    phi: f32,    // Elevation (vertical angle in degrees)
    
    // Computed camera attributes
    position: zlm.Vec3,
    front: zlm.Vec3,
    up: zlm.Vec3,
    right: zlm.Vec3,
    world_up: zlm.Vec3,

    // Camera options
    mouse_sensitivity: f32,
    zoom_sensitivity: f32,
    zoom: f32,
    min_radius: f32,
    max_radius: f32,

    /// Initialize orbit camera with custom parameters
    pub fn initOrbit(
        target: zlm.Vec3,
        radius: f32,
        theta: f32,
        phi: f32,
    ) Camera {
        var camera = Camera{
            .target = target,
            .radius = radius,
            .theta = theta,
            .phi = phi,
            .position = zlm.Vec3.zero,
            .front = zlm.Vec3.zero,
            .up = zlm.Vec3.zero,
            .right = zlm.Vec3.zero,
            .world_up = zlm.Vec3.new(0.0, 1.0, 0.0),
            .mouse_sensitivity = DEFAULT_SENSITIVITY,
            .zoom_sensitivity = DEFAULT_ZOOM_SENSITIVITY,
            .zoom = DEFAULT_ZOOM,
            .min_radius = DEFAULT_MIN_RADIUS,
            .max_radius = DEFAULT_MAX_RADIUS,
        };
        camera.updateCameraPosition();
        return camera;
    }

    /// Initialize camera with default orbit values
    pub fn init() Camera {
        return initOrbit(
            zlm.Vec3.new(0.0, 0.0, 0.0), // Look at origin
            DEFAULT_RADIUS,
            DEFAULT_THETA,
            DEFAULT_PHI,
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


    /// Processes input received from mouse movement for orbit camera
    pub fn processMouseMovement(
        self: *Self,
        xoffset: f32,
        yoffset: f32,
    ) void {
        // Update azimuth (horizontal rotation)
        self.theta += xoffset * self.mouse_sensitivity;
        
        // Update elevation (vertical rotation)
        self.phi -= yoffset * self.mouse_sensitivity;

        // Constrain phi to prevent flipping
        if (self.phi > 89.0) {
            self.phi = 89.0;
        }
        if (self.phi < -89.0) {
            self.phi = -89.0;
        }

        // Update camera position based on new angles
        self.updateCameraPosition();
    }

    /// Processes input received from mouse scroll wheel (adjusts distance)
    pub fn processMouseScroll(self: *Self, yoffset: f32) void {
        self.radius -= yoffset * self.zoom_sensitivity;
        
        // Clamp radius to min/max values
        if (self.radius < self.min_radius) {
            self.radius = self.min_radius;
        }
        if (self.radius > self.max_radius) {
            self.radius = self.max_radius;
        }

        // Update camera position based on new radius
        self.updateCameraPosition();
    }

    /// Calculates the camera position from spherical coordinates
    fn updateCameraPosition(self: *Self) void {
        // Convert spherical coordinates to Cartesian
        const theta_rad = std.math.degreesToRadians(self.theta);
        const phi_rad = std.math.degreesToRadians(self.phi);

        // Calculate position relative to target
        const x = self.radius * @cos(phi_rad) * @cos(theta_rad);
        const y = self.radius * @sin(phi_rad);
        const z = self.radius * @cos(phi_rad) * @sin(theta_rad);

        self.position = zlm.Vec3.new(x, y, z).add(self.target);

        // Calculate camera direction (from position to target)
        self.front = self.target.sub(self.position).normalize();

        // Recalculate Right and Up vectors
        self.right = self.front.cross(self.world_up).normalize();
        self.up = self.right.cross(self.front).normalize();
    }
};

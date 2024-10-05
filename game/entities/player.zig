const std = @import("std");
const delve = @import("delve");
const math = delve.math;

pub const PlayerControllerComponent = struct {
    time: f32 = 0.0,
    name: []const u8,

    camera: delve.graphics.camera.Camera = undefined,

    pub fn init(self: *PlayerControllerComponent) void {
        self.camera = delve.graphics.camera.Camera.init(90.0, 0.01, 512, math.Vec3.up);
        self.camera.position.y = 10.0;
    }

    pub fn deinit(self: *PlayerControllerComponent) void {
        _ = self;
    }

    pub fn tick(self: *PlayerControllerComponent, delta: f32) void {
        self.time += delta;

        // do mouse look
        self.camera.runSimpleCamera(30 * delta, 60 * delta, true);
    }
};

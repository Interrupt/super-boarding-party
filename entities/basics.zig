const std = @import("std");
const delve = @import("delve");
const entities = @import("../game/entities.zig");
const math = delve.math;

/// The EntityComponent that gives a world location and rotation to an Entity
pub const TransformComponent = struct {
    position: math.Vec3 = math.Vec3.zero,
    rotation: math.Quaternion = math.Quaternion.identity,
    scale: math.Vec3 = math.Vec3.one,

    pub fn init(self: *TransformComponent, interface: entities.EntityComponent) void {
        _ = self;
        _ = interface;
    }

    pub fn deinit(self: *TransformComponent) void {
        _ = self;
    }

    pub fn tick(self: *TransformComponent, delta: f32) void {
        _ = self;
        _ = delta;
    }
};

const std = @import("std");
const delve = @import("delve");
const entities = @import("../game/entities.zig");
const main = @import("../main.zig");

const math = delve.math;

/// Gives a physical collision AABB to an Entity
pub const BoxCollisionComponent = struct {
    size: math.Vec3 = math.Vec3.one,

    owner: entities.Entity = entities.InvalidEntity,

    pub fn init(self: *BoxCollisionComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;
    }

    pub fn deinit(self: *BoxCollisionComponent) void {
        _ = self;
    }

    pub fn tick(self: *BoxCollisionComponent, delta: f32) void {
        _ = self;
        _ = delta;
    }

    pub fn renderDebug(self: *BoxCollisionComponent) void {
        main.render_instance.drawDebugCube(self.getPosition(), self.size, delve.math.Vec3.x_axis, delve.colors.red);
    }
};

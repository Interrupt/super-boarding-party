const std = @import("std");
const delve = @import("delve");
const entities = @import("../game/entities.zig");
const main = @import("../main.zig");

const math = delve.math;
const spatial = delve.spatial;

/// Gives a physical collision AABB to an Entity
pub const BoxCollisionComponent = struct {
    size: math.Vec3 = math.Vec3.one.scale(2.5),

    owner: entities.Entity = entities.InvalidEntity,

    pub fn init(self: *BoxCollisionComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;
    }

    pub fn deinit(self: *BoxCollisionComponent) void {
        _ = self;
    }

    pub fn tick(self: *BoxCollisionComponent, delta: f32) void {
        _ = delta;

        self.renderDebug();
    }

    pub fn renderDebug(self: *BoxCollisionComponent) void {
        _ = self;
        // main.render_instance.drawDebugCube(self.owner.getPosition(), delve.math.Vec3.zero, self.size, delve.math.Vec3.x_axis, delve.colors.red);
    }

    pub fn getBoundingBox(self: *BoxCollisionComponent) spatial.BoundingBox {
        return delve.spatial.BoundingBox.init(self.owner.getPosition(), self.size);
    }
};

pub fn getComponentStorage(world: *entities.World) *entities.ComponentStorage(BoxCollisionComponent) {
    return world.components.getStorageForType(BoxCollisionComponent) catch {
        delve.debug.fatal("Could not get BoxCollisionComponent storage!", .{});
        return undefined;
    };
}

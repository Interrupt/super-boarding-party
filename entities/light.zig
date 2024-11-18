const std = @import("std");
const delve = @import("delve");
const entities = @import("../game/entities.zig");
const math = delve.math;

/// Adds a dynamic light to this entity
pub const LightComponent = struct {
    // properties
    color: delve.colors.Color = delve.colors.white,
    radius: f32 = 4.0,
    brightness: f32 = 1.0,
    is_directional: bool = false,

    position: math.Vec3 = math.Vec3.zero,
    position_offset: math.Vec3 = math.Vec3.zero,

    // interface
    owner: entities.Entity = entities.InvalidEntity,

    // calculated
    world_position: math.Vec3 = undefined,
    world_rotation: math.Quaternion = undefined,

    pub fn init(self: *LightComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;
    }

    pub fn deinit(self: *LightComponent) void {
        _ = self;
    }

    pub fn tick(self: *LightComponent, delta: f32) void {
        _ = delta;

        // cache our final world position
        const owner_rotation = self.owner.getRotation();
        self.world_position = self.owner.getPosition().add(owner_rotation.rotateVec3(self.position)).add(self.position_offset);
        self.world_rotation = owner_rotation;
    }
};

pub fn getComponentStorage(world: *entities.World) *entities.ComponentStorage(LightComponent) {
    return world.components.getStorageForType(LightComponent) catch {
        delve.debug.fatal("Could not get LightComponent storage!", .{});
        return undefined;
    };
}

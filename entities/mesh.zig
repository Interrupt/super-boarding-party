const std = @import("std");
const delve = @import("delve");
const math = delve.math;
const entities = @import("../game/entities.zig");

pub const MeshComponent = struct {
    position: math.Vec3,
    scale: f32 = 4.0,
    color: delve.colors.Color = delve.colors.white,
    position_offset: math.Vec3 = math.Vec3.zero,
    rotation_offset: math.Quaternion = math.Quaternion.identity,

    mesh_path: []const u8 = "meshes/SciFiHelmet.gltf",
    mesh: delve.graphics.mesh.Mesh = undefined,

    attach_to_parent: bool = true,

    // interface
    owner: entities.Entity = entities.InvalidEntity,

    // calculated
    world_position: math.Vec3 = undefined,

    pub fn init(self: *MeshComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;
    }

    pub fn deinit(self: *MeshComponent) void {
        _ = self;
    }

    pub fn tick(self: *MeshComponent, delta: f32) void {
        _ = delta;

        // cache our final world position
        if (self.attach_to_parent) {
            const owner_rotation = self.owner.getRotation();
            self.world_position = self.owner.getRenderPosition().add(owner_rotation.rotateVec3(self.position));
        } else {
            self.world_position = self.position;
        }
    }
};

pub fn getComponentStorage(world: *entities.World) *entities.ComponentStorage(MeshComponent) {
    return world.components.getStorageForType(MeshComponent) catch {
        delve.debug.fatal("Could not get MeshComponent storage!", .{});
        return undefined;
    };
}

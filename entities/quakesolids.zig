const std = @import("std");
const delve = @import("delve");
const basics = @import("basics.zig");
const actor_stats = @import("actor_stats.zig");
const box_collision = @import("box_collision.zig");
const character = @import("character.zig");
const monster = @import("monster.zig");
const sprites = @import("sprite.zig");
const entities = @import("../game/entities.zig");
const quakemap = @import("quakemap.zig");
const spatialhash = @import("../utils/spatial_hash.zig");

const math = delve.math;
const spatial = delve.spatial;
const graphics = delve.platform.graphics;

pub var spatial_hash: spatialhash.SpatialHash(QuakeSolidsComponent) = undefined;
pub var did_init_spatial_hash: bool = false;

pub const QuakeSolidsComponent = struct {
    // properties
    transform: math.Mat4,

    // the quake entity
    quake_map: *delve.utils.quakemap.QuakeMap,
    quake_entity: *delve.utils.quakemap.Entity,

    // interface
    owner: entities.Entity = entities.InvalidEntity,

    // calculated
    meshes: std.ArrayList(delve.graphics.mesh.Mesh) = undefined,
    bounds: delve.spatial.BoundingBox = undefined,
    starting_pos: math.Vec3 = undefined,

    pub fn init(self: *QuakeSolidsComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;

        const allocator = delve.mem.getAllocator();
        self.meshes = self.quake_map.buildMeshesForEntity(self.quake_entity, allocator, math.Mat4.identity, &quakemap.materials, &quakemap.fallback_quake_material) catch {
            delve.debug.log("Could not make quake entity solid meshes", .{});
            return;
        };

        self.bounds = self.getBounds();
        self.owner.setPosition(self.bounds.center);
        self.starting_pos = self.bounds.center;

        if (self.owner.getComponent(box_collision.BoxCollisionComponent)) |box| {
            box.size = self.bounds.max.sub(self.bounds.min);
        }
    }

    pub fn getEntitySolids(self: *QuakeSolidsComponent) []delve.utils.quakemap.Solid {
        return self.quake_entity.solids.items;
    }

    pub fn deinit(self: *QuakeSolidsComponent) void {
        _ = self;
    }

    pub fn tick(self: *QuakeSolidsComponent, delta: f32) void {
        _ = self;
        _ = delta;
    }

    pub fn getBounds(self: *QuakeSolidsComponent) spatial.BoundingBox {
        const floatMax = std.math.floatMax(f32);
        const floatMin = std.math.floatMin(f32);

        var min: math.Vec3 = math.Vec3.new(floatMax, floatMax, floatMax);
        var max: math.Vec3 = math.Vec3.new(floatMin, floatMin, floatMin);

        for (self.quake_entity.solids.items) |*solid| {
            for (solid.faces.items) |*face| {
                const face_bounds = spatial.BoundingBox.initFromPositions(face.vertices);
                min = math.Vec3.min(min, face_bounds.min);
                max = math.Vec3.max(max, face_bounds.max);
            }
        }

        return spatial.BoundingBox{
            .center = math.Vec3.new(min.x + (max.x - min.x) * 0.5, min.y + (max.y - min.y) * 0.5, min.z + (max.z - min.z) * 0.5),
            .min = min,
            .max = max,
        };
    }
};

pub fn updateSpatialHash(world: *entities.World) void {
    if (!did_init_spatial_hash) {
        spatial_hash = spatialhash.SpatialHash(QuakeSolidsComponent).init(4.0, delve.mem.getAllocator());
        did_init_spatial_hash = true;
    }

    spatial_hash.clear();

    var it = getComponentStorage(world).iterator();
    while (it.next()) |c| {
        spatial_hash.addEntry(c, c.bounds, false) catch {
            continue;
        };
    }
}

pub fn getComponentStorage(world: *entities.World) *entities.ComponentStorage(QuakeSolidsComponent) {
    return world.components.getStorageForType(QuakeSolidsComponent) catch {
        delve.debug.fatal("Could not get QuakeSolidsComponent storage!", .{});
        return undefined;
    };
}

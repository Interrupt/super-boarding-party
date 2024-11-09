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

// materials!
var did_init_materials: bool = false;
var fallback_material: graphics.Material = undefined;
var fallback_quake_material: delve.utils.quakemap.QuakeMaterial = undefined;
var materials: std.StringHashMap(delve.utils.quakemap.QuakeMaterial) = undefined;

// shader setup
const lit_shader = delve.shaders.default_basic_lighting;
const basic_lighting_fs_uniforms: []const delve.platform.graphics.MaterialUniformDefaults = &[_]delve.platform.graphics.MaterialUniformDefaults{ .CAMERA_POSITION, .COLOR_OVERRIDE, .ALPHA_CUTOFF, .AMBIENT_LIGHT, .DIRECTIONAL_LIGHT, .POINT_LIGHTS_16, .FOG_DATA };

pub const QuakeSolidsComponent = struct {
    // properties
    transform: math.Mat4,

    time: f32 = 0.0,

    // the quake entity
    quake_map: *delve.utils.quakemap.QuakeMap = undefined,
    quake_entity: delve.utils.quakemap.Entity = undefined,

    // meshes for drawing
    meshes: std.ArrayList(delve.graphics.mesh.Mesh) = undefined,

    // interface
    owner: entities.Entity = entities.InvalidEntity,

    pub fn init(self: *QuakeSolidsComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;

        const allocator = delve.mem.getAllocator();
        self.meshes = self.quake_map.buildMeshesForEntity(&self.quake_entity, allocator, math.Mat4.identity, &quakemap.materials, &quakemap.fallback_quake_material) catch {
            return;
        };
    }

    pub fn getEntitySolids(self: *QuakeSolidsComponent) []delve.utils.quakemap.Solid {
        return self.quake_entity.solids.items;
    }

    pub fn deinit(self: *QuakeSolidsComponent) void {
        _ = self;
    }

    pub fn tick(self: *QuakeSolidsComponent, delta: f32) void {
        self.time += delta;
    }
};

pub fn getBoundsForSolid(solid: *delve.utils.quakemap.Solid) spatial.BoundingBox {
    const floatMax = std.math.floatMax(f32);
    const floatMin = std.math.floatMin(f32);

    var min: math.Vec3 = math.Vec3.new(floatMax, floatMax, floatMax);
    var max: math.Vec3 = math.Vec3.new(floatMin, floatMin, floatMin);

    for (solid.faces.items) |*face| {
        const face_bounds = spatial.BoundingBox.initFromPositions(face.vertices);
        min = math.Vec3.min(min, face_bounds.min);
        max = math.Vec3.max(max, face_bounds.max);
    }

    return spatial.BoundingBox{
        .center = math.Vec3.new(min.x + (max.x - min.x) * 0.5, min.y + (max.y - min.y) * 0.5, min.z + (max.z - min.z) * 0.5),
        .min = min,
        .max = max,
    };
}

pub fn getComponentStorage(world: *entities.World) *entities.ComponentStorage(QuakeSolidsComponent) {
    return world.components.getStorageForType(QuakeSolidsComponent) catch {
        delve.debug.fatal("Could not get QuakeSolidsComponent storage!", .{});
        return undefined;
    };
}

const std = @import("std");
const delve = @import("delve");
const collision = @import("../utils/collision.zig");
const basics = @import("basics.zig");
const actor_stats = @import("actor_stats.zig");
const box_collision = @import("box_collision.zig");
const character = @import("character.zig");
const main = @import("../main.zig");
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
    hidden: bool = false,
    collides_entities: bool = true,

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
        for (self.meshes.items) |*m| {
            m.deinit();
        }
        self.meshes.deinit();
    }

    pub fn getBounds(self: *QuakeSolidsComponent) spatial.BoundingBox {
        const floatMax = std.math.floatMax(f32);
        const floatMin = -floatMax;

        var max: math.Vec3 = math.Vec3.new(floatMin, floatMin, floatMin);
        var min: math.Vec3 = math.Vec3.new(floatMax, floatMax, floatMax);

        for (self.quake_entity.solids.items) |*solid| {
            for (solid.faces.items) |*face| {
                for (face.vertices) |*vert| {
                    min.x = @min(vert.x, min.x);
                    min.y = @min(vert.y, min.y);
                    min.z = @min(vert.z, min.z);

                    max.x = @max(vert.x, max.x);
                    max.y = @max(vert.y, max.y);
                    max.z = @max(vert.z, max.z);
                }
            }
        }

        return spatial.BoundingBox{
            .center = math.Vec3.new(min.x + (max.x - min.x) * 0.5, min.y + (max.y - min.y) * 0.5, min.z + (max.z - min.z) * 0.5),
            .min = min,
            .max = max,
        };
    }

    pub fn checkCollision(self: *QuakeSolidsComponent, pos: math.Vec3, size: math.Vec3) bool {
        const offset_amount = self.owner.getPosition().sub(self.starting_pos);
        const offset_bounds = delve.spatial.BoundingBox.init(pos.sub(offset_amount), size);

        for (self.quake_entity.solids.items) |solid| {
            const did_collide = solid.checkBoundingBoxCollision(offset_bounds);
            if (did_collide) {
                return true;
            }
        }

        return false;
    }

    pub fn checkEntityCollision(self: *QuakeSolidsComponent, offset: math.Vec3, checking: entities.Entity) ?entities.Entity {
        if (!self.collides_entities)
            return null;

        const offset_amount = self.owner.getPosition().sub(self.starting_pos);
        var adj_bounds = self.bounds;
        adj_bounds.min = adj_bounds.min.add(offset_amount);
        adj_bounds.max = adj_bounds.max.add(offset_amount);
        adj_bounds.center = adj_bounds.center.add(offset_amount);

        const found = box_collision.spatial_hash.getEntriesNear(adj_bounds);
        for (found) |box| {
            if (!box.collides_entities or checking.id.id == box.owner.id.id or !box.collides_entities)
                continue;

            if (self.checkCollision(box.owner.getPosition().sub(offset), box.size))
                return box.owner;
        }

        return null;
    }

    pub fn checkCollisionWithVelocity(self: *QuakeSolidsComponent, pos: math.Vec3, size: math.Vec3, velocity: math.Vec3) ?collision.CollisionHit {
        var worldhit: ?collision.CollisionHit = null;
        var hitlen: f32 = undefined;

        const offset_amount = self.owner.getPosition().sub(self.starting_pos);
        const offset_bounds = delve.spatial.BoundingBox.init(pos.sub(offset_amount), size);

        for (self.quake_entity.solids.items) |solid| {
            const did_collide = solid.checkBoundingBoxCollisionWithVelocity(offset_bounds, velocity);
            if (did_collide) |hit| {
                const adj_hit_loc = hit.loc.add(offset_amount);

                const collision_hit: collision.CollisionHit = .{
                    .pos = adj_hit_loc,
                    .normal = hit.plane.normal,
                };

                if (worldhit == null) {
                    worldhit = collision_hit;
                    hitlen = offset_bounds.center.sub(collision_hit.pos).len();
                } else {
                    const newlen = offset_bounds.center.sub(collision_hit.pos).len();
                    if (newlen < hitlen) {
                        hitlen = newlen;
                        worldhit = collision_hit;
                    }
                }
            }
        }

        return worldhit;
    }

    pub fn checkRayCollision(self: *QuakeSolidsComponent, ray_start: math.Vec3, ray_end: math.Vec3) ?collision.CollisionHit {
        const ray_dir = ray_end.sub(ray_start);
        const ray_dir_norm = ray_end.sub(ray_start).norm();
        const ray_len = ray_dir.len();

        const offset_amount = self.owner.getPosition().sub(self.starting_pos);
        const offset_ray = delve.spatial.Ray.init(ray_start.sub(offset_amount), ray_dir_norm);

        var worldhit: ?collision.CollisionHit = null;
        var hitlen: f32 = undefined;

        const ray = delve.spatial.Ray.init(ray_start, ray_dir_norm);

        for (self.quake_entity.solids.items) |solid| {
            const did_collide = solid.checkRayCollision(offset_ray);
            if (did_collide) |hit| {
                const adj_hit_loc = hit.loc.add(offset_amount);
                const collision_hit: collision.CollisionHit = .{
                    .pos = adj_hit_loc,
                    .normal = hit.plane.normal,
                };

                if (worldhit == null) {
                    worldhit = collision_hit;
                    hitlen = ray.pos.sub(collision_hit.pos).len();
                } else {
                    const newlen = ray.pos.sub(collision_hit.pos).len();
                    if (newlen < hitlen) {
                        hitlen = newlen;
                        worldhit = collision_hit;
                    }
                }
            }
        }

        // If our hit was too far out, then it was not a good hit
        if (hitlen > ray_len)
            return null;

        return worldhit;
    }

    pub fn renderDebug(self: *QuakeSolidsComponent) void {
        const size = self.bounds.max.sub(self.bounds.min);
        main.render_instance.drawDebugWireframeCube(self.owner.getPosition(), delve.math.Vec3.zero, size, delve.math.Vec3.y_axis, delve.colors.yellow);
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
        const offset_amount = c.owner.getPosition().sub(c.starting_pos);
        var adj_bounds = c.bounds;
        adj_bounds.min = adj_bounds.min.add(offset_amount);
        adj_bounds.max = adj_bounds.max.add(offset_amount);
        adj_bounds.center = adj_bounds.center.add(offset_amount);

        spatial_hash.addEntry(c, adj_bounds, false) catch {
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

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
    quake_entity_idx: usize,
    quake_map_entity_id: entities.EntityId = undefined,

    quake_map: ?*quakemap.QuakeMapComponent = null,
    quake_entity: ?*delve.utils.quakemap.Entity = null,

    // interface
    owner: entities.Entity = entities.InvalidEntity,

    // calculated
    _meshes: std.ArrayList(delve.graphics.mesh.Mesh) = undefined,
    bounds: delve.spatial.BoundingBox = undefined,
    starting_pos: math.Vec3 = undefined,
    _arena_allocator: std.heap.ArenaAllocator = undefined,
    first_init: bool = true,

    pub fn init(self: *QuakeSolidsComponent, interface: entities.EntityComponent) void {
        defer self.first_init = false;
        self.owner = interface.owner;
        self._arena_allocator = std.heap.ArenaAllocator.init(delve.mem.getAllocator());

        // grab our quake map if loading
        if (!self.first_init) {
            delve.debug.log("Fixing up quake map pointer: {d}", .{self.quake_map_entity_id.id});
            const found_world = self.owner.getOwningWorld();
            if (found_world == null) {
                delve.debug.log("Could not find world!", .{});
                return;
            }

            delve.debug.log("Getting component storage for world: {d}", .{found_world.?.id});
            var map_it = quakemap.getComponentStorage(found_world.?).iterator();
            while (map_it.next()) |map| {
                delve.debug.log("Found map: {d}", .{map.owner_id.id});
                if (map.owner_id.equals(self.quake_map_entity_id)) {
                    // found our map!
                    self.quake_map = map;
                    break;
                }
            }
        }

        if (self.quake_map != null) {
            self.quake_map_entity_id = self.quake_map.?.owner_id;

            // grab our entity ref
            self.quake_entity = &self.quake_map.?.quake_map.entities.items[self.quake_entity_idx];
        }

        const allocator = self._arena_allocator.allocator();
        self._meshes = self.quake_map.?.quake_map.buildMeshesForEntity(self.quake_entity.?, allocator, math.Mat4.identity, &quakemap.materials, &quakemap.fallback_quake_material) catch {
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

    pub fn linkUpSolid(self: *QuakeSolidsComponent) void {
        if (self.quake_map == null)
            return;

        // grab our entity ref
        self.quake_entity = &self.quake_map.?.quake_map.entities.items[self.quake_entity_idx];

        const allocator = self._arena_allocator.allocator();
        self._meshes = self.quake_map.?.quake_map.buildMeshesForEntity(self.quake_entity, allocator, math.Mat4.identity, &quakemap.materials, &quakemap.fallback_quake_material) catch {
            delve.debug.log("Could not make quake entity solid meshes", .{});
            return;
        };
    }

    pub fn getEntitySolids(self: *QuakeSolidsComponent) []delve.utils.quakemap.Solid {
        if (self.quake_entity == null)
            return &[_]delve.utils.quakemap.Solid{};

        return self.quake_entity.?.solids.items;
    }

    pub fn deinit(self: *QuakeSolidsComponent) void {
        for (self._meshes.items) |*m| {
            m.deinit();
        }
        self._meshes.deinit();

        self._arena_allocator.deinit();
    }

    pub fn getBounds(self: *QuakeSolidsComponent) spatial.BoundingBox {
        const floatMax = std.math.floatMax(f32);
        const floatMin = -floatMax;

        var max: math.Vec3 = math.Vec3.new(floatMin, floatMin, floatMin);
        var min: math.Vec3 = math.Vec3.new(floatMax, floatMax, floatMax);

        const solids = self.getEntitySolids();
        for (solids) |*solid| {
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
        const offsetbounds = delve.spatial.BoundingBox.init(pos.sub(offset_amount), size);

        const solids = self.getEntitySolids();
        for (solids) |solid| {
            const did_collide = solid.checkBoundingBoxCollision(offsetbounds);
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
        var adjbounds = self.bounds;
        adjbounds.min = adjbounds.min.add(offset_amount);
        adjbounds.max = adjbounds.max.add(offset_amount);
        adjbounds.center = adjbounds.center.add(offset_amount);

        const found = box_collision.spatial_hash.getEntriesNear(adjbounds);
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
        const offsetbounds = delve.spatial.BoundingBox.init(pos.sub(offset_amount), size);

        const solids = self.getEntitySolids();
        for (solids) |solid| {
            const did_collide = solid.checkBoundingBoxCollisionWithVelocity(offsetbounds, velocity);
            if (did_collide) |hit| {
                const adj_hit_loc = hit.loc.add(offset_amount);

                const collision_hit: collision.CollisionHit = .{
                    .pos = adj_hit_loc,
                    .normal = hit.plane.normal,
                };

                if (worldhit == null) {
                    worldhit = collision_hit;
                    hitlen = offsetbounds.center.sub(collision_hit.pos).len();
                } else {
                    const newlen = offsetbounds.center.sub(collision_hit.pos).len();
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

        const solids = self.getEntitySolids();
        for (solids) |solid| {
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
        var adjbounds = c.bounds;
        adjbounds.min = adjbounds.min.add(offset_amount);
        adjbounds.max = adjbounds.max.add(offset_amount);
        adjbounds.center = adjbounds.center.add(offset_amount);

        spatial_hash.addEntry(c, adjbounds, false) catch {
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

pub fn deinit() void {
    if (did_init_spatial_hash)
        spatial_hash.deinit();
}

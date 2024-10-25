const std = @import("std");
const delve = @import("delve");
const quakemap = @import("../entities/quakemap.zig");
const box_collision = @import("../entities/box_collision.zig");
const entities = @import("../game/entities.zig");
const math = delve.math;
const spatial = delve.spatial;

// MoveInfo wraps a move attempt, values will be updated after resolving.
pub const MoveInfo = struct {
    pos: math.Vec3,
    vel: math.Vec3,
    size: math.Vec3,

    // lerp objects when stepping up
    step_lerp_timer: f32 = 1.0,
    step_lerp_amount: f32 = 0.0,
    step_lerp_startheight: f32 = 0.0,

    checking: entities.Entity,
    max_slide_bumps: usize = 5,
};

pub const CollisionHit = struct {
    pos: delve.math.Vec3,
    normal: delve.math.Vec3,
    entity: ?entities.Entity = null,
    can_step_up_on: bool = true,
};

pub fn clipVelocity(vel: math.Vec3, normal: math.Vec3, overbounce: f32) math.Vec3 {
    const backoff = vel.dot(normal) * overbounce;
    const change = normal.scale(backoff);
    return vel.sub(change);
}

pub fn doStepSlideMove(world: *entities.World, move: *MoveInfo, delta: f32) bool {
    const stepheight: f32 = 1.25;
    const start_pos = move.pos;
    const start_vel = move.vel;

    if (doSlideMove(world, move, delta) == false) {
        // got where we needed to go can stop here!
        return false;
    }

    const firsthit_player_pos = move.pos;
    const firsthit_player_vel = move.vel;

    // don't step when you have upwards velocity still!
    if (move.vel.y > 1.75) {
        return true;
    }

    const step_vec = delve.math.Vec3.new(0, stepheight, 0);
    const stairhit_up = collidesWithMapWithVelocity(world, start_pos, move.size, step_vec, move.checking);
    if (stairhit_up != null) {
        // just use our first slidemove
        return false;
    }

    // try a slidemove in the air!
    move.pos = start_pos.add(step_vec);
    move.vel = start_vel;
    _ = doSlideMove(world, move, delta);

    // need to press down now!
    const stair_fall_vec = step_vec.scale(-1.0);
    const stair_fall_hit = collidesWithMapWithVelocity(world, move.pos, move.size, stair_fall_vec, move.checking);
    if (stair_fall_hit) |h| {
        // don't let us step up on mobs!
        if (!h.can_step_up_on) {
            move.pos = firsthit_player_pos;
            move.vel = firsthit_player_vel;
            return false;
        }

        move.pos = h.pos.add(math.Vec3.new(0, 0.0001, 0));

        const first_len = start_pos.sub(firsthit_player_pos).len();
        const this_len = start_pos.sub(move.pos).len();

        // just use the first move if that moved us further, or we stepped onto a wall
        if (first_len > this_len or h.normal.y < 0.7) {
            move.pos = firsthit_player_pos;
            move.vel = firsthit_player_vel;
            return true;
        }

        // we did step up, so lerp our position
        move.step_lerp_timer = 0.0;
        move.step_lerp_amount = start_pos.y - move.pos.y;
        move.step_lerp_startheight = start_pos.y;

        return true;
    }

    // in the air? use the original slidemove
    move.pos = firsthit_player_pos;
    move.vel = firsthit_player_vel;
    return true;
}

// moves and slides the move. returns true if there was a blocking collision
pub fn doSlideMove(world: *entities.World, move: *MoveInfo, delta: f32) bool {
    var bump_planes: [10]delve.math.Vec3 = undefined;
    var num_bump_planes: usize = 0;

    // never turn against initial velocity
    bump_planes[num_bump_planes] = move.vel.norm();
    num_bump_planes += 1;

    var num_bumps: i32 = 0;

    const max_bump_count = move.max_slide_bumps;
    for (0..max_bump_count) |_| {
        const move_player_vel = move.vel.scale(delta);
        const movehit = collidesWithMapWithVelocity(world, move.pos, move.size, move_player_vel, move.checking);

        if (movehit == null) {
            // easy case, can just move
            move.pos = move.pos.add(move_player_vel);
            break;
        }

        num_bumps += 1;
        const hit_plane_normal = movehit.?.normal;

        // back away from the hit a teeny bit to fix epsilon errors
        move.pos = movehit.?.pos.add(move_player_vel.norm().scale(-0.0001));

        // check if this is one we hit before already!
        // if so, nudge out against it
        var did_nudge = false;
        for (0..num_bump_planes) |pidx| {
            if (hit_plane_normal.dot(bump_planes[pidx]) > 0.99) {
                move.vel = move.vel.add(hit_plane_normal.scale(0.001));
                did_nudge = true;
                break;
            }
        }

        if (did_nudge)
            continue;

        bump_planes[num_bump_planes] = hit_plane_normal;
        num_bump_planes += 1;

        var clip_vel = move.vel;
        for (0..num_bump_planes) |pidx| {
            const plane_normal = bump_planes[pidx];
            const into = move.vel.dot(plane_normal);
            if (into >= 0.1) {
                // ignore planes that we don't interact with
                continue;
            }

            clip_vel = clipVelocity(move.vel, plane_normal, 1.01);

            // see if there is a second plane we hit now (creases!)
            for (0..num_bump_planes) |pidx2| {
                if (pidx == pidx2)
                    continue;

                const plane2_normal = bump_planes[pidx2];
                const into2 = move.vel.dot(plane2_normal);
                if (into2 >= 0.1) {
                    // ignore planes that we don't interact with
                    continue;
                }

                clip_vel = clipVelocity(clip_vel, plane2_normal, 1.01);

                // check if it goes into the original clip plane
                if (clip_vel.dot(plane_normal) >= 0)
                    continue;

                const dir = plane_normal.cross(plane2_normal).norm();
                const d = dir.dot(move.vel);
                clip_vel = dir.scale(d);

                // see if there is a third plane we hit now
                for (0..num_bump_planes) |pidx3| {
                    if (pidx3 == pidx or pidx3 == pidx2)
                        continue;

                    // ignore moves that don't interact
                    if (clip_vel.dot(bump_planes[pidx3]) >= 0.1)
                        continue;

                    // uhoh, stop dead!
                    move.vel = delve.math.Vec3.zero;
                    return true;
                }
            }

            // if we fixed all intersections, try another move!
            move.vel = clip_vel;
            break;
        }
    }

    return num_bumps > 0;
}

pub fn isOnGround(world: *entities.World, move: MoveInfo) bool {
    const check_down = math.Vec3.new(0, -0.001, 0);
    return groundCheck(world, move, check_down) != null;
}

pub fn groundCheck(world: *entities.World, move: MoveInfo, check_down: math.Vec3) ?math.Vec3 {
    const movehit = collidesWithMapWithVelocity(world, move.pos, move.size, check_down, move.checking);
    if (movehit == null)
        return null;

    if (movehit.?.normal.y >= 0.7)
        return movehit.?.pos;

    return null;
}

pub fn collidesWithMap(world: *entities.World, pos: math.Vec3, size: math.Vec3, checking: entities.Entity) bool {
    const bounds = delve.spatial.BoundingBox.init(pos, size);

    // check world
    var map_it = quakemap.getComponentStorage(world).iterator();
    while (map_it.next()) |map| {
        const solids = map.solid_spatial_hash.getEntriesNear(bounds);
        for (solids) |solid| {
            if (solid.custom_flags == 1) {
                continue;
            }

            const did_collide = solid.checkBoundingBoxCollision(bounds);
            if (did_collide) {
                return true;
            }
        }

        // and also entities
        // for (quake_map.entities.items) |entity| {
        //     // ignore triggers and stuff
        //     if (!std.mem.startsWith(u8, entity.classname, "func"))
        //         continue;
        //
        //     for (entity.solids.items) |solid| {
        //         const did_collide = solid.checkBoundingBoxCollision(bounds);
        //         if (did_collide) {
        //             return true;
        //         }
        //     }
        // }
    }

    // Also make sure we're not encroaching any entities
    if (checkEntityCollision(world, pos, size, checking)) |_| {
        return true;
    }

    return false;
}

pub fn collidesWithMapWithVelocity(world: *entities.World, pos: math.Vec3, size: math.Vec3, velocity: math.Vec3, checking: entities.Entity) ?CollisionHit {
    const bounds = delve.spatial.BoundingBox.init(pos, size);

    var worldhit: ?CollisionHit = null;
    var hitlen: f32 = undefined;

    var num_checked: usize = 0;
    // defer delve.debug.log("Checked {d} solids", .{num_checked});

    const start_bounds = spatial.BoundingBox.init(pos, size);
    const end_bounds = spatial.BoundingBox.init(pos.add(velocity), size);
    const final_bounds: spatial.BoundingBox = .{
        .min = math.Vec3.min(start_bounds.min, end_bounds.min),
        .max = math.Vec3.max(start_bounds.max, end_bounds.max),
        .center = start_bounds.center.add(end_bounds.center).scale(0.5),
    };

    // check world
    var map_it = quakemap.getComponentStorage(world).iterator();
    while (map_it.next()) |map| {
        const solids = map.solid_spatial_hash.getEntriesNear(final_bounds);
        for (solids) |solid| {
            if (solid.custom_flags == 1) {
                continue;
            }

            num_checked += 1;

            const did_collide = solid.checkBoundingBoxCollisionWithVelocity(bounds, velocity);
            if (did_collide) |hit| {
                const collision_hit: CollisionHit = .{
                    .pos = hit.loc,
                    .normal = hit.plane.normal,
                };

                if (worldhit == null) {
                    worldhit = collision_hit;
                    hitlen = bounds.center.sub(hit.loc).len();
                } else {
                    const newlen = bounds.center.sub(hit.loc).len();
                    if (newlen < hitlen) {
                        hitlen = newlen;
                        worldhit = collision_hit;
                    }
                }
            }
        }

        // and also entities
        // for (quake_map.entities.items) |entity| {
        //     // ignore triggers and stuff
        //     if (!std.mem.startsWith(u8, entity.classname, "func"))
        //         continue;
        //
        //     for (entity.solids.items) |solid| {
        //         const did_collide = solid.checkBoundingBoxCollisionWithVelocity(bounds, velocity);
        //         if (did_collide) |hit| {
        //             if (worldhit == null) {
        //                 worldhit = hit;
        //                 hitlen = bounds.center.sub(hit.loc).len();
        //             } else {
        //                 const newlen = bounds.center.sub(hit.loc).len();
        //                 if (newlen < hitlen) {
        //                     hitlen = newlen;
        //                     worldhit = hit;
        //                 }
        //             }
        //         }
        //     }
        // }
    }

    // Also check for Entity hits
    const hit_opt = sweepEntityCollision(world, pos, velocity, size, checking);
    if (hit_opt) |hit| {
        if (worldhit == null) {
            worldhit = hit;
            hitlen = pos.sub(hit.pos).len();
        } else {
            const newlen = pos.sub(hit.pos).len();
            if (newlen < hitlen) {
                hitlen = newlen;
                worldhit = hit;
            }
        }
    }

    return worldhit;
}

pub fn rayCollidesWithMap(world: *entities.World, ray: delve.spatial.Ray) ?CollisionHit {
    return raySegmentCollidesWithMap(world, ray.pos, ray.pos.add(ray.dir.scale(1000000)));
}

pub fn raySegmentCollidesWithMap(world: *entities.World, ray_start: math.Vec3, ray_end: math.Vec3) ?CollisionHit {
    var worldhit: ?CollisionHit = null;
    var hitlen: f32 = undefined;

    var num_checked: usize = 0;
    // defer delve.debug.log("Checked {d} solids", .{num_checked});

    const ray_dir = ray_end.sub(ray_start);
    const ray_len = ray_dir.len();
    const ray = delve.spatial.Ray.init(ray_start, ray_dir.norm());

    // check world
    var map_it = quakemap.getComponentStorage(world).iterator();
    while (map_it.next()) |map| {
        // if (ray.intersectBoundingBox(map.solid_spatial_hash.bounds) != null) {
        //     continue;
        // }

        const solids = map.quake_map.worldspawn.solids.items;
        for (solids) |solid| {
            if (solid.custom_flags == 1) {
                continue;
            }

            num_checked += 1;

            const did_collide = solid.checkRayCollision(ray);
            if (did_collide) |hit| {
                const collision_hit: CollisionHit = .{
                    .pos = hit.loc,
                    .normal = hit.plane.normal,
                };

                if (worldhit == null) {
                    worldhit = collision_hit;
                    hitlen = ray_start.sub(hit.loc).len();
                } else {
                    const newlen = ray_start.sub(hit.loc).len();
                    if (newlen < hitlen) {
                        hitlen = newlen;
                        worldhit = collision_hit;
                    }
                }
            }
        }

        // and also entities
        // for (quake_map.entities.items) |entity| {
        //     // ignore triggers and stuff
        //     if (!std.mem.startsWith(u8, entity.classname, "func"))
        //         continue;
        //
        //     for (entity.solids.items) |solid| {
        //         const did_collide = solid.checkBoundingBoxCollisionWithVelocity(bounds, velocity);
        //         if (did_collide) |hit| {
        //             if (worldhit == null) {
        //                 worldhit = hit;
        //                 hitlen = bounds.center.sub(hit.loc).len();
        //             } else {
        //                 const newlen = bounds.center.sub(hit.loc).len();
        //                 if (newlen < hitlen) {
        //                     hitlen = newlen;
        //                     worldhit = hit;
        //                 }
        //             }
        //         }
        //     }
        // }
    }

    // If our hit was too far out, then it was not a good hit
    if (hitlen > ray_len)
        return null;

    return worldhit;
}

/// Returns true if the point is in a liquid
pub fn collidesWithLiquid(world: *entities.World, pos: math.Vec3, size: math.Vec3) bool {
    const bounds = delve.spatial.BoundingBox.init(pos, size);

    // check world
    var map_it = quakemap.getComponentStorage(world).iterator();
    while (map_it.next()) |map| {
        const solids = map.solid_spatial_hash.getEntriesNear(bounds);
        for (solids) |solid| {
            if (solid.custom_flags != 1) {
                continue;
            }

            const did_collide = solid.checkBoundingBoxCollision(bounds);
            if (did_collide)
                return true;
        }
    }

    return false;
}

pub fn checkEntityCollision(world: *entities.World, pos: math.Vec3, size: math.Vec3, checking: entities.Entity) ?entities.Entity {
    _ = world;
    const bounds = delve.spatial.BoundingBox.init(pos, size);

    const found = box_collision.spatial_hash.getEntriesNear(bounds);
    for (found) |box| {
        if (checking.id.id == box.owner.id.id) {
            continue;
        }

        const check_bounds = box.getBoundingBox();
        if (bounds.intersects(check_bounds)) {
            return box.owner;
        }
    }

    return null;
}

pub fn sweepEntityCollision(world: *entities.World, pos: delve.math.Vec3, vel: delve.math.Vec3, size: delve.math.Vec3, checking: entities.Entity) ?CollisionHit {
    _ = world;
    const size_inflate = size.scale(0.5);

    const vel_len = vel.len();
    const ray = delve.spatial.Ray.init(pos, vel.norm());

    // start higher than our possible length
    var found_len = std.math.floatMax(f32);
    var found_hit: ?CollisionHit = null;

    // TODO: If the sweep is long enough, switch to getEntriesAlong
    const found = box_collision.spatial_hash.getEntriesNear(spatial.BoundingBox.init(pos, size).inflate(vel_len));

    var count: i32 = 0;
    for (found) |box| {
        if (checking.id.id == box.owner.id.id) {
            continue;
        }

        defer count += 1;

        // inflate the bounding box to include the passed in size
        var check_bounds = box.getBoundingBox();
        check_bounds.min = check_bounds.min.sub(size_inflate);
        check_bounds.max = check_bounds.max.add(size_inflate);

        const hit_opt = ray.intersectBoundingBox(check_bounds);
        if (hit_opt) |hit| {
            const hit_len = pos.sub(hit.hit_pos).len();
            if (hit_len > vel_len)
                continue;

            if (hit_len >= found_len)
                continue;

            found_len = hit_len;
            found_hit = .{
                .pos = hit.hit_pos,
                .normal = hit.normal,
                .entity = box.owner,
                .can_step_up_on = box.can_step_up_on,
            };
        }
    }

    // delve.debug.log("Checked {d} entities", .{count});

    return found_hit;
}

pub fn checkRayEntityCollision(world: *entities.World, ray: delve.spatial.Ray, checking: entities.Entity) ?CollisionHit {
    // start higher than our possible length
    var found_len = std.math.floatMax(f32);
    var found_hit: ?CollisionHit = null;

    var box_it = box_collision.getComponentStorage(world).iterator();
    while (box_it.next()) |box| {
        if (checking.id.id == box.owner.id.id) {
            continue;
        }

        const check_bounds = box.getBoundingBox();
        const hit_opt = ray.intersectBoundingBox(check_bounds);
        if (hit_opt) |hit| {
            const hit_len = ray.pos.sub(hit.hit_pos).len();
            if (hit_len >= found_len)
                continue;

            found_len = hit_len;
            found_hit = .{
                .pos = hit.hit_pos,
                .normal = hit.normal,
                .entity = box.owner,
            };
        }
    }

    return found_hit;
}

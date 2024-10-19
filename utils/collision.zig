const std = @import("std");
const delve = @import("delve");
const quakemap = @import("../entities/quakemap.zig");
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
    const stairhit_up = collidesWithMapWithVelocity(world, start_pos, move.size, step_vec);
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
    const stair_fall_hit = collidesWithMapWithVelocity(world, move.pos, move.size, stair_fall_vec);
    if (stair_fall_hit) |h| {
        move.pos = h.loc.add(math.Vec3.new(0, 0.0001, 0));

        const first_len = start_pos.sub(firsthit_player_pos).len();
        const this_len = start_pos.sub(move.pos).len();

        // just use the first move if that moved us further, or we stepped onto a wall
        if (first_len > this_len or h.plane.normal.y < 0.7) {
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
    var bump_planes: [8]delve.math.Vec3 = undefined;
    var num_bump_planes: usize = 0;

    // never turn against initial velocity
    bump_planes[num_bump_planes] = move.vel.norm();
    num_bump_planes += 1;

    var num_bumps: i32 = 0;

    const max_bump_count = 5;
    for (0..max_bump_count) |_| {
        const move_player_vel = move.vel.scale(delta);
        const movehit = collidesWithMapWithVelocity(world, move.pos, move.size, move_player_vel);

        if (movehit == null) {
            // easy case, can just move
            move.pos = move.pos.add(move_player_vel);
            break;
        }

        num_bumps += 1;
        const hit_plane = movehit.?.plane;

        // back away from the hit a teeny bit to fix epsilon errors
        move.pos = movehit.?.loc.add(move_player_vel.norm().scale(-0.0001));

        // check if this is one we hit before already!
        // if so, nudge out against it
        var did_nudge = false;
        for (0..num_bump_planes) |pidx| {
            if (hit_plane.normal.dot(bump_planes[pidx]) > 0.99) {
                move.vel = move.vel.add(hit_plane.normal.scale(0.001));
                did_nudge = true;
                break;
            }
        }

        if (did_nudge)
            continue;

        bump_planes[num_bump_planes] = hit_plane.normal;
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
    const movehit = collidesWithMapWithVelocity(world, move.pos, move.size, check_down);
    if (movehit == null)
        return null;

    if (movehit.?.plane.normal.y >= 0.7)
        return movehit.?.loc;

    return null;
}

pub fn collidesWithMap(world: *entities.World, pos: math.Vec3, size: math.Vec3) bool {
    const bounds = delve.spatial.BoundingBox.init(pos, size);

    // check world
    var map_it = quakemap.getComponentStorage(world).iterator();
    while (map_it.next()) |map| {
        const solids = map.solid_spatial_hash.getSolidsNear(bounds);
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
    return false;
}

pub fn collidesWithMapWithVelocity(world: *entities.World, pos: math.Vec3, size: math.Vec3, velocity: math.Vec3) ?delve.utils.quakemap.QuakeMapHit {
    const bounds = delve.spatial.BoundingBox.init(pos, size);

    var worldhit: ?delve.utils.quakemap.QuakeMapHit = null;
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
        const solids = map.solid_spatial_hash.getSolidsNear(final_bounds);
        for (solids) |solid| {
            if (solid.custom_flags == 1) {
                continue;
            }

            num_checked += 1;

            const did_collide = solid.checkBoundingBoxCollisionWithVelocity(bounds, velocity);
            if (did_collide) |hit| {
                if (worldhit == null) {
                    worldhit = hit;
                    hitlen = bounds.center.sub(hit.loc).len();
                } else {
                    const newlen = bounds.center.sub(hit.loc).len();
                    if (newlen < hitlen) {
                        hitlen = newlen;
                        worldhit = hit;
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

    return worldhit;
}

pub fn rayCollidesWithMap(world: *entities.World, ray: delve.spatial.Ray) ?delve.utils.quakemap.QuakeMapHit {
    return raySegmentCollidesWithMap(world, ray.pos, ray.pos.add(ray.dir.scale(1000000)));
}

pub fn raySegmentCollidesWithMap(world: *entities.World, ray_start: math.Vec3, ray_end: math.Vec3) ?delve.utils.quakemap.QuakeMapHit {
    var worldhit: ?delve.utils.quakemap.QuakeMapHit = null;
    var hitlen: f32 = undefined;

    var num_checked: usize = 0;
    // defer delve.debug.log("Checked {d} solids", .{num_checked});

    const ray_dir = ray_start.sub(ray_end);
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
                if (worldhit == null) {
                    worldhit = hit;
                    hitlen = ray_start.sub(hit.loc).len();
                } else {
                    const newlen = ray_start.sub(hit.loc).len();
                    if (newlen < hitlen) {
                        hitlen = newlen;
                        worldhit = hit;
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
        const solids = map.solid_spatial_hash.getSolidsNear(bounds);
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

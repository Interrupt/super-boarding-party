const std = @import("std");
const delve = @import("delve");
const math = delve.math;
const spatial = delve.spatial;

// lerp the camera when stepping up
pub var step_lerp_timer: f32 = 1.0;
pub var step_lerp_amount: f32 = 0.0;
pub var step_lerp_startheight: f32 = 0.0;

// MoveInfo wraps a move attempt, values will be updated after resolving.
pub const MoveInfo = struct {
    pos: math.Vec3,
    vel: math.Vec3,
    size: math.Vec3,
};

// WorldInfo wraps the needed info about the game world to collide against
pub const WorldInfo = struct {
    quake_map: *delve.utils.quakemap.QuakeMap,
};

pub fn clipVelocity(vel: math.Vec3, normal: math.Vec3, overbounce: f32) math.Vec3 {
    const backoff = vel.dot(normal) * overbounce;
    const change = normal.scale(backoff);
    return vel.sub(change);
}

pub fn doStepSlideMove(world: *const WorldInfo, move: *MoveInfo, delta: f32) bool {
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
        step_lerp_timer = 0.0;
        step_lerp_amount = start_pos.y - move.pos.y;
        step_lerp_startheight = start_pos.y;

        return true;
    }

    // in the air? use the original slidemove
    move.pos = firsthit_player_pos;
    move.vel = firsthit_player_vel;
    return true;
}

// moves and slides the move. returns true if there was a blocking collision
pub fn doSlideMove(world: *const WorldInfo, move: *MoveInfo, delta: f32) bool {
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

pub fn isOnGround(world: *const WorldInfo, move: MoveInfo) bool {
    const check_down = math.Vec3.new(0, -0.001, 0);
    return groundCheck(world, move, check_down) != null;
}

pub fn groundCheck(world: *const WorldInfo, move: MoveInfo, check_down: math.Vec3) ?math.Vec3 {
    const movehit = collidesWithMapWithVelocity(world, move.pos, move.size, check_down);
    if (movehit == null)
        return null;

    if (movehit.?.plane.normal.y >= 0.7)
        return movehit.?.loc;

    return null;
}

pub fn collidesWithMap(world: *const WorldInfo, pos: math.Vec3, size: math.Vec3) bool {
    const bounds = delve.spatial.BoundingBox.init(pos, size);
    const quake_map = world.quake_map;

    // check world
    for (quake_map.worldspawn.solids.items) |solid| {
        if (solid.custom_flags == 1) {
            continue;
        }

        const did_collide = solid.checkBoundingBoxCollision(bounds);
        if (did_collide) {
            return true;
        }
    }

    // and also entities
    for (quake_map.entities.items) |entity| {
        // ignore triggers and stuff
        if (!std.mem.startsWith(u8, entity.classname, "func"))
            continue;

        for (entity.solids.items) |solid| {
            const did_collide = solid.checkBoundingBoxCollision(bounds);
            if (did_collide) {
                return true;
            }
        }
    }
    return false;
}

pub fn collidesWithMapWithVelocity(world: *const WorldInfo, pos: math.Vec3, size: math.Vec3, velocity: math.Vec3) ?delve.utils.quakemap.QuakeMapHit {
    const bounds = delve.spatial.BoundingBox.init(pos, size);
    const quake_map = world.quake_map;

    var worldhit: ?delve.utils.quakemap.QuakeMapHit = null;
    var hitlen: f32 = undefined;

    // check world
    for (quake_map.worldspawn.solids.items) |solid| {
        if (solid.custom_flags == 1) {
            continue;
        }

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
    for (quake_map.entities.items) |entity| {
        // ignore triggers and stuff
        if (!std.mem.startsWith(u8, entity.classname, "func"))
            continue;

        for (entity.solids.items) |solid| {
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
    }

    return worldhit;
}

/// Returns true if the point is in a liquid
pub fn collidesWithLiquid(world: *const WorldInfo, pos: math.Vec3, size: math.Vec3) bool {
    const bounds = delve.spatial.BoundingBox.init(pos, size);
    const quake_map = world.quake_map;

    // check world
    for (quake_map.worldspawn.solids.items) |solid| {
        if (solid.custom_flags != 1) {
            continue;
        }

        const did_collide = solid.checkBoundingBoxCollision(bounds);
        if (did_collide)
            return true;
    }

    return false;
}

const std = @import("std");
const delve = @import("delve");
const app = delve.app;

const graphics = delve.platform.graphics;
const math = delve.math;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var allocator: std.mem.Allocator = undefined;

var camera: delve.graphics.camera.Camera = undefined;
var fallback_material: graphics.Material = undefined;

// the quake map
var quake_map: delve.utils.quakemap.QuakeMap = undefined;

// meshes for drawing
var map_meshes: std.ArrayList(delve.graphics.mesh.Mesh) = undefined;
var entity_meshes: std.ArrayList(delve.graphics.mesh.Mesh) = undefined;
var cube_mesh: delve.graphics.mesh.Mesh = undefined;

// quake maps load at a different scale and rotation - adjust for that
var map_transform: math.Mat4 = undefined;

// movement constants
const gravity_amount: f32 = -75.0;
const player_move_speed: f32 = 24.0;
const player_ground_acceleration: f32 = 4.0;
const player_air_acceleration: f32 = 0.5;
const player_friction: f32 = 10.0;
const air_friction: f32 = 0.1;

// player state
var bounding_box_size: math.Vec3 = math.Vec3.new(2, 3, 2);
var player_pos: math.Vec3 = math.Vec3.zero;
var player_vel: math.Vec3 = math.Vec3.zero;
var on_ground = true;

var do_noclip = false;

pub fn main() !void {
    const example = delve.modules.Module{
        .name = "quakemap_example",
        .init_fn = on_init,
        .tick_fn = on_tick,
        .draw_fn = on_draw,
    };

    // Pick the allocator to use depending on platform
    const builtin = @import("builtin");
    if (builtin.os.tag == .wasi or builtin.os.tag == .emscripten) {
        // Web builds hack: use the C allocator to avoid OOM errors
        // See https://github.com/ziglang/zig/issues/19072
        try delve.init(std.heap.c_allocator);
    } else {
        try delve.init(gpa.allocator());
    }

    try delve.modules.registerModule(example);
    try delve.module.fps_counter.registerModule();

    try app.start(app.AppConfig{ .title = "Delve Framework - Quake Map Example", .sampler_pool_size = 256 });
}

pub fn on_init() !void {
    // use the Delve Framework global allocator
    allocator = delve.mem.getAllocator();

    // scale and rotate the map
    const map_scale = delve.math.Vec3.new(0.1, 0.1, 0.1); // Quake seems to be about 0.07, 0.07, 0.07
    map_transform = delve.math.Mat4.scale(map_scale).mul(delve.math.Mat4.rotate(-90, delve.math.Vec3.x_axis));

    // Read quake map contents
    const file = try std.fs.cwd().openFile("assets/testmap.map", .{});
    defer file.close();

    const buffer_size = 8024000;
    const file_buffer = try file.readToEndAlloc(allocator, buffer_size);

    var err: delve.utils.quakemap.ErrorInfo = undefined;
    quake_map = delve.utils.quakemap.QuakeMap.read(allocator, file_buffer, map_transform, &err) catch {
        delve.debug.log("Error reading quake map: {}", .{err});
        return;
    };

    // Create a fallback material to use when no texture could be loaded
    const fallback_tex = graphics.createDebugTexture();
    fallback_material = graphics.Material.init(.{
        .shader = graphics.Shader.initDefault(.{ .vertex_attributes = delve.graphics.mesh.getShaderAttributes() }),
        .texture_0 = fallback_tex,
        .samplers = &[_]graphics.FilterMode{.NEAREST},
    });

    // create our camera
    camera = delve.graphics.camera.Camera.init(90.0, 0.01, 512, math.Vec3.up);
    camera.position.y = 7.0;

    // set our player position
    player_pos = getPlayerStartPosition(&quake_map).mulMat4(map_transform);

    var materials = std.StringHashMap(delve.utils.quakemap.QuakeMaterial).init(allocator);
    const shader = graphics.Shader.initDefault(.{ .vertex_attributes = delve.graphics.mesh.getShaderAttributes() });

    // collect all of the solids from the world and entities
    var all_solids = std.ArrayList(delve.utils.quakemap.Solid).init(allocator);
    defer all_solids.deinit();

    try all_solids.appendSlice(quake_map.worldspawn.solids.items);
    for (quake_map.entities.items) |e| {
        try all_solids.appendSlice(e.solids.items);
    }

    // make materials out of all the required textures we found
    for (all_solids.items) |solid| {
        for (solid.faces.items) |face| {
            var mat_name = std.ArrayList(u8).init(allocator);
            try mat_name.writer().print("{s}", .{face.texture_name});
            try mat_name.append(0);

            var tex_path = std.ArrayList(u8).init(allocator);
            try tex_path.writer().print("assets/textures/{s}.png", .{face.texture_name});
            try tex_path.append(0);

            const mat_name_owned = try mat_name.toOwnedSlice();
            const mat_name_null = mat_name_owned[0 .. mat_name_owned.len - 1 :0];

            const found = materials.get(mat_name_null);
            if (found == null) {
                const texpath = try tex_path.toOwnedSlice();
                const tex_path_null = texpath[0 .. texpath.len - 1 :0];

                var tex_img: delve.images.Image = delve.images.loadFile(tex_path_null) catch {
                    delve.debug.log("Could not load image: {s}", .{tex_path_null});
                    try materials.put(mat_name_null, .{ .material = fallback_material });
                    continue;
                };
                const tex = graphics.Texture.init(&tex_img);

                const mat = graphics.Material.init(.{
                    .shader = shader,
                    .samplers = &[_]graphics.FilterMode{.NEAREST},
                    .texture_0 = tex,
                });
                try materials.put(mat_name_null, .{ .material = mat, .tex_size_x = @intCast(tex.width), .tex_size_y = @intCast(tex.height) });

                // delve.debug.log("Loaded image: {s}", .{tex_path_null});
            }
        }
    }

    // make meshes out of the quake map, batched by material
    map_meshes = try quake_map.buildWorldMeshes(allocator, math.Mat4.identity, materials, .{ .material = fallback_material });
    entity_meshes = try quake_map.buildEntityMeshes(allocator, math.Mat4.identity, materials, .{ .material = fallback_material });

    // make a bounding box cube
    cube_mesh = try delve.graphics.mesh.createCube(math.Vec3.new(0, 0, 0), bounding_box_size, delve.colors.red, fallback_material);

    // set a bg color
    delve.platform.graphics.setClearColor(delve.colors.examples_bg_light);

    delve.platform.app.captureMouse(true);
}

pub fn on_tick(delta: f32) void {
    if (delve.platform.input.isKeyJustPressed(.ESCAPE))
        delve.platform.app.exit();

    // apply gravity!
    if (!do_noclip)
        player_vel.y += gravity_amount * delta;

    // collect move direction from input
    var move_dir: math.Vec2 = math.Vec2.zero;

    var cam_walk_dir = camera.direction;
    cam_walk_dir.y = 0.0;
    cam_walk_dir = cam_walk_dir.norm();

    if (delve.platform.input.isKeyPressed(.W)) {
        move_dir.x -= cam_walk_dir.x;
        move_dir.y -= cam_walk_dir.z;
    }
    if (delve.platform.input.isKeyPressed(.S)) {
        move_dir.x += cam_walk_dir.x;
        move_dir.y += cam_walk_dir.z;
    }
    if (delve.platform.input.isKeyPressed(.D)) {
        const right_dir = camera.getRightDirection();
        move_dir.x += right_dir.x;
        move_dir.y += right_dir.z;
    }
    if (delve.platform.input.isKeyPressed(.A)) {
        const right_dir = camera.getRightDirection();
        move_dir.x -= right_dir.x;
        move_dir.y -= right_dir.z;
    }

    // jump and fly!
    if (delve.platform.input.isKeyPressed(.SPACE) and on_ground) player_vel.y = 20.0;
    if (delve.platform.input.isKeyPressed(.F)) player_vel.y = 15.0;
    if (delve.platform.input.isKeyPressed(.G)) player_vel.y = -15.0;
    if (delve.platform.input.isKeyJustPressed(.N)) do_noclip = !do_noclip;

    // can now apply player movement based on direction
    move_dir = move_dir.norm();
    const accel = if (on_ground) player_ground_acceleration else player_air_acceleration;
    const current_velocity = math.Vec2.new(player_vel.x, player_vel.z);

    if (current_velocity.len() < player_move_speed) {
        const new_velocity = current_velocity.add(move_dir.scale(accel));
        if (new_velocity.len() < player_move_speed) {
            // can increase our velocity
            player_vel.x = new_velocity.x;
            player_vel.z = new_velocity.y;
        } else {
            // clamp to max speed!
            const max_speed = new_velocity.norm().scale(player_move_speed);
            player_vel.x = max_speed.x;
            player_vel.z = max_speed.y;
        }
    }

    // try to move the player
    if (!do_noclip) {
        if (on_ground or player_vel.y <= 0.001) {
            _ = do_player_step_slidemove(delta);
        } else {
            _ = do_player_slidemove(delta);
        }

        on_ground = is_on_ground();
    } else {
        // in noclip mode, just move!
        player_pos = player_pos.add(player_vel.scale(delta));
    }

    // apply friction to the player
    const speed = player_vel.len();
    if (speed > 0) {
        var velocity_drop = speed * delta;
        velocity_drop *= if (on_ground) player_friction else air_friction;

        const newspeed = (speed - velocity_drop) / speed;
        player_vel = player_vel.scale(newspeed);
    }

    // position camera
    camera.position = player_pos;
    camera.position.y += bounding_box_size.y * 0.35; // eye height

    // do mouse look
    camera.runSimpleCamera(0, 60 * delta, true);
}

pub fn clip_velocity(vel: math.Vec3, normal: math.Vec3, overbounce: f32) math.Vec3 {
    const backoff = vel.dot(normal) * overbounce;
    const change = normal.scale(backoff);
    return vel.sub(change);
}

pub fn do_player_step_slidemove(delta: f32) bool {
    const stepheight: f32 = 1.25;

    const start_pos = player_pos;
    const start_vel = player_vel;

    if (do_player_slidemove(delta) == false) {
        // got where we needed to go can stop here!
        return false;
    }

    const firsthit_player_pos = player_pos;
    const firsthit_player_vel = player_vel;

    // don't step when you have upwards velocity still!
    if (player_vel.y > 1.75) {
        return true;
    }

    const step_vec = delve.math.Vec3.new(0, stepheight, 0);
    const stairhit_up = collidesWithMapWithVelocity(start_pos, bounding_box_size, step_vec);
    if (stairhit_up != null) {
        // just use our first slidemove
        return false;
    }

    // try a slidemove in the air!
    player_pos = start_pos.add(step_vec);
    player_vel = start_vel;
    _ = do_player_slidemove(delta);

    // need to press down now!
    const stair_fall_vec = step_vec.scale(-1.0);
    const stair_fall_hit = collidesWithMapWithVelocity(player_pos, bounding_box_size, stair_fall_vec);
    if (stair_fall_hit) |h| {
        player_pos = h.loc.add(math.Vec3.new(0, 0.0001, 0));

        const first_len = start_pos.sub(firsthit_player_pos).len();
        const this_len = start_pos.sub(player_pos).len();

        // just use the first move if that moved us further
        if (first_len > this_len) {
            player_pos = firsthit_player_pos;
            player_vel = firsthit_player_vel;
        }

        return true;
    }

    // in the air? use the original slidemove
    player_pos = firsthit_player_pos;
    player_vel = firsthit_player_vel;
    return true;
}

// moves and slides the player. returns true if there was a blocking collision
pub fn do_player_slidemove(delta: f32) bool {
    var bump_planes = std.ArrayList(delve.math.Vec3).init(delve.mem.getAllocator());
    defer bump_planes.deinit();

    // never turn against initial velocity
    bump_planes.append(player_vel.norm()) catch {};

    var num_bumps: i32 = 0;

    const max_bump_count = 5;
    for (0..max_bump_count) |_| {
        const move_player_vel = player_vel.scale(delta);
        const movehit = collidesWithMapWithVelocity(player_pos, bounding_box_size, move_player_vel);

        if (movehit == null) {
            // easy case, can just move
            player_pos = player_pos.add(move_player_vel);
            break;
        }

        num_bumps += 1;
        const hit_plane = movehit.?.plane;

        // back away from the hit a teeny bit to fix epsilon errors
        player_pos = movehit.?.loc.add(move_player_vel.norm().scale(-0.0001));

        // check if this is one we hit before already!
        // if so, nudge out against it
        var did_nudge = false;
        for (0..bump_planes.items.len) |pidx| {
            if (hit_plane.normal.dot(bump_planes.items[pidx]) > 0.99) {
                player_vel = player_vel.add(hit_plane.normal.scale(0.001));
                did_nudge = true;
                break;
            }
        }

        if (did_nudge)
            continue;

        bump_planes.append(hit_plane.normal) catch {};

        var clip_vel = player_vel;
        for (0..bump_planes.items.len) |pidx| {
            const plane_normal = bump_planes.items[pidx];
            const into = player_vel.dot(plane_normal);
            if (into >= 0.1) {
                // ignore planes that we don't interact with
                continue;
            }

            clip_vel = clip_velocity(player_vel, plane_normal, 1.01);

            // see if there is a second plane we hit now (creases!)
            for (0..bump_planes.items.len) |pidx2| {
                if (pidx == pidx2)
                    continue;

                const plane2_normal = bump_planes.items[pidx2];
                const into2 = player_vel.dot(plane2_normal);
                if (into2 >= 0.1) {
                    // ignore planes that we don't interact with
                    continue;
                }

                clip_vel = clip_velocity(clip_vel, plane2_normal, 1.01);

                // check if it goes into the original clip plane
                if (clip_vel.dot(plane_normal) >= 0)
                    continue;

                const dir = plane_normal.cross(plane2_normal).norm();
                const d = dir.dot(player_vel);
                clip_vel = dir.scale(d);

                // see if there is a third plane we hit now
                for (0..bump_planes.items.len) |pidx3| {
                    if (pidx3 == pidx or pidx3 == pidx2)
                        continue;

                    // ignore moves that don't interact
                    if (clip_vel.dot(bump_planes.items[pidx3]) >= 0.1)
                        continue;

                    // uhoh, stop dead!
                    player_vel = delve.math.Vec3.zero;
                    return true;
                }
            }

            // if we fixed all intersections, try another move!
            player_vel = clip_vel;
            break;
        }
    }

    return num_bumps > 0;
}

pub fn is_on_ground() bool {
    const check_down = math.Vec3.new(0, -0.001, 0);
    const movehit = collidesWithMapWithVelocity(player_pos, bounding_box_size, check_down);
    if (movehit == null) {
        return false;
    }

    return movehit.?.plane.normal.y >= 0.7;
}

pub fn on_draw() void {
    const model = math.Mat4.identity;
    const proj_view_matrix = camera.getProjView();

    // draw the world solids
    for (0..map_meshes.items.len) |idx| {
        map_meshes.items[idx].draw(proj_view_matrix, model);
    }
    // and also entity solids
    for (0..entity_meshes.items.len) |idx| {
        entity_meshes.items[idx].draw(proj_view_matrix, model);
    }

    // for visualizing the player bounding box
    // cube_mesh.draw(proj_view_matrix, math.Mat4.translate(camera.position));
}

pub fn collidesWithMap(pos: math.Vec3, size: math.Vec3) bool {
    const bounds = delve.spatial.BoundingBox.init(pos, size);

    // check world
    for (quake_map.worldspawn.solids.items) |solid| {
        const did_collide = solid.checkBoundingBoxSolidCollision(bounds);
        if (did_collide)
            return true;
    }

    // and also entities
    for (quake_map.entities.items) |entity| {
        for (entity.solids.items) |solid| {
            const did_collide = solid.checkBoundingBoxSolidCollision(bounds);
            if (did_collide)
                return true;
        }
    }
    return false;
}

pub fn collidesWithMapWithVelocity(pos: math.Vec3, size: math.Vec3, velocity: math.Vec3) ?delve.utils.quakemap.QuakeMapHit {
    const bounds = delve.spatial.BoundingBox.init(pos, size);

    var worldhit: ?delve.utils.quakemap.QuakeMapHit = null;
    var hitlen: f32 = undefined;

    // check world
    for (quake_map.worldspawn.solids.items) |solid| {
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

/// Returns the player start position from the map
pub fn getPlayerStartPosition(map: *delve.utils.quakemap.QuakeMap) math.Vec3 {
    for (map.entities.items) |entity| {
        if (std.mem.eql(u8, entity.classname, "info_player_start")) {
            const offset = entity.getVec3Property("origin") catch {
                delve.debug.log("Could not read player start offset property!", .{});
                break;
            };
            return offset;
        }
    }

    return math.Vec3.new(0, 0, 0);
}

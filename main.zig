const std = @import("std");
const delve = @import("delve");
const app = delve.app;

const graphics = delve.platform.graphics;
const math = delve.math;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var allocator = gpa.allocator();

var camera: delve.graphics.camera.Camera = undefined;
var fallback_material: graphics.Material = undefined;

// the quake map
var quake_map: delve.utils.quakemap.QuakeMap = undefined;

// meshes for drawing
var map_meshes: std.ArrayList(delve.graphics.mesh.Mesh) = undefined;
var entity_meshes: std.ArrayList(delve.graphics.mesh.Mesh) = undefined;
var cube_mesh: delve.graphics.mesh.Mesh = undefined;

// quake maps load at a different scale and rotation - adjust for that
var map_transform: math.Mat4 = delve.math.Mat4.scale(delve.math.Vec3.new(0.1, 0.1, 0.1)).mul(delve.math.Mat4.rotate(-90, delve.math.Vec3.x_axis));

// player state
var bounding_box_size: math.Vec3 = math.Vec3.new(2, 3, 2);
var player_pos: math.Vec3 = math.Vec3.zero;
var player_vel: math.Vec3 = math.Vec3.zero;
var on_ground = true;

var time: f64 = 0.0;

pub fn main() !void {
    const example = delve.modules.Module{
        .name = "quakemap_example",
        .init_fn = on_init,
        .tick_fn = on_tick,
        .draw_fn = on_draw,
    };

    try delve.modules.registerModule(example);
    try delve.module.fps_counter.registerModule();

    try app.start(app.AppConfig{ .title = "Delve Framework - Quake Map Example" });
}

pub fn on_init() !void {
    // scale and rotate the map
    map_transform = delve.math.Mat4.scale(delve.math.Vec3.new(0.1, 0.1, 0.1)).mul(delve.math.Mat4.rotate(-90, delve.math.Vec3.x_axis));

    // Read quake map contents
    const file = try std.fs.cwd().openFile("testmap.map", .{});
    defer file.close();

    const buffer_size = 1024000;
    const file_buffer = try file.readToEndAlloc(allocator, buffer_size);
    defer allocator.free(file_buffer);

    var err: delve.utils.quakemap.ErrorInfo = undefined;
    quake_map = try delve.utils.quakemap.QuakeMap.read(allocator, file_buffer, map_transform, &err);

    // Create a fallback material to use when no texture could be loaded
    const fallback_tex = graphics.createDebugTexture();
    fallback_material = graphics.Material.init(.{
        .shader = graphics.Shader.initDefault(.{}),
        .texture_0 = fallback_tex,
        .samplers = &[_]graphics.FilterMode{.NEAREST},
    });

    // create our camera
    camera = delve.graphics.camera.Camera.init(90.0, 0.01, 512, math.Vec3.up);
    camera.position.y = 7.0;

    // set our player position
    player_pos = math.Vec3.new(0, 16, 0);

    var materials = std.StringHashMap(delve.utils.quakemap.QuakeMaterial).init(allocator);
    const shader = graphics.Shader.initDefault(.{});

    // make materials out of all the required textures
    for (quake_map.worldspawn.solids.items) |solid| {
        for (solid.faces.items) |face| {
            var mat_name = std.ArrayList(u8).init(allocator);
            try mat_name.writer().print("{s}", .{face.texture_name});
            try mat_name.append(0);

            var tex_path = std.ArrayList(u8).init(allocator);
            try tex_path.writer().print("textures/{s}.png", .{face.texture_name});
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
        std.os.exit(0);

    time += delta;

    const gravity_amount: f32 = -75.0;
    const player_move_speed: f32 = 24.0;
    const player_ground_acceleration: f32 = 4.0;
    const player_air_acceleration: f32 = 0.5;
    const player_friction: f32 = 10.0;
    const air_friction: f32 = 0.1;

    // apply gravity!
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
    do_player_move(delta);

    // player friction!
    const speed = player_vel.len();
    if (speed > 0) {
        var velocity_drop = speed * delta;
        velocity_drop *= if (on_ground) player_friction else air_friction;

        var newspeed = (speed - velocity_drop) / speed;
        player_vel = player_vel.scale(newspeed);
    }

    // position camera
    camera.position = player_pos;
    camera.position.y += bounding_box_size.y * 0.35; // eye height

    // do mouse look
    camera.runSimpleCamera(0, 60 * delta, true);
}

pub fn do_player_move(delta: f32) void {
    const stepheight: f32 = 1.0;
    const bounceback: f32 = 0.00002;

    on_ground = false;

    var move_player_vel = player_vel.scale(delta);
    const movehit = collidesWithMapWithVelocity(player_pos, bounding_box_size, player_vel.scale(delta));

    if (movehit == null) {
        // easy case, can just move
        player_pos = player_pos.add(move_player_vel);
        return;
    } else {
        // hit a wall! move up to it
        if (movehit.?.plane.normal.y < 0.2) {
            const end_pos = player_pos.add(move_player_vel);
            const orig_dist = end_pos.sub(player_pos).len();
            const new_dist = movehit.?.loc.add(movehit.?.plane.normal.scale(bounceback)).sub(player_pos).len();

            const move_factor: f32 = new_dist / orig_dist;

            player_pos = movehit.?.loc.add(movehit.?.plane.normal.scale(bounceback));

            move_player_vel = move_player_vel.scale(move_factor);
        }
    }

    // check if we can walk up a stair - break it into two steps, the up and the over
    const stairstep: math.Vec3 = math.Vec3.new(0, stepheight, 0);
    const stairhit_up = collidesWithMapWithVelocity(player_pos, bounding_box_size, stairstep);

    // move as high as we can vertically before tracing over
    var start_over_trace = player_pos.add(stairstep);
    if (stairhit_up) |up_hit| {
        start_over_trace = up_hit.loc;
    }

    // now try moving over again
    const stairhit_over = collidesWithMapWithVelocity(start_over_trace, bounding_box_size, move_player_vel);

    if (stairhit_over == null) {
        // free space! move to the new free spot
        player_pos = start_over_trace.add(move_player_vel);

        // press back down to step
        const hitpos = collidesWithMapWithVelocity(player_pos, bounding_box_size, stairstep.scale(-1.0));

        if (hitpos) |h| {
            // stick to the step
            player_pos = h.loc;
            player_pos.y += 0.0001; // bounce back

            if (h.plane.normal.y > 0.85) {
                // on a mostly flat floor
                player_vel.y = 0.0;
            } else {
                // on a steep slope! slide us down
                var slope_vel = h.plane.normal.scale(4);
                slope_vel.y = 0.0;
                player_vel = player_vel.add(slope_vel);
            }

            // if the ground is not too sloped, let us jump
            if (h.plane.normal.y > 0.75) {
                on_ground = true;
            }

            return;
        }

        // no stair hit, probably off a ledge. can just fall back down to the step height
        player_pos = player_pos.add(stairstep.scale(-1.0));
        return;
    }

    // hit a wall or something, so redirect velocity along that direction!
    const hit_plane = stairhit_over.?.plane;
    const wall_hit_point = start_over_trace.add(player_vel);
    const hit_dist = hit_plane.distanceToPoint(wall_hit_point);
    player_vel = player_vel.add(hit_plane.normal.scale(-(hit_dist)));
    player_vel = player_vel.add(hit_plane.normal.scale(0.01)); // add some bounceback

    var slide_vel = player_vel.scale(delta);

    // If we hit a wall, just slide horizontally
    if (hit_plane.normal.y < 0.1)
        slide_vel.y = 0;

    // try to wall slide!
    // TODO: do this as a whole other pass so that we can try to step up again!
    const slidehit = collidesWithMapWithVelocity(player_pos, bounding_box_size, slide_vel);
    if (slidehit == null) {
        player_pos = player_pos.add(slide_vel);
    }

    // still try to fall
    const fall_vel = math.Vec3.new(0, player_vel.y * delta, 0);
    const fallhit = collidesWithMapWithVelocity(player_pos, bounding_box_size, fall_vel);

    if (fallhit) |h| {
        // stick to the ground
        if (player_vel.y < 0) {
            player_pos = h.loc;
            player_pos.y += 0.0001;
            on_ground = true;
        }

        // either hit a ceiling or a floor, so kill vertical velocity
        player_vel.y = 0.0;
        return;
    }

    // no fall hit, can just fall down
    player_pos = player_pos.add(fall_vel);
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

const std = @import("std");
const collision = @import("collision.zig");
const delve = @import("delve");
const app = delve.app;

const graphics = delve.platform.graphics;
const math = delve.math;

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

// lights!
var lights: std.ArrayList(delve.platform.graphics.PointLight) = undefined;

var fog: delve.platform.graphics.FogParams = .{};

// movement properties
var gravity_amount: f32 = -75.0;
var player_move_speed: f32 = 24.0;
var player_ground_acceleration: f32 = 3.0;
var player_air_acceleration: f32 = 0.5;
var player_friction: f32 = 10.0;
var air_friction: f32 = 0.1;
var water_friction: f32 = 4.0;
var jump_acceleration: f32 = 20.0;

pub const PlayerMoveMode = enum {
    WALKING,
    FLYING,
    NOCLIP,
};

// player state
pub const player = struct {
    var move_mode: PlayerMoveMode = .WALKING;
    var size: math.Vec3 = math.Vec3.new(2, 3, 2);
    var pos: math.Vec3 = math.Vec3.zero;
    var vel: math.Vec3 = math.Vec3.zero;
    var on_ground = true;
    var in_water = false;
    var eyes_in_water = false;
};

// shader setup
const lit_shader = delve.shaders.default_basic_lighting;
const basic_lighting_fs_uniforms: []const delve.platform.graphics.MaterialUniformDefaults = &[_]delve.platform.graphics.MaterialUniformDefaults{ .CAMERA_POSITION, .COLOR_OVERRIDE, .ALPHA_CUTOFF, .AMBIENT_LIGHT, .DIRECTIONAL_LIGHT, .POINT_LIGHTS_16, .FOG_DATA };

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
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        try delve.init(gpa.allocator());
    }

    try delve.modules.registerModule(example);
    try delve.module.fps_counter.registerModule();

    // register some console commands
    try delve.debug.registerConsoleCommand("noclip", cvar_toggleNoclip, "Toggle noclip");
    try delve.debug.registerConsoleCommand("fly", cvar_toggleFlyMode, "Toggle flying");

    // and some console variables
    try delve.debug.registerConsoleVariable("p.speed", &player_move_speed, "Player move speed");
    try delve.debug.registerConsoleVariable("p.acceleration", &player_ground_acceleration, "Player move acceleration");
    try delve.debug.registerConsoleVariable("p.groundfriction", &player_friction, "Player ground friction");
    try delve.debug.registerConsoleVariable("p.airfriction", &air_friction, "Player air friction");
    try delve.debug.registerConsoleVariable("p.waterfriction", &water_friction, "Player water friction");
    try delve.debug.registerConsoleVariable("p.jump", &jump_acceleration, "Player jump acceleration");

    try app.start(app.AppConfig{ .title = "Delve Framework - Quake Map Example", .sampler_pool_size = 256 });
}

pub fn on_init() !void {
    // use the Delve Framework global allocator
    const allocator = delve.mem.getAllocator();

    lights = std.ArrayList(delve.platform.graphics.PointLight).init(allocator);

    const world_shader = graphics.Shader.initFromBuiltin(.{ .vertex_attributes = delve.graphics.mesh.getShaderAttributes() }, lit_shader);
    const black_tex = delve.platform.graphics.createSolidTexture(0x00000000);

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
        .shader = world_shader,
        .texture_0 = fallback_tex,
        .texture_1 = black_tex,
        .samplers = &[_]graphics.FilterMode{.NEAREST},
        .default_fs_uniform_layout = basic_lighting_fs_uniforms,
    });

    // create our camera
    camera = delve.graphics.camera.Camera.init(90.0, 0.01, 512, math.Vec3.up);
    camera.position.y = 7.0;

    // set our player starting position
    player.pos = getPlayerStartPosition(&quake_map).mulMat4(map_transform);

    // mark solids using the liquid texture as being water
    for (quake_map.worldspawn.solids.items) |*solid| {
        for (solid.faces.items) |*face| {
            // if any face is using our water texture, mark the solid as being water
            // for Quake 1 maps, you would check for '~' or '#' at the start of the texture name
            if (std.mem.eql(u8, face.texture_name, "tech_17")) {
                solid.custom_flags = 1; // use 1 for water!
            }

            // bias the face vertices a bit to avoid depth fighting
            if (solid.custom_flags == 1) {
                for (face.vertices) |*vert| {
                    vert.* = vert.add(face.plane.normal.scale(0.01));
                }
            }
        }
    }

    // collect all of the solids from the world and entities
    var all_solids = std.ArrayList(delve.utils.quakemap.Solid).init(allocator);
    defer all_solids.deinit();

    try all_solids.appendSlice(quake_map.worldspawn.solids.items);
    for (quake_map.entities.items) |e| {
        try all_solids.appendSlice(e.solids.items);
    }

    // make materials out of all the required textures we found
    var materials = std.StringHashMap(delve.utils.quakemap.QuakeMaterial).init(allocator);
    for (all_solids.items) |*solid| {
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
                    .shader = world_shader,
                    .samplers = &[_]graphics.FilterMode{.NEAREST},
                    .texture_0 = tex,
                    .texture_1 = black_tex,
                    .default_fs_uniform_layout = basic_lighting_fs_uniforms,
                    .cull_mode = if (solid.custom_flags != 1) .BACK else .NONE,
                });
                try materials.put(mat_name_null, .{ .material = mat, .tex_size_x = @intCast(tex.width), .tex_size_y = @intCast(tex.height) });

                // delve.debug.log("Loaded image: {s}", .{tex_path_null});
            }
        }
    }

    // make meshes out of the quake map, batched by material
    map_meshes = try quake_map.buildWorldMeshes(allocator, math.Mat4.identity, materials, .{ .material = fallback_material });
    entity_meshes = try quake_map.buildEntityMeshes(allocator, math.Mat4.identity, materials, .{ .material = fallback_material });

    // find all the lights!
    for (quake_map.entities.items) |entity| {
        if (std.mem.eql(u8, entity.classname, "light")) {
            const light_pos = try entity.getVec3Property("origin");
            var light_radius: f32 = 10.0;
            var light_color: delve.colors.Color = delve.colors.white;

            // quake light properties!
            if (entity.getFloatProperty("light")) |value| {
                light_radius = value * 0.125;
            } else |_| {}

            // our light properties!
            if (entity.getFloatProperty("radius")) |value| {
                light_radius = value;
            } else |_| {}

            if (entity.getVec3Property("_color")) |value| {
                light_color.r = value.x / 255.0;
                light_color.g = value.y / 255.0;
                light_color.b = value.z / 255.0;
            } else |_| {}

            try lights.append(.{ .pos = light_pos.mulMat4(map_transform), .radius = light_radius, .color = light_color });
        }
    }

    // make a bounding box cube
    cube_mesh = try delve.graphics.mesh.createCube(math.Vec3.new(0, 0, 0), player.size, delve.colors.red, fallback_material);

    // do some setup
    delve.platform.graphics.setClearColor(delve.colors.examples_bg_dark);
    delve.platform.app.captureMouse(true);
}

pub fn on_tick(delta: f32) void {
    if (delve.platform.input.isKeyJustPressed(.ESCAPE))
        delve.platform.app.exit();

    // setup the world to collide against
    const world = collision.WorldInfo{
        .quake_map = &quake_map,
    };

    // first, check if we started in the water.
    // only count as being in water if the player is mostly in water
    const water_check_height = math.Vec3.new(0, player.size.y * 0.45, 0);
    const water_bounding_box_size = math.Vec3.new(player.size.x, player.size.y * 0.5, player.size.z);

    player.in_water = collision.collidesWithLiquid(&world, player.pos.add(water_check_height), water_bounding_box_size);

    // accelerate the player from input
    acceleratePlayer();

    // now apply gravity
    if (player.move_mode == .WALKING and !player.on_ground and !player.in_water) {
        player.vel.y += gravity_amount * delta;
    }

    // save the initial move position in case something bad happens
    const start_pos = player.pos;
    const start_vel = player.vel;
    const start_on_ground = player.on_ground;

    // setup our move data
    var move_info = collision.MoveInfo{
        .pos = player.pos,
        .vel = player.vel,
        .size = player.size,
    };

    // now we can try to move
    if (player.move_mode == .WALKING) {
        if ((player.on_ground or player.vel.y <= 0.001) and !player.in_water) {
            _ = collision.doStepSlideMove(&world, &move_info, delta);
        } else {
            _ = collision.doSlideMove(&world, &move_info, delta);
        }

        // check if we are on the ground now
        player.on_ground = collision.isOnGround(&world, move_info) and !player.in_water;

        // if we were on ground before, check if we should stick to a slope
        if (start_on_ground and !player.on_ground) {
            if (collision.groundCheck(&world, move_info, math.Vec3.new(0, -0.125, 0))) |pos| {
                move_info.pos = pos.add(delve.math.Vec3.new(0, 0.0001, 0));
                player.on_ground = true;
            }
        }
    } else if (player.move_mode == .FLYING) {
        // when flying, just do the slide movement
        _ = collision.doSlideMove(&world, &move_info, delta);
        player.on_ground = false;
    } else if (player.move_mode == .NOCLIP) {
        // in noclip mode, ignore collision!
        player.pos = player.pos.add(player.vel.scale(delta));
        player.on_ground = false;
    }

    // use our new positions from the move after resolving
    if (player.move_mode != .NOCLIP) {
        player.pos = move_info.pos;
        player.vel = move_info.vel;

        // If we're encroaching something now, pop us out of it
        if (collision.collidesWithMap(&world, player.pos, player.size)) {
            player.pos = start_pos;
            player.vel = start_vel;
        }
    }

    // slow down the player based on what we are touching
    applyFriction(delta);

    // finally, position camera
    camera.position = player.pos;

    // smooth the camera when stepping up onto something
    if (collision.step_lerp_timer < 1.0) {
        collision.step_lerp_timer += delta * 10.0;
        camera.position.y = delve.utils.interpolation.EaseQuad.applyOut(collision.step_lerp_startheight, camera.position.y, collision.step_lerp_timer);
    }

    // add eye height
    camera.position.y += player.size.y * 0.35;

    // do mouse look
    camera.runSimpleCamera(0, 60 * delta, true);
}

pub fn acceleratePlayer() void {
    // Collect move direction from input
    var move_dir: math.Vec3 = math.Vec3.zero;
    var cam_walk_dir = camera.direction;

    // ignore the camera facing up or down when not flying or swimming
    if (player.move_mode == .WALKING and !player.in_water)
        cam_walk_dir.y = 0.0;

    cam_walk_dir = cam_walk_dir.norm();

    if (delve.platform.input.isKeyPressed(.W)) {
        move_dir = move_dir.sub(cam_walk_dir);
    }
    if (delve.platform.input.isKeyPressed(.S)) {
        move_dir = move_dir.add(cam_walk_dir);
    }
    if (delve.platform.input.isKeyPressed(.D)) {
        const right_dir = camera.getRightDirection();
        move_dir = move_dir.add(right_dir);
    }
    if (delve.platform.input.isKeyPressed(.A)) {
        const right_dir = camera.getRightDirection();
        move_dir = move_dir.sub(right_dir);
    }

    // ignore vertical acceleration when walking
    if (player.move_mode == .WALKING and !player.in_water) {
        move_dir.y = 0;
    }

    // jump and swim!
    if (player.move_mode == .WALKING) {
        if (delve.platform.input.isKeyJustPressed(.SPACE) and player.on_ground) {
            player.vel.y = jump_acceleration;
            player.on_ground = false;
        } else if (delve.platform.input.isKeyPressed(.SPACE) and player.in_water) {
            if (player.eyes_in_water) {
                // if we're under water, just move us up
                move_dir.y += 1.0;
            } else {
                // if we're at the top of the water, jump!
                player.vel.y = jump_acceleration;
            }
        }
    } else {
        // when flying, space will move us up
        if (delve.platform.input.isKeyPressed(.SPACE)) {
            move_dir.y += 1.0;
        }
    }

    // can now apply player movement based on direction
    move_dir = move_dir.norm();

    // default to the basic ground acceleration
    var accel = player_ground_acceleration;

    // in walking mode, choose acceleration based on being in the air, ground, or water
    if (player.move_mode == .WALKING) {
        accel = if (player.on_ground and !player.in_water) player_ground_acceleration else player_air_acceleration;
    }

    // ignore vertical velocity when walking!
    var current_velocity = player.vel;
    if (player.move_mode == .WALKING and !player.in_water) {
        current_velocity.y = 0;
    }

    // accelerate up to the move speed
    if (current_velocity.len() < player_move_speed) {
        const new_velocity = current_velocity.add(move_dir.scale(accel));
        const use_vertical_accel = player.move_mode != .WALKING or player.in_water;

        if (new_velocity.len() < player_move_speed) {
            // under the max speed, can accelerate
            player.vel.x = new_velocity.x;
            player.vel.z = new_velocity.z;

            if (use_vertical_accel)
                player.vel.y = new_velocity.y;
        } else {
            // clamp to max speed!
            const max_speed = new_velocity.norm().scale(player_move_speed);
            player.vel.x = max_speed.x;
            player.vel.z = max_speed.z;

            if (use_vertical_accel)
                player.vel.y = max_speed.y;
        }
    }
}

pub fn applyFriction(delta: f32) void {
    const speed = player.vel.len();
    if (speed > 0) {
        var velocity_drop = speed * delta;
        var friction_amount = player_friction;

        if (player.move_mode == .WALKING) {
            friction_amount = if (player.on_ground) player_friction else if (player.in_water) water_friction else air_friction;
        }

        velocity_drop *= friction_amount;

        const newspeed = (speed - velocity_drop) / speed;
        player.vel = player.vel.scale(newspeed);
    }
}

pub fn on_draw() void {
    const model = math.Mat4.identity;
    const view_mats = camera.update();

    // make a skylight and a light for the player
    const directional_light: delve.platform.graphics.DirectionalLight = .{
        .dir = delve.math.Vec3.new(0.2, 0.8, 0.1).norm(),
        .color = delve.colors.navy,
        .brightness = 0.5,
    };

    const player_light: delve.platform.graphics.PointLight = .{
        .pos = camera.position,
        .radius = 25.0,
        .color = delve.colors.yellow,
    };

    // final list of point lights for the materials
    const max_lights: usize = 16;
    var point_lights: [max_lights]delve.platform.graphics.PointLight = [_]delve.platform.graphics.PointLight{.{ .color = delve.colors.black }} ** max_lights;
    point_lights[0] = player_light;

    // sort the level's lights, and make sure they are actually visible before putting in the final list
    std.sort.insertion(delve.platform.graphics.PointLight, lights.items, {}, compareLights);

    var num_lights: usize = 1;
    for (0..lights.items.len) |i| {
        if (num_lights >= max_lights)
            break;

        const viewFrustum = camera.getViewFrustum();
        const in_frustum = viewFrustum.containsSphere(lights.items[i].pos, lights.items[i].radius * 0.5);

        if (!in_frustum)
            continue;

        point_lights[num_lights] = lights.items[i];
        num_lights += 1;
    }

    // check if our eyes are under water
    const world = collision.WorldInfo{ .quake_map = &quake_map };
    const eyes_check_height = math.Vec3.new(0, player.size.y * 0.6, 0);
    const water_bounding_box_size = math.Vec3.new(player.size.x, player.size.y * 0.5, player.size.z);
    player.eyes_in_water = collision.collidesWithLiquid(&world, player.pos.add(eyes_check_height), water_bounding_box_size);

    fog = .{};
    if (player.eyes_in_water) {
        fog.color = delve.colors.forest_green;
        fog.amount = 0.75;
        fog.start = -50.0;
        fog.end = 50.0;
    }

    // draw the world solids!
    for (map_meshes.items) |*mesh| {
        mesh.material.params.point_lights = &point_lights;
        mesh.material.params.directional_light = directional_light;
        mesh.material.params.fog = fog;
        mesh.draw(view_mats, model);
    }

    // and also entity solids
    for (entity_meshes.items) |*mesh| {
        mesh.material.params.point_lights = &point_lights;
        mesh.material.params.directional_light = directional_light;
        mesh.material.params.fog = fog;
        mesh.draw(view_mats, model);
    }

    // for visualizing the player bounding box
    // cube_mesh.draw(proj_view_matrix, math.Mat4.translate(camera.position));
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

// sort lights based on distance and light radius
fn compareLights(_: void, lhs: delve.platform.graphics.PointLight, rhs: delve.platform.graphics.PointLight) bool {
    const rhs_dist = camera.position.sub(rhs.pos).len();
    const lhs_dist = camera.position.sub(lhs.pos).len();

    const rhs_mod = (rhs.radius * rhs.radius) * 0.005;
    const lhs_mod = (lhs.radius * lhs.radius) * 0.005;

    return rhs_dist - rhs_mod >= lhs_dist - lhs_mod;
}

pub fn cvar_toggleNoclip() void {
    if (player.move_mode != .NOCLIP) {
        player.move_mode = .NOCLIP;
        delve.debug.log("Noclip on! Walls mean nothing to you.", .{});
    } else {
        player.move_mode = .WALKING;
        delve.debug.log("Noclip off", .{});
    }
}

pub fn cvar_toggleFlyMode() void {
    if (player.move_mode != .FLYING) {
        player.move_mode = .FLYING;
        delve.debug.log("Flymode on! You feel lighter.", .{});
    } else {
        player.move_mode = .WALKING;
        delve.debug.log("Flymode off", .{});
    }
}

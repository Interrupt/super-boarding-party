const std = @import("std");
const delve = @import("delve");
const app = delve.app;

const graphics = delve.platform.graphics;
const math = delve.math;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

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
    var allocator = gpa.allocator();

    // Read quake map contents
    const file = try std.fs.cwd().openFile("testmap.map", .{});
    defer file.close();

    const buffer_size = 1024000;
    const file_buffer = try file.readToEndAlloc(allocator, buffer_size);
    defer allocator.free(file_buffer);

    var err: delve.utils.quakemap.ErrorInfo = undefined;
    quake_map = try delve.utils.quakemap.QuakeMap.read(allocator, file_buffer, &err);

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

    map_transform = delve.math.Mat4.scale(delve.math.Vec3.new(0.1, 0.1, 0.1)).mul(delve.math.Mat4.rotate(-90, delve.math.Vec3.x_axis));

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
    map_meshes = try quake_map.buildWorldMeshes(allocator, map_transform, materials, .{ .material = fallback_material });
    entity_meshes = try quake_map.buildEntityMeshes(allocator, map_transform, materials, .{ .material = fallback_material });

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
    const player_move_speed: f32 = 4.0;
    const player_friction: f32 = 100.0;

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

    // apply player movement
    move_dir = move_dir.norm();
    player_vel.x += player_move_speed * move_dir.x;
    player_vel.z += player_move_speed * move_dir.y;

    // check collision with the world against our three axes
    if (collidesWithMap(player_pos.add(math.Vec3.new(player_vel.x * delta, 0, 0)), bounding_box_size))
        player_vel.x = 0.0;

    if (collidesWithMap(player_pos.add(math.Vec3.new(0, 0, player_vel.z * delta)), bounding_box_size))
        player_vel.z = 0.0;

    if (collidesWithMap(player_pos.add(math.Vec3.new(0, player_vel.y * delta, 0)), bounding_box_size)) {
        on_ground = player_vel.y < 0.0;
        player_vel.y = 0.0;
    } else {
        on_ground = false;
    }

    // can update the player position now
    player_pos = player_pos.add(player_vel.scale(delta));

    // position camera
    camera.position = player_pos;
    camera.position.y += bounding_box_size.y * 0.35; // eye height

    // do mouse look
    camera.runSimpleCamera(0, 60 * delta, true);

    // dumb friction! this is probably so broken
    player_vel.x *= player_friction * delta;
    player_vel.z *= player_friction * delta;
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
    const invert_map_transform = map_transform.invert();
    const bounds = delve.spatial.BoundingBox.init(pos.mulMat4(invert_map_transform), size.mulMat4(invert_map_transform));

    // check world
    for (quake_map.worldspawn.solids.items) |solid| {
        const did_collide = solid.checkBoundingBoxCollision(bounds);
        if (did_collide)
            return true;
    }

    // and also entities
    for (quake_map.entities.items) |entity| {
        for (entity.solids.items) |solid| {
            const did_collide = solid.checkBoundingBoxCollision(bounds);
            if (did_collide)
                return true;
        }
    }
    return false;
}

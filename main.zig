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
    const player_friction: f32 = 0.8;

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
    player_vel.x += player_move_speed * move_dir.x;
    player_vel.z += player_move_speed * move_dir.y;

    // try to move the player
    do_player_move(delta);

    // dumb friction! this needs to take into account delta time
    player_vel.x *= player_friction;
    player_vel.z *= player_friction;

    // position camera
    camera.position = player_pos;
    camera.position.y += bounding_box_size.y * 0.35; // eye height

    // do mouse look
    camera.runSimpleCamera(0, 60 * delta, true);
}

pub fn do_player_move(delta: f32) void {
    const stepheight: f32 = 1.0;

    on_ground = false;

    const movehit = collidesWithMapWithVelocity(player_pos, bounding_box_size, player_vel.scale(delta));

    if (movehit == null) {
        // easy case, can just move
        player_pos = player_pos.add(player_vel.scale(delta));
        return;
    }

    // check if we can walk up a stair - break it into two steps, the up and the over
    const stairstep: math.Vec3 = math.Vec3.new(0, stepheight, 0);
    const stairhit_up = collidesWithMapWithVelocity(player_pos, bounding_box_size, stairstep);

    if (stairhit_up == null) {
        const stairhit_over = collidesWithMapWithVelocity(player_pos.add(stairstep), bounding_box_size, player_vel.scale(delta));

        if (stairhit_over == null) {
            // free space! move up to the step height
            player_pos = player_pos.add(stairstep).add(player_vel.scale(delta));

            // press back down to step
            const hitpos = collidesWithMapWithVelocity(player_pos, bounding_box_size, stairstep.scale(-1.0));

            if (hitpos) |h| {
                // stick to the step
                const transformed = h.loc.mulMat4(map_transform);
                player_pos = transformed;
                player_pos.y += 0.0001;
                player_vel.y = 0.0;
                on_ground = true;
                return;
            }

            // weird! not on a step?
            return;
        }
    }

    // assume we hit a wall!
    player_vel.x = 0.0;
    player_vel.z = 0.0;

    // todo: get hit normal, adjust velocity based on that

    // still try to fall
    const fallhit = collidesWithMapWithVelocity(player_pos, bounding_box_size, player_vel.scale(delta));

    if (fallhit) |h| {
        // stick to the ground
        if (player_vel.y < 0) {
            const transformed = h.loc.mulMat4(map_transform);
            player_pos = transformed;
            player_pos.y += 0.0001;
            on_ground = true;
        }

        // either hit a ceiling or a floor, so kill vertical velocity
        player_vel.y = 0.0;
        return;
    }

    // no fall hit, can just fall down
    player_pos = player_pos.add(player_vel.scale(delta));
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
        const did_collide = checkBoundingBoxSolidCollision(&solid, bounds);
        if (did_collide)
            return true;
    }

    // and also entities
    for (quake_map.entities.items) |entity| {
        for (entity.solids.items) |solid| {
            const did_collide = checkBoundingBoxSolidCollision(&solid, bounds);
            if (did_collide)
                return true;
        }
    }
    return false;
}

pub fn collidesWithMapWithVelocity(pos: math.Vec3, size: math.Vec3, velocity: math.Vec3) ?WorldHit {
    const invert_map_transform = map_transform.invert();
    const bounds = delve.spatial.BoundingBox.init(pos.mulMat4(invert_map_transform), size.mulMat4(invert_map_transform));

    var worldhit: ?WorldHit = null;
    var hitlen: f32 = undefined;

    // check world
    for (quake_map.worldspawn.solids.items) |solid| {
        const did_collide = checkCollisionWithVelocity(&solid, bounds, velocity.mulMat4(invert_map_transform));
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
            const did_collide = checkCollisionWithVelocity(&solid, bounds, velocity.mulMat4(invert_map_transform));
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

pub fn checkBoundingBoxSolidCollision(self: *const delve.utils.quakemap.Solid, bounds: delve.spatial.BoundingBox) bool {
    const size = bounds.max.sub(bounds.min).scale(0.5);
    const planes = getExpandedPlanes(self, size) catch {
        return false;
    };
    defer planes.deinit();

    const point = bounds.center;

    if (planes.items.len == 0)
        return false;

    for (planes.items) |p| {
        if (p.testPoint(point) == .FRONT)
            return false;
    }

    return true;
}

pub const WorldHit = struct {
    loc: math.Vec3,
    plane: delve.spatial.Plane,
};

// Get the planes expanded by the Minkowski sum of the bounding box
pub fn getExpandedPlanes(self: *const delve.utils.quakemap.Solid, size: math.Vec3) !std.ArrayList(delve.spatial.Plane) {
    var expanded_planes: std.ArrayList(delve.spatial.Plane) = std.ArrayList(delve.spatial.Plane).init(allocator);
    errdefer expanded_planes.deinit();

    if (self.faces.items.len == 0)
        return expanded_planes;

    // build a bounding box as we go
    var solid_bounds = delve.spatial.BoundingBox.initFromPositions(self.faces.items[0].vertices);

    for (self.faces.items) |*face| {
        var expand_dist: f32 = 0;

        // expand the solids bounding box bounds based on our verts
        for (face.vertices) |vert| {
            const min = vert.min(solid_bounds.min);
            const max = vert.max(solid_bounds.max);
            solid_bounds.min = min;
            solid_bounds.max = max;
        }

        // x_axis
        const x_d = face.plane.normal.dot(math.Vec3.x_axis);
        if (x_d > 0) expand_dist += -x_d * size.x;

        const x_d_n = face.plane.normal.dot(math.Vec3.x_axis.scale(-1));
        if (x_d_n > 0) expand_dist += -x_d_n * size.x;

        // y_axis
        const y_d = face.plane.normal.dot(math.Vec3.y_axis);
        if (y_d > 0) expand_dist += y_d * size.y;

        const y_d_n = face.plane.normal.dot(math.Vec3.y_axis.scale(-1));
        if (y_d_n > 0) expand_dist += y_d_n * size.y;

        // z_axis
        const z_d = face.plane.normal.dot(math.Vec3.z_axis);
        if (z_d > 0) expand_dist += -z_d * size.z;

        const z_d_n = face.plane.normal.dot(math.Vec3.z_axis.scale(-1));
        if (z_d_n > 0) expand_dist += -z_d_n * size.z;

        var expandedface = face.plane;
        expandedface.d += expand_dist;

        try expanded_planes.append(expandedface);
    }

    // Make the Minkowski sum of both bounding boxes
    solid_bounds.min.x -= size.x;
    solid_bounds.min.y -= -size.y;
    solid_bounds.min.z -= size.z;

    solid_bounds.max.x += size.x;
    solid_bounds.max.y += -size.y;
    solid_bounds.max.z += size.z;

    // Can use the sum as our bevel planes
    const bevel_planes = solid_bounds.getPlanes();
    for (bevel_planes) |plane| {
        try expanded_planes.append(plane);
    }

    return expanded_planes;
}

pub fn checkCollisionWithVelocity(self: *const delve.utils.quakemap.Solid, bounds: delve.spatial.BoundingBox, velocity: math.Vec3) ?WorldHit {
    var worldhit: ?WorldHit = null;

    const size = bounds.max.sub(bounds.min).scale(0.5);
    const planes = getExpandedPlanes(self, size) catch {
        return null;
    };
    defer planes.deinit();

    const point = bounds.center;
    const next = point.add(velocity);

    if (planes.items.len == 0)
        return null;

    for (0..planes.items.len) |idx| {
        const p = planes.items[idx];
        if (p.testPoint(next) == .FRONT)
            return null;

        const hit = p.intersectLine(point, next);
        if (hit) |h| {
            var didhit = true;
            for (0..planes.items.len) |h_idx| {
                if (idx == h_idx)
                    continue;

                // check that this hit point is behind the other clip planes
                const pp = planes.items[h_idx];
                if (pp.testPoint(h) == .FRONT) {
                    didhit = false;
                    break;
                }
            }

            if (didhit) {
                worldhit = .{
                    .loc = h,
                    .plane = p,
                };
            }
        }
    }

    return worldhit;
}

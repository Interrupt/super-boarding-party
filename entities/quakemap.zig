const std = @import("std");
const delve = @import("delve");
const entities = @import("../game/entities.zig");

const math = delve.math;
const spatial = delve.spatial;
const graphics = delve.platform.graphics;

// Cache of all loaded QuakeMapComponents
pub var loaded_quake_maps: ?std.ArrayList(*QuakeMapComponent) = null;

// materials!
var did_init_materials: bool = false;
var fallback_material: graphics.Material = undefined;
var fallback_quake_material: delve.utils.quakemap.QuakeMaterial = undefined;
var materials: std.StringHashMap(delve.utils.quakemap.QuakeMaterial) = undefined;

// shader setup
const lit_shader = delve.shaders.default_basic_lighting;
const basic_lighting_fs_uniforms: []const delve.platform.graphics.MaterialUniformDefaults = &[_]delve.platform.graphics.MaterialUniformDefaults{ .CAMERA_POSITION, .COLOR_OVERRIDE, .ALPHA_CUTOFF, .AMBIENT_LIGHT, .DIRECTIONAL_LIGHT, .POINT_LIGHTS_16, .FOG_DATA };

pub const QuakeMapComponent = struct {
    // properties
    filename: []const u8,
    transform: math.Mat4,

    time: f32 = 0.0,
    player_start: math.Vec3 = math.Vec3.zero,

    // the loaded map
    quake_map: delve.utils.quakemap.QuakeMap = undefined,

    // quake maps load at a different scale and rotation - adjust for that
    map_transform: math.Mat4 = undefined,

    // meshes for drawing
    map_meshes: std.ArrayList(delve.graphics.mesh.Mesh) = undefined,
    entity_meshes: std.ArrayList(delve.graphics.mesh.Mesh) = undefined,

    // map lights
    lights: std.ArrayList(delve.platform.graphics.PointLight) = undefined,

    // spatial hash!
    solid_spatial_hash: SpatialHash = undefined,

    pub fn init(self: *QuakeMapComponent, interface: entities.EntityComponent) void {
        _ = interface;

        self.init_world() catch {
            delve.debug.log("Could not init quake map component!", .{});
        };

        if (loaded_quake_maps == null) {
            loaded_quake_maps = std.ArrayList(*QuakeMapComponent).init(delve.mem.getAllocator());
        }

        loaded_quake_maps.?.append(self) catch {
            delve.debug.log("Could not cache quake map component!", .{});
        };
    }

    pub fn init_world(self: *QuakeMapComponent) !void {
        // use the Delve Framework global allocator
        const allocator = delve.mem.getAllocator();

        self.solid_spatial_hash = SpatialHash.init(16.0, allocator);

        self.lights = std.ArrayList(delve.platform.graphics.PointLight).init(allocator);

        const world_shader = try graphics.Shader.initFromBuiltin(.{ .vertex_attributes = delve.graphics.mesh.getShaderAttributes() }, lit_shader);
        const black_tex = delve.platform.graphics.createSolidTexture(0x00000000);

        // scale and rotate the map
        const map_scale = delve.math.Vec3.new(0.1, 0.1, 0.1); // Quake seems to be about 0.07, 0.07, 0.07
        self.map_transform = delve.math.Mat4.scale(map_scale).mul(delve.math.Mat4.rotate(-90, delve.math.Vec3.x_axis));

        // Read quake map contents
        const file = try std.fs.cwd().openFile(self.filename, .{});
        defer file.close();

        const buffer_size = 8024000;
        const file_buffer = try file.readToEndAlloc(allocator, buffer_size);
        defer allocator.free(file_buffer);

        var err: delve.utils.quakemap.ErrorInfo = undefined;
        self.quake_map = delve.utils.quakemap.QuakeMap.read(allocator, file_buffer, self.map_transform, &err) catch {
            delve.debug.log("Error reading quake map: {}", .{err});
            return;
        };

        // init the materials list for quake maps to use, if not already
        if (!did_init_materials) {
            materials = std.StringHashMap(delve.utils.quakemap.QuakeMaterial).init(allocator);

            // Create a fallback material to use when no texture could be loaded
            const fallback_tex = graphics.createDebugTexture();
            fallback_material = try graphics.Material.init(.{
                .shader = world_shader,
                .texture_0 = fallback_tex,
                .texture_1 = black_tex,
                .samplers = &[_]graphics.FilterMode{.NEAREST},
                .default_fs_uniform_layout = basic_lighting_fs_uniforms,
            });

            fallback_quake_material = .{
                .material = fallback_material,
            };

            did_init_materials = true;
        }

        // set our player starting position
        self.player_start = getPlayerStartPosition(&self.quake_map).mulMat4(self.map_transform).mulMat4(self.transform);

        // apply final transform!
        // TODO: Why is this neccessary? Translating planes by a Mat4 seems borked
        for (self.quake_map.worldspawn.solids.items) |*solid| {
            for (solid.faces.items) |*face| {
                face.plane = delve.spatial.Plane.initFromTriangle(face.vertices[0].mulMat4(self.transform), face.vertices[1].mulMat4(self.transform), face.vertices[2].mulMat4(self.transform));

                // also move the verts!
                for (face.vertices) |*vert| {
                    vert.* = vert.mulMat4(self.transform);
                }
            }
            solid.bounds = solid.bounds.transform(self.transform);
        }

        // mark solids using the liquid texture as being water
        for (self.quake_map.worldspawn.solids.items) |*solid| {
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

        // also add the solids to the spatial hash!
        self.solid_spatial_hash.addSolids(self.quake_map.worldspawn.solids.items) catch {
            delve.debug.log("Could not add faces to spatial hash!", .{});
        };

        // collect all of the solids from the world and entities
        var all_solids = std.ArrayList(delve.utils.quakemap.Solid).init(allocator);
        defer all_solids.deinit();

        try all_solids.appendSlice(self.quake_map.worldspawn.solids.items);
        for (self.quake_map.entities.items) |e| {
            try all_solids.appendSlice(e.solids.items);
        }

        // make materials out of all the required textures we found
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
                    defer tex_img.deinit();
                    const tex = graphics.Texture.init(tex_img);

                    const mat = try graphics.Material.init(.{
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
        self.map_meshes = try self.quake_map.buildWorldMeshes(allocator, math.Mat4.identity, &materials, &fallback_quake_material);
        self.entity_meshes = try self.quake_map.buildEntityMeshes(allocator, math.Mat4.identity, &materials, &fallback_quake_material);

        // find all the lights!
        for (self.quake_map.entities.items) |entity| {
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

                try self.lights.append(.{ .pos = light_pos.mulMat4(self.map_transform).mulMat4(self.transform), .radius = light_radius, .color = light_color });
            }
        }
    }

    pub fn getWorldSolids(self: *QuakeMapComponent) []delve.utils.quakemap.Solid {
        return self.quake_map.worldspawn.solids.items;
    }

    pub fn deinit(self: *QuakeMapComponent) void {
        _ = self;
    }

    pub fn tick(self: *QuakeMapComponent, delta: f32) void {
        self.time += delta;
    }
};

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

// Spatial Hash implementation
// TODO: Move this to it's own file!

pub const SpatialHashLoc = struct {
    x_cell: i32,
    y_cell: i32,
    z_cell: i32,
};

pub const SpatialHashCell = struct {
    solids: std.ArrayList(*delve.utils.quakemap.Solid),
};

pub const SpatialHash = struct {
    cell_size: f32,
    allocator: std.mem.Allocator,
    cells: std.AutoHashMap(SpatialHashLoc, SpatialHashCell),

    bounds: spatial.BoundingBox = undefined,
    scratch: std.ArrayList(*delve.utils.quakemap.Solid),

    pub fn init(cell_size: f32, allocator: std.mem.Allocator) SpatialHash {
        const floatMax = std.math.floatMax(f32);
        const floatMin = std.math.floatMin(f32);

        return .{
            .cell_size = cell_size,
            .allocator = allocator,
            .cells = std.AutoHashMap(SpatialHashLoc, SpatialHashCell).init(allocator),
            .scratch = std.ArrayList(*delve.utils.quakemap.Solid).init(allocator),
            .bounds = spatial.BoundingBox.init(math.Vec3.new(floatMax, floatMax, floatMax), math.Vec3.new(floatMin, floatMin, floatMin)),
        };
    }

    pub fn locToCellSpace(self: *SpatialHash, loc: delve.math.Vec3) SpatialHashLoc {
        return .{
            .x_cell = @intFromFloat(@floor(loc.x / self.cell_size)),
            .y_cell = @intFromFloat(@floor(loc.y / self.cell_size)),
            .z_cell = @intFromFloat(@floor(loc.z / self.cell_size)),
        };
    }

    pub fn locToCellSpaceVec3(self: *SpatialHash, loc: delve.math.Vec3) delve.math.Vec3 {
        return .{
            .x = loc.x / self.cell_size,
            .y = loc.y / self.cell_size,
            .z = loc.z / self.cell_size,
        };
    }

    pub fn getSolidsNear(self: *SpatialHash, bounds: spatial.BoundingBox) []*delve.utils.quakemap.Solid {
        self.scratch.clearRetainingCapacity();

        // This is not always exact, so add a bit of an epsilon here!
        const area = bounds.inflate(0.01);

        if (!self.bounds.intersects(area)) {
            return self.scratch.items;
        }

        const min = self.locToCellSpace(area.min);
        const max = self.locToCellSpace(area.max);

        // const log_center = self.locToCellSpace(area.center);
        // delve.debug.log("Loc: {d} {d} {d}", .{ log_center.x_cell, log_center.y_cell, log_center.z_cell });

        const num_x: usize = @intCast(max.x_cell - min.x_cell);
        const num_y: usize = @intCast(max.y_cell - min.y_cell);
        const num_z: usize = @intCast(max.z_cell - min.z_cell);

        for (0..num_x + 1) |x| {
            for (0..num_y + 1) |y| {
                for (0..num_z + 1) |z| {
                    const hash_key = .{ .x_cell = min.x_cell + @as(i32, @intCast(x)), .y_cell = min.y_cell + @as(i32, @intCast(y)), .z_cell = min.z_cell + @as(i32, @intCast(z)) };
                    self.addUniqueSolidsFromCell(&self.scratch, hash_key);
                }
            }
        }

        return self.scratch.items;
    }

    pub fn getSolidsAlong(self: *SpatialHash, ray_start: math.Vec3, ray_end: math.Vec3) []*delve.utils.quakemap.Solid {
        self.scratch.clearRetainingCapacity();

        // Use the DDA algorithm to collect solids from all encountered cells for this ray segment

        const ray = ray_end.sub(ray_start);
        const ray_len = ray.len();
        const ray_dir = ray.norm();

        // first, check if we have anything to do here at all
        // const check_ray = delve.spatial.Ray.init(ray_start, ray);
        // if (check_ray.intersectBoundingBox(self.bounds) == null) {
        //     return self.scratch.items;
        // }

        // find the starting and ending cells
        const ray_start_cell: SpatialHashLoc = self.locToCellSpace(ray_start);
        const ray_end_cell: SpatialHashLoc = self.locToCellSpace(ray_end);

        const step_x: i32 = if (ray_dir.x >= 0) 1 else -1;
        const step_y: i32 = if (ray_dir.y >= 0) 1 else -1;
        const step_z: i32 = if (ray_dir.z >= 0) 1 else -1;

        const step_x_f: f32 = @floatFromInt(step_x);
        const step_y_f: f32 = @floatFromInt(step_y);
        const step_z_f: f32 = @floatFromInt(step_z);

        // distance along the ray to the next cell boundary
        const next_cell_boundary_x: f32 = @as(f32, @floatFromInt(ray_start_cell.x_cell + step_x)) * self.cell_size;
        const next_cell_boundary_y: f32 = @as(f32, @floatFromInt(ray_start_cell.y_cell + step_y)) * self.cell_size;
        const next_cell_boundary_z: f32 = @as(f32, @floatFromInt(ray_start_cell.z_cell + step_z)) * self.cell_size;

        // distance until the next vertical cell boundary
        var t_max_x = if (ray_dir.x != 0) (next_cell_boundary_x - ray_start.x) / ray_dir.x else std.math.floatMax(f32);
        var t_max_y = if (ray_dir.y != 0) (next_cell_boundary_y - ray_start.y) / ray_dir.y else std.math.floatMax(f32);
        var t_max_z = if (ray_dir.z != 0) (next_cell_boundary_z - ray_start.z) / ray_dir.z else std.math.floatMax(f32);

        // how far the ray needs to travel to equal the width of a cell
        const t_delta_x = if (ray_dir.x != 0) self.cell_size / ray_dir.x * step_x_f else std.math.floatMax(f32);
        const t_delta_y = if (ray_dir.y != 0) self.cell_size / ray_dir.y * step_y_f else std.math.floatMax(f32);
        const t_delta_z = if (ray_dir.z != 0) self.cell_size / ray_dir.z * step_z_f else std.math.floatMax(f32);

        var diff_vec = math.Vec3.new(0, 0, 0);
        var negative_ray = false;
        if (ray_start_cell.x_cell != ray_end_cell.x_cell and ray_dir.x < 0) {
            diff_vec.x = -1;
            negative_ray = true;
        }
        if (ray_start_cell.y_cell != ray_end_cell.y_cell and ray_dir.y < 0) {
            diff_vec.y = -1;
            negative_ray = true;
        }
        if (ray_start_cell.z_cell != ray_end_cell.z_cell and ray_dir.z < 0) {
            diff_vec.z = -1;
            negative_ray = true;
        }

        var current_cell = ray_start_cell;

        if (negative_ray) {
            current_cell.x_cell += @intFromFloat(diff_vec.x);
            current_cell.y_cell += @intFromFloat(diff_vec.y);
            current_cell.z_cell += @intFromFloat(diff_vec.z);
        }

        // delve.debug.log("Visited cell: {d} {d} {d}", .{ current_cell.x_cell, current_cell.y_cell, current_cell.z_cell });
        self.addUniqueSolidsFromCell(&self.scratch, current_cell);

        // guard against looping forever!
        const max_hops: i32 = @as(i32, @intFromFloat(ray_len / self.cell_size)) * 2;
        var cur_hops: i32 = 0;
        while (current_cell.x_cell != ray_end_cell.x_cell or current_cell.y_cell != ray_end_cell.y_cell or current_cell.z_cell != ray_end_cell.z_cell) {
            if (t_max_x < t_max_y) {
                if (t_max_x < t_max_z) {
                    current_cell.x_cell += step_x;
                    t_max_x += t_delta_x;
                } else {
                    current_cell.z_cell += step_z;
                    t_max_z += t_delta_z;
                }
            } else {
                if (t_max_y < t_max_z) {
                    current_cell.y_cell += step_y;
                    t_max_y += t_delta_y;
                } else {
                    current_cell.z_cell += step_z;
                    t_max_z += t_delta_z;
                }
            }

            // delve.debug.log("Visited cell: {d} {d} {d}", .{ current_cell.x_cell, current_cell.y_cell, current_cell.z_cell });
            self.addUniqueSolidsFromCell(&self.scratch, current_cell);

            cur_hops += 1;
            if (cur_hops > max_hops)
                break;
        }

        return self.scratch.items;
    }

    pub fn addUniqueSolidsFromCell(self: *SpatialHash, add_to_list: *std.ArrayList(*delve.utils.quakemap.Solid), loc: SpatialHashLoc) void {
        if (self.cells.getPtr(loc)) |cell| {
            // Only return unique solids!
            for (cell.solids.items) |solid| {
                var existing = false;
                for (add_to_list.items) |existing_solid| {
                    if (solid == existing_solid) {
                        existing = true;
                        break;
                    }
                }

                if (existing)
                    continue;

                add_to_list.append(solid) catch {};
            }
        }
    }

    pub fn addSolids(self: *SpatialHash, solids: []delve.utils.quakemap.Solid) !void {
        for (solids) |*solid| {
            const bounds = getBoundsForSolid(solid);
            const cell_min = self.locToCellSpace(bounds.min);
            const cell_max = self.locToCellSpace(bounds.max);

            const num_x: usize = @intCast(cell_max.x_cell - cell_min.x_cell);
            const num_y: usize = @intCast(cell_max.y_cell - cell_min.y_cell);
            const num_z: usize = @intCast(cell_max.z_cell - cell_min.z_cell);

            // delve.debug.log("Solid size: {d} {d}", .{ num_x + 1, num_y + 1 });

            for (0..num_x + 1) |x| {
                for (0..num_y + 1) |y| {
                    for (0..num_z + 1) |z| {
                        const hash_key = .{ .x_cell = cell_min.x_cell + @as(i32, @intCast(x)), .y_cell = cell_min.y_cell + @as(i32, @intCast(y)), .z_cell = cell_min.z_cell + @as(i32, @intCast(z)) };
                        var hash_cell = self.cells.getPtr(hash_key);

                        if (hash_cell != null) {
                            // This cell existed already, just add to it
                            try hash_cell.?.solids.append(solid);
                            // delve.debug.log("Added solid to existing list {any}", .{hash_key});
                        } else {
                            // This cell is new, create it first!
                            var cell_solids = std.ArrayList(*delve.utils.quakemap.Solid).init(self.allocator);
                            try cell_solids.append(solid);
                            try self.cells.put(hash_key, .{ .solids = cell_solids });
                            // delve.debug.log("Created new cells list at {any}", .{hash_key});
                        }
                    }
                }
            }

            // Update our bounds to include the new solid
            self.bounds.min = math.Vec3.min(self.bounds.min, bounds.min);
            self.bounds.max = math.Vec3.max(self.bounds.max, bounds.max);
        }
    }
};

pub fn getBoundsForSolid(solid: *delve.utils.quakemap.Solid) spatial.BoundingBox {
    const floatMax = std.math.floatMax(f32);
    const floatMin = std.math.floatMin(f32);

    var min: math.Vec3 = math.Vec3.new(floatMax, floatMax, floatMax);
    var max: math.Vec3 = math.Vec3.new(floatMin, floatMin, floatMin);

    for (solid.faces.items) |*face| {
        const face_bounds = spatial.BoundingBox.initFromPositions(face.vertices);
        min = math.Vec3.min(min, face_bounds.min);
        max = math.Vec3.max(max, face_bounds.max);
    }

    return spatial.BoundingBox{
        .center = math.Vec3.new(min.x + (max.x - min.x) * 0.5, min.y + (max.y - min.y) * 0.5, min.z + (max.z - min.z) * 0.5),
        .min = min,
        .max = max,
    };
}

pub fn getComponentStorage(world: *entities.World) *entities.ComponentStorage(QuakeMapComponent) {
    return world.components.getStorageForType(QuakeMapComponent) catch {
        delve.debug.fatal("Could not get QuakeMapComponent storage!", .{});
        return undefined;
    };
}

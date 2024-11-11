const std = @import("std");
const delve = @import("delve");
const basics = @import("basics.zig");
const actor_stats = @import("actor_stats.zig");
const box_collision = @import("box_collision.zig");
const character = @import("character.zig");
const monster = @import("monster.zig");
const sprites = @import("sprite.zig");
const quakesolids = @import("quakesolids.zig");
const entities = @import("../game/entities.zig");
const spatialhash = @import("../utils/spatial_hash.zig");
pub const mover = @import("mover.zig");

const math = delve.math;
const spatial = delve.spatial;
const graphics = delve.platform.graphics;

// Cache of all loaded QuakeMapComponents
pub var loaded_quake_maps: ?std.ArrayList(*QuakeMapComponent) = null;

// materials!
pub var did_init_materials: bool = false;
pub var fallback_material: graphics.Material = undefined;
pub var fallback_quake_material: delve.utils.quakemap.QuakeMaterial = undefined;
pub var materials: std.StringHashMap(delve.utils.quakemap.QuakeMaterial) = undefined;

// shader setup
pub const lit_shader = delve.shaders.default_basic_lighting;
pub const basic_lighting_fs_uniforms: []const delve.platform.graphics.MaterialUniformDefaults = &[_]delve.platform.graphics.MaterialUniformDefaults{ .CAMERA_POSITION, .COLOR_OVERRIDE, .ALPHA_CUTOFF, .AMBIENT_LIGHT, .DIRECTIONAL_LIGHT, .POINT_LIGHTS_16, .FOG_DATA };

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
    solid_spatial_hash: spatialhash.SpatialHash(delve.utils.quakemap.Solid) = undefined,

    // interface
    owner: entities.Entity = entities.InvalidEntity,

    pub fn init(self: *QuakeMapComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;

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

        self.solid_spatial_hash = spatialhash.SpatialHash(delve.utils.quakemap.Solid).init(6.0, allocator);

        self.lights = std.ArrayList(delve.platform.graphics.PointLight).init(allocator);

        const world_shader = try graphics.Shader.initFromBuiltin(.{ .vertex_attributes = delve.graphics.mesh.getShaderAttributes() }, lit_shader);
        const black_tex = delve.platform.graphics.createSolidTexture(0x00000000);

        // translate, scale and rotate the map
        const map_scale = delve.math.Vec3.new(0.1, 0.1, 0.1); // Quake seems to be about 0.07, 0.07, 0.07
        self.map_transform = self.transform.mul(delve.math.Mat4.scale(map_scale).mul(delve.math.Mat4.rotate(-90, delve.math.Vec3.x_axis)));

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
        self.player_start = getPlayerStartPosition(&self.quake_map).mulMat4(self.map_transform);

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
        for (self.quake_map.worldspawn.solids.items) |*solid| {
            self.solid_spatial_hash.addEntry(solid, getBoundsForSolid(solid), false) catch {
                delve.debug.log("Could not add face to spatial hash!", .{});
            };
        }

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

                try self.lights.append(.{ .pos = light_pos.mulMat4(self.map_transform), .radius = light_radius, .color = light_color });
            }
        }

        const world_opt = entities.getWorld(self.owner.getWorldId());
        if (world_opt == null)
            return;

        // spawn monsters!
        for (self.quake_map.entities.items) |*entity| {
            if (std.mem.eql(u8, entity.classname, "monster_alien")) {
                const entity_pos = try entity.getVec3Property("origin");
                const monster_pos = entity_pos.mulMat4(self.map_transform);

                var m = try world_opt.?.createEntity(.{});
                _ = try m.createNewComponent(basics.TransformComponent, .{ .position = monster_pos });
                _ = try m.createNewComponent(character.CharacterMovementComponent, .{ .max_slide_bumps = 2 });
                _ = try m.createNewComponent(box_collision.BoxCollisionComponent, .{ .size = delve.math.Vec3.new(2, 2.5, 2), .can_step_up_on = false });
                _ = try m.createNewComponent(monster.MonsterController, .{});
                _ = try m.createNewComponent(actor_stats.ActorStats, .{ .hp = 10 });
                _ = try m.createNewComponent(sprites.SpriteComponent, .{ .position = delve.math.Vec3.new(0, 0.8, 0.0), .billboard_type = .XZ });
            }
            if (std.mem.eql(u8, entity.classname, "func_plat")) {
                var move_height: f32 = 6.0;
                var move_speed: f32 = 6.0;

                if (entity.getFloatProperty("height")) |v| {
                    move_height = v * 0.1;
                } else |_| {}

                if (entity.getFloatProperty("speed")) |v| {
                    move_speed = v;
                } else |_| {}

                var m = try world_opt.?.createEntity(.{});
                _ = try m.createNewComponent(basics.TransformComponent, .{ .position = delve.math.Vec3.zero });
                _ = try m.createNewComponent(mover.MoverComponent, .{
                    .move_amount = math.Vec3.y_axis.scale(move_height),
                    .move_time = move_speed,
                    .return_time = move_speed,
                    .return_delay_time = 3.0, // quake default
                });
                _ = try m.createNewComponent(quakesolids.QuakeSolidsComponent, .{ .quake_map = &self.quake_map, .quake_entity = entity, .transform = self.map_transform });
            }
            if (std.mem.eql(u8, entity.classname, "func_door")) {
                var move_height: f32 = 5.0;
                var move_speed: f32 = 1.0;

                if (entity.getFloatProperty("height")) |v| {
                    move_height = v * 0.1;
                } else |_| {}

                if (entity.getFloatProperty("speed")) |v| {
                    move_speed = v;
                } else |_| {}

                var m = try world_opt.?.createEntity(.{});
                _ = try m.createNewComponent(basics.TransformComponent, .{ .position = delve.math.Vec3.zero });
                _ = try m.createNewComponent(mover.MoverComponent, .{
                    .move_amount = math.Vec3.y_axis.scale(move_height),
                    .move_time = move_speed,
                    .return_time = move_speed,
                    .return_delay_time = 3.0, // quake default
                });
                _ = try m.createNewComponent(quakesolids.QuakeSolidsComponent, .{ .quake_map = &self.quake_map, .quake_entity = entity, .transform = self.map_transform });
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

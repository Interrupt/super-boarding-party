const std = @import("std");
const delve = @import("delve");
const audio = @import("audio.zig");
const basics = @import("basics.zig");
const actor_stats = @import("actor_stats.zig");
const box_collision = @import("box_collision.zig");
const breakables = @import("breakable.zig");
const character = @import("character.zig");
const explosion = @import("explosion.zig");
const emitter = @import("particle_emitter.zig");
const lights = @import("light.zig");
const monster = @import("monster.zig");
const sprites = @import("sprite.zig");
const string = @import("../utils/string.zig");
const meshes = @import("mesh.zig");
const items = @import("item.zig");
const text = @import("text.zig");
const textures = @import("../managers/textures.zig");
const quakesolids = @import("quakesolids.zig");
const weapons = @import("weapon.zig");
const triggers = @import("triggers.zig");
const entities = @import("../game/entities.zig");
const spatialhash = @import("../utils/spatial_hash.zig");
const bvhtree = @import("../utils/bvhtree.zig");
const main = @import("../main.zig");
const scripting = @import("../game/scripting.zig");

pub const mover = @import("mover.zig");

const ArrayList = @import("../utils/arraylist.zig").ArrayList;

const math = delve.math;
const spatial = delve.spatial;
const graphics = delve.platform.graphics;

// Cache of all loaded QuakeMapComponents
// pub var loaded_quake_maps: ?ArrayList(*QuakeMapComponent) = null;

pub const MaterialAnimation = struct {
    material: delve.platform.graphics.Material,
    textures: ArrayList(textures.LoadedTexture),
};

// materials!
pub var did_init_materials: bool = false;
pub var fallback_material: graphics.Material = undefined;
pub var clip_texture: graphics.Texture = undefined;
pub var fallback_quake_material: delve.utils.quakemap.QuakeMaterial = undefined;
pub var materials: std.StringHashMap(delve.utils.quakemap.QuakeMaterial) = undefined;
pub var material_animations: ArrayList(MaterialAnimation) = undefined;
pub var world_shader: graphics.Shader = undefined;

// shader setup
pub const lit_shader = delve.shaders.default_basic_lighting;
pub const basic_lighting_fs_uniforms: []const delve.platform.graphics.MaterialUniformDefaults = &[_]delve.platform.graphics.MaterialUniformDefaults{ .CAMERA_POSITION, .COLOR_OVERRIDE, .ALPHA_CUTOFF, .AMBIENT_LIGHT, .DIRECTIONAL_LIGHT, .POINT_LIGHTS_16, .FOG_DATA };

// Landmark positions are used to align two maps
pub const Landmark = struct {
    pos: math.Vec3 = math.Vec3.zero,
    angle: f32 = 0.0,
};

pub const PlayerStart = struct {
    pos: math.Vec3,
    angle: f32 = 0,

    pub fn mulMat4(self: *const PlayerStart, matrix: delve.math.Mat4) PlayerStart {
        return .{
            .pos = self.pos.mulMat4(matrix),
            .angle = self.angle,
        };
    }
};

pub const QuakeMapComponent = struct {
    // properties
    filename: string.String,
    transform: math.Mat4,
    transform_landmark_name: ?string.String = null,
    transform_landmark_angle: f32 = 0.0,
    check_for_space: bool = true, // when generating, should we check for space?

    time: f32 = 0.0,
    player_start: PlayerStart = .{ .pos = math.Vec3.zero },

    // persist if we have initialized or not
    did_init: bool = false,

    // the loaded map
    quake_map: delve.utils.quakemap.QuakeMap = undefined,
    // quake_map_arena_allocator: std.heap.ArenaAllocator = undefined,

    // quake maps load at a different scale and rotation - adjust for that
    map_transform: math.Mat4 = undefined,
    map_scale: math.Vec3 = math.Vec3.new(0.03, 0.03, 0.03), // Quake seems to be about 0.07, 0.07, 0.07 - ours is 0.1

    // meshes for drawing (using unmanaged lists)
    map_meshes: std.ArrayList(delve.graphics.mesh.Mesh) = undefined,
    entity_meshes: std.ArrayList(delve.graphics.mesh.Mesh) = undefined,

    // map lights
    lights: ArrayList(delve.platform.graphics.PointLight) = undefined,
    directional_light: delve.platform.graphics.DirectionalLight = .{ .color = delve.colors.black },

    // spatial hash!
    solid_spatial_hash: spatialhash.SpatialHash(delve.utils.quakemap.Solid) = undefined,

    // bvhtree!
    bvh_tree: bvhtree.BVHTree = undefined,

    // interface
    owner: entities.Entity = entities.InvalidEntity,
    owner_id: entities.EntityId = undefined,

    // calculated
    quake_map_idx: usize = 0,
    _file_buffer: ?[]const u8 = null,
    angle_offset: f32 = 0.0,
    bounds: delve.spatial.BoundingBox = undefined,
    is_valid: bool = true,

    pub fn default() @This() {
        return .{ .filename = string.String.init("maps/default.map"), .transform = math.Mat4.identity };
    }

    pub fn init(self: *QuakeMapComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;
        defer self.did_init = true;

        if (!self.did_init) {
            delve.debug.log("Saved owner id {d}", .{self.owner.id.id});
            self.owner_id = self.owner.id;
        }

        const allocator = delve.mem.getAllocator();
        self.solid_spatial_hash = spatialhash.SpatialHash(delve.utils.quakemap.Solid).init(6.0, allocator);
        self.bvh_tree = bvhtree.BVHTree.init(allocator);
        self.lights = ArrayList(delve.platform.graphics.PointLight).init(allocator);

        const is_generated_map = !std.mem.endsWith(u8, self.filename.get(), ".map");
        const orig_transform = self.transform;
        const orig_angle = self.angle_offset;

        var orig_path = string.init(self.filename.get());
        defer orig_path.deinit();

        if (!is_generated_map) {
            self.loadMap() catch {
                delve.debug.log("Could not initialize quake map component!", .{});
            };
            self.initMap() catch {
                delve.debug.err("Could not initialize quake map component!", .{});
            };
            return;
        }

        if (is_generated_map) {
            var is_valid = false;
            var gen_count: usize = 0;

            while (!is_valid and gen_count < 20) {
                defer gen_count += 1;
                self.transform = orig_transform;
                self.angle_offset = orig_angle;

                // pick a random level each time
                self.filename.set(orig_path.get());
                self.pickRandomLevel() catch {
                    delve.debug.log("Could not find random level!", .{});
                };

                self.loadMap() catch {
                    delve.debug.log("Could not initialize quake map component!", .{});
                };

                is_valid = true;

                // Done here unless we need to check for overlaps
                if (!self.check_for_space)
                    continue;

                // give ourselves a little room when checking for space
                const bounds = self.bounds.inflate(-1);

                // check if we overlap any other maps!
                var map_it = getComponentStorage(self.owner.getOwningWorld().?).iterator();

                while (map_it.next()) |map| {
                    if (map == self)
                        continue;

                    if (bounds.intersects(map.bounds)) {
                        delve.debug.warning("Generated map overlaps another map! Retrying...", .{});
                        is_valid = false;

                        // const size = map.bounds.max.sub(map.bounds.min);
                        // main.render_instance.drawDebugWireframeCube(map.bounds.center, delve.math.Vec3.zero, size, delve.math.Vec3.y_axis, delve.colors.red);
                        // const size_two = bounds.max.sub(bounds.min);
                        // main.render_instance.drawDebugWireframeCube(bounds.center, delve.math.Vec3.zero, size_two, delve.math.Vec3.y_axis, delve.colors.red);

                        break;
                    }
                }
            }

            // TODO: if we did not get a valid map, try again somehow!
            if (!is_valid) {
                delve.debug.err("Could not create map!", .{});
                self.is_valid = false;
            }

            self.initMap() catch {
                delve.debug.err("Could not initialize quake map component!", .{});
            };
        }

        // if (loaded_quake_maps == null) {
        //     loaded_quake_maps = ArrayList(*QuakeMapComponent).init(delve.mem.getAllocator());
        // }

        // loaded_quake_maps.?.append(self) catch {
        //     delve.debug.log("Could not cache quake map component!", .{});
        // };
    }

    pub fn getTextureAnimFrames(self: *QuakeMapComponent, texture_name: []const u8) !ArrayList(textures.LoadedTexture) {
        _ = self;
        var anim_textures = ArrayList(textures.LoadedTexture).init(delve.mem.getAllocator());
        var idx: usize = 0;

        // default to one frame
        var max: usize = 1;

        // If we are an animation ,load more!
        if (std.mem.endsWith(u8, texture_name, "00")) {
            max = 100;
        }

        const tex_without_frame = texture_name[0 .. texture_name.len - 2];
        while (idx < max) {
            defer idx += 1;

            var tex_path = ArrayList(u8).init(delve.mem.getAllocator());
            if (idx == 0) {
                try tex_path.print("assets/textures/{s}.png", .{texture_name});
            } else if (idx <= 9) {
                try tex_path.print("assets/textures/{s}0{d}.png", .{ tex_without_frame, idx });
            } else {
                try tex_path.print("assets/textures/{s}{d}.png", .{ tex_without_frame, idx });
            }

            defer tex_path.deinit();

            // fixup Quake water materials
            std.mem.replaceScalar(u8, tex_path.items, '*', '#');

            const loaded_tex = textures.getOrLoadTexture(tex_path.items);

            // warn if the base texture was missing!
            if (!loaded_tex.found and idx == 0)
                delve.debug.warning("Could not load image: {s}", .{tex_path.items});

            if (loaded_tex.found or idx == 0)
                try anim_textures.append(loaded_tex);

            if (!loaded_tex.found)
                break;
        }

        delve.debug.log("Loaded {d} frames of textures for {s}", .{ anim_textures.items.len, texture_name });
        return anim_textures;
    }

    pub fn pickRandomLevel(self: *QuakeMapComponent) !void {
        const now = std.Io.Timestamp.now(delve.io.getIo(), .real);
        var rand = std.Random.DefaultPrng.init(@bitCast(now.toMilliseconds()));
        var random = rand.random();

        var found_paths = ArrayList([]const u8).init(delve.mem.getAllocator());
        defer found_paths.deinit();

        // could be given more than one path, eg: "assets/levels/halls,assets/levels/rooms"
        var path_it = std.mem.splitScalar(u8, self.filename.get(), ',');
        while (path_it.next()) |path| {
            try found_paths.append(path);
        }

        const picked_path_index = random.intRangeAtMost(usize, 0, found_paths.items.len - 1);
        const picked_path = found_paths.items[picked_path_index];

        // Read through the filename to check if it's a directory, then list files
        const io = delve.io.getIo();
        var dir = try std.Io.Dir.cwd().openDir(io, picked_path, .{ .iterate = true });
        defer dir.close(io);

        var found_maps = ArrayList([]const u8).init(delve.mem.getAllocator());
        defer found_maps.deinit();

        var it = dir.iterate();
        while (try it.next(io)) |entry| {
            if (entry.kind == .file) {
                if (!std.mem.endsWith(u8, entry.name, ".map"))
                    continue;

                try found_maps.append(entry.name);
            }
        }

        if (found_maps.items.len == 0)
            return;

        const picked_index = random.intRangeAtMost(usize, 0, found_maps.items.len - 1);
        const picked_file = found_maps.items[picked_index];
        delve.debug.log("Picked random map file: {s}", .{picked_file});

        var new_path = ArrayList(u8).init(delve.mem.getAllocator());
        defer new_path.deinit();

        try new_path.print("{s}/{s}", .{ picked_path, picked_file });
        self.filename.set(new_path.items);
    }

    pub fn loadMap(self: *QuakeMapComponent) !void {
        const allocator = delve.mem.getAllocator();

        // free the last map, if one was already loaded
        if (self._file_buffer != null) {
            delve.mem.getAllocator().free(self._file_buffer.?);
            self.quake_map.deinit();
        }

        // translate, scale and rotate the map
        self.map_transform = self.transform.mul(delve.math.Mat4.scale(self.map_scale).mul(delve.math.Mat4.rotate(-90, delve.math.Vec3.x_axis)));

        // Read quake map contents
        delve.debug.log("Initializing QuakeMapComponent: filename '{s}'", .{self.filename.get()});
        const buffer_size = 8024000;
        const file_buffer = try std.Io.Dir.cwd().readFileAlloc(delve.io.getIo(), self.filename.get(), allocator, .limited(buffer_size));
        self._file_buffer = file_buffer;
        // defer allocator.free(file_buffer);

        var err: delve.utils.quakemap.ErrorInfo = undefined;

        // pick the transform to use when loading
        const load_transform = if (self.transform_landmark_name == null) self.map_transform else math.Mat4.identity;

        self.quake_map = delve.utils.quakemap.QuakeMap.read(allocator, file_buffer, load_transform, &err) catch {
            delve.debug.log("Error reading quake map: {}", .{err});
            return;
        };

        // find our landmark offset, if one was asked for
        if (self.transform_landmark_name) |landmark_str| {
            const landmark = getLandmark(&self.quake_map, landmark_str.get());
            const landmark_offset_transformed = landmark.pos.mulMat4(self.map_transform);
            const transformed_origin = delve.math.Vec3.zero.mulMat4(self.map_transform);
            const rotate_angle = self.transform_landmark_angle - landmark.angle;

            const map_translate_amount = transformed_origin.sub(landmark_offset_transformed);

            // update our map transforms by applying our rotation and offset
            self.transform = self.transform.mul(delve.math.Mat4.rotate(rotate_angle, delve.math.Vec3.new(0, 1, 0)));
            self.transform = self.transform.mul(delve.math.Mat4.translate(map_translate_amount));
            self.map_transform = self.transform.mul(delve.math.Mat4.scale(self.map_scale).mul(delve.math.Mat4.rotate(-90, delve.math.Vec3.x_axis)));
            self.angle_offset = rotate_angle;

            // can now apply the final transform to the map
            self.quake_map.applyTransform(self.map_transform);
        }

        // calculate our bounds now!
        self.bounds = getBoundsForMap(&self.quake_map);
    }

    pub fn initMap(self: *QuakeMapComponent) !void {
        const allocator = delve.mem.getAllocator();
        const black_tex = delve.platform.graphics.createSolidTexture(0x00000000);

        // init the materials list for quake maps to use, if not already
        if (!did_init_materials) {
            materials = std.StringHashMap(delve.utils.quakemap.QuakeMaterial).init(allocator);
            material_animations = ArrayList(MaterialAnimation).init(allocator);
            world_shader = try graphics.Shader.initFromBuiltin(.{ .vertex_attributes = delve.graphics.mesh.getShaderAttributes() }, lit_shader);

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

            const invisible_tex = graphics.createSolidTexture(0x00000000);
            clip_texture = invisible_tex;

            did_init_materials = true;
        }

        // set our player starting position
        self.player_start = getPlayerStartPosition(&self.quake_map).mulMat4(self.map_transform);
        self.player_start.angle += self.angle_offset;

        // also add the solids to the spatial hash!
        for (self.quake_map.worldspawn.solids.items) |*solid| {
            // first, mark specials (water, skip, clip)
            for (solid.faces.items) |*face| {
                if (std.mem.eql(u8, face.texture_name, "tech_17") or std.mem.startsWith(u8, face.texture_name, "*") or std.mem.startsWith(u8, face.texture_name, "#")) {
                    solid.custom_flags = 1; // use 1 for water!
                } else if (std.mem.startsWith(u8, face.texture_name, "CLIP") or std.mem.startsWith(u8, face.texture_name, "skip")) {
                    if (solid.custom_flags != 1)
                        solid.custom_flags = 2; // use 2 for clip!
                }
            }

            self.solid_spatial_hash.addEntry(solid, getBoundsForSolid(solid), false) catch {
                delve.debug.log("Could not add face to spatial hash!", .{});
            };

            self.bvh_tree.insert(solid) catch {
                delve.debug.log("Could not add solid to bvh tree!", .{});
            };
        }

        // collect all of the solids from the world and entities
        var all_solids = ArrayList(delve.utils.quakemap.Solid).init(allocator);
        defer all_solids.deinit();

        try all_solids.appendSlice(self.quake_map.worldspawn.solids.items);
        for (self.quake_map.entities.items) |e| {
            try all_solids.appendSlice(e.solids.items);
        }

        // make materials out of all the required textures we found
        for (all_solids.items) |*solid| {
            for (solid.faces.items) |*face| {
                // we'll use this as the material key, so don't throw it away
                var mat_name = ArrayList(u8).init(allocator);
                try mat_name.print("{s}", .{face.texture_name});

                // make the clip or skip faces invisible
                var is_invisible: bool = false;
                if (std.mem.startsWith(u8, face.texture_name, "clip") or std.mem.startsWith(u8, face.texture_name, "skip")) {
                    is_invisible = true;
                }

                const found = materials.get(mat_name.items);
                if (found == null) {
                    const anim_textures = try self.getTextureAnimFrames(face.texture_name);
                    const loaded_tex = anim_textures.items[0];

                    var mat = try graphics.Material.init(.{
                        .shader = world_shader,
                        .samplers = &[_]graphics.FilterMode{.NEAREST},
                        .texture_0 = loaded_tex.texture,
                        .texture_1 = black_tex,
                        .default_fs_uniform_layout = basic_lighting_fs_uniforms,
                        .cull_mode = if (solid.custom_flags != 1) .BACK else .NONE,
                    });

                    // water should pan a bit
                    if (solid.custom_flags != 1) {
                        mat.state.params.texture_pan.y = 10.0;
                    }

                    try materials.put(try mat_name.toOwnedSlice(), .{
                        .material = mat,
                        .tex_size_x = @intCast(loaded_tex.texture.width),
                        .tex_size_y = @intCast(loaded_tex.texture.height),
                        .hidden = is_invisible,
                    });

                    try material_animations.append(.{
                        .textures = anim_textures,
                        .material = mat,
                    });
                } else {
                    // did not add a material, have to clean up our name
                    mat_name.deinit();
                }
            }
        }

        // make meshes out of the quake map, batched by material
        self.map_meshes = try self.quake_map.buildWorldMeshes(allocator, math.Mat4.identity, &materials, &fallback_quake_material);
        self.entity_meshes = try self.quake_map.buildEntityMeshes(allocator, math.Mat4.identity, &materials, &fallback_quake_material);

        // if not a valid map, don't spawn entities!
        if (!self.is_valid)
            return;

        // find all the lights!
        for (self.quake_map.entities.items) |entity| {
            if (std.mem.eql(u8, entity.classname, "light_directional")) {
                const light_pos = entity.getVec3Property("origin").?;
                _ = light_pos;
                var light_radius: f32 = 10.0;
                var light_color: delve.colors.Color = delve.colors.white;
                var pitch: f32 = 45.0;
                var yaw: f32 = 25.0;

                // quake light properties!
                if (entity.getFloatProperty("light")) |value| {
                    light_radius = value * 0.125;
                }

                // our light properties!
                if (entity.getFloatProperty("radius")) |value| {
                    light_radius = value;
                }

                if (entity.getFloatProperty("pitch")) |value| {
                    pitch = value;
                }

                if (entity.getFloatProperty("yaw")) |value| {
                    yaw = value;
                }

                if (entity.getVec3Property("_color")) |value| {
                    light_color.r = value.x / 255.0;
                    light_color.g = value.y / 255.0;
                    light_color.b = value.z / 255.0;
                }

                const light_dir = delve.math.Vec3.x_axis.rotate(pitch, math.Vec3.z_axis).rotate(yaw, math.Vec3.y_axis).norm();
                self.directional_light = .{ .color = light_color, .brightness = 1.0, .dir = light_dir };
            }
        }

        // Don't spawn entities twice!
        if (self.did_init)
            return;

        const world_opt = entities.getWorld(self.owner.getWorldId());
        if (world_opt == null)
            return;

        // spawn entities!
        var entity_idx: usize = 0;
        for (self.quake_map.entities.items) |*entity| {
            defer entity_idx += 1;

            // Let lua scripts handle the actual entity spawning logic
            try scripting.callLuaFunction("QuakemapSpawnEntity", .{ entity, self, entity_idx });
        }
    }

    pub fn getWorldSolids(self: *QuakeMapComponent) []delve.utils.quakemap.Solid {
        return self.quake_map.worldspawn.solids.items;
    }

    pub fn deinit(self: *QuakeMapComponent) void {
        const allocator = delve.mem.getAllocator();

        defer self.quake_map.deinit();

        for (self.entity_meshes.items) |*em| {
            em.deinit();
        }
        self.entity_meshes.deinit(allocator);

        for (self.map_meshes.items) |*wm| {
            wm.deinit();
        }
        self.map_meshes.deinit(allocator);

        self.solid_spatial_hash.deinit();
        self.bvh_tree.deinit();

        self.filename.deinit();
        if (self.transform_landmark_name != null) self.transform_landmark_name.?.deinit();

        if (self._file_buffer != null)
            delve.mem.getAllocator().free(self._file_buffer.?);
    }

    pub fn tick(self: *QuakeMapComponent, delta: f32) void {
        self.time += delta;

        // const box = getBoundsForMap(&self.quake_map);
        // const size = box.max.sub(box.min);
        // main.render_instance.drawDebugWireframeCube(box.center, delve.math.Vec3.zero, size, delve.math.Vec3.y_axis, delve.colors.cyan);

        if (!self.is_valid)
            self.owner.deinit();
    }

    // Custom component serializer
    pub fn jsonStringify(self: *const QuakeMapComponent, out: anytype) !void {
        try out.objectField("filename");
        try out.write(self.filename.get());

        try out.objectField("transform");
        try out.write(self.transform);

        try out.objectField("time");
        try out.write(self.time);

        try out.objectField("did_init");
        try out.write(self.did_init);

        try out.objectField("owner_id");
        try out.write(self.owner_id);
    }

    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !QuakeMapComponent {
        const start_token = try source.next();
        if (.object_begin != start_token) return error.UnexpectedToken;

        _ = try source.next();
        const filename = try std.json.innerParse([]const u8, allocator, source, options);

        _ = try source.next();
        const transform = try std.json.innerParse(math.Mat4, allocator, source, options);

        _ = try source.next();
        const time = try std.json.innerParse(f32, allocator, source, options);

        _ = try source.next();
        const did_init = try std.json.innerParse(bool, allocator, source, options);

        _ = try source.next();
        const owner_id = try std.json.innerParse(entities.EntityId, allocator, source, options);

        const end_token = try source.next();
        if (.object_end != end_token) return error.UnexpectedToken;

        delve.debug.log("JsonParsed quake map with filename: '{s}'", .{filename});
        return .{ .filename = string.init(filename), .transform = transform, .time = time, .did_init = did_init, .owner_id = owner_id };
    }

    // pub fn getPlayerStartPos(self: *QuakeMapComponent) math.Vec3 {
    //     return self.player_start.pos;
    // }
    // pub fn getPlayerStartAngle(self: *QuakeMapComponent) f32 {
    //     return self.player_start.angle;
    // }
};

pub fn deinit() void {
    delve.debug.log("Freeing quake map component materials", .{});
    if (did_init_materials) {
        const allocator = delve.mem.getAllocator();

        var it = materials.iterator();
        while (it.next()) |mat| {
            mat.value_ptr.material.deinit();
            allocator.free(mat.key_ptr.*);
        }
        materials.deinit();

        for (material_animations.items) |anim| {
            anim.textures.deinit();
        }
        material_animations.deinit();

        fallback_material.deinit();
        clip_texture.destroy();
        did_init_materials = false;

        world_shader.destroy();
    }
}

/// Returns the player start position from the map
pub fn getPlayerStartPosition(map: *delve.utils.quakemap.QuakeMap) PlayerStart {
    for (map.entities.items) |entity| {
        if (std.mem.eql(u8, entity.classname, "info_player_start")) {
            const offset: math.Vec3 = entity.getVec3Property("origin") orelse math.Vec3.zero;
            const angle: f32 = entity.getFloatProperty("angle") orelse 0;
            return .{ .pos = offset, .angle = angle };
        }
    }

    return .{ .pos = math.Vec3.new(0, 0, 0) };
}

pub fn getLandmark(map: *delve.utils.quakemap.QuakeMap, landmark_name: []const u8) Landmark {
    var fallback_landmark = Landmark{};

    for (map.entities.items) |entity| {
        if (std.mem.eql(u8, entity.classname, "info_landmark")) {
            var offset = math.Vec3.zero;

            if (entity.getVec3Property("origin")) |v| {
                offset = v;
            } else {
                delve.debug.log("Could not read player start offset property!", .{});
                continue;
            }

            var angle: f32 = 0;
            if (entity.getFloatProperty("angle")) |v| {
                angle = v;
            }

            // stick to 0-360
            angle = @mod(angle, 360.0);

            const landmark = Landmark{ .pos = offset, .angle = angle };

            var entity_name: []const u8 = undefined;
            if (entity.getStringProperty("targetname")) |v| {
                entity_name = v;
            } else {
                // no name, but could maybe use it as a fallback
                delve.debug.log("Found fallback landmark offset", .{});
                fallback_landmark = landmark;
                continue;
            }

            if (std.mem.eql(u8, landmark_name, entity_name)) {
                delve.debug.log("Found landmark '{s}", .{landmark_name});
                return landmark;
            }
        }
    }

    return fallback_landmark;
}

pub fn getBoundsForMap(map: *delve.utils.quakemap.QuakeMap) spatial.BoundingBox {
    var set_min_max = true;
    var min: math.Vec3 = undefined;
    var max: math.Vec3 = undefined;

    for (map.worldspawn.solids.items) |*solid| {
        const solid_bounds = getBoundsForSolid(solid);

        if (set_min_max) {
            defer set_min_max = false;
            min = solid_bounds.min;
            max = solid_bounds.max;
        }

        min = math.Vec3.min(min, solid_bounds.min);
        max = math.Vec3.max(max, solid_bounds.max);
    }

    return spatial.BoundingBox{
        .center = math.Vec3.new(min.x + (max.x - min.x) * 0.5, min.y + (max.y - min.y) * 0.5, min.z + (max.z - min.z) * 0.5),
        .min = min,
        .max = max,
    };
}

pub fn getBoundsForSolid(solid: *delve.utils.quakemap.Solid) spatial.BoundingBox {
    if (solid.faces.items.len == 0)
        return spatial.BoundingBox{ .center = math.Vec3.zero, .min = math.Vec3.zero, .max = math.Vec3.zero };

    var min = solid.faces.items[0].vertices[0];
    var max = min;

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

// pub fn callLuaSpawnFunction() !void {
//     const registry = scripting.registry;
//     const lua = delve.scripting.lua.getLua();
//
//     // Get the function to call, and push it onto the stack
//     _ = try lua.getGlobal("QuakemapSpawnEntity");
//
//     if (!lua.isFunction(-1)) {
//         delve.debug.log("{s} is not a function in Lua!", .{"QuakemapSpawnEntity"});
//         return;
//     }
//
//     var num_args: usize = 0;
//
//     // Push this value onto the stack
//     registry.toAny(f);
//
//     num_args = num_args + 1;
//
//     // Call the function!
//     lua.protectedCall(.{ .args = num_args });
// }

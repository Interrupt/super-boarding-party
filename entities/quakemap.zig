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
pub const mover = @import("mover.zig");

const math = delve.math;
const spatial = delve.spatial;
const graphics = delve.platform.graphics;

// Cache of all loaded QuakeMapComponents
// pub var loaded_quake_maps: ?std.ArrayList(*QuakeMapComponent) = null;

pub const MaterialAnimation = struct {
    material: delve.platform.graphics.Material,
    textures: std.ArrayList(textures.LoadedTexture),
};

// materials!
pub var did_init_materials: bool = false;
pub var fallback_material: graphics.Material = undefined;
pub var clip_texture: graphics.Texture = undefined;
pub var fallback_quake_material: delve.utils.quakemap.QuakeMaterial = undefined;
pub var materials: std.StringHashMap(delve.utils.quakemap.QuakeMaterial) = undefined;
pub var material_animations: std.ArrayList(MaterialAnimation) = undefined;
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

    // meshes for drawing
    map_meshes: std.ArrayList(delve.graphics.mesh.Mesh) = undefined,
    entity_meshes: std.ArrayList(delve.graphics.mesh.Mesh) = undefined,

    // map lights
    lights: std.ArrayList(delve.platform.graphics.PointLight) = undefined,
    directional_light: delve.platform.graphics.DirectionalLight = .{ .color = delve.colors.black },

    // spatial hash!
    solid_spatial_hash: spatialhash.SpatialHash(delve.utils.quakemap.Solid) = undefined,

    // interface
    owner: entities.Entity = entities.InvalidEntity,
    owner_id: entities.EntityId = undefined,

    // calculated
    quake_map_idx: usize = 0,
    _file_buffer: ?[]const u8 = null,

    pub fn init(self: *QuakeMapComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;

        if (!self.did_init) {
            delve.debug.log("Saved owner id {d}", .{self.owner.id.id});
            self.owner_id = self.owner.id;
        }

        self.init_world() catch {
            delve.debug.log("Could not init quake map component!", .{});
        };

        self.did_init = true;

        // if (loaded_quake_maps == null) {
        //     loaded_quake_maps = std.ArrayList(*QuakeMapComponent).init(delve.mem.getAllocator());
        // }

        // loaded_quake_maps.?.append(self) catch {
        //     delve.debug.log("Could not cache quake map component!", .{});
        // };
    }

    pub fn getTextureAnimFrames(self: *QuakeMapComponent, texture_name: []const u8) !std.ArrayList(textures.LoadedTexture) {
        _ = self;
        var anim_textures = std.ArrayList(textures.LoadedTexture).init(delve.mem.getAllocator());
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

            var tex_path = std.ArrayList(u8).init(delve.mem.getAllocator());
            if (idx == 0) {
                try tex_path.writer().print("assets/textures/{s}.png", .{texture_name});
            } else if (idx <= 9) {
                try tex_path.writer().print("assets/textures/{s}0{d}.png", .{ tex_without_frame, idx });
            } else {
                try tex_path.writer().print("assets/textures/{s}{d}.png", .{ tex_without_frame, idx });
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

    pub fn init_world(self: *QuakeMapComponent) !void {
        const allocator = delve.mem.getAllocator();

        self.solid_spatial_hash = spatialhash.SpatialHash(delve.utils.quakemap.Solid).init(6.0, allocator);

        self.lights = std.ArrayList(delve.platform.graphics.PointLight).init(allocator);

        const black_tex = delve.platform.graphics.createSolidTexture(0x00000000);

        // translate, scale and rotate the map
        self.map_transform = self.transform.mul(delve.math.Mat4.scale(self.map_scale).mul(delve.math.Mat4.rotate(-90, delve.math.Vec3.x_axis)));

        // Read quake map contents
        delve.debug.log("Initializing QuakeMapComponent: filename '{s}'", .{self.filename.str});
        const file = try std.fs.cwd().openFile(self.filename.str, .{});
        defer file.close();

        const buffer_size = 8024000;
        const file_buffer = try file.readToEndAlloc(allocator, buffer_size);
        self._file_buffer = file_buffer;
        // defer allocator.free(file_buffer);

        var err: delve.utils.quakemap.ErrorInfo = undefined;

        // find our landmark offset, if one was asked for
        if (self.transform_landmark_name) |landmark_str| {
            // read the map to try to get the landmark position
            // TODO: update quake map utils to have a version that just reads entities!
            var quake_map_landmark = delve.utils.quakemap.QuakeMap.read(allocator, file_buffer, self.map_transform, &err) catch {
                delve.debug.log("Error reading quake map: {}", .{err});
                return;
            };
            defer quake_map_landmark.deinit();

            const landmark = getLandmark(&quake_map_landmark, landmark_str.str);
            const landmark_offset_transformed = landmark.pos.mulMat4(self.map_transform);
            const transformed_origin = delve.math.Vec3.zero.mulMat4(self.map_transform);
            const rotate_angle = self.transform_landmark_angle - landmark.angle;

            const map_translate_amount = transformed_origin.sub(landmark_offset_transformed);

            // update our map transforms by applying our rotation and offset
            self.transform = self.transform.mul(delve.math.Mat4.rotate(rotate_angle, delve.math.Vec3.new(0, 1, 0)));
            self.transform = self.transform.mul(delve.math.Mat4.translate(map_translate_amount));
            self.map_transform = self.transform.mul(delve.math.Mat4.scale(self.map_scale).mul(delve.math.Mat4.rotate(-90, delve.math.Vec3.x_axis)));
        }

        self.quake_map = delve.utils.quakemap.QuakeMap.read(allocator, file_buffer, self.map_transform, &err) catch {
            delve.debug.log("Error reading quake map: {}", .{err});
            return;
        };

        // init the materials list for quake maps to use, if not already
        if (!did_init_materials) {
            materials = std.StringHashMap(delve.utils.quakemap.QuakeMaterial).init(allocator);
            material_animations = std.ArrayList(MaterialAnimation).init(allocator);
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
            for (solid.faces.items) |*face| {
                // we'll use this as the material key, so don't throw it away
                var mat_name = std.ArrayList(u8).init(allocator);
                try mat_name.writer().print("{s}", .{face.texture_name});

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
                        .texture_0 = if (!is_invisible) loaded_tex.texture else clip_texture,
                        .texture_1 = black_tex,
                        .default_fs_uniform_layout = basic_lighting_fs_uniforms,
                        .cull_mode = if (solid.custom_flags != 1) .BACK else .NONE,
                    });

                    if (solid.custom_flags != 1) {
                        mat.state.params.texture_pan.y = 10.0;
                    }

                    try materials.put(try mat_name.toOwnedSlice(), .{
                        .material = mat,
                        .tex_size_x = @intCast(loaded_tex.texture.width),
                        .tex_size_y = @intCast(loaded_tex.texture.height),
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

        // find all the lights!
        for (self.quake_map.entities.items) |entity| {
            if (std.mem.eql(u8, entity.classname, "light_directional")) {
                const light_pos = try entity.getVec3Property("origin");
                _ = light_pos;
                var light_radius: f32 = 10.0;
                var light_color: delve.colors.Color = delve.colors.white;
                var pitch: f32 = 45.0;
                var yaw: f32 = 25.0;

                // quake light properties!
                if (entity.getFloatProperty("light")) |value| {
                    light_radius = value * 0.125;
                } else |_| {}

                // our light properties!
                if (entity.getFloatProperty("radius")) |value| {
                    light_radius = value;
                } else |_| {}

                if (entity.getFloatProperty("pitch")) |value| {
                    pitch = value;
                } else |_| {}

                if (entity.getFloatProperty("yaw")) |value| {
                    yaw = value;
                } else |_| {}

                if (entity.getVec3Property("_color")) |value| {
                    light_color.r = value.x / 255.0;
                    light_color.g = value.y / 255.0;
                    light_color.b = value.z / 255.0;
                } else |_| {}

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

            var entity_name: ?[]const u8 = null;
            if (entity.getStringProperty("targetname")) |v| {
                entity_name = v;
            } else |_| {}

            var target_name: ?[]const u8 = null;
            if (entity.getStringProperty("target")) |v| {
                target_name = v;
            } else |_| {}

            var path_target_name: ?[]const u8 = null;
            if (entity.getStringProperty("pathtarget")) |v| {
                path_target_name = v;
            } else |_| {}

            var killtarget_name: ?[]const u8 = null;
            if (entity.getStringProperty("killtarget")) |v| {
                killtarget_name = v;
            } else |_| {}

            var entity_origin: math.Vec3 = math.Vec3.zero;
            if (entity.getVec3Property("origin")) |v| {
                entity_origin = v.mulMat4(self.map_transform);
            } else |_| {}

            if (std.mem.startsWith(u8, entity.classname, "monster_")) {
                var hostile: bool = true;
                var spawns: bool = true;

                if (entity.getStringProperty("hostile")) |v| {
                    hostile = std.mem.eql(u8, v, "true");
                } else |_| {}

                // Not in easy
                if ((entity.spawnflags & 0b100000000) == 256) {
                    spawns = false;
                }
                // Not in Normal
                if ((entity.spawnflags & 0b1000000000) == 512) {
                    spawns = false;
                }

                if (spawns) {
                    var m = try world_opt.?.createEntity(.{});
                    if (entity_name) |name| {
                        _ = try m.createNewComponent(basics.NameComponent, .{ .name = string.init(name) });
                    }
                    _ = try m.createNewComponent(basics.TransformComponent, .{ .position = entity_origin });
                    _ = try m.createNewComponent(character.CharacterMovementComponent, .{ .max_slide_bumps = 2 });
                    _ = try m.createNewComponent(box_collision.BoxCollisionComponent, .{ .size = delve.math.Vec3.new(1.5, 2.5, 1.5), .can_step_up_on = false });
                    _ = try m.createNewComponent(monster.MonsterController, .{ .hostile = hostile });
                    _ = try m.createNewComponent(actor_stats.ActorStats, .{ .max_hp = 5 });
                    _ = try m.createNewComponent(sprites.SpriteComponent, .{ .position = delve.math.Vec3.new(0, 0.25, 0.0), .billboard_type = .XZ, .scale = 3.0 });
                }
            }
            if (std.mem.startsWith(u8, entity.classname, "light")) {
                var light_radius: f32 = 10.0;
                var light_color: delve.colors.Color = delve.colors.white;
                var light_style: usize = 0;
                var is_on: bool = true;
                var brightness: f32 = 1.0;

                const is_light_flourospark = std.mem.eql(u8, entity.classname, "light_fluorospark");
                const is_light_flouro = std.mem.eql(u8, entity.classname, "light_fluoro");
                if (is_light_flourospark) {
                    light_style = 10;
                }

                // quake light properties!
                if (entity.getFloatProperty("light")) |value| {
                    light_radius = value * 0.125;
                } else |_| {}

                // our light properties!
                if (entity.getFloatProperty("radius")) |value| {
                    light_radius = value;
                } else |_| {}

                if (entity.getFloatProperty("brightness")) |value| {
                    brightness = value;
                } else |_| {}

                if (entity.getVec3Property("_color")) |value| {
                    light_color.r = value.x / 255.0;
                    light_color.g = value.y / 255.0;
                    light_color.b = value.z / 255.0;
                } else |_| {}

                if (entity.getFloatProperty("style")) |value| {
                    light_style = @intFromFloat(value);
                } else |_| {}

                if ((entity.spawnflags & 0b00000001) == 1) {
                    // 1 = initially dark
                    is_on = false;
                }

                var m = try world_opt.?.createEntity(.{});
                _ = try m.createNewComponent(basics.TransformComponent, .{ .position = entity_origin });
                _ = try m.createNewComponent(lights.LightComponent, .{
                    .position = math.Vec3.zero,
                    .color = light_color,
                    .brightness = brightness,
                    .radius = light_radius,
                    .style = @enumFromInt(light_style),
                    .is_on = is_on,
                });
                if (entity_name) |name| {
                    _ = try m.createNewComponent(basics.NameComponent, .{ .name = string.init(name) });
                }
                if (is_light_flourospark) {
                    // light sparks!
                    _ = try m.createNewComponent(emitter.ParticleEmitterComponent, .{
                        .emitter_type = .CONTINUOUS,
                        .num = 3,
                        .num_variance = 10,
                        .spritesheet = string.init("sprites/blank"),
                        .lifetime = 0.5,
                        .lifetime_variance = 1.0,
                        .velocity = math.Vec3.y_axis.scale(-0.5),
                        .velocity_variance = math.Vec3.one.scale(15.0),
                        .gravity = -75,
                        .color = delve.colors.orange,
                        .scale = 0.3125, // 1 / 32
                        .end_color = delve.colors.tan,
                        .delete_owner_when_done = false,
                        .spawn_interval_variance = 5.0,
                    });
                    _ = try m.createNewComponent(audio.AudioComponent, .{
                        .sound_path = string.init("assets/audio/sfx/sparks.mp3"),
                        .volume = 1.5,
                    });
                }
                if (is_light_flouro) {
                    _ = try m.createNewComponent(audio.AudioComponent, .{
                        .sound_path = string.init("assets/audio/sfx/light-hum-2.mp3"),
                        .volume = 1.0,
                    });
                }
            }
            if (std.mem.eql(u8, entity.classname, "func_plat")) {
                var move_height: ?f32 = null;
                var move_speed: f32 = 100.0;
                var wait_time: f32 = 3.0;
                var move_dir: math.Vec3 = math.Vec3.y_axis;
                var lip_amount: f32 = 8.0;

                if (entity.getFloatProperty("height")) |v| {
                    move_height = v * self.map_scale.y;
                } else |_| {}

                if (entity.getFloatProperty("speed")) |v| {
                    move_speed = v;
                } else |_| {}

                if (entity.getFloatProperty("wait")) |v| {
                    wait_time = v;
                } else |_| {}

                if (entity.getVec3Property("direction")) |v| {
                    move_dir = v;
                } else |_| {}

                if (entity.getFloatProperty("lip")) |v| {
                    lip_amount = v;
                } else |_| {}

                // adjust move speed for our map scale
                move_speed = move_speed * self.map_scale.y;

                var m = try world_opt.?.createEntity(.{});
                _ = try m.createNewComponent(basics.TransformComponent, .{ .position = delve.math.Vec3.zero });
                const solid_comp = try m.createNewComponent(quakesolids.QuakeSolidsComponent, .{
                    .quake_map = self,
                    .quake_entity_idx = entity_idx,
                    .transform = self.map_transform,
                });

                // figure out our move direction normal
                const move_vec_norm = move_dir.norm();

                var move_amount = math.Vec3.zero;

                if (move_height) |height| {
                    move_amount = move_vec_norm.scale(height);
                } else {
                    // Use our lip amount instead
                    // Move amount will be our size, minus the lip amount
                    move_amount = solid_comp.bounds.max.sub(solid_comp.bounds.min).mul(move_vec_norm);
                    move_amount = move_amount.sub(move_vec_norm.mul(self.map_scale.scale(lip_amount)));
                }

                _ = try m.createNewComponent(mover.MoverComponent, .{
                    .start_type = .WAIT_FOR_BUMP,
                    .move_amount = move_amount,
                    .move_time = move_amount.len() / move_speed,
                    .return_time = move_amount.len() / move_speed,
                    .return_delay_time = wait_time,
                    .start_delay = 0.25,
                    .start_lowered = true,
                });
                _ = try m.createNewComponent(audio.AudioComponent, .{
                    .sound_path = string.init("assets/audio/sfx/mover.wav"),
                    .start_mode = .Wait,
                });
            }
            if (std.mem.eql(u8, entity.classname, "func_door") or std.mem.eql(u8, entity.classname, "func_door_secret")) {
                var move_speed: f32 = 50.0;
                var wait_time: f32 = 3.0;
                var move_angle: f32 = 0.0;
                var lip_amount: f32 = 4.0;
                var starts_open: bool = false;
                var returns: bool = true;
                var health: f32 = 0.0;
                var locked_message: []const u8 = "";

                if (entity.getFloatProperty("speed")) |v| {
                    move_speed = v;
                } else |_| {}

                if (entity.getFloatProperty("wait")) |v| {
                    wait_time = v;
                } else |_| {}

                if (entity.getFloatProperty("angle")) |v| {
                    move_angle = v;
                } else |_| {}

                if (entity.getFloatProperty("lip")) |v| {
                    lip_amount = v;
                } else |_| {}

                if (entity.getFloatProperty("health")) |v| {
                    health = v;
                } else |_| {}

                if (entity.getStringProperty("message")) |v| {
                    locked_message = v;
                } else |_| {}

                // check spawnflags
                const is_secret_door = std.mem.eql(u8, entity.classname, "func_door_secret");
                if (!is_secret_door and (entity.spawnflags & 0b00000001) == 1) {
                    // 1 = starts open
                    starts_open = true;
                }
                if (is_secret_door and (entity.spawnflags & 0b00000001) == 1) {
                    // 1 = opens once
                    returns = false;
                }

                // adjust move speed for our map scale
                move_speed = move_speed * self.map_scale.y;

                var m = try world_opt.?.createEntity(.{});
                _ = try m.createNewComponent(basics.TransformComponent, .{ .position = delve.math.Vec3.zero });
                const solid_comp = try m.createNewComponent(quakesolids.QuakeSolidsComponent, .{
                    .quake_map = self,
                    .quake_entity_idx = entity_idx,
                    .transform = self.map_transform,
                });

                if (entity_name) |name| {
                    _ = try m.createNewComponent(basics.NameComponent, .{ .name = string.init(name) });
                }

                // figure out our move direction normal
                var move_vec_norm = delve.math.Vec3.x_axis.rotate(move_angle, math.Vec3.y_axis).norm();
                if (move_angle == -1.0) {
                    move_vec_norm = delve.math.Vec3.y_axis;
                } else if (move_angle == -2.0) {
                    move_vec_norm = delve.math.Vec3.y_axis.scale(-1);
                }

                // our move amount is our size, minus the lip amount
                var move_amount = solid_comp.bounds.max.sub(solid_comp.bounds.min).mul(move_vec_norm);
                move_amount = move_amount.sub(move_vec_norm.mul(self.map_scale.scale(lip_amount)));

                const mvr = try m.createNewComponent(mover.MoverComponent, .{
                    .start_type = if (entity_name == null) .WAIT_FOR_BUMP else .WAIT_FOR_TRIGGER,
                    .move_amount = move_amount,
                    .move_time = move_amount.len() / move_speed,
                    .return_time = move_amount.len() / move_speed,
                    .returns = wait_time != -1 and returns,
                    .return_delay_time = wait_time,
                    .start_delay = 0.1,
                    .starts_overlapping_movers = true,
                    .start_moved = starts_open,
                    .message = string.init(locked_message),
                });

                // secret doors open by being shot, not bumped
                if (mvr.start_type == .WAIT_FOR_BUMP and (health > 0 or is_secret_door))
                    mvr.start_type = .WAIT_FOR_DAMAGE;

                _ = try m.createNewComponent(audio.AudioComponent, .{
                    .sound_path = string.init("assets/audio/sfx/mover.wav"),
                    .start_mode = .Wait,
                });
            }
            if (std.mem.eql(u8, entity.classname, "func_button")) {
                var move_angle: f32 = 0.0;
                var lip_amount: f32 = 4.0;
                var move_speed: f32 = 15.0;
                var message: []const u8 = "";
                var delay: f32 = 0.0;
                var wait: f32 = 0.15;

                if (entity.getFloatProperty("angle")) |v| {
                    move_angle = v;
                } else |_| {}

                if (entity.getFloatProperty("lip")) |v| {
                    lip_amount = v;
                } else |_| {}

                if (entity.getFloatProperty("speed")) |v| {
                    move_speed = v;
                } else |_| {}

                if (entity.getStringProperty("message")) |v| {
                    message = v;
                } else |_| {}

                if (entity.getFloatProperty("wait")) |v| {
                    wait = v;
                } else |_| {}

                if (entity.getFloatProperty("delay")) |v| {
                    delay = v;
                } else |_| {}

                // adjust move speed for our map scale
                move_speed = move_speed * self.map_scale.y;

                var m = try world_opt.?.createEntity(.{});
                _ = try m.createNewComponent(basics.TransformComponent, .{ .position = delve.math.Vec3.zero });
                const solid_comp = try m.createNewComponent(quakesolids.QuakeSolidsComponent, .{
                    .quake_map = self,
                    .quake_entity_idx = entity_idx,
                    .transform = self.map_transform,
                });

                if (entity_name) |name| {
                    _ = try m.createNewComponent(basics.NameComponent, .{ .name = string.init(name) });
                }

                // figure out our move direction normal
                var move_vec_norm = delve.math.Vec3.x_axis.rotate(move_angle, math.Vec3.y_axis).norm();
                if (move_angle == -1.0) {
                    move_vec_norm = delve.math.Vec3.y_axis;
                } else if (move_angle == -2.0) {
                    move_vec_norm = delve.math.Vec3.y_axis.scale(-1);
                }

                // our move amount is our size, minus the lip amount
                var move_amount = solid_comp.bounds.max.sub(solid_comp.bounds.min).mul(move_vec_norm);
                move_amount = move_amount.sub(move_vec_norm.mul(self.map_scale.scale(lip_amount)));

                _ = try m.createNewComponent(mover.MoverComponent, .{
                    .start_type = .WAIT_FOR_BUMP,
                    .move_amount = move_amount,
                    .move_time = move_amount.len() / move_speed,
                    .return_time = move_amount.len() / move_speed,
                    .return_delay_time = wait,
                    .returns = wait != -1,
                    .start_delay = 0.0,
                    .play_end_sound = false,
                });

                if (path_target_name) |path_target| {
                    _ = try m.createNewComponent(triggers.TriggerComponent, .{
                        .target = if (target_name != null) string.init(target_name.?) else string.empty,
                        .value = string.init(path_target),
                        .killtarget = if (killtarget_name != null) string.init(killtarget_name.?) else string.empty,
                        .play_sound = true,
                        .message = string.init(message),
                        .delay = delay,
                    });
                } else {
                    _ = try m.createNewComponent(triggers.TriggerComponent, .{
                        .target = if (target_name != null) string.init(target_name.?) else string.empty,
                        .play_sound = true,
                        .killtarget = if (killtarget_name != null) string.init(killtarget_name.?) else string.empty,
                        .message = string.init(message),
                        .delay = delay,
                    });
                }
            }
            if (std.mem.eql(u8, entity.classname, "func_train")) {
                var move_speed: f32 = 100.0;
                var starts_moving: bool = false;
                var starts_bump: bool = false;

                if (entity.getFloatProperty("speed")) |v| {
                    move_speed = v;
                } else |_| {}

                if (entity.getStringProperty("starts_moving")) |v| {
                    starts_moving = std.mem.eql(u8, v, "true");
                } else |_| {}

                if (entity.getStringProperty("starts_bump")) |v| {
                    starts_bump = std.mem.eql(u8, v, "true");
                } else |_| {}

                // adjust move speed for our map scale
                move_speed = move_speed * self.map_scale.y;

                const move_amount = delve.math.Vec3.y_axis.scale(675.0).mul(self.map_scale);

                var m = try world_opt.?.createEntity(.{});
                _ = try m.createNewComponent(basics.TransformComponent, .{ .position = delve.math.Vec3.zero });
                _ = try m.createNewComponent(mover.MoverComponent, .{
                    .start_type = if (starts_moving) .IMMEDIATE else if (starts_bump) .WAIT_FOR_BUMP else .WAIT_FOR_TRIGGER,
                    .lookup_path_on_start = true,
                    .move_amount = move_amount,
                    .move_time = move_amount.len() / move_speed,
                    .move_speed = move_speed,
                    .return_speed = move_speed,
                    .returns = false,
                    .returns_on_squish = false,
                    .return_time = move_amount.len() / move_speed,
                    .return_delay_time = 3,
                    .start_delay = 0.0,
                    .start_at_target = if (target_name != null) string.init(target_name.?) else null,
                });
                _ = try m.createNewComponent(quakesolids.QuakeSolidsComponent, .{
                    .quake_map = self,
                    .quake_entity_idx = entity_idx,
                    .transform = self.map_transform,
                });

                if (entity_name) |name| {
                    _ = try m.createNewComponent(basics.NameComponent, .{ .name = string.init(name) });
                }
                if (target_name) |target| {
                    _ = try m.createNewComponent(triggers.TriggerComponent, .{ .target = string.init(target) });
                }
                _ = try m.createNewComponent(audio.AudioComponent, .{
                    .sound_path = string.init("assets/audio/sfx/mover.wav"),
                    .start_mode = .Wait,
                });
            }
            if (std.mem.eql(u8, entity.classname, "trigger_elevator") or std.mem.eql(u8, entity.classname, "trigger_relay")) {
                var message: []const u8 = "";
                var delay: f32 = 0.0;

                if (entity.getFloatProperty("delay")) |v| {
                    delay = v;
                } else |_| {}

                var m = try world_opt.?.createEntity(.{});
                _ = try m.createNewComponent(basics.TransformComponent, .{ .position = entity_origin });

                if (entity_name) |name| {
                    _ = try m.createNewComponent(basics.NameComponent, .{ .name = string.init(name) });
                }
                if (entity.getStringProperty("message")) |v| {
                    message = v;
                } else |_| {}

                _ = try m.createNewComponent(triggers.TriggerComponent, .{
                    .target = if (target_name != null) string.init(target_name.?) else string.empty,
                    .killtarget = if (killtarget_name != null) string.init(killtarget_name.?) else string.empty,
                    .message = string.init(message),
                    .delay = delay,
                });
            }
            if (std.mem.eql(u8, entity.classname, "path_corner")) {
                var message: []const u8 = "";

                if (entity.getStringProperty("message")) |v| {
                    message = v;
                } else |_| {}

                var m = try world_opt.?.createEntity(.{});
                _ = try m.createNewComponent(basics.TransformComponent, .{ .position = entity_origin });

                if (entity_name) |name| {
                    _ = try m.createNewComponent(basics.NameComponent, .{ .name = string.init(name) });
                }

                if (target_name) |target| {
                    var value: []const u8 = target;
                    if (path_target_name) |path_target| {
                        value = path_target;
                    }
                    _ = try m.createNewComponent(triggers.TriggerComponent, .{
                        .target = string.init(target),
                        .value = string.init(value),
                        .is_path_node = true,
                        .message = string.init(message),
                    });
                }
            }
            if (std.mem.eql(u8, entity.classname, "func_illusionary") or std.mem.eql(u8, entity.classname, "func_detail")) {
                var m = try world_opt.?.createEntity(.{});
                _ = try m.createNewComponent(basics.TransformComponent, .{ .position = delve.math.Vec3.zero });
                _ = try m.createNewComponent(quakesolids.QuakeSolidsComponent, .{
                    .quake_map = self,
                    .quake_entity_idx = entity_idx,
                    .transform = self.map_transform,
                    .collides_entities = false,
                });
            }
            if (std.mem.eql(u8, entity.classname, "func_wall")) {
                var m = try world_opt.?.createEntity(.{});
                _ = try m.createNewComponent(basics.TransformComponent, .{ .position = delve.math.Vec3.zero });
                _ = try m.createNewComponent(quakesolids.QuakeSolidsComponent, .{
                    .quake_map = self,
                    .quake_entity_idx = entity_idx,
                    .transform = self.map_transform,
                });
            }
            if (std.mem.eql(u8, entity.classname, "func_breakable")) {
                var m = try world_opt.?.createEntity(.{});

                if (entity_name) |name| {
                    _ = try m.createNewComponent(basics.NameComponent, .{ .name = string.init(name) });
                }

                _ = try m.createNewComponent(basics.TransformComponent, .{ .position = delve.math.Vec3.zero });
                _ = try m.createNewComponent(actor_stats.ActorStats, .{ .max_hp = 5 });
                _ = try m.createNewComponent(breakables.BreakableComponent, .{});
                _ = try m.createNewComponent(quakesolids.QuakeSolidsComponent, .{
                    .quake_map = self,
                    .quake_entity_idx = entity_idx,
                    .transform = self.map_transform,
                });

                if (target_name != null) {
                    _ = try m.createNewComponent(triggers.TriggerComponent, .{
                        .target = if (target_name != null) string.init(target_name.?) else string.empty,
                        .killtarget = if (killtarget_name != null) string.init(killtarget_name.?) else string.empty,
                    });
                }
            }
            if (std.mem.eql(u8, entity.classname, "trigger_multiple") or std.mem.eql(u8, entity.classname, "trigger_secret") or std.mem.eql(u8, entity.classname, "trigger_teleport")) {
                var message: []const u8 = "";
                var delay: f32 = 0.0;
                var wait: f32 = 0.0;
                var health: f32 = 0.0;
                var screen_shake: f32 = 0.0;

                const is_secret = std.mem.eql(u8, entity.classname, "trigger_secret");
                const is_teleporter = std.mem.eql(u8, entity.classname, "trigger_teleport");
                if (is_secret) {
                    message = "You found a secret area!";
                }

                if (entity.getStringProperty("message")) |v| {
                    message = v;
                } else |_| {}

                if (entity.getFloatProperty("delay")) |v| {
                    delay = v;
                } else |_| {}

                if (entity.getFloatProperty("wait")) |v| {
                    wait = v;
                } else |_| {}

                if (entity.getFloatProperty("health")) |v| {
                    health = v;
                } else |_| {}

                if (entity.getFloatProperty("shake")) |v| {
                    screen_shake = v / 16.0;
                } else |_| {}

                var m = try world_opt.?.createEntity(.{});
                if (entity_name) |name| {
                    _ = try m.createNewComponent(basics.NameComponent, .{ .name = string.init(name) });
                }

                _ = try m.createNewComponent(basics.TransformComponent, .{ .position = delve.math.Vec3.zero });
                _ = try m.createNewComponent(quakesolids.QuakeSolidsComponent, .{
                    .quake_map = self,
                    .quake_entity_idx = entity_idx,
                    .transform = self.map_transform,
                    .collides_entities = health > 0,
                    .hidden = true,
                });
                _ = try m.createNewComponent(triggers.TriggerComponent, .{
                    .trigger_type = if (is_teleporter) .TELEPORT else .BASIC,
                    .target = if (target_name != null) string.init(target_name.?) else string.empty,
                    .killtarget = if (killtarget_name != null) string.init(killtarget_name.?) else string.empty,
                    .message = string.init(message),
                    .delay = delay,
                    .wait = wait,
                    .only_once = is_secret,
                    .is_volume = true,
                    .is_secret = is_secret,
                    .play_sound = is_secret,
                    .trigger_on_damage = health > 0,
                    .screen_shake_amt = screen_shake,
                });
            }
            if (std.mem.eql(u8, entity.classname, "trigger_once")) {
                var message: []const u8 = "";
                var delay: f32 = 0.0;
                var health: f32 = 0.0;
                var screen_shake: f32 = 0.0;

                if (entity.getStringProperty("message")) |v| {
                    message = v;
                } else |_| {}

                if (entity.getFloatProperty("delay")) |v| {
                    delay = v;
                } else |_| {}

                if (entity.getFloatProperty("health")) |v| {
                    health = v;
                } else |_| {}

                if (entity.getFloatProperty("shake")) |v| {
                    screen_shake = v / 16.0;
                } else |_| {}

                var m = try world_opt.?.createEntity(.{});
                if (entity_name) |name| {
                    _ = try m.createNewComponent(basics.NameComponent, .{ .name = string.init(name) });
                }

                _ = try m.createNewComponent(basics.TransformComponent, .{ .position = delve.math.Vec3.zero });
                _ = try m.createNewComponent(quakesolids.QuakeSolidsComponent, .{
                    .quake_map = self,
                    .quake_entity_idx = entity_idx,
                    .transform = self.map_transform,
                    .collides_entities = health > 0,
                    .hidden = true,
                });
                _ = try m.createNewComponent(triggers.TriggerComponent, .{
                    .target = if (target_name != null) string.init(target_name.?) else string.empty,
                    .killtarget = if (killtarget_name != null) string.init(killtarget_name.?) else string.empty,
                    .message = string.init(message),
                    .delay = delay,
                    .is_volume = true,
                    .only_once = true,
                    .trigger_on_damage = health > 0,
                    .screen_shake_amt = screen_shake,
                });
            }
            if (std.mem.eql(u8, entity.classname, "trigger_counter")) {
                var message: []const u8 = "";
                var delay: f32 = 0.0;
                var health: f32 = 0.0;
                var count: i32 = 1;

                if (entity.getStringProperty("message")) |v| {
                    message = v;
                } else |_| {}

                if (entity.getFloatProperty("delay")) |v| {
                    delay = v;
                } else |_| {}

                if (entity.getFloatProperty("health")) |v| {
                    health = v;
                } else |_| {}

                if (entity.getFloatProperty("count")) |v| {
                    count = @intFromFloat(v);
                } else |_| {}

                var m = try world_opt.?.createEntity(.{});
                if (entity_name) |name| {
                    _ = try m.createNewComponent(basics.NameComponent, .{ .name = string.init(name) });
                }

                _ = try m.createNewComponent(basics.TransformComponent, .{ .position = delve.math.Vec3.zero });
                _ = try m.createNewComponent(quakesolids.QuakeSolidsComponent, .{
                    .quake_map = self,
                    .quake_entity_idx = entity_idx,
                    .transform = self.map_transform,
                    .collides_entities = health > 0,
                    .hidden = true,
                });
                _ = try m.createNewComponent(triggers.TriggerComponent, .{
                    .trigger_type = .COUNTER,
                    .target = if (target_name != null) string.init(target_name.?) else string.empty,
                    .killtarget = if (killtarget_name != null) string.init(killtarget_name.?) else string.empty,
                    .message = string.init(message),
                    .delay = delay,
                    .is_volume = true,
                    .trigger_on_damage = health > 0,
                    .trigger_count = count,
                });
            }
            if (std.mem.eql(u8, entity.classname, "trigger_changelevel")) {
                var message: []const u8 = "";
                var map: []const u8 = "";
                var delay: f32 = 0.0;
                var health: f32 = 0.0;
                var count: i32 = 1;

                if (entity.getStringProperty("message")) |v| {
                    message = v;
                } else |_| {}

                if (entity.getStringProperty("map")) |v| {
                    map = v;
                } else |_| {}

                if (entity.getFloatProperty("delay")) |v| {
                    delay = v;
                } else |_| {}

                if (entity.getFloatProperty("health")) |v| {
                    health = v;
                } else |_| {}

                if (entity.getFloatProperty("count")) |v| {
                    count = @intFromFloat(v);
                } else |_| {}

                var m = try world_opt.?.createEntity(.{});
                if (entity_name) |name| {
                    _ = try m.createNewComponent(basics.NameComponent, .{ .name = string.init(name) });
                }

                _ = try m.createNewComponent(basics.TransformComponent, .{ .position = delve.math.Vec3.zero });
                _ = try m.createNewComponent(quakesolids.QuakeSolidsComponent, .{
                    .quake_map = self,
                    .quake_entity_idx = entity_idx,
                    .transform = self.map_transform,
                    .collides_entities = health > 0,
                    .hidden = true,
                });
                _ = try m.createNewComponent(triggers.TriggerComponent, .{
                    .trigger_type = .CHANGE_LEVEL,
                    .target = if (target_name != null) string.init(target_name.?) else string.empty,
                    .killtarget = if (killtarget_name != null) string.init(killtarget_name.?) else string.empty,
                    .message = string.init(message),
                    .delay = delay,
                    .is_volume = true,
                    .trigger_on_damage = health > 0,
                    .trigger_count = count,
                    .change_map_target = string.init(map),
                });
            }
            if (std.mem.eql(u8, entity.classname, "info_teleport_destination")) {
                var m = try world_opt.?.createEntity(.{});
                _ = try m.createNewComponent(basics.TransformComponent, .{ .position = entity_origin });
                if (entity_name) |name| {
                    _ = try m.createNewComponent(basics.NameComponent, .{ .name = string.init(name) });
                }
            }
            if (std.mem.eql(u8, entity.classname, "prop_static")) {
                var m = try world_opt.?.createEntity(.{});
                _ = try m.createNewComponent(basics.TransformComponent, .{ .position = entity_origin });

                const mesh_path: [:0]const u8 = "assets/meshes/SciFiHelmet.gltf";
                const texture_diffuse: [:0]const u8 = "assets/meshes/SciFiHelmet_BaseColor_512.png";
                const texture_emissive: [:0]const u8 = "assets/meshes/black.png";
                var scale: f32 = 32.0;
                var angle: f32 = 0.0;

                // if (entity.getStringProperty("texture_diffuse")) |v| {
                //     var diffuse = std.ArrayList(u8).init(allocator);
                //     try diffuse.writer().print("assets/{s}", .{v});
                //     texture_diffuse = try diffuse.toOwnedSliceSentinel(0);
                // } else |_| {}
                //
                // if (entity.getStringProperty("texture_emissive")) |v| {
                //     var diffuse = std.ArrayList(u8).init(allocator);
                //     try diffuse.writer().print("assets/{s}", .{v});
                //     texture_emissive = try diffuse.toOwnedSliceSentinel(0);
                // } else |_| {}
                //
                // if (entity.getStringProperty("model")) |v| {
                //     var model = std.ArrayList(u8).init(allocator);
                //     try model.writer().print("assets/{s}", .{v});
                //     mesh_path = try model.toOwnedSliceSentinel(0);
                // } else |_| {}

                if (entity.getFloatProperty("scale")) |v| {
                    scale = v;
                } else |_| {}

                if (entity.getFloatProperty("angle")) |v| {
                    angle = v;
                } else |_| {}

                _ = try m.createNewComponent(meshes.MeshComponent, .{
                    .mesh_path = string.init(mesh_path),
                    .texture_diffuse_path = string.init(texture_diffuse),
                    .texture_emissive_path = string.init(texture_emissive),
                    .scale = scale * self.map_scale.x,
                });

                m.setRotation(delve.math.Quaternion.fromAxisAndAngle(angle, delve.math.Vec3.y_axis));
            }
            if (std.mem.eql(u8, entity.classname, "env_sprite")) {
                var texture: ?[]const u8 = null;
                var spritesheet: []const u8 = "sprites/sprites";
                var spritesheet_col: u32 = 0;
                var spritesheet_row: u32 = 0;
                var scale: f32 = 3.0;
                var blend: f32 = 0.0;

                var tex_path: ?std.ArrayList(u8) = null;
                defer if (tex_path != null) tex_path.?.deinit();

                // Could have a spritesheet
                if (entity.getStringProperty("spritesheet")) |v| {
                    spritesheet = v;
                } else |_| {}

                if (entity.getFloatProperty("spritesheet_col")) |v| {
                    spritesheet_col = @intFromFloat(v);
                } else |_| {}

                if (entity.getFloatProperty("spritesheet_row")) |v| {
                    spritesheet_row = @intFromFloat(v);
                } else |_| {}

                // Or a texture image
                if (entity.getStringProperty("model")) |v| {
                    tex_path = std.ArrayList(u8).init(allocator);
                    try tex_path.?.writer().print("assets/{s}", .{v});
                    texture = tex_path.?.items;
                } else |_| {}

                if (entity.getFloatProperty("scale")) |v| {
                    scale = v;
                } else |_| {}

                if (entity.getFloatProperty("blend")) |v| {
                    blend = v;
                } else |_| {}

                var m = try world_opt.?.createEntity(.{});
                _ = try m.createNewComponent(basics.TransformComponent, .{ .position = entity_origin });
                _ = try m.createNewComponent(sprites.SpriteComponent, .{
                    .blend_mode = if (blend > 0) .ALPHA else .OPAQUE,
                    .position = delve.math.Vec3.zero,
                    .billboard_type = .XZ,
                    .scale = scale * 3.0,
                    .spritesheet = string.init(spritesheet),
                    .spritesheet_col = spritesheet_col,
                    .spritesheet_row = spritesheet_row,
                    .texture_path = if (texture != null) string.init(texture.?) else null,
                });
            }
            if (std.mem.eql(u8, entity.classname, "env_explosion")) {
                var does_damage: bool = true;
                if (entity.getFloatProperty("do_damage")) |v| {
                    does_damage = v > 0.0;
                } else |_| {}

                var m = try world_opt.?.createEntity(.{});
                _ = try m.createNewComponent(basics.TransformComponent, .{ .position = entity_origin });
                var exp = try m.createNewComponent(explosion.ExplosionComponent, .{ .state = .WaitingForTrigger });
                if (entity_name) |name| {
                    _ = try m.createNewComponent(basics.NameComponent, .{ .name = string.init(name) });
                }

                if (!does_damage)
                    exp.range = 0;
            }
            if (std.mem.startsWith(u8, entity.classname, "item_")) {
                var item_type: items.ItemType = .Medkit;
                var spritesheet_col: u32 = 0;
                var spritesheet_row: u32 = 4;
                var weapon_type = weapons.WeaponType.Pistol;
                var ammo_type = weapons.AmmoType.PistolBullets;

                if (std.mem.startsWith(u8, entity.classname, "item_ammo")) {
                    item_type = .Ammo;
                    spritesheet_col = 1;
                    spritesheet_row = 4;
                } else if (std.mem.startsWith(u8, entity.classname, "item_weapon")) {
                    item_type = .Weapon;
                    spritesheet_col = 0;
                    spritesheet_row = 0;
                }

                // weapons
                if (std.mem.eql(u8, entity.classname, "item_weapon_pistol")) {
                    weapon_type = .RocketLauncher;
                    spritesheet_row = 0;
                }
                if (std.mem.eql(u8, entity.classname, "item_weapon_rifle")) {
                    weapon_type = .AssaultRifle;
                    spritesheet_row = 1;
                }
                if (std.mem.eql(u8, entity.classname, "item_weapon_rockets")) {
                    weapon_type = .RocketLauncher;
                    spritesheet_row = 2;
                }
                if (std.mem.eql(u8, entity.classname, "item_weapon_plasma")) {
                    weapon_type = .PlasmaRifle;
                    spritesheet_row = 3;
                }

                // ammo
                if (std.mem.eql(u8, entity.classname, "item_ammo_pistol")) {
                    ammo_type = .PistolBullets;
                    spritesheet_col = 0;
                }
                if (std.mem.eql(u8, entity.classname, "item_ammo_rifle")) {
                    ammo_type = .RifleBullets;
                    spritesheet_col = 0;
                }
                if (std.mem.eql(u8, entity.classname, "item_ammo_rockets")) {
                    ammo_type = .Rockets;
                    spritesheet_col = 1;
                }
                if (std.mem.eql(u8, entity.classname, "item_ammo_plasma")) {
                    ammo_type = .BatteryCells;
                    spritesheet_col = 2;
                }

                var m = try world_opt.?.createEntity(.{});
                _ = try m.createNewComponent(basics.TransformComponent, .{ .position = entity_origin });
                _ = try m.createNewComponent(items.ItemComponent, .{
                    .item_type = item_type,
                    .item_subtype_weapon = weapon_type,
                    .item_subtype_ammo = ammo_type,
                });
                _ = try m.createNewComponent(box_collision.BoxCollisionComponent, .{ .size = delve.math.Vec3.new(1.5, 2.5, 1.5), .collides_entities = false });
                _ = try m.createNewComponent(sprites.SpriteComponent, .{
                    .position = delve.math.Vec3.zero,
                    .billboard_type = .XZ,
                    .scale = 1.0,
                    .spritesheet = string.init("sprites/items"),
                    .spritesheet_col = spritesheet_col,
                    .spritesheet_row = spritesheet_row,
                });
            }
            if (std.mem.eql(u8, entity.classname, "prop_text")) {
                var m = try world_opt.?.createEntity(.{});

                var text_msg: []const u8 = "";
                var scale: f32 = 32.0;
                var unlit: bool = true;

                if (entity.getStringProperty("text")) |v| {
                    text_msg = v;
                } else |_| {}

                if (entity.getFloatProperty("scale")) |v| {
                    scale = v;
                } else |_| {}

                if (entity.getFloatProperty("unlit")) |v| {
                    unlit = v > 0.99;
                } else |_| {}

                _ = try m.createNewComponent(basics.TransformComponent, .{ .position = entity_origin });
                _ = try m.createNewComponent(text.TextComponent, .{ .text = string.init(text_msg), .scale = scale * self.map_scale.x, .unlit = unlit });

                if (entity.getFloatProperty("angle")) |v| {
                    m.setRotation(delve.math.Quaternion.fromAxisAndAngle(v + 90, delve.math.Vec3.y_axis));
                } else |_| {}
            }
            if (std.mem.eql(u8, entity.classname, "ambient_comp_hum")) {
                var m = try world_opt.?.createEntity(.{});
                _ = try m.createNewComponent(basics.TransformComponent, .{ .position = entity_origin });
                _ = try m.createNewComponent(audio.AudioComponent, .{
                    .sound_path = string.init("assets/audio/sfx/computer-hum.mp3"),
                    .volume = 1.0,
                });
            }
            if (std.mem.eql(u8, entity.classname, "info_streaming_level")) {
                var level_path: []const u8 = "";
                var landmark_name: []const u8 = "entrance";
                var angle: f32 = 0.0;

                if (entity.getStringProperty("level")) |v| {
                    level_path = v;
                } else |_| {}
                if (entity.getStringProperty("landmark")) |v| {
                    landmark_name = v;
                } else |_| {}
                if (entity.getFloatProperty("angle")) |v| {
                    angle = v;
                } else |_| {}

                var m = try world_opt.?.createEntity(.{});
                _ = try m.createNewComponent(basics.TransformComponent, .{ .position = entity_origin });
                _ = try m.createNewComponent(QuakeMapComponent, .{
                    .filename = string.init(level_path),
                    .transform = delve.math.Mat4.translate(entity_origin),
                    .transform_landmark_name = string.init(landmark_name),
                    .transform_landmark_angle = angle,
                });
                if (entity_name) |name| {
                    _ = try m.createNewComponent(basics.NameComponent, .{ .name = string.init(name) });
                }
            }
        }
    }

    pub fn getWorldSolids(self: *QuakeMapComponent) []delve.utils.quakemap.Solid {
        return self.quake_map.worldspawn.solids.items;
    }

    pub fn deinit(self: *QuakeMapComponent) void {
        defer self.quake_map.deinit();

        for (self.entity_meshes.items) |*em| {
            em.deinit();
        }
        self.entity_meshes.deinit();

        for (self.map_meshes.items) |*wm| {
            wm.deinit();
        }
        self.map_meshes.deinit();

        self.solid_spatial_hash.deinit();

        self.filename.deinit();
        if (self.transform_landmark_name != null) self.transform_landmark_name.?.deinit();

        if (self._file_buffer != null)
            delve.mem.getAllocator().free(self._file_buffer.?);
    }

    pub fn tick(self: *QuakeMapComponent, delta: f32) void {
        self.time += delta;
    }

    // Custom component serializer
    pub fn jsonStringify(self: *const QuakeMapComponent, out: anytype) !void {
        try out.objectField("filename");
        try out.write(self.filename.str);

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
            const offset = entity.getVec3Property("origin") catch {
                delve.debug.log("Could not read player start offset property!", .{});
                break;
            };

            var angle: f32 = 0;
            if (entity.getFloatProperty("angle")) |v| {
                angle = v;
            } else |_| {}

            return .{ .pos = offset, .angle = angle };
        }
    }

    return .{ .pos = math.Vec3.new(0, 0, 0) };
}

pub fn getLandmark(map: *delve.utils.quakemap.QuakeMap, landmark_name: []const u8) Landmark {
    var fallback_landmark = Landmark{};

    for (map.entities.items) |entity| {
        if (std.mem.eql(u8, entity.classname, "info_landmark")) {
            const offset = entity.getVec3Property("origin") catch {
                delve.debug.log("Could not read player start offset property!", .{});
                continue;
            };

            var angle: f32 = 0;
            if (entity.getFloatProperty("angle")) |v| {
                angle = v;
            } else |_| {}

            // stick to 0-360
            angle = @mod(angle, 360.0);

            const landmark = Landmark{ .pos = offset, .angle = angle };

            var entity_name: []const u8 = undefined;
            if (entity.getStringProperty("targetname")) |v| {
                entity_name = v;
            } else |_| {
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

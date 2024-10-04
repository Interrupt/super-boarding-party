const std = @import("std");
const delve = @import("delve");

const math = delve.math;
const graphics = delve.platform.graphics;

// materials!
var did_init_materials: bool = false;
var fallback_material: graphics.Material = undefined;
var fallback_quake_material: delve.utils.quakemap.QuakeMaterial = undefined;
var materials: std.StringHashMap(delve.utils.quakemap.QuakeMaterial) = undefined;

// shader setup
const lit_shader = delve.shaders.default_basic_lighting;
const basic_lighting_fs_uniforms: []const delve.platform.graphics.MaterialUniformDefaults = &[_]delve.platform.graphics.MaterialUniformDefaults{ .CAMERA_POSITION, .COLOR_OVERRIDE, .ALPHA_CUTOFF, .AMBIENT_LIGHT, .DIRECTIONAL_LIGHT, .POINT_LIGHTS_16, .FOG_DATA };

pub const QuakeMapComponent = struct {
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

    pub fn init(self: *QuakeMapComponent) void {
        self.init_world() catch {
            delve.debug.log("Could not init quake map component!", .{});
        };
    }

    pub fn init_world(self: *QuakeMapComponent) !void {
        // use the Delve Framework global allocator
        const allocator = delve.mem.getAllocator();

        self.lights = std.ArrayList(delve.platform.graphics.PointLight).init(allocator);

        const world_shader = try graphics.Shader.initFromBuiltin(.{ .vertex_attributes = delve.graphics.mesh.getShaderAttributes() }, lit_shader);
        const black_tex = delve.platform.graphics.createSolidTexture(0x00000000);

        // scale and rotate the map
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

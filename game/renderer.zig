const std = @import("std");
const delve = @import("delve");
const game = @import("game.zig");
const entities = @import("entities.zig");
const quakemap = @import("../entities/quakemap.zig");
const quakesolids = @import("../entities/quakesolids.zig");
const sprites = @import("../entities/sprite.zig");
const meshes = @import("../entities/mesh.zig");
const text = @import("../entities/text.zig");
const lights = @import("../entities/light.zig");
const actor_stats = @import("../entities/actor_stats.zig");
const weapon = @import("../entities/weapon.zig");
const emitters = @import("../entities/particle_emitter.zig");
const spritesheets = @import("../managers/spritesheets.zig");

const lit_sprite_shader = @import("../shaders/lit-sprites.glsl.zig");

const math = delve.math;
const graphics = delve.platform.graphics;
const batcher = delve.graphics.batcher;

const Camera = delve.graphics.camera.Camera;

var did_init: bool = false;
var debug_material: graphics.Material = undefined;
var debug_cube_mesh: delve.graphics.mesh.Mesh = undefined;

const RenderState = struct {
    view_mats: graphics.CameraMatrices,
    fog: graphics.MaterialFogParams = .{},
    lighting: graphics.MaterialLightParams = .{},
};

pub const DebugDrawCommand = struct {
    mesh: *delve.graphics.mesh.Mesh,
    color: delve.colors.Color,
    transform: math.Mat4,
    lifetime: f32 = 0.0,
};

pub const RenderInstance = struct {
    allocator: std.mem.Allocator,
    lights: std.ArrayList(graphics.PointLight),
    directional_light: graphics.DirectionalLight = .{ .color = delve.colors.white, .brightness = 0.0 },
    sprite_batch: batcher.SpriteBatcher,
    ui_batch: batcher.SpriteBatcher,
    debug_draw_commands: std.ArrayList(DebugDrawCommand),
    width: usize,
    height: usize,
    width_f: f32,
    height_f: f32,
    time: f64 = 0.0,

    sprite_shader_opaque: graphics.Shader,
    sprite_shader_blend: graphics.Shader,
    sprite_shader_lit: graphics.Shader,

    offscreen_pass: graphics.RenderPass,
    offscreen_pass_2: graphics.RenderPass,
    offscreen_material: graphics.Material,
    offscreen_material_2: graphics.Material,

    debug_material: graphics.Material,

    // just so that we can clean them up more easily later
    basic_shaders: std.ArrayList(graphics.Shader),

    pub fn init(allocator: std.mem.Allocator) !RenderInstance {
        var basic_shaders = std.ArrayList(graphics.Shader).init(allocator);

        if (!did_init) {
            const debug_shader = try graphics.Shader.initDefault(.{ .vertex_attributes = delve.graphics.mesh.getShaderAttributes() });
            try basic_shaders.append(debug_shader);

            debug_material = try graphics.Material.init(.{
                .shader = debug_shader,
                .texture_0 = graphics.createSolidTexture(0xFFFFFFFF),
                .samplers = &[_]graphics.FilterMode{.NEAREST},
                .cull_mode = .NONE,
                .depth_compare = .ALWAYS,
            });

            const debug_cube_mesh_size = math.Vec3.new(1, 1, 1);
            debug_cube_mesh = try delve.graphics.mesh.createCube(math.Vec3.new(0, 0, 0), debug_cube_mesh_size, delve.colors.white, debug_material);

            // preload some assets!
            _ = try spritesheets.loadSpriteSheet("sprites/entities", "assets/sprites/entities.png", 16, 8);
            _ = try spritesheets.loadSpriteSheet("sprites/items", "assets/sprites/items.png", 4, 8);
            _ = try spritesheets.loadSpriteSheet("sprites/particles", "assets/sprites/particles.png", 8, 4);
            _ = try spritesheets.loadSpriteSheet("sprites/sprites", "assets/sprites/sprites.png", 4, 8);
            _ = try spritesheets.loadSpriteSheet("sprites/blank", "assets/sprites/blank.png", 4, 4);
        }

        const offscreen_pass = graphics.RenderPass.init(.{
            .width = @intCast(delve.platform.app.getWidth()),
            .height = @intCast(delve.platform.app.getHeight()),
            .write_depth = true,
            .write_stencil = true,
        });

        const offscreen_pass_2 = graphics.RenderPass.init(.{
            .width = @intCast(delve.platform.app.getWidth()),
            .height = @intCast(delve.platform.app.getHeight()),
        });

        delve.debug.log("Created renderer with size: {d}x{d}", .{ delve.platform.app.getWidth(), delve.platform.app.getHeight() });

        const offscreen_shader_1 = try graphics.Shader.initDefault(.{ .blend_mode = graphics.BlendMode.ADD });
        try basic_shaders.append(offscreen_shader_1);
        const offscreen_material = try graphics.Material.init(.{
            .shader = offscreen_shader_1,
            .texture_0 = offscreen_pass.render_texture_color,
            .samplers = &[_]graphics.FilterMode{.NEAREST},
            .cull_mode = .NONE,
            .blend_mode = .ADD,
        });

        const offscreen_shader_2 = try graphics.Shader.initDefault(.{ .blend_mode = graphics.BlendMode.NONE });
        try basic_shaders.append(offscreen_shader_2);
        const offscreen_material_2 = try graphics.Material.init(.{
            .shader = offscreen_shader_2,
            .texture_0 = offscreen_pass_2.render_texture_color,
            .samplers = &[_]graphics.FilterMode{.NEAREST},
            .cull_mode = .NONE,
            .blend_mode = .NONE,
        });

        return .{
            .allocator = allocator,
            .lights = std.ArrayList(delve.platform.graphics.PointLight).init(allocator),
            .sprite_batch = try batcher.SpriteBatcher.init(.{}),
            .ui_batch = try batcher.SpriteBatcher.init(.{}),
            .debug_draw_commands = std.ArrayList(DebugDrawCommand).init(allocator),

            // sprite shaders
            .sprite_shader_opaque = try graphics.Shader.initDefault(.{}),
            .sprite_shader_blend = try graphics.Shader.initDefault(.{ .blend_mode = graphics.BlendMode.BLEND, .depth_write_enabled = false }),
            .sprite_shader_lit = try graphics.Shader.initFromBuiltin(.{ .blend_mode = graphics.BlendMode.BLEND, .depth_write_enabled = true }, lit_sprite_shader),

            .offscreen_pass = offscreen_pass,
            .offscreen_pass_2 = offscreen_pass_2,
            .offscreen_material = offscreen_material,
            .offscreen_material_2 = offscreen_material_2,

            .width = @intCast(delve.platform.app.getWidth()),
            .height = @intCast(delve.platform.app.getHeight()),
            .width_f = @floatFromInt(delve.platform.app.getWidth()),
            .height_f = @floatFromInt(delve.platform.app.getHeight()),

            .basic_shaders = basic_shaders,
            .debug_material = debug_material,
        };
    }

    pub fn resize(self: *RenderInstance) void {
        const width: u32 = @intCast(delve.platform.app.getWidth());
        const height: u32 = @intCast(delve.platform.app.getHeight());

        const width_f: f32 = @floatFromInt(width);
        const height_f: f32 = @floatFromInt(height);

        self.width = width;
        self.height = height;
        self.width_f = width_f;
        self.height_f = height_f;

        // Recreate our offscreen buffers when the app size changes
        self.offscreen_pass.destroy();
        self.offscreen_pass_2.destroy();

        self.offscreen_pass = graphics.RenderPass.init(.{
            .width = width,
            .height = height,
            .write_depth = true,
            .write_stencil = true,
        });

        self.offscreen_pass_2 = graphics.RenderPass.init(.{
            .width = width,
            .height = height,
        });

        // set our offscreen materials to use the new offscreen textures
        self.offscreen_material.state.textures[0] = self.offscreen_pass.render_texture_color;
        self.offscreen_material_2.state.textures[0] = self.offscreen_pass_2.render_texture_color;
    }

    pub fn deinit(self: *RenderInstance) void {
        delve.debug.log("Render instance tearing down", .{});

        self.sprite_shader_opaque.destroy();
        self.sprite_shader_blend.destroy();
        self.sprite_shader_lit.destroy();

        self.sprite_batch.deinit();
        self.ui_batch.deinit();
        self.debug_draw_commands.deinit();
        self.lights.deinit();

        self.offscreen_material.deinit();
        self.offscreen_material_2.deinit();
        self.debug_material.deinit();

        for (self.basic_shaders.items) |*s| {
            s.destroy();
        }
        self.basic_shaders.deinit();
    }

    /// Called right before drawing
    pub fn update(self: *RenderInstance, game_instance: *game.GameInstance) void {
        // Go collect all of the lights
        self.lights.clearRetainingCapacity();

        // var map_it = quakemap.getComponentStorage(game_instance.world).iterator();
        // while (map_it.next()) |map| {
        //     self.lights.appendSlice(map.lights.items) catch {};
        //     self.directional_light = map.directional_light;
        // }

        self.directional_light = .{
            .color = delve.colors.black,
        };

        // gather lights from LightComponents
        self.addLightsFromLightComponents(game_instance);

        // reset sprite batches
        self.sprite_batch.reset();
        self.ui_batch.reset();

        self.time = game_instance.time;
    }

    pub fn pre_draw(self: *RenderInstance, game_instance: *game.GameInstance) void {
        if (game_instance.player_controller == null)
            return;

        const player_controller = game_instance.player_controller.?;

        const camera = &player_controller.camera;
        const view_mats = camera.update();

        var fog: delve.platform.graphics.MaterialFogParams = .{};
        var lighting: delve.platform.graphics.MaterialLightParams = .{};

        // make a skylight and a light for the player
        const directional_light = self.directional_light;
        const ambient_light = directional_light.color.scale(0.2);

        // final list of point lights for the materials
        const max_lights: usize = 16;
        var point_lights: [max_lights]delve.platform.graphics.PointLight = [_]delve.platform.graphics.PointLight{.{ .color = delve.colors.black }} ** max_lights;

        // sort the level's lights, and make sure they are actually visible before putting in the final list
        std.sort.insertion(delve.platform.graphics.PointLight, self.lights.items, camera, compareLights);

        // set the underwater fog color
        if (player_controller.eyes_in_water) {
            fog.color = delve.colors.forest_green;
            fog.amount = 0.75;
            fog.start = -50.0;
            fog.end = 50.0;
        }

        // set the lighting material params
        lighting.point_lights = &point_lights;
        lighting.directional_light = directional_light;
        lighting.ambient_light = ambient_light;

        const num_passes_f: f32 = @as(f32, @floatFromInt(self.lights.items.len)) / 16;
        const num_passes: usize = @intFromFloat(@ceil(num_passes_f));
        var light_offset: usize = 0;

        // delve.debug.log("Num light passes: {d}", .{num_passes});

        // Just clear the screen if there are no passes to draw
        if (num_passes == 0) {
            delve.platform.graphics.beginPass(self.offscreen_pass_2, delve.colors.black);
            delve.platform.graphics.endPass();
        }

        for (0..num_passes) |i| {
            // start by clearing out the lights list
            var num_lights: usize = 0;
            for (0..max_lights) |light_idx| {
                point_lights[light_idx] = .{ .color = delve.colors.black };
            }

            // only use directional or ambient light for pass 0
            if (i > 0) {
                lighting.directional_light = .{ .color = delve.colors.black };
                lighting.ambient_light = delve.colors.black;
                fog = .{};
            }

            for (light_offset..light_offset + max_lights) |light_idx| {
                if (num_lights >= max_lights)
                    break;

                if (light_idx >= self.lights.items.len)
                    break;

                point_lights[num_lights] = self.lights.items[light_idx];
                num_lights += 1;
            }
            light_offset += max_lights;

            // start our offscreen pass
            self.offscreen_pass.config.clear_depth = i == 0;
            self.offscreen_pass.config.clear_stencil = i == 0;
            delve.platform.graphics.beginPass(self.offscreen_pass, delve.colors.black);

            // Now we can draw the world
            const render_state = .{ .view_mats = view_mats, .lighting = lighting, .fog = fog };
            self.drawQuakeMapComponents(game_instance, render_state);
            self.drawQuakeSolidsComponents(game_instance, render_state);

            // Draw meshes next
            self.drawMeshComponents(game_instance, render_state);

            if (i == 0) {
                // Next draw any sprites
                self.drawSpriteComponents(game_instance, render_state);
                self.drawTextComponents(game_instance, render_state);

                // And draw particle emitters next
                self.drawParticleEmitterComponents(game_instance, render_state);

                // Build our sprite batch
                self.sprite_batch.apply();

                // Draw our final sprite batch
                self.sprite_batch.draw(view_mats, math.Mat4.identity);
            }

            // end the offscreen pass
            delve.platform.graphics.endPass();

            // now do the ping / pong!
            delve.platform.graphics.beginPass(self.offscreen_pass_2, if (i == 0) delve.colors.black else null);
            delve.platform.graphics.drawDebugRectangleWithMaterial(&self.offscreen_material, 0.0, 0.0, self.width_f, self.height_f);
            delve.platform.graphics.endPass();
        }
    }

    /// Actual draw function
    pub fn draw(self: *RenderInstance, game_instance: *game.GameInstance) void {
        // draw our game state UI after anything else
        defer game_instance.states.draw();

        if (game_instance.player_controller == null)
            return;

        const player_controller = game_instance.player_controller.?;
        const camera = &player_controller.camera;
        const view_mats = camera.update();

        // draw our final render
        delve.platform.graphics.drawDebugRectangleWithMaterial(&self.offscreen_material_2, 0.0, 0.0, self.width_f, self.height_f);

        // can draw the hud now too
        self.drawHud(game_instance);

        // Draw any debug info we have
        for (self.debug_draw_commands.items) |*draw_cmd| {
            var material = debug_material;
            material.state.params.draw_color = draw_cmd.color;

            draw_cmd.mesh.drawWithMaterial(material, view_mats, draw_cmd.transform);

            draw_cmd.lifetime -= delve.platform.app.getCurrentDeltaTime();
        }
    }

    pub fn post_draw(self: *RenderInstance, game_instance: *game.GameInstance) void {
        _ = game_instance;

        // render the imgui ui
        delve.platform.app.renderImgui();

        // clear the debug draw commands
        self.debug_draw_commands.clearRetainingCapacity();
    }

    pub fn drawDebugCube(self: *RenderInstance, pos: math.Vec3, offset: math.Vec3, size: math.Vec3, dir: math.Vec3, color: delve.colors.Color) void {
        var transform: math.Mat4 = math.Mat4.translate(pos);

        if (!(dir.x == 0 and dir.y == 1 and dir.z == 0)) {
            if (!(dir.x == 0 and dir.y == -1 and dir.z == 0)) {
                // only need to rotate when we're not already facing up
                transform = transform.mul(math.Mat4.direction(dir, math.Vec3.y_axis)).mul(math.Mat4.rotate(90, math.Vec3.x_axis));
            } else {
                // flip upside down!
                transform = transform.mul(math.Mat4.rotate(180, math.Vec3.x_axis));
            }
        }

        transform = transform.mul(math.Mat4.translate(offset));
        transform = transform.mul(math.Mat4.scale(size));

        for (self.debug_draw_commands.items) |*draw_cmd| {
            if (draw_cmd.lifetime < 0) {
                draw_cmd.* = .{ .mesh = &debug_cube_mesh, .transform = transform, .color = color };
                return;
            }
        }

        self.debug_draw_commands.append(.{ .mesh = &debug_cube_mesh, .transform = transform, .color = color }) catch {};
    }

    pub fn drawDebugWireframeCube(self: *RenderInstance, pos: math.Vec3, offset: math.Vec3, size: math.Vec3, dir: math.Vec3, color: delve.colors.Color) void {
        _ = offset;
        const thickness: f32 = 0.01;

        const x_axis_offset = math.Vec3.x_axis.scale(0.5).mul(size);
        const y_axis_offset = math.Vec3.y_axis.scale(0.5).mul(size);
        const z_axis_offset = math.Vec3.z_axis.scale(0.5).mul(size);
        const x_axis_offset_flip = math.Vec3.x_axis.scale(-0.5).mul(size);
        const y_axis_offset_flip = math.Vec3.y_axis.scale(-0.5).mul(size);
        const z_axis_offset_flip = math.Vec3.z_axis.scale(-0.5).mul(size);

        // bottom horizontal lines
        self.drawDebugCube(pos, y_axis_offset.add(z_axis_offset), math.Vec3.new(1, thickness, thickness).mul(size), dir, color);
        self.drawDebugCube(pos, y_axis_offset_flip.add(z_axis_offset), math.Vec3.new(1, thickness, thickness).mul(size), dir, color);
        self.drawDebugCube(pos, x_axis_offset.add(z_axis_offset), math.Vec3.new(thickness, 1, thickness).mul(size), dir, color);
        self.drawDebugCube(pos, x_axis_offset_flip.add(z_axis_offset), math.Vec3.new(thickness, 1, thickness).mul(size), dir, color);

        // top horizontal lines
        self.drawDebugCube(pos, y_axis_offset.add(z_axis_offset_flip), math.Vec3.new(1, thickness, thickness).mul(size), dir, color);
        self.drawDebugCube(pos, y_axis_offset_flip.add(z_axis_offset_flip), math.Vec3.new(1, thickness, thickness).mul(size), dir, color);
        self.drawDebugCube(pos, x_axis_offset.add(z_axis_offset_flip), math.Vec3.new(thickness, 1, thickness).mul(size), dir, color);
        self.drawDebugCube(pos, x_axis_offset_flip.add(z_axis_offset_flip), math.Vec3.new(thickness, 1, thickness).mul(size), dir, color);

        // vertical lines
        self.drawDebugCube(pos, y_axis_offset.add(x_axis_offset), math.Vec3.new(thickness, thickness, 1).mul(size), dir, color);
        self.drawDebugCube(pos, y_axis_offset_flip.add(x_axis_offset), math.Vec3.new(thickness, thickness, 1).mul(size), dir, color);
        self.drawDebugCube(pos, y_axis_offset.add(x_axis_offset_flip), math.Vec3.new(thickness, thickness, 1).mul(size), dir, color);
        self.drawDebugCube(pos, y_axis_offset_flip.add(x_axis_offset_flip), math.Vec3.new(thickness, thickness, 1).mul(size), dir, color);

        // self.drawDebugCube(pos, x_axis_offset.scale(-1).add(y_axis_offset), math.Vec3.new(1, thickness, thickness).mul(size), dir, color);
        // self.drawDebugCube(pos, math.Vec3.zero, math.Vec3.new(thickness, 1, thickness).mul(size), dir, color);
        // self.drawDebugCube(pos, math.Vec3.zero, math.Vec3.new(thickness, thickness, 1).mul(size), dir, color);
    }

    pub fn drawDebugTranslateGizmo(self: *RenderInstance, pos: math.Vec3, size: math.Vec3, dir: math.Vec3) void {
        const thickness: f32 = 0.075;
        const node_size: f32 = 0.125;

        self.drawDebugCube(pos, math.Vec3.x_axis.scale(0.5).mul(size), math.Vec3.new(1, thickness, thickness).mul(size), dir, delve.colors.red);
        self.drawDebugCube(pos, math.Vec3.y_axis.scale(0.5).mul(size), math.Vec3.new(thickness, 1, thickness).mul(size), dir, delve.colors.green);
        self.drawDebugCube(pos, math.Vec3.z_axis.scale(0.5).mul(size), math.Vec3.new(thickness, thickness, 1).mul(size), dir, delve.colors.blue);
        self.drawDebugCube(pos, math.Vec3.zero, math.Vec3.new(node_size, node_size, node_size).mul(size), dir, delve.colors.white);
    }

    fn drawQuakeMapComponents(self: *RenderInstance, game_instance: *game.GameInstance, render_state: RenderState) void {

        // advance material animations
        const anim_time = self.time * 8;
        for (quakemap.material_animations.items) |anim| {
            if (anim.textures.items.len <= 1)
                continue;

            const anim_frames = anim.textures.items.len;
            const frame_index = @mod(anim_time, @as(f32, @floatFromInt(anim_frames)));
            anim.material.state.textures[0] = anim.textures.items[@as(usize, @intFromFloat(frame_index))].texture;
        }

        var map_it = quakemap.getComponentStorage(game_instance.world).iterator();
        while (map_it.next()) |map| {
            // draw the world solids!
            for (map.map_meshes.items) |*mesh| {
                const model = delve.math.Mat4.identity;
                mesh.material.state.params.lighting = render_state.lighting;
                mesh.material.state.params.fog = render_state.fog;
                mesh.draw(render_state.view_mats, model);
            }

            // Can debug draw the bvh tree if needed
            // map.bvh_tree.debugDraw();
        }
    }

    fn drawQuakeSolidsComponents(self: *RenderInstance, game_instance: *game.GameInstance, render_state: RenderState) void {
        _ = self;

        var solids_it = quakesolids.getComponentStorage(game_instance.world).iterator();
        while (solids_it.next()) |solids| {
            if (solids.hidden)
                continue;

            // draw the world solids!
            for (solids._meshes.items) |*mesh| {
                const model = delve.math.Mat4.translate(solids.owner.getRenderPosition().sub(solids.starting_pos));
                mesh.material.state.params.lighting = render_state.lighting;
                mesh.material.state.params.fog = render_state.fog;
                mesh.draw(render_state.view_mats, model);
            }
        }
    }

    fn drawMeshComponents(self: *RenderInstance, game_instance: *game.GameInstance, render_state: RenderState) void {
        _ = self;

        var mesh_it = meshes.getComponentStorage(game_instance.world).iterator();
        while (mesh_it.next()) |mesh_comp| {
            if (mesh_comp._mesh) |*mesh| {
                const owner_pos = mesh_comp.owner.getRenderPosition();
                const owner_rot = mesh_comp.owner.getRotation();
                const world_pos = owner_pos.add(owner_rot.rotateVec3(mesh_comp.position));

                const model = delve.math.Mat4.translate(world_pos).mul(owner_rot.toMat4()).mul(delve.math.Mat4.scale(delve.math.Vec3.one.scale(mesh_comp.scale)));

                mesh.material.state.params.lighting = render_state.lighting;
                mesh.material.state.params.fog = render_state.fog;
                mesh.draw(render_state.view_mats, model);
            }
        }
    }

    fn drawSpriteComponents(self: *RenderInstance, game_instance: *game.GameInstance, render_state: RenderState) void {
        const player_controller = game_instance.player_controller.?;
        const camera = &player_controller.camera;

        // set up a matrix that will billboard to face the camera, but ignore the up dir
        // const billboard_dir = math.Vec3.new(camera.direction.x, 0, camera.direction.z).norm();
        const billboard_dir = camera.direction.scale(-1);
        const billboard_full_rot_matrix = math.Mat4.billboard(billboard_dir, camera.up);
        const billboard_xz_rot_matrix = math.Mat4.billboard(billboard_dir.mul(delve.math.Vec3.new(1.0, 0.0, 1.0)), camera.up);

        var sprite_count: i32 = 0;

        // Update lighting for spritesheets
        var spritesheet_it = spritesheets.sprite_sheets.iterator();
        while (spritesheet_it.next()) |kv| {
            const spritesheet = kv.value_ptr;

            // Update the lighting and fog states for our spritesheet materials
            spritesheet.material.state.params.lighting = render_state.lighting;
            spritesheet.material.state.params.fog = render_state.fog;
            spritesheet.material_blend.state.params.lighting = render_state.lighting;
            spritesheet.material_blend.state.params.fog = render_state.fog;
        }

        var sprite_iterator = sprites.getComponentStorage(game_instance.world).iterator();
        while (sprite_iterator.next()) |sprite| {
            if (!sprite.visible)
                continue;

            // Either use the given material, or one from the spritesheet
            if (sprite.material) |material| {
                material.state.params.lighting = render_state.lighting;
                material.state.params.fog = render_state.fog;
                self.sprite_batch.useMaterial(material);
            } else {
                // No material, use the spritesheet if one is found
                const spritesheet_opt = sprite._spritesheet;
                if (spritesheet_opt == null)
                    continue;

                const opaque_material = if (sprite.use_lighting) spritesheet_opt.?.material else spritesheet_opt.?.material_unlit;
                const blend_material = if (sprite.use_lighting) spritesheet_opt.?.material_blend else spritesheet_opt.?.material_blend_unlit;
                switch (sprite.blend_mode) {
                    .OPAQUE => self.sprite_batch.useMaterial(opaque_material),
                    .ALPHA => self.sprite_batch.useMaterial(blend_material),
                }

                if (sprite.flash_timer > 0.0) {
                    self.sprite_batch.useMaterial(spritesheet_opt.?.material_flash);
                }
            }

            sprite_count += 1;

            if (sprite.billboard_type == .XZ) {
                self.sprite_batch.setTransformMatrix(math.Mat4.translate(sprite.world_position.add(sprite.position_offset)).mul(billboard_xz_rot_matrix));
            } else if (sprite.billboard_type == .XYZ) {
                self.sprite_batch.setTransformMatrix(math.Mat4.translate(sprite.world_position.add(sprite.position_offset)).mul(billboard_full_rot_matrix));
            } else {
                self.sprite_batch.setTransformMatrix(math.Mat4.translate(sprite.world_position.add(sprite.position_offset)).mul(sprite.rotation_offset.toMat4()));
            }

            self.sprite_batch.addRectangle(sprite.draw_rect.centered(), sprite.draw_tex_region, sprite.color);
        }

        // delve.debug.log("Drew {d} sprites", .{sprite_count});
    }

    fn drawTextComponents(self: *RenderInstance, game_instance: *game.GameInstance, render_state: RenderState) void {
        _ = render_state;
        var text_it = text.getComponentStorage(game_instance.world).iterator();
        while (text_it.next()) |text_comp| {
            const found_font = delve.fonts.getLoadedFont("KodeMono");
            if (found_font) |font| {
                var x_pos: f32 = 0;
                var y_pos: f32 = 0;
                self.sprite_batch.setTransformMatrix(math.Mat4.translate(text_comp.owner.getRenderPosition()).mul(text_comp.owner.getRotation().toMat4()));

                if (text_comp._spritesheet) |sheet| {
                    self.sprite_batch.useMaterial(sheet.material_blend);
                } else {
                    self.sprite_batch.useShader(self.sprite_shader_blend);
                    self.sprite_batch.useTexture(font.texture);
                }

                addStringToSpriteBatch(font, &self.sprite_batch, text_comp.text.str, &x_pos, &y_pos, 0.01 * text_comp.scale, delve.colors.white);
            } else {
                delve.debug.log("Could not find font to draw text component!", .{});
            }
        }
    }

    pub fn addStringToSpriteBatch(font: *delve.fonts.LoadedFont, sprite_batch: *batcher.SpriteBatcher, string: []const u8, x_pos: *f32, y_pos: *f32, scale: f32, color: delve.colors.Color) void {
        addStringToSpriteBatchWithKerning(font, sprite_batch, string, x_pos, y_pos, 0, 0, scale, color);
    }

    pub fn addStringToSpriteBatchWithKerning(font: *delve.fonts.LoadedFont, sprite_batch: *batcher.SpriteBatcher, string: []const u8, x_pos: *f32, y_pos: *f32, line_height_mod: f32, kerning_mod: f32, scale: f32, color: delve.colors.Color) void {
        const orig_x: f32 = x_pos.*;

        for (string) |char| {
            if (char == '\n') {
                x_pos.* = orig_x;
                y_pos.* += font.font_size + line_height_mod;
                continue;
            }

            const char_quad_t = delve.fonts.getCharQuad(font, char - 32, x_pos, y_pos);
            sprite_batch.addRectangle(char_quad_t.rect.scale(scale), char_quad_t.tex_region, color);
            x_pos.* += kerning_mod;
        }

        x_pos.* = orig_x;
        y_pos.* += font.font_size + line_height_mod;
    }

    fn drawParticleEmitterComponents(self: *RenderInstance, game_instance: *game.GameInstance, render_state: RenderState) void {
        _ = render_state;

        const player_controller = game_instance.player_controller.?;
        const camera = &player_controller.camera;

        // set up a matrix that will billboard to face the camera, but ignore the up dir
        // const billboard_dir = math.Vec3.new(camera.direction.x, 0, camera.direction.z).norm();
        const billboard_dir = math.Vec3.new(camera.direction.x, camera.direction.y, camera.direction.z).norm();
        const billboard_full_rot_matrix = math.Mat4.billboard(billboard_dir, camera.up);
        const billboard_xz_rot_matrix = math.Mat4.billboard(billboard_dir.mul(delve.math.Vec3.new(1.0, 0.0, 1.0)), camera.up);

        var sprite_count: i32 = 0;
        const fixed_timestep_lerp = delve.platform.app.getFixedTimestepLerp(false);

        const particles_opt = emitters.particle_storage.getPtr(game_instance.world.id);
        if (particles_opt == null) {
            return;
        }

        const particles = particles_opt.?;
        var particle_iterator = particles.iterator(0);
        while (particle_iterator.next()) |particle| {
            // only draw alive particles
            if (!particle.is_alive)
                continue;

            const sprite: *sprites.SpriteComponent = &particle.sprite;
            const spritesheet_opt = sprite._spritesheet;
            if (spritesheet_opt == null) {
                continue;
            }

            const opaque_material = if (sprite.use_lighting) spritesheet_opt.?.material else spritesheet_opt.?.material_unlit;
            const blend_material = if (sprite.use_lighting) spritesheet_opt.?.material_blend else spritesheet_opt.?.material_blend_unlit;
            switch (sprite.blend_mode) {
                .OPAQUE => self.sprite_batch.useMaterial(opaque_material),
                .ALPHA => self.sprite_batch.useMaterial(blend_material),
            }

            // pixel scale
            const scale = particle.sprite.scale;
            const scale_mat = math.Mat4.scale(math.Vec3.one.scale(scale));

            defer sprite_count += 1;

            const next_draw_pos = sprite.world_position.add(sprite.position_offset);
            const last_draw_pos = sprite._last_world_position.add(sprite.position_offset);
            const draw_pos = math.Vec3.lerp(last_draw_pos, next_draw_pos, fixed_timestep_lerp);

            if (sprite.billboard_type == .XZ) {
                self.sprite_batch.setTransformMatrix(math.Mat4.translate(draw_pos).mul(billboard_xz_rot_matrix).mul(scale_mat));
            } else {
                self.sprite_batch.setTransformMatrix(math.Mat4.translate(draw_pos).mul(billboard_full_rot_matrix).mul(scale_mat));
            }
            self.sprite_batch.addRectangle(sprite.draw_rect.centered(), sprite.draw_tex_region, sprite.color);
        }

        // delve.debug.log("Drew {d} sprites", .{ sprite_count });
    }

    fn drawHud(self: *RenderInstance, game_instance: *game.GameInstance) void {
        const spritesheet_opt = spritesheets.getSpriteSheet("sprites/blank");
        if (spritesheet_opt == null)
            return;

        if (game_instance.player_controller == null)
            return;

        const player = game_instance.player_controller.?;
        var ui_alpha: f32 = 1.0;

        // draw the screen flash
        if (game_instance.player_controller.?.screen_flash_color) |flash_color| {
            if (player.screen_flash_time > 0.0) {
                var flash_color_adj = flash_color;
                const flash_a = player.screen_flash_timer / player.screen_flash_time;
                flash_color_adj.a *= delve.utils.interpolation.EaseQuad.applyIn(0.0, 1.0, flash_a);

                // add our flash overlay rectangle
                const rect = delve.spatial.Rect.new(math.Vec2.new(0, 0), math.Vec2.new(self.width_f, self.height_f));
                self.ui_batch.useTexture(spritesheet_opt.?.texture);
                self.ui_batch.useShader(self.sprite_shader_blend);
                self.ui_batch.addRectangle(rect.centered(), .{}, flash_color_adj);

                // If we're fading from a full color, also fade the UI
                if (flash_color.a == 1.0)
                    ui_alpha = 1.0 - flash_a;
            }
        }

        // draw health and ammo!
        var health_text_buffer: [8:0]u8 = .{0} ** 8;
        var ammo_text_buffer: [8:0]u8 = .{0} ** 8;

        var health_text_color: delve.colors.Color = delve.colors.Color.new(0.9, 0.9, 0.9, ui_alpha);
        const ammo_text_color: delve.colors.Color = delve.colors.Color.new(0.9, 0.9, 0.9, ui_alpha);

        if (player.owner.getComponent(actor_stats.ActorStats)) |s| {
            _ = std.fmt.bufPrint(&health_text_buffer, "{}", .{s.hp}) catch {
                return;
            };

            if (s.hp <= 20)
                health_text_color = delve.colors.Color.new(0.9, 0.2, 0.2, 1.0);
        }

        var draw_ammo: bool = true;
        if (player.owner.getComponent(weapon.WeaponComponent)) |w| {
            draw_ammo = w.uses_ammo;
            if (draw_ammo) {
                const ammo_count = w.getAmmoCount();
                _ = std.fmt.bufPrint(&ammo_text_buffer, "{}", .{ammo_count}) catch {
                    return;
                };
            }
        }

        const ammo_text_x: f32 = @floatFromInt(delve.platform.app.getWidth() - 40 * 3);
        const text_y: f32 = @floatFromInt(delve.platform.app.getHeight() - 42);

        delve.platform.graphics.setDebugTextScale(2.25);

        // draw health
        delve.platform.graphics.setDebugTextColor(health_text_color);
        delve.platform.graphics.drawDebugText(4.0, text_y, &health_text_buffer);

        //draw ammo
        if (draw_ammo) {
            delve.platform.graphics.setDebugTextColor(ammo_text_color);
            delve.platform.graphics.drawDebugText(ammo_text_x, text_y, &ammo_text_buffer);
        }

        var message_y_pos: usize = 0;
        if (player._msg_time > 0.0 and player._message[0] != 0) {
            const msg = player._message;
            var msg_len: usize = 0;
            for (msg, 0..) |c, idx| {
                if (c == 0) {
                    msg_len = idx;
                    break;
                }
            }

            if (msg_len > 0) {
                const m = msg[0..msg_len :0];
                const msg_len_f: f32 = @floatFromInt(msg_len);
                const draw_x: f32 = @as(f32, @floatFromInt(delve.platform.app.getWidth())) / 2.0;
                const draw_y: f32 = @as(f32, @floatFromInt(delve.platform.app.getHeight())) / 2.0;

                delve.platform.graphics.setDebugTextScale(1.0);
                delve.platform.graphics.drawDebugText(draw_x - (msg_len_f * 16) * 0.5, draw_y + @as(f32, @floatFromInt(message_y_pos)), m);
                message_y_pos += 22;
            }
        }

        // draw ui sprites
        const projection = graphics.getProjectionPerspective(60, 0.01, 20.0);
        const view = delve.math.Mat4.lookat(.{ .x = 0.0, .y = 0.0, .z = 0.02 }, delve.math.Vec3.zero, delve.math.Vec3.up);
        self.ui_batch.apply();
        self.ui_batch.draw(.{ .view = view, .proj = projection }, math.Mat4.identity);
    }

    fn addLightsFromLightComponents(self: *RenderInstance, game_instance: *game.GameInstance) void {
        if (game_instance.player_controller == null)
            return;

        const player_controller = game_instance.player_controller.?;
        const camera = &player_controller.camera;
        const viewFrustum = camera.getViewFrustum();
        const max_light_dist: f32 = 70.0;

        var light_it = lights.getComponentStorage(game_instance.world).iterator();
        while (light_it.next()) |light| {
            if (!light.is_on or light.brightness <= 0.0 or light.radius <= 0.0)
                continue;

            const light_dist = light.world_position.sub(camera.position).len();
            const light_radius_adj = if (light_dist > max_light_dist) (light_dist - max_light_dist) * 0.35 else 0;

            const point_light: delve.platform.graphics.PointLight = .{
                .pos = light.world_position,
                .radius = light.radius - light_radius_adj,
                .color = light.color,
                .brightness = light.brightness,
            };

            // might have adjusted the radius based on distance!
            if (point_light.radius <= 0.0)
                continue;

            const in_frustum = viewFrustum.containsSphere(point_light.pos, point_light.radius * 0.7);
            if (!in_frustum) {
                continue;
            }

            self.lights.append(point_light) catch {};
        }

        // delve.debug.log("Num lights: {d}", .{self.lights.items.len});
    }
};

// sort lights based on distance and light radius
fn compareLights(camera: *Camera, lhs: delve.platform.graphics.PointLight, rhs: delve.platform.graphics.PointLight) bool {
    const rhs_dist = camera.position.sub(rhs.pos).len();
    const lhs_dist = camera.position.sub(lhs.pos).len();

    const rhs_mod = (rhs.radius * rhs.radius) * 0.005;
    const lhs_mod = (lhs.radius * lhs.radius) * 0.005;

    return rhs_dist - rhs_mod >= lhs_dist - lhs_mod;
}

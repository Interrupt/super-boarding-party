const std = @import("std");
const delve = @import("delve");
const game = @import("game.zig");
const entities = @import("entities.zig");
const quakemap = @import("../entities/quakemap.zig");
const quakesolids = @import("../entities/quakesolids.zig");
const sprites = @import("../entities/sprite.zig");
const lights = @import("../entities/light.zig");
const actor_stats = @import("../entities/actor_stats.zig");
const emitters = @import("../entities/particle_emitter.zig");
const spritesheets = @import("../utils/spritesheet.zig");

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
};

pub const RenderInstance = struct {
    allocator: std.mem.Allocator,
    lights: std.ArrayList(graphics.PointLight),
    sprite_batch: batcher.SpriteBatcher,
    ui_batch: batcher.SpriteBatcher,
    debug_draw_commands: std.ArrayList(DebugDrawCommand),

    sprite_shader_opaque: graphics.Shader,
    sprite_shader_blend: graphics.Shader,

    pub fn init(allocator: std.mem.Allocator) !RenderInstance {
        if (!did_init) {
            const debug_shader = try graphics.Shader.initDefault(.{ .vertex_attributes = delve.graphics.mesh.getShaderAttributes() });
            debug_material = try graphics.Material.init(.{
                .shader = debug_shader,
                .texture_0 = graphics.createSolidTexture(0xFFFFFFFF),
                .samplers = &[_]graphics.FilterMode{.NEAREST},
            });

            const debug_cube_mesh_size = math.Vec3.new(1, 1, 1);
            debug_cube_mesh = try delve.graphics.mesh.createCube(math.Vec3.new(0, 0, 0), debug_cube_mesh_size, delve.colors.white, debug_material);

            // preload some assets!
            _ = try spritesheets.loadSpriteSheet("sprites/entities", "assets/sprites/entities.png", 16, 8);
            _ = try spritesheets.loadSpriteSheet("sprites/items", "assets/sprites/items.png", 4, 8);
            _ = try spritesheets.loadSpriteSheet("sprites/particles", "assets/sprites/particles.png", 8, 4);
            _ = try spritesheets.loadSpriteSheet("sprites/sprites", "assets/sprites/sprites.png", 8, 4);
            _ = try spritesheets.loadSpriteSheet("sprites/blank", "assets/sprites/blank.png", 4, 4);
        }

        return .{
            .allocator = allocator,
            .lights = std.ArrayList(delve.platform.graphics.PointLight).init(allocator),
            .sprite_batch = try batcher.SpriteBatcher.init(.{}),
            .ui_batch = try batcher.SpriteBatcher.init(.{}),
            .debug_draw_commands = std.ArrayList(DebugDrawCommand).init(allocator),

            // sprite shaders
            .sprite_shader_opaque = try graphics.Shader.initDefault(.{}),
            .sprite_shader_blend = try graphics.Shader.initDefault(.{ .blend_mode = graphics.BlendMode.BLEND, .depth_write_enabled = false }),
        };
    }

    pub fn deinit(self: *RenderInstance) void {
        _ = self;
        delve.debug.log("Render instance tearing down", .{});
    }

    /// Called right before drawing
    pub fn update(self: *RenderInstance, game_instance: *game.GameInstance) void {
        // Go collect all of the lights
        self.lights.clearRetainingCapacity();

        var map_it = quakemap.getComponentStorage(game_instance.world).iterator();
        while (map_it.next()) |map| {
            self.lights.appendSlice(map.lights.items) catch {};
        }

        // gather lights from LightComponents
        self.addLightsFromLightComponents(game_instance);

        // reset sprite batches
        self.sprite_batch.reset();
        self.ui_batch.reset();
    }

    /// Actual draw function
    pub fn draw(self: *RenderInstance, game_instance: *game.GameInstance) void {
        if (game_instance.player_controller == null)
            return;

        const player_controller = game_instance.player_controller.?;

        const camera = &player_controller.camera;
        const view_mats = camera.update();

        var fog: delve.platform.graphics.MaterialFogParams = .{};
        var lighting: delve.platform.graphics.MaterialLightParams = .{};

        // make a skylight and a light for the player
        const directional_light: delve.platform.graphics.DirectionalLight = .{
            .dir = delve.math.Vec3.new(0.2, 0.8, 0.1).norm(),
            .color = delve.colors.white,
            .brightness = 0.5,
        };

        const ambient_light = directional_light.color.scale(0.2);

        // final list of point lights for the materials
        const max_lights: usize = 16;
        var point_lights: [max_lights]delve.platform.graphics.PointLight = [_]delve.platform.graphics.PointLight{.{ .color = delve.colors.black }} ** max_lights;

        // sort the level's lights, and make sure they are actually visible before putting in the final list
        std.sort.insertion(delve.platform.graphics.PointLight, self.lights.items, camera, compareLights);

        var num_lights: usize = 0;
        for (0..self.lights.items.len) |i| {
            if (num_lights >= max_lights)
                break;

            const viewFrustum = camera.getViewFrustum();
            const in_frustum = viewFrustum.containsSphere(self.lights.items[i].pos, self.lights.items[i].radius * 0.5);

            if (!in_frustum)
                continue;

            point_lights[num_lights] = self.lights.items[i];
            num_lights += 1;
        }

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

        // Now we can draw the world
        self.drawQuakeMapComponents(game_instance, .{ .view_mats = view_mats, .lighting = lighting, .fog = fog });
        self.drawQuakeSolidsComponents(game_instance, .{ .view_mats = view_mats, .lighting = lighting, .fog = fog });

        // Next draw any sprites
        self.drawSpriteComponents(game_instance, .{ .view_mats = view_mats, .lighting = lighting, .fog = fog });

        // And draw particle emitters next
        self.drawParticleEmitterComponents(game_instance, .{ .view_mats = view_mats, .lighting = lighting, .fog = fog });

        // Draw our final sprite batch
        self.sprite_batch.apply();
        self.sprite_batch.draw(view_mats, math.Mat4.identity);

        self.drawHud(game_instance);

        // Draw any debug info we have
        for (self.debug_draw_commands.items) |draw_cmd| {
            var material = debug_material;
            material.state.params.draw_color = draw_cmd.color;

            draw_cmd.mesh.drawWithMaterial(material, view_mats, draw_cmd.transform);
        }
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
        _ = self;

        var map_it = quakemap.getComponentStorage(game_instance.world).iterator();
        while (map_it.next()) |map| {
            // draw the world solids!
            for (map.map_meshes.items) |*mesh| {
                const model = delve.math.Mat4.identity;
                mesh.material.state.params.lighting = render_state.lighting;
                mesh.material.state.params.fog = render_state.fog;
                mesh.draw(render_state.view_mats, model);
            }

            // and also entity solids
            // for (map.entity_meshes.items) |*mesh| {
            //     const model = delve.math.Mat4.identity;
            //     mesh.material.state.params.lighting = render_state.lighting;
            //     mesh.material.state.params.fog = render_state.fog;
            //     mesh.draw(render_state.view_mats, model);
            // }
        }
    }

    fn drawQuakeSolidsComponents(self: *RenderInstance, game_instance: *game.GameInstance, render_state: RenderState) void {
        _ = self;

        var solids_it = quakesolids.getComponentStorage(game_instance.world).iterator();
        while (solids_it.next()) |solids| {
            // draw the world solids!
            for (solids.meshes.items) |*mesh| {
                const model = delve.math.Mat4.translate(solids.owner.getPosition().sub(solids.starting_pos));
                mesh.material.state.params.lighting = render_state.lighting;
                mesh.material.state.params.fog = render_state.fog;
                mesh.draw(render_state.view_mats, model);
            }
        }
    }

    fn drawSpriteComponents(self: *RenderInstance, game_instance: *game.GameInstance, render_state: RenderState) void {
        _ = render_state;

        const player_controller = game_instance.player_controller.?;
        const camera = &player_controller.camera;

        // set up a matrix that will billboard to face the camera, but ignore the up dir
        // const billboard_dir = math.Vec3.new(camera.direction.x, 0, camera.direction.z).norm();
        const billboard_dir = math.Vec3.new(camera.direction.x, camera.direction.y, camera.direction.z).norm();
        const billboard_full_rot_matrix = math.Mat4.billboard(billboard_dir, camera.up);
        const billboard_xz_rot_matrix = math.Mat4.billboard(billboard_dir.mul(delve.math.Vec3.new(1.0, 0.0, 1.0)), camera.up);

        var sprite_count: i32 = 0;

        var sprite_iterator = sprites.getComponentStorage(game_instance.world).iterator();
        while (sprite_iterator.next()) |sprite| {
            const spritesheet_opt = spritesheets.getSpriteSheet(sprite.spritesheet);
            if (spritesheet_opt == null)
                continue;

            defer sprite_count += 1;

            switch (sprite.blend_mode) {
                .OPAQUE => self.sprite_batch.useMaterial(spritesheet_opt.?.material),
                .ALPHA => self.sprite_batch.useMaterial(spritesheet_opt.?.material_blend),
            }

            if (sprite.flash_timer > 0.0) {
                self.sprite_batch.useMaterial(spritesheet_opt.?.material_flash);
            }

            if (sprite.billboard_type == .XZ) {
                self.sprite_batch.setTransformMatrix(math.Mat4.translate(sprite.world_position.add(sprite.position_offset)).mul(billboard_xz_rot_matrix));
            } else if (sprite.billboard_type == .XYZ) {
                self.sprite_batch.setTransformMatrix(math.Mat4.translate(sprite.world_position.add(sprite.position_offset)).mul(billboard_full_rot_matrix));
            } else {
                self.sprite_batch.setTransformMatrix(math.Mat4.translate(sprite.world_position.add(sprite.position_offset)).mul(sprite.rotation_offset.toMat4()));
            }

            self.sprite_batch.addRectangle(sprite.draw_rect.centered(), sprite.draw_tex_region, sprite.color);
        }

        // delve.debug.log("Drew {d} sprites", .{ sprite_count });
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

        var emitter_iterator = emitters.getComponentStorage(game_instance.world).iterator();
        while (emitter_iterator.next()) |emitter| {
            var particle_iterator = emitter.particles.iterator(0);
            while (particle_iterator.next()) |particle| {
                // only draw alive particles
                if (!particle.is_alive)
                    continue;

                const sprite: *sprites.SpriteComponent = &particle.sprite;
                const spritesheet_opt = spritesheets.getSpriteSheet(sprite.spritesheet);
                if (spritesheet_opt == null) {
                    continue;
                }

                // pixel scale
                const scale = particle.sprite.scale;
                const scale_mat = math.Mat4.scale(math.Vec3.one.scale(scale));

                defer sprite_count += 1;
                self.sprite_batch.useTexture(spritesheet_opt.?.texture);
                if (sprite.billboard_type == .XZ) {
                    self.sprite_batch.setTransformMatrix(math.Mat4.translate(sprite.world_position.add(sprite.position_offset)).mul(billboard_xz_rot_matrix).mul(scale_mat));
                } else {
                    self.sprite_batch.setTransformMatrix(math.Mat4.translate(sprite.world_position.add(sprite.position_offset)).mul(billboard_full_rot_matrix).mul(scale_mat));
                }
                self.sprite_batch.addRectangle(sprite.draw_rect.centered(), sprite.draw_tex_region, sprite.color);
            }
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

        // draw the screen flash

        if (game_instance.player_controller.?.screen_flash_color) |flash_color| {
            if (player.screen_flash_time > 0.0) {
                var flash_color_adj = flash_color;
                const flash_a = player.screen_flash_timer / player.screen_flash_time;
                flash_color_adj.a *= delve.utils.interpolation.EaseQuad.applyIn(0.0, 1.0, flash_a);

                // add our flash overlay rectangle
                const rect = delve.spatial.Rect.new(math.Vec2.new(0, 0), math.Vec2.new(1024.0, 768.0));
                self.ui_batch.useTexture(spritesheet_opt.?.texture);
                self.ui_batch.useShader(self.sprite_shader_blend);
                self.ui_batch.addRectangle(rect.centered(), .{}, flash_color_adj);
            }
        }

        // draw health!
        if (player.owner.getComponent(actor_stats.ActorStats)) |s| {
            var health_text_buffer: [8:0]u8 = .{0} ** 8;
            _ = std.fmt.bufPrint(&health_text_buffer, "{}", .{s.hp}) catch {
                return;
            };

            delve.platform.graphics.setDebugTextScale(2.25);

            if (s.hp > 20) {
                delve.platform.graphics.setDebugTextColor(delve.colors.Color.new(0.9, 0.9, 0.9, 1.0));
            } else {
                delve.platform.graphics.setDebugTextColor(delve.colors.Color.new(0.9, 0.2, 0.2, 1.0));
            }

            delve.platform.graphics.drawDebugText(4.0, 480.0, &health_text_buffer);
        }

        var message_y_pos: usize = 0;
        for (player._messages.items) |msg| {
            var msg_len: usize = 0;
            for (msg, 0..) |c, idx| {
                if (c == 0) {
                    msg_len = idx;
                    break;
                }
            }

            if (msg_len > 0) {
                const m = msg[0..msg_len :0];
                delve.platform.graphics.setDebugTextScale(1.0);
                delve.platform.graphics.drawDebugText(240.0, 250.0 + @as(f32, @floatFromInt(message_y_pos)), m);
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
        var light_it = lights.getComponentStorage(game_instance.world).iterator();
        while (light_it.next()) |light| {
            if (light.brightness <= 0.0 or light.radius <= 0.0)
                continue;

            const point_light: delve.platform.graphics.PointLight = .{
                .pos = light.world_position,
                .radius = light.radius,
                .color = light.color,
                .brightness = light.brightness,
            };

            self.lights.append(point_light) catch {};
        }
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

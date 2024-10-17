const std = @import("std");
const delve = @import("delve");
const game = @import("game.zig");
const entities = @import("entities.zig");
const quakemap = @import("../entities/quakemap.zig");
const sprites = @import("../entities/sprite.zig");

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
    debug_draw_commands: std.ArrayList(DebugDrawCommand),

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
        }

        return .{
            .allocator = allocator,
            .lights = std.ArrayList(delve.platform.graphics.PointLight).init(allocator),
            .sprite_batch = try batcher.SpriteBatcher.init(.{}),
            .debug_draw_commands = std.ArrayList(DebugDrawCommand).init(allocator),
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

        var map_it = quakemap.getComponentStorage(&game_instance.world).iterator();
        while (map_it.next()) |map| {
            self.lights.appendSlice(map.lights.items) catch {};
        }

        // reset sprite batch
        self.sprite_batch.reset();
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

        // get the dynamic lights
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
        std.sort.insertion(delve.platform.graphics.PointLight, self.lights.items, camera, compareLights);

        var num_lights: usize = 1;
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

        // Next draw any sprites
        self.drawSpriteComponents(game_instance, .{ .view_mats = view_mats, .lighting = lighting, .fog = fog });

        // Draw our final sprite batch
        self.sprite_batch.apply();
        self.sprite_batch.draw(view_mats, math.Mat4.identity);

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

        var map_it = quakemap.getComponentStorage(&game_instance.world).iterator();
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

    fn drawSpriteComponents(self: *RenderInstance, game_instance: *game.GameInstance, render_state: RenderState) void {
        _ = render_state;

        const player_controller = game_instance.player_controller.?;
        const camera = &player_controller.camera;

        // set up a matrix that will billboard to face the camera, but ignore the up dir
        const billboard_dir = math.Vec3.new(camera.direction.x, 0, camera.direction.z).norm();
        const rot_matrix = math.Mat4.billboard(billboard_dir, camera.up);

        var sprite_count: i32 = 0;

        var sprite_iterator = sprites.getComponentStorage(&game_instance.world).iterator();
        while (sprite_iterator.next()) |sprite| {
            defer sprite_count += 1;
            self.sprite_batch.useTexture(sprite.texture);
            self.sprite_batch.setTransformMatrix(math.Mat4.translate(sprite.world_position.add(sprite.position_offset)).mul(rot_matrix));
            self.sprite_batch.addRectangle(sprite.draw_rect.centered(), sprite.draw_tex_region, sprite.color);
        }

        // delve.debug.log("Drew {d} sprites", .{ sprite_count });
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

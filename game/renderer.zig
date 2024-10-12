const std = @import("std");
const delve = @import("delve");
const game = @import("game.zig");
const world = @import("entities/world.zig");

const math = delve.math;
const graphics = delve.platform.graphics;

const Camera = delve.graphics.camera.Camera;

var did_init: bool = false;
var debug_material: graphics.Material = undefined;
var debug_cube_mesh: delve.graphics.mesh.Mesh = undefined;

const RenderState = struct {
    view_mats: graphics.CameraMatrices,
    fog: graphics.MaterialFogParams = .{},
    lighting: graphics.MaterialLightParams = .{},
};

pub const RenderInstance = struct {
    allocator: std.mem.Allocator,
    lights: std.ArrayList(graphics.PointLight),
    debug_cubes: std.ArrayList(math.Vec3),

    pub fn init(allocator: std.mem.Allocator) !RenderInstance {
        if (!did_init) {
            const debug_shader = try graphics.Shader.initDefault(.{ .vertex_attributes = delve.graphics.mesh.getShaderAttributes() });
            debug_material = try graphics.Material.init(.{
                .shader = debug_shader,
                .texture_0 = graphics.createDebugTexture(),
                .samplers = &[_]graphics.FilterMode{.NEAREST},
            });

            const debug_cube_mesh_size = math.Vec3.new(1, 1, 1);
            debug_cube_mesh = try delve.graphics.mesh.createCube(math.Vec3.new(0, 0, 0), debug_cube_mesh_size, delve.colors.red, debug_material);
        }

        return .{
            .allocator = allocator,
            .lights = std.ArrayList(delve.platform.graphics.PointLight).init(allocator),
            .debug_cubes = std.ArrayList(math.Vec3).init(allocator),
        };
    }

    pub fn deinit(self: *RenderInstance) void {
        _ = self;
        delve.debug.log("Render instance tearing down", .{});
    }

    pub fn update(self: *RenderInstance, game_instance: *game.GameInstance) void {
        // Go collect all of the lights
        self.lights.clearRetainingCapacity();

        for (game_instance.game_entities.items) |*e| {
            if (e.getSceneComponent(world.QuakeMapComponent)) |map| {
                self.lights.appendSlice(map.lights.items) catch {};
            }
        }
    }

    pub fn draw(self: *RenderInstance, game_instance: *game.GameInstance) void {
        if (game_instance.player_controller == null)
            return;

        const camera = &game_instance.player_controller.?.camera;
        const view_mats = camera.update();

        const fog: delve.platform.graphics.MaterialFogParams = .{};
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

        // set the lighting material params
        lighting.point_lights = &point_lights;
        lighting.directional_light = directional_light;
        lighting.ambient_light = ambient_light;

        // now we can draw the world
        drawQuakeMapComponents(game_instance, .{ .view_mats = view_mats, .lighting = lighting, .fog = fog });

        // Draw any debug info we have
        for (self.debug_cubes.items) |pos| {
            // delve.debug.log("Drawing debug cube at: {d:1} {d:1} {d:1}", .{ pos.x, pos.y, pos.z });
            debug_cube_mesh.draw(view_mats, math.Mat4.translate(pos));
        }
        self.debug_cubes.clearRetainingCapacity();
    }

    pub fn drawDebugCube(self: *RenderInstance, pos: math.Vec3) void {
        self.debug_cubes.append(pos) catch {};
    }
};

fn drawQuakeMapComponents(game_instance: *game.GameInstance, render_state: RenderState) void {
    for (game_instance.game_entities.items) |*e| {
        if (e.getSceneComponent(world.QuakeMapComponent)) |map| {
            // draw the world solids!
            for (map.map_meshes.items) |*mesh| {
                const model = delve.math.Mat4.identity;
                mesh.material.state.params.lighting = render_state.lighting;
                mesh.material.state.params.fog = render_state.fog;
                mesh.draw(render_state.view_mats, model);
            }

            // and also entity solids
            for (map.entity_meshes.items) |*mesh| {
                const model = delve.math.Mat4.identity;
                mesh.material.state.params.lighting = render_state.lighting;
                mesh.material.state.params.fog = render_state.fog;
                mesh.draw(render_state.view_mats, model);
            }
        }
    }
}

// sort lights based on distance and light radius
fn compareLights(camera: *Camera, lhs: delve.platform.graphics.PointLight, rhs: delve.platform.graphics.PointLight) bool {
    const rhs_dist = camera.position.sub(rhs.pos).len();
    const lhs_dist = camera.position.sub(lhs.pos).len();

    const rhs_mod = (rhs.radius * rhs.radius) * 0.005;
    const lhs_mod = (lhs.radius * lhs.radius) * 0.005;

    return rhs_dist - rhs_mod >= lhs_dist - lhs_mod;
}

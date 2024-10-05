const std = @import("std");
const collision = @import("collision.zig");
const delve = @import("delve");
const player = @import("game/entities/player.zig");
const app = delve.app;

const game = @import("game/game.zig");
const renderer = @import("game/renderer.zig");

const graphics = delve.platform.graphics;
const math = delve.math;

var entity_allocator = std.heap.GeneralPurposeAllocator(.{}){};
pub var game_instance: game.GameInstance = undefined;
pub var render_instance: renderer.RenderInstance = undefined;

var camera: delve.graphics.camera.Camera = undefined;
var fallback_material: graphics.Material = undefined;

var time: f64 = 0.0;

// the quake map
var quake_map: delve.utils.quakemap.QuakeMap = undefined;

// meshes for drawing
var map_meshes: std.ArrayList(delve.graphics.mesh.Mesh) = undefined;
var entity_meshes: std.ArrayList(delve.graphics.mesh.Mesh) = undefined;
var cube_mesh: delve.graphics.mesh.Mesh = undefined;

// quake maps load at a different scale and rotation - adjust for that
var map_transform: math.Mat4 = undefined;

// materials!
var fallback_quake_material: delve.utils.quakemap.QuakeMaterial = undefined;
var materials: std.StringHashMap(delve.utils.quakemap.QuakeMaterial) = undefined;

// lights!
var lights: std.ArrayList(delve.platform.graphics.PointLight) = undefined;

var fog: delve.platform.graphics.MaterialFogParams = .{};
var lighting: delve.platform.graphics.MaterialLightParams = .{};

// shader setup
const lit_shader = delve.shaders.default_basic_lighting;
const basic_lighting_fs_uniforms: []const delve.platform.graphics.MaterialUniformDefaults = &[_]delve.platform.graphics.MaterialUniformDefaults{ .CAMERA_POSITION, .COLOR_OVERRIDE, .ALPHA_CUTOFF, .AMBIENT_LIGHT, .DIRECTIONAL_LIGHT, .POINT_LIGHTS_16, .FOG_DATA };

pub fn main() !void {
    const example = delve.modules.Module{
        .name = "main_module",
        .init_fn = on_init,
        .tick_fn = on_tick,
        .draw_fn = on_draw,
        .cleanup_fn = on_cleanup,
    };

    // Pick the allocator to use depending on platform
    const builtin = @import("builtin");
    if (builtin.os.tag == .wasi or builtin.os.tag == .emscripten) {
        // Web builds hack: use the C allocator to avoid OOM errors
        // See https://github.com/ziglang/zig/issues/19072
        try delve.init(std.heap.c_allocator);
    } else {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        try delve.init(gpa.allocator());
    }

    try delve.modules.registerModule(example);
    try delve.module.fps_counter.registerModule();

    // register some console commands
    try delve.debug.registerConsoleCommand("noclip", cvar_toggleNoclip, "Toggle noclip");
    try delve.debug.registerConsoleCommand("fly", cvar_toggleFlyMode, "Toggle flying");

    // and some console variables
    try delve.debug.registerConsoleVariable("p.speed", &player.move_speed, "Player move speed");
    try delve.debug.registerConsoleVariable("p.acceleration", &player.ground_acceleration, "Player move acceleration");
    try delve.debug.registerConsoleVariable("p.groundfriction", &player.friction, "Player ground friction");
    try delve.debug.registerConsoleVariable("p.airfriction", &player.air_friction, "Player air friction");
    try delve.debug.registerConsoleVariable("p.waterfriction", &player.water_friction, "Player water friction");
    try delve.debug.registerConsoleVariable("p.jump", &player.jump_acceleration, "Player jump acceleration");

    try app.start(app.AppConfig{ .title = "Super Boarding Party Pro", .sampler_pool_size = 512, .buffer_pool_size = 4096 });
}

pub fn on_init() !void {
    // use the Delve Framework global allocator
    const allocator = delve.mem.getAllocator();
    game_instance = game.GameInstance.init(allocator);
    render_instance = renderer.RenderInstance.init(allocator);

    // do some setup
    delve.platform.graphics.setClearColor(delve.colors.examples_bg_dark);
    delve.platform.app.captureMouse(true);

    try game_instance.start();
}

pub fn on_cleanup() !void {
    game_instance.deinit();
    render_instance.deinit();
}

pub fn on_tick(delta: f32) void {
    if (delve.platform.input.isKeyJustPressed(.ESCAPE))
        delve.platform.app.exit();

    // update our game time
    time += delta;

    game_instance.tick(delta);
}

pub fn on_draw() void {
    render_instance.update(&game_instance);
    render_instance.draw(&game_instance);
}

// Returns the player start position from the map
// pub fn getPlayerStartPosition(map: *delve.utils.quakemap.QuakeMap) math.Vec3 {
//     for (map.entities.items) |entity| {
//         if (std.mem.eql(u8, entity.classname, "info_player_start")) {
//             const offset = entity.getVec3Property("origin") catch {
//                 delve.debug.log("Could not read player start offset property!", .{});
//                 break;
//             };
//             return offset;
//         }
//     }
//
//     return math.Vec3.new(0, 0, 0);
// }

pub fn cvar_toggleNoclip() void {
    if (game_instance.player.state.move_mode != .NOCLIP) {
        game_instance.player.state.move_mode = .NOCLIP;
        delve.debug.log("Noclip on! Walls mean nothing to you.", .{});
    } else {
        game_instance.player.state.move_mode = .WALKING;
        delve.debug.log("Noclip off", .{});
    }
}

pub fn cvar_toggleFlyMode() void {
    if (game_instance.player.state.move_mode != .FLYING) {
        game_instance.player.state.move_mode = .FLYING;
        delve.debug.log("Flymode on! You feel lighter.", .{});
    } else {
        game_instance.player.state.move_mode = .WALKING;
        delve.debug.log("Flymode off", .{});
    }
}

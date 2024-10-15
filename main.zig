const std = @import("std");
const collision = @import("collision.zig");
const delve = @import("delve");
const player = @import("game/entities/player.zig");
const app = delve.app;

const game = @import("game/game.zig");
const renderer = @import("game/renderer.zig");

const graphics = delve.platform.graphics;
const math = delve.math;

pub var game_instance: game.GameInstance = undefined;
pub var render_instance: renderer.RenderInstance = undefined;

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

    try app.start(app.AppConfig{ .title = "Super Boarding Party Pro", .sampler_pool_size = 1024, .buffer_pool_size = 4096 });
}

pub fn on_init() !void {
    // use the Delve Framework global allocator
    const allocator = delve.mem.getAllocator();
    game_instance = game.GameInstance.init(allocator);
    render_instance = try renderer.RenderInstance.init(allocator);

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

    game_instance.tick(delta);
}

pub fn on_draw() void {
    render_instance.update(&game_instance);
    render_instance.draw(&game_instance);
}

pub fn cvar_toggleNoclip() void {
    if (game_instance.player_controller) |pc| {
        if (pc.state.move_mode != .NOCLIP) {
            pc.state.move_mode = .NOCLIP;
            delve.debug.log("Noclip on! Walls mean nothing to you.", .{});
        } else {
            pc.state.move_mode = .WALKING;
            delve.debug.log("Noclip off", .{});
        }
    }
}

pub fn cvar_toggleFlyMode() void {
    if (game_instance.player_controller) |pc| {
        if (pc.state.move_mode != .FLYING) {
            pc.state.move_mode = .FLYING;
            delve.debug.log("Flymode on! You feel lighter.", .{});
        } else {
            pc.state.move_mode = .WALKING;
            delve.debug.log("Flymode off", .{});
        }
    }
}

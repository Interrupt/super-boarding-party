const std = @import("std");
const delve = @import("delve");

const game = @import("game/game.zig");
const entities = @import("game/entities.zig");
const renderer = @import("game/renderer.zig");

const basics = @import("entities/basics.zig");
const box_collision = @import("entities/box_collision.zig");
const movers = @import("entities/mover.zig");
const collision = @import("utils/collision.zig");
const player = @import("entities/player.zig");
const character = @import("entities/character.zig");
const monsters = @import("entities/monster.zig");

const texture_manager = @import("managers/textures.zig");
const spritesheet_manager = @import("managers/spritesheets.zig");

const app = delve.app;
const graphics = delve.platform.graphics;
const math = delve.math;

pub var game_instance: game.GameInstance = undefined;
pub var render_instance: renderer.RenderInstance = undefined;

pub fn main() !void {
    const example = delve.modules.Module{
        .name = "main_module",
        .init_fn = on_init,
        .tick_fn = on_tick,
        .fixed_tick_fn = on_physics_tick,
        .pre_draw_fn = on_pre_draw,
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

    // init modules
    try delve.modules.registerModule(example);
    try delve.module.fps_counter.registerModule();

    // register some console commands
    try delve.debug.registerConsoleCommand("noclip", cvar_toggleNoclip, "Toggle noclip");
    try delve.debug.registerConsoleCommand("fly", cvar_toggleFlyMode, "Toggle flying");
    try delve.debug.registerConsoleCommand("loadmap", console_addMapCheat, "Load a test map");
    try delve.debug.registerConsoleCommand("killall", console_killall, "Kill all monsters");

    // and some console variables
    try delve.debug.registerConsoleVariable("p.jump", &player.jump_acceleration, "Player jump acceleration");
    try delve.debug.registerConsoleVariable("d.collision", &box_collision.enable_debug_viz, "Draw debug collision viz");
    try delve.debug.registerConsoleVariable("d.movers", &movers.enable_debug_viz, "Draw mover debug viz");

    try app.start(app.AppConfig{
        .title = "Super Boarding Party Pro",
        .enable_audio = true,
        .sampler_pool_size = 1024,
        .buffer_pool_size = 4096,
        .width = 1280,
        .height = 700,
    });
}

const TestAllocator = struct {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;
    var initialized: bool = false;
};

fn system_allocator() std.mem.Allocator {
    if (!TestAllocator.initialized) {
        TestAllocator.gpa = .{};
    }

    return TestAllocator.gpa.allocator();
}

pub fn on_init() !void {
    const alloc = system_allocator();
    _ = alloc;

    // init managers
    try texture_manager.init();
    try spritesheet_manager.init();

    // init game and renderer
    const allocator = delve.mem.getAllocator();
    game_instance = game.GameInstance.init(allocator);
    render_instance = try renderer.RenderInstance.init(allocator);

    // do some setup
    delve.platform.graphics.setClearColor(delve.colors.examples_bg_dark);
    delve.platform.app.captureMouse(true);
    delve.platform.app.setFixedTimestep(1.0 / 40.0); // tick physics at 40hz

    delve.platform.audio.enableSpatialAudio(true);

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

pub fn on_physics_tick(delta: f32) void {
    game_instance.physics_tick(delta);
}

pub fn on_pre_draw() void {
    render_instance.update(&game_instance);
    render_instance.pre_draw(&game_instance);
}

pub fn on_draw() void {
    render_instance.draw(&game_instance);
}

pub fn cvar_toggleNoclip() void {
    if (game_instance.player_controller) |pc| {
        if (pc.getMoveMode() != .NOCLIP) {
            pc.setMoveMode(.NOCLIP);
            delve.debug.log("Noclip on! Walls mean nothing to you.", .{});
        } else {
            pc.setMoveMode(.WALKING);
            delve.debug.log("Noclip off", .{});
        }
    }
}

pub fn cvar_toggleFlyMode() void {
    if (game_instance.player_controller) |pc| {
        if (pc.getMoveMode() != .FLYING) {
            pc.setMoveMode(.FLYING);
            delve.debug.log("Flymode on! You feel lighter.", .{});
        } else {
            pc.setMoveMode(.WALKING);
            delve.debug.log("Flymode off", .{});
        }
    }
}

pub fn console_addMapCheat() void {
    if (game_instance.player_controller) |pc| {
        game_instance.addMapCheat("assets/E1M1.map", pc.getPosition()) catch {
            return;
        };
        delve.debug.log("Loaded a map!", .{});
    }
}

pub fn console_killall() void {
    var it = monsters.getComponentStorage(game_instance.world).iterator();
    while (it.next()) |m| {
        m.onDeath(0, entities.InvalidEntity);
    }
}

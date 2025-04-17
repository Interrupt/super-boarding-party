const std = @import("std");
const delve = @import("delve");
const imgui = delve.imgui;
const game = @import("../game.zig");
const game_states = @import("../game_states.zig");
const game_screen = @import("game_screen.zig");

const imgui_img_id: ?*anyopaque = null;

const main = @import("../../main.zig");

pub const TitleScreen = struct {
    owner: *game.GameInstance,
    background_img_id: ?*anyopaque = null,
    should_continue: bool = false,

    pub fn init(game_instance: *game.GameInstance) !game_states.GameState {
        const title_screen: *TitleScreen = try delve.mem.getAllocator().create(TitleScreen);
        title_screen.owner = game_instance;

        title_screen.background_img_id = main.render_instance.offscreen_material.makeImguiTexture(0, 0);

        return .{
            .impl_ptr = title_screen,
            .typename = @typeName(@This()),
            ._interface_on_start = on_start,
            ._interface_tick = tick,
            ._interface_deinit = deinit,
        };
    }

    pub fn on_start(self_impl: *anyopaque, game_instance: *game.GameInstance) !void {
        const self = @as(*TitleScreen, @ptrCast(@alignCast(self_impl)));
        _ = self;

        // Start fresh!
        game_instance.world.clearEntities();
    }

    pub fn tick(self_impl: *anyopaque, delta: f32) void {
        const self = @as(*TitleScreen, @ptrCast(@alignCast(self_impl)));
        _ = delta;

        // Continue here so that we clear the 'justPressed' inputs
        if (self.should_continue) {
            const game_scr = game_screen.GameScreen.init(self.owner) catch {
                delve.debug.log("Could not init game state!", .{});
                return;
            };
            self.owner.states.setState(game_scr);
            return;
        }

        // Draw a test UI
        const window_flags = imgui.ImGuiWindowFlags_NoTitleBar |
            imgui.ImGuiWindowFlags_NoResize |
            imgui.ImGuiWindowFlags_NoMove |
            imgui.ImGuiWindowFlags_NoScrollbar |
            imgui.ImGuiWindowFlags_NoSavedSettings |
            imgui.ImGuiWindowFlags_NoInputs;

        imgui.igSetNextWindowPos(.{ .x = 40, .y = 180 }, imgui.ImGuiCond_Once, .{ .x = 0, .y = 0 });
        imgui.igSetNextWindowSize(.{ .x = 800, .y = 300 }, imgui.ImGuiCond_Once);

        _ = imgui.igBegin("Title Screen Window", 0, window_flags);

        imgui.igText("Super Boarding Party Title Screen");
        imgui.igSpacing();
        imgui.igText("Press any key to start!");

        imgui.igEnd();

        // check if we should move to the next state
        var should_continue: bool = delve.platform.input.isKeyPressed(.SPACE);
        should_continue = should_continue or delve.platform.input.isKeyPressed(.ENTER);
        should_continue = should_continue or delve.platform.input.isMouseButtonJustPressed(.LEFT);
        self.should_continue = should_continue;
    }

    pub fn deinit(self_impl: *anyopaque) void {
        const self = @as(*TitleScreen, @ptrCast(@alignCast(self_impl)));
        delve.mem.getAllocator().destroy(self);
    }
};

const std = @import("std");
const delve = @import("delve");
const imgui = delve.imgui;
const game = @import("../game.zig");
const game_states = @import("../game_states.zig");

const imgui_img_id: ?*anyopaque = null;

const main = @import("../../main.zig");

pub const TitleScreen = struct {
    background_img_id: ?*anyopaque = null,

    pub fn init() !game_states.GameState {
        const title_screen: *TitleScreen = try delve.mem.getAllocator().create(TitleScreen);

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
        _ = game_instance;

        const self = @as(*TitleScreen, @ptrCast(@alignCast(self_impl)));
        _ = self;
    }

    pub fn tick(self_impl: *anyopaque, delta: f32) void {
        _ = delta;

        const self = @as(*TitleScreen, @ptrCast(@alignCast(self_impl)));

        // delve.debug.log("Title screen tick!", .{});

        const window_flags = imgui.ImGuiWindowFlags_NoTitleBar |
            imgui.ImGuiWindowFlags_NoResize |
            imgui.ImGuiWindowFlags_NoMove |
            imgui.ImGuiWindowFlags_NoScrollbar |
            imgui.ImGuiWindowFlags_NoSavedSettings |
            imgui.ImGuiWindowFlags_NoInputs;

        imgui.igSetNextWindowPos(.{ .x = 40, .y = 180 }, imgui.ImGuiCond_Once, .{ .x = 0, .y = 0 });
        imgui.igSetNextWindowSize(.{ .x = 400, .y = 300 }, imgui.ImGuiCond_Once);
        _ = imgui.igBegin("Title Screen Window", 0, window_flags);
        imgui.igText("Super Boarding Party Title Screen");

        imgui.igSpacing();

        imgui.igText("Offscreen Buffers");
        _ = imgui.igBeginTable("buffers", 2, 0, .{ .x = 0, .y = 0 }, 0);
        _ = imgui.igTableNextRow(0, 0);
        _ = imgui.igTableNextColumn();

        _ = imgui.igImage(
            self.background_img_id,
            .{ .x = 180, .y = 180 }, // size
            .{ .x = 0, .y = 0 }, // u
            .{ .x = 1.0, .y = 1.0 }, // v
            .{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 }, // tint color
            .{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 }, // border color
        );

        _ = imgui.igTableNextColumn();

        _ = imgui.igImage(
            self.background_img_id,
            .{ .x = 180, .y = 180 }, // size
            .{ .x = 0, .y = 0 }, // u
            .{ .x = 1.0, .y = 1.0 }, // v
            .{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 }, // tint color
            .{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 }, // border color
        );

        _ = imgui.igEndTable();

        imgui.igEnd();

        // check if se should move to the next state
        const should_continue = delve.platform.input.isKeyPressed(.SPACE);

        if (should_continue) {}
    }

    pub fn deinit(self_impl: *anyopaque) void {
        const self = @as(*TitleScreen, @ptrCast(@alignCast(self_impl)));
        delve.mem.getAllocator().destroy(self);
    }
};

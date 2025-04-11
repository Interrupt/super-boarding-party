const std = @import("std");
const delve = @import("delve");
const imgui = delve.imgui;
const game_states = @import("../game_states.zig");

pub const TitleScreen = struct {
    pub fn init() !game_states.GameState {
        const title_screen: *TitleScreen = try delve.mem.getAllocator().create(TitleScreen);
        return .{
            .impl_ptr = title_screen,
            .typename = @typeName(@This()),
            ._interface_tick = tick,
            ._interface_deinit = deinit,
        };
    }

    pub fn tick(self_impl: *anyopaque, delta: f32) void {
        _ = self_impl;
        _ = delta;

        // delve.debug.log("Title screen tick!", .{});
        //
        const window_flags = imgui.ImGuiWindowFlags_NoTitleBar |
            imgui.ImGuiWindowFlags_NoResize |
            imgui.ImGuiWindowFlags_NoMove |
            imgui.ImGuiWindowFlags_NoScrollbar |
            imgui.ImGuiWindowFlags_NoSavedSettings |
            imgui.ImGuiWindowFlags_NoInputs;

        imgui.igSetNextWindowPos(.{ .x = 40, .y = 180 }, imgui.ImGuiCond_Once, .{ .x = 0, .y = 0 });
        imgui.igSetNextWindowSize(.{ .x = 400, .y = 100 }, imgui.ImGuiCond_Once);
        _ = imgui.igBegin("Title Screen Window", 0, window_flags);
        imgui.igText("Super Boarding Party Title Screen");
        imgui.igEnd();
    }

    pub fn deinit(self_impl: *anyopaque) void {
        const self = @as(*TitleScreen, @ptrCast(self_impl));
        delve.mem.getAllocator().destroy(self);
    }
};

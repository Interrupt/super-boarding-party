const std = @import("std");
const delve = @import("delve");
const imgui = delve.imgui;
const game = @import("../game.zig");
const game_states = @import("../game_states.zig");
const game_screen = @import("game_screen.zig");

const imgui_img_id: ?*anyopaque = null;

const main = @import("../../main.zig");

pub const ScreenState = enum {
    IDLE,
    FADING_IN,
    FADING_OUT,
    TO_NEXT_SCREEN,
};

pub const TitleScreen = struct {
    owner: *game.GameInstance,

    bg_texture: delve.platform.graphics.Texture,
    background_img_id: ?*anyopaque = null,

    fade_timer: f32,
    screen_state: ScreenState,

    pub fn init(game_instance: *game.GameInstance) !game_states.GameState {
        const title_screen: *TitleScreen = try delve.mem.getAllocator().create(TitleScreen);
        title_screen.owner = game_instance;

        // load the image for our splash bg
        var bg_image = try delve.images.loadFile("assets/ui/splash.png");
        defer bg_image.deinit();

        // make a texture and imgui tex out of it
        const tex = delve.platform.graphics.Texture.init(bg_image);
        title_screen.bg_texture = tex;
        title_screen.background_img_id = tex.makeImguiTexture();

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

        // fade in to start
        self.screen_state = .FADING_IN;
        self.fade_timer = 0.0;

        // Start fresh!
        game_instance.world.clearEntities();
    }

    pub fn tick(self_impl: *anyopaque, delta: f32) void {
        const self = @as(*TitleScreen, @ptrCast(@alignCast(self_impl)));
        const app = delve.platform.app;
        const window_size = delve.math.Vec2.new(@floatFromInt(app.getWidth()), @floatFromInt(app.getHeight()));

        // scale our background to fit the window
        const bg_scale = window_size.x / 800.0;
        var ui_alpha: f32 = 1.0;

        switch (self.screen_state) {
            .IDLE => {
                // check if we should move to the next state
                var should_continue: bool = delve.platform.input.isKeyPressed(.SPACE);
                should_continue = should_continue or delve.platform.input.isKeyPressed(.ENTER);
                should_continue = should_continue or delve.platform.input.isMouseButtonJustPressed(.LEFT);

                if (should_continue) {
                    self.fade_timer = 0.0;
                    self.screen_state = .FADING_OUT;
                }
            },
            .FADING_IN => {
                self.fade_timer += delta * 2.0;
                ui_alpha = std.math.clamp(self.fade_timer, 0.0, 1.0);

                if (self.fade_timer >= 1.0) {
                    self.fade_timer = 0.0;
                    self.screen_state = .IDLE;
                }
            },
            .FADING_OUT => {
                self.fade_timer += delta * 2.0;

                if (self.fade_timer >= 1.0) {
                    self.screen_state = .TO_NEXT_SCREEN;
                }

                ui_alpha = 1.0 - self.fade_timer;
            },
            .TO_NEXT_SCREEN => {
                delve.debug.log("Moving to main game", .{});
                const game_scr = game_screen.GameScreen.init(self.owner) catch {
                    delve.debug.log("Could not init game state!", .{});
                    return;
                };
                self.owner.states.setState(game_scr);
                return;
            },
        }

        ui_alpha = std.math.clamp(ui_alpha, 0.0, 1.0);

        // set a background color
        imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_WindowBg, .{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 1.0 });

        // Draw the title screen UI
        const window_flags = imgui.ImGuiWindowFlags_NoTitleBar |
            imgui.ImGuiWindowFlags_NoResize |
            imgui.ImGuiWindowFlags_NoMove |
            imgui.ImGuiWindowFlags_NoScrollbar |
            imgui.ImGuiWindowFlags_NoSavedSettings |
            imgui.ImGuiWindowFlags_NoInputs;

        imgui.igSetNextWindowPos(.{ .x = 0, .y = 0 }, imgui.ImGuiCond_Once, .{ .x = 0, .y = 0 });
        imgui.igSetNextWindowSize(.{ .x = window_size.x, .y = window_size.y }, imgui.ImGuiCond_Once);

        _ = imgui.igBegin("Title Screen Window", 0, window_flags);

        _ = imgui.igImage(
            self.background_img_id,
            .{ .x = 800 * bg_scale, .y = 400 * bg_scale }, // size
            .{ .x = 0, .y = 0 }, // u
            .{ .x = 1.0, .y = 1.0 }, // v
            .{ .x = 1.0, .y = 1.0, .z = 1.0, .w = ui_alpha }, // tint color
            .{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 0.0 }, // border color
        );

        imgui.igEnd();
        imgui.igPopStyleColor(1);
    }

    pub fn deinit(self_impl: *anyopaque) void {
        const self = @as(*TitleScreen, @ptrCast(@alignCast(self_impl)));

        self.bg_texture.destroy();
        delve.mem.getAllocator().destroy(self);
    }
};

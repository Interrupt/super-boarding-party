const std = @import("std");
const delve = @import("delve");
const imgui = delve.imgui;
const game = @import("../game.zig");
const game_states = @import("../game_states.zig");
const title_screen = @import("title_screen.zig");

const imgui_img_id: ?*anyopaque = null;

const main = @import("../../main.zig");

pub const ScreenState = enum {
    IDLE,
    FADING_IN,
    FADING_OUT,
    TO_NEXT_SCREEN,
};

pub const DeathScreen = struct {
    owner: *game.GameInstance,

    bg_texture: delve.platform.graphics.Texture = undefined,
    background_img_id: u64 = undefined,

    fade_timer: f32 = 0.0,
    ui_alpha: f32 = 0.0,
    bg_color: delve.colors.Color = delve.colors.red,
    screen_state: ScreenState = .FADING_IN,

    time: f64 = 0.0,

    pub fn init(game_instance: *game.GameInstance) !game_states.GameState {
        const death_screen: *DeathScreen = try delve.mem.getAllocator().create(DeathScreen);

        // init memory, set owner
        death_screen.* = .{ .owner = game_instance };

        // load the image for our splash bg
        var bg_image = try delve.images.loadFile("assets/ui/death_screen.png");
        defer bg_image.deinit();

        // make a texture and imgui tex out of it
        const tex = delve.platform.graphics.Texture.init(bg_image);
        death_screen.bg_texture = tex;
        death_screen.background_img_id = tex.makeImguiTexture();

        return .{
            .impl_ptr = death_screen,
            .typename = @typeName(@This()),
            ._interface_on_start = on_start,
            ._interface_tick = tick,
            ._interface_draw = draw,
            ._interface_deinit = deinit,
        };
    }

    pub fn on_start(self_impl: *anyopaque, game_instance: *game.GameInstance) !void {
        const self = @as(*DeathScreen, @ptrCast(@alignCast(self_impl)));

        // fade in to start
        self.screen_state = .FADING_IN;
        self.bg_color = delve.colors.red;
        self.fade_timer = 0.0;

        // Start fresh!
        game_instance.world.clearEntities();
    }

    pub fn tick(self_impl: *anyopaque, delta: f32) void {
        const self = @as(*DeathScreen, @ptrCast(@alignCast(self_impl)));

        self.time += @floatCast(delta);
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
                self.fade_timer += delta * 0.5;
                ui_alpha = self.fade_timer;

                if (self.fade_timer >= 1.0) {
                    self.fade_timer = 0.0;
                    self.screen_state = .IDLE;
                }
            },
            .FADING_OUT => {
                self.fade_timer += delta * 0.5;

                if (self.fade_timer >= 1.0) {
                    self.screen_state = .TO_NEXT_SCREEN;
                }

                ui_alpha = 1.0 - self.fade_timer;
                self.bg_color = delve.colors.red.scale(ui_alpha);
            },
            .TO_NEXT_SCREEN => {
                delve.debug.log("Moving to title screen", .{});
                const title_scr = title_screen.TitleScreen.init(self.owner) catch {
                    delve.debug.log("Could not init title state!", .{});
                    return;
                };
                self.owner.states.setState(title_scr);
                return;
            },
        }

        self.ui_alpha = std.math.clamp(ui_alpha, 0.0, 1.0);
    }

    pub fn draw(self_impl: *anyopaque) void {
        const self = @as(*DeathScreen, @ptrCast(@alignCast(self_impl)));
        const app = delve.platform.app;
        var ui_alpha = self.ui_alpha;

        // scale our background to fit the window
        const window_size = delve.math.Vec2.new(@floatFromInt(app.getWidth()), @floatFromInt(app.getHeight()));
        const bg_scale = window_size.x / 800.0;

        // Flash the death text!
        const flash_anim = @mod(self.time, 2.0);
        if (flash_anim > 1.25)
            ui_alpha *= 0.0;

        // set a background color
        // imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_WindowBg, .{ .x = self.bg_color.r, .y = self.bg_color.g, .z = self.bg_color.b, .w = 1.0 });

        // Draw the title screen UI
        const window_flags = imgui.ImGuiWindowFlags_NoTitleBar |
            imgui.ImGuiWindowFlags_NoResize |
            imgui.ImGuiWindowFlags_NoMove |
            imgui.ImGuiWindowFlags_NoScrollbar |
            imgui.ImGuiWindowFlags_NoSavedSettings |
            imgui.ImGuiWindowFlags_NoInputs;

        imgui.igSetNextWindowPos(.{ .x = 0, .y = 0 }, imgui.ImGuiCond_Once);
        imgui.igSetNextWindowSize(.{ .x = window_size.x, .y = window_size.y }, imgui.ImGuiCond_Once);

        _ = imgui.igBegin("Death Screen Window", 0, window_flags);

        _ = imgui.igImage(
            .{ ._TexID = self.background_img_id },
            .{ .x = 800 * bg_scale, .y = 400 * bg_scale }, // size
        );

        imgui.igEnd();
        // imgui.igPopStyleColor();
    }

    pub fn deinit(self_impl: *anyopaque) void {
        const self = @as(*DeathScreen, @ptrCast(@alignCast(self_impl)));

        self.bg_texture.destroy();
        delve.mem.getAllocator().destroy(self);
    }
};

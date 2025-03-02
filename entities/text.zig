const std = @import("std");
const delve = @import("delve");
const math = delve.math;
const entities = @import("../game/entities.zig");
const string = @import("../utils/string.zig");
const spritesheets = @import("../managers/spritesheets.zig");
const graphics = delve.platform.graphics;
const debug = delve.debug;

const emissive_shader_builtin = delve.shaders.default_basic_lighting;

pub const TextComponent = struct {
    text: string.String,
    scale: f32 = 1.0,
    color: delve.colors.Color = delve.colors.white,
    unlit: bool = true,

    attach_to_parent: bool = true,

    // interface
    owner: entities.Entity = entities.InvalidEntity,

    // calculated
    _spritesheet: ?*spritesheets.SpriteSheet = null,

    pub fn init(self: *TextComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;

        if (delve.fonts.getLoadedFont("Tiny5") == null) {
            _ = delve.fonts.loadFont("Tiny5", "assets/fonts/Tiny5-Regular.ttf", 512, 100) catch {
                return;
            };
        }
        if (delve.fonts.getLoadedFont("KodeMono") == null) {
            _ = delve.fonts.loadFont("KodeMono", "assets/fonts/KodeMono-Regular.ttf", 512, 100) catch {
                return;
            };

            _ = spritesheets.loadSpriteSheetFromFont("font_KodeMono", "KodeMono") catch {
                delve.debug.err("Could not load sprite sheet from font!", .{});
                return;
            };
        }

        self._spritesheet = spritesheets.getSpriteSheet("font_KodeMono");
    }

    pub fn deinit(self: *TextComponent) void {
        self.text.deinit();
    }

    pub fn tick(self: *TextComponent, delta: f32) void {
        _ = self;
        _ = delta;
    }
};

pub fn getComponentStorage(world: *entities.World) *entities.ComponentStorage(TextComponent) {
    return world.components.getStorageForType(TextComponent) catch {
        delve.debug.fatal("Could not get TextComponent storage!", .{});
        return undefined;
    };
}

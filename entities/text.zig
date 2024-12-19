const std = @import("std");
const delve = @import("delve");
const math = delve.math;
const entities = @import("../game/entities.zig");
const graphics = delve.platform.graphics;
const images = delve.images;
const debug = delve.debug;

const emissive_shader_builtin = delve.shaders.default_basic_lighting;

pub const TextComponent = struct {
    text: []const u8 = "Hello World",
    scale: f32 = 1.0,
    color: delve.colors.Color = delve.colors.white,

    attach_to_parent: bool = true,

    owned_text_buffer: [128]u8 = std.mem.zeroes([128]u8),

    // interface
    owner: entities.Entity = entities.InvalidEntity,

    pub fn init(self: *TextComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;
        @memcpy(self.owned_text_buffer[0..self.text.len], self.text);
        self.text = self.owned_text_buffer[0..self.text.len];

        _ = delve.fonts.loadFont("Tiny5", "assets/fonts/Tiny5-Regular.ttf", 512, 100) catch {
            return;
        };
        _ = delve.fonts.loadFont("KodeMono", "assets/fonts/KodeMono-Regular.ttf", 512, 100) catch {
            return;
        };
    }

    pub fn deinit(self: *TextComponent) void {
        _ = self;
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

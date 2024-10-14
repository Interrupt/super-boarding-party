const std = @import("std");
const delve = @import("delve");
const math = delve.math;
const entities = @import("../entities.zig");

pub const SpriteComponent = struct {
    texture: delve.platform.graphics.Texture,
    position: math.Vec3,
    color: delve.colors.Color = delve.colors.white,

    draw_rect: delve.spatial.Rect = .{ .x = 0, .y = 0, .width = 1.0, .height = 1.0 },
    draw_tex_region: delve.graphics.sprites.TextureRegion = .{},

    pub fn init(self: *SpriteComponent, base: *entities.EntitySceneComponent) void {
        _ = self;
        _ = base;
    }

    pub fn deinit(self: *SpriteComponent) void {
        _ = self;
    }

    pub fn tick(self: *SpriteComponent, delta: f32) void {
        _ = self;
        _ = delta;
    }

    pub fn getPosition(self: *SpriteComponent) delve.math.Vec3 {
        return self.position;
    }

    pub fn getRotation(self: *SpriteComponent) delve.math.Quaternion {
        _ = self;
        return delve.math.Quaternion.identity;
    }

    pub fn getBounds(self: *SpriteComponent) delve.spatial.BoundingBox {
        const size: f32 = @max(self.draw_rect.width, self.draw_rect.height);
        return delve.spatial.BoundingBox.init(self.getPosition(), math.Vec3.new(size, size, size));
    }
};

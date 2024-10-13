const std = @import("std");
const delve = @import("delve");
const math = delve.math;

pub const SpriteComponent = struct {
    texture: delve.platform.graphics.Texture,
    pos: math.Vec3,
    scale: math.Vec3 = math.Vec3.one,
    color: delve.colors.Color = delve.colors.white,

    pub fn init(self: *SpriteComponent) void {
        _ = self;
    }

    pub fn deinit(self: *SpriteComponent) void {
        _ = self;
    }

    pub fn tick(self: *SpriteComponent, delta: f32) void {
        _ = self;
        _ = delta;
    }

    pub fn getPosition(self: *SpriteComponent) delve.math.Vec3 {
        return self.pos;
    }

    pub fn getBounds(self: *SpriteComponent) delve.spatial.BoundingBox {
        return delve.spatial.BoundingBox.init(self.getPosition(), self.scale);
    }
};

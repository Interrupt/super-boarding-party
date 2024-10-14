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

    position_offset: math.Vec3 = math.Vec3.zero,
    time: f64 = 0.0,

    pub fn init(self: *SpriteComponent, owner: *entities.Entity) void {
        _ = self;
        _ = owner;
    }

    pub fn deinit(self: *SpriteComponent, owner: *entities.Entity) void {
        _ = self;
        _ = owner;
    }

    pub fn tick(self: *SpriteComponent, owner: *entities.Entity, delta: f32) void {
        _ = owner;

        self.time += @floatCast(delta);
        self.position_offset.x = @floatCast(std.math.sin(self.time * 2.0));
    }

    pub fn getPosition(self: *SpriteComponent) delve.math.Vec3 {
        return self.position.add(self.position_offset);
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

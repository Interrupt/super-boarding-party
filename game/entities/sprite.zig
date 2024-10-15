const std = @import("std");
const delve = @import("delve");
const math = delve.math;
const entities = @import("../entities.zig");

const RndGen = std.rand.DefaultPrng;
var rnd = RndGen.init(0);

pub const SpriteComponent = struct {
    texture: delve.platform.graphics.Texture,
    position: math.Vec3,
    color: delve.colors.Color = delve.colors.white,
    index: i32 = 0,

    make_test_child: bool = false,

    draw_rect: delve.spatial.Rect = .{ .x = 0, .y = 0, .width = 1.0, .height = 1.0 },
    draw_tex_region: delve.graphics.sprites.TextureRegion = .{},

    position_offset: math.Vec3 = math.Vec3.zero,
    time: f64 = 0.0,

    world_position: math.Vec3 = undefined,

    pub fn init(self: *SpriteComponent, owner: *entities.Entity) void {
        if(self.make_test_child) {
            for(0..100) |i| {
                const spread: f32 = 10.0;
                const spread_half = spread * 0.5;

                const pos = math.Vec3 {
                    .x = rnd.random().float(f32) * spread - spread_half,
                    .y = rnd.random().float(f32) * spread - spread_half + 10.0,
                    .z = rnd.random().float(f32) * spread - spread_half,
                };

                _ = owner.createNewSceneComponent(SpriteComponent, .{
                    .texture = self.texture,
                    .position = pos,
                    .color = self.color,
                    .index = @intCast(i),
                    .draw_rect = .{ .x = 0, .y = 0, .width = 1.0, .height = 1.0 },
                }) catch {
                    return;
                };
            }
        }
    }

    pub fn deinit(self: *SpriteComponent, owner: *entities.Entity) void {
        _ = self;
        _ = owner;
    }

    pub fn tick(self: *SpriteComponent, owner: *entities.Entity, delta: f32) void {
        self.time += @floatCast(delta);
        self.position_offset.x = @floatCast(std.math.sin(self.time * 2.0 + @as(f32, @floatFromInt(self.index)) * 1000.0));

        if(self.index == 0)
            self.position_offset.x = @floatCast(std.math.sin(self.time * 0.1) * 20.0);

        // now we can set our final world position
        const root = owner.getRootSceneComponent();
        self.world_position = self.position.add(self.position_offset);
        if(root) |r| {
            if(r.cast(SpriteComponent)) |root_sprite| {
                if(root_sprite != self)
                    self.world_position = self.world_position.add(root_sprite.getPosition());
            }
        }
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

pub fn getComponentStorage(world: *entities.World) !*entities.ComponentStorage(SpriteComponent) {
    const storage = try world.components.getStorageForType(SpriteComponent);

    // convert type-erased storage to typed
    return storage.getStorage(entities.ComponentStorage(SpriteComponent));
}

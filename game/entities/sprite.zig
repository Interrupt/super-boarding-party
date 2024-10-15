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
    owner: *entities.Entity = undefined,

    pub fn init(self: *SpriteComponent, owner: *entities.Entity) void {
        self.owner = owner;
        if (self.make_test_child) {
            for (0..100) |i| {
                const spread: f32 = 10.0;
                const spread_half = spread * 0.5;

                const pos = math.Vec3{
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
        _ = owner;
        self.time += @floatCast(delta);
        self.position_offset.x = @floatCast(std.math.sin(self.time * 2.0 + @as(f32, @floatFromInt(self.index)) * 1000.0));

        if (self.index == 0)
            self.position_offset.x = @floatCast(std.math.sin(self.time * 0.1) * 20.0);

        // now we can set our final world position
        self.world_position = self.getWorldPosition();
        self.world_position = utilsGetWorldPosition(self, self.owner, SpriteComponent);
    }

    pub fn getPosition(self: *SpriteComponent) delve.math.Vec3 {
        return self.position.add(self.position_offset);
    }

    pub fn getWorldPosition(self: *SpriteComponent) delve.math.Vec3 {
        // If we're not the root, add the root position on
        const root = self.owner.getRootSceneComponent();

        if (root) |r| {
            const we_are_root = self.owner.isRootSceneComponent(self);
            if (!we_are_root)
                return self.getPosition().add(r.getPosition());
        }

        return self.getPosition();
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

pub fn utilsGetWorldPosition(self: *anyopaque, owner: *entities.Entity, comptime ComponentType: type) delve.math.Vec3 {
    const typed_self_ptr: *ComponentType = @ptrCast(@alignCast(self));

    // If we're not the root, add the root position on
    const root_opt = owner.getRootSceneComponent();
    if (root_opt) |root| {
        const we_are_root = owner.isRootSceneComponent(self);
        if (!we_are_root)
            return typed_self_ptr.getPosition().add(root.getPosition());
    }

    return typed_self_ptr.getPosition();
}

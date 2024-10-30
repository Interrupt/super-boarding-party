const std = @import("std");
const delve = @import("delve");
const math = delve.math;
const entities = @import("../game/entities.zig");

const RndGen = std.rand.DefaultPrng;
var rnd = RndGen.init(1);

pub const SpriteComponent = struct {
    spritesheet: [:0]const u8 = "sprites/entities",
    spritesheet_row: usize = 0,
    spritesheet_col: usize = 0,

    position: math.Vec3,
    scale: f32 = 4.0,
    color: delve.colors.Color = delve.colors.white,
    position_offset: math.Vec3 = math.Vec3.zero,

    draw_rect: delve.spatial.Rect = .{ .x = 0, .y = 0, .width = 4.0, .height = 4.0 },
    draw_tex_region: delve.graphics.sprites.TextureRegion = .{},

    owner: entities.Entity = entities.InvalidEntity,

    world_position: math.Vec3 = undefined,
    animation: ?delve.graphics.sprites.PlayingAnimation = null,

    pub fn init(self: *SpriteComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;

        // self.playAnimation(entity_sprite_sheet.getAnimation("entities_0").?, true, 10.0);
    }

    pub fn deinit(self: *SpriteComponent) void {
        _ = self;
    }

    pub fn tick(self: *SpriteComponent, delta: f32) void {
        if (self.animation) |*anim| {
            anim.tick(delta);

            const cur_frame = anim.getCurrentFrame();
            self.draw_rect = delve.spatial.Rect.new(cur_frame.offset, cur_frame.size.scale(self.scale));
            self.draw_tex_region = cur_frame.region;
        } else {
            self.draw_rect = delve.spatial.Rect.new(delve.math.Vec2.zero, delve.math.Vec2.one.scale(self.scale));
        }

        // cache our final world position
        const owner_rotation = self.owner.getRotation();
        self.world_position = self.owner.getPosition().add(owner_rotation.rotateVec3(self.position));
    }

    pub fn playAnimation(self: *SpriteComponent, animation: delve.graphics.sprites.SpriteAnimation, looping: bool, speed: f32) void {
        var playing_anim = animation.play();
        playing_anim.loop(looping);
        playing_anim.setSpeed(speed);
        playing_anim.animation.frames = playing_anim.animation.frames[0..2];
        self.animation = playing_anim;
    }
};

pub fn getComponentStorage(world: *entities.World) *entities.ComponentStorage(SpriteComponent) {
    return world.components.getStorageForType(SpriteComponent) catch {
        delve.debug.fatal("Could not get SpriteComponent storage!", .{});
        return undefined;
    };
}

const std = @import("std");
const delve = @import("delve");
const math = delve.math;
const entities = @import("../game/entities.zig");

const RndGen = std.rand.DefaultPrng;
var rnd = RndGen.init(1);

const spritesheet = @import("../utils/spritesheet.zig");

pub const BillboardType = enum {
    XYZ,
    XZ,
    NONE,
};

pub const BlendMode = enum {
    OPAQUE,
    ALPHA,
};

pub const SpriteComponent = struct {
    // properties
    spritesheet: [:0]const u8 = "sprites/entities",
    spritesheet_row: usize = 0,
    spritesheet_col: usize = 0,

    position: math.Vec3,
    scale: f32 = 4.0,
    color: delve.colors.Color = delve.colors.white,
    position_offset: math.Vec3 = math.Vec3.zero,
    rotation_offset: math.Quaternion = math.Quaternion.identity,
    billboard_type: BillboardType = .XYZ,
    blend_mode: BlendMode = .OPAQUE,

    reset_animation_when_done: bool = true,

    draw_rect: delve.spatial.Rect = .{ .x = 0, .y = 0, .width = 4.0, .height = 4.0 },
    draw_tex_region: delve.graphics.sprites.TextureRegion = .{},

    flash_timer: f32 = 0.0,

    attach_to_parent: bool = true,

    // interface
    owner: entities.Entity = entities.InvalidEntity,

    // calculated
    world_position: math.Vec3 = undefined,
    animation: ?delve.graphics.sprites.PlayingAnimation = null,

    _first_tick: bool = true,
    _last_world_position: math.Vec3 = undefined,

    pub fn init(self: *SpriteComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;
    }

    pub fn deinit(self: *SpriteComponent) void {
        _ = self;
    }

    pub fn tick(self: *SpriteComponent, delta: f32) void {
        if (self.animation) |*anim| {
            // play animation, and reset when done
            anim.tick(delta);

            if (self.reset_animation_when_done and anim.isDonePlaying())
                self.animation = null;
        }

        if (self.animation) |*anim| {
            const cur_frame = anim.getCurrentFrame();
            self.draw_rect = delve.spatial.Rect.new(cur_frame.offset, cur_frame.size.scale(self.scale));
            self.draw_tex_region = cur_frame.region;
        } else {
            self.draw_rect = delve.spatial.Rect.new(delve.math.Vec2.zero, delve.math.Vec2.one.scale(self.scale));

            const spritesheet_opt = spritesheet.getSpriteSheet(self.spritesheet);
            if (spritesheet_opt == null)
                return;

            const tex_region_opt = spritesheet_opt.?.getSprite(self.spritesheet_row, self.spritesheet_col);
            if (tex_region_opt != null) {
                self.draw_tex_region = tex_region_opt.?.region;
            }
        }

        // run our flash timer
        if (self.flash_timer > 0.0)
            self.flash_timer = @max(0.0, self.flash_timer - delta);

        self._last_world_position = self.world_position;

        // cache our final world position
        if (self.attach_to_parent) {
            const owner_rotation = self.owner.getRotation();
            self.world_position = self.owner.getRenderPosition().add(owner_rotation.rotateVec3(self.position));
        } else {
            self.world_position = self.position;
        }

        if (self._first_tick)
            self._last_world_position = self.world_position;
    }

    pub fn playAnimation(self: *SpriteComponent, row: usize, start_frame: usize, num_frames: usize, looping: bool, speed: f32) void {
        if (spritesheet.getSpriteSheet(self.spritesheet)) |sheet| {
            const playing_anim_opt = sheet.playAnimationByIndex(row);
            if (playing_anim_opt == null) {
                delve.debug.log("Could not find animation to play! Row: {d}", .{row});
                return;
            }

            var playing_anim = playing_anim_opt.?;
            playing_anim.loop(looping);
            playing_anim.setSpeed(speed);
            playing_anim.animation.frames = playing_anim.animation.frames[start_frame..num_frames];
            self.animation = playing_anim;
        }
    }
};

pub fn getComponentStorage(world: *entities.World) *entities.ComponentStorage(SpriteComponent) {
    return world.components.getStorageForType(SpriteComponent) catch {
        delve.debug.fatal("Could not get SpriteComponent storage!", .{});
        return undefined;
    };
}

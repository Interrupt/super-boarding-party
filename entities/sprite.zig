const std = @import("std");
const delve = @import("delve");
const math = delve.math;
const entities = @import("../game/entities.zig");

const RndGen = std.rand.DefaultPrng;
var rnd = RndGen.init(1);

var did_make_sheet = false;
var entity_sprite_sheet: delve.graphics.sprites.AnimatedSpriteSheet = undefined;
var entity_texture: delve.platform.graphics.Texture = undefined;

pub const SpriteComponent = struct {
    texture: delve.platform.graphics.Texture,
    position: math.Vec3,
    color: delve.colors.Color = delve.colors.white,
    position_offset: math.Vec3 = math.Vec3.zero,
    time: f32 = 0.0,

    draw_rect: delve.spatial.Rect = .{ .x = 0, .y = 0, .width = 1.0, .height = 1.0 },
    draw_tex_region: delve.graphics.sprites.TextureRegion = .{},

    world_position: math.Vec3 = undefined,
    interface: entities.EntitySceneComponent = undefined,

    animation: ?delve.graphics.sprites.PlayingAnimation = null,

    pub fn init(self: *SpriteComponent, interface: entities.EntitySceneComponent) void {
        self.interface = interface;

        if (!did_make_sheet)
            makeSpritesheet();

        self.texture = entity_texture;
        self.playAnimation(entity_sprite_sheet.getAnimation("entities_0").?, true, 10.0);
    }

    pub fn deinit(self: *SpriteComponent) void {
        _ = self;
    }

    pub fn tick(self: *SpriteComponent, delta: f32) void {
        self.time += delta;

        if (self.animation) |*anim| {
            anim.tick(delta);

            const cur_frame = anim.getCurrentFrame();
            self.draw_rect = delve.spatial.Rect.new(cur_frame.offset, cur_frame.size.scale(4.0));
            self.draw_tex_region = cur_frame.region;
        }

        // cache our final world position
        self.world_position = self.interface.getWorldPosition();
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

    pub fn playAnimation(self: *SpriteComponent, animation: delve.graphics.sprites.SpriteAnimation, looping: bool, speed: f32) void {
        var playing_anim = animation.play();
        playing_anim.loop(looping);
        playing_anim.setSpeed(speed);
        playing_anim.animation.frames = playing_anim.animation.frames[0..2];
        self.animation = playing_anim;
    }
};

pub fn getComponentStorage(world: *entities.World) !*entities.ComponentStorage(SpriteComponent) {
    const storage = try world.components.getStorageForType(SpriteComponent);

    // convert type-erased storage to typed
    return storage.getStorage(entities.ComponentStorage(SpriteComponent));
}

pub fn makeSpritesheet() void {
    did_make_sheet = true;

    delve.debug.log("Creating test spritesheet", .{});

    var spritesheet_image = delve.images.loadFile("assets/sprites/entities.png") catch {
        delve.debug.log("Could not load image", .{});
        return;
    };
    defer spritesheet_image.deinit();

    // make the texture to draw
    entity_texture = delve.platform.graphics.Texture.init(spritesheet_image);

    // create a set of animations from our sprite sheet
    entity_sprite_sheet = delve.graphics.sprites.AnimatedSpriteSheet.initFromGrid(8, 16, "entities_") catch {
        delve.debug.log("Could not create sprite sheet!", .{});
        return;
    };
}
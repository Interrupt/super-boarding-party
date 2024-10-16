const std = @import("std");
const delve = @import("delve");
const math = delve.math;
const entities = @import("../game/entities.zig");

const RndGen = std.rand.DefaultPrng;
var rnd = RndGen.init(0);

var did_make_sheet = false;
var entity_sprite_sheet: delve.graphics.sprites.AnimatedSpriteSheet = undefined;
var entity_texture: delve.platform.graphics.Texture = undefined;

pub const SpriteComponent = struct {
    texture: delve.platform.graphics.Texture,
    position: math.Vec3,
    color: delve.colors.Color = delve.colors.white,
    position_offset: math.Vec3 = math.Vec3.zero,

    draw_rect: delve.spatial.Rect = .{ .x = 0, .y = 0, .width = 1.0, .height = 1.0 },
    draw_tex_region: delve.graphics.sprites.TextureRegion = .{},

    world_position: math.Vec3 = undefined,
    interface: entities.EntitySceneComponent = undefined,

    pub fn init(self: *SpriteComponent, interface: entities.EntitySceneComponent) void {
        self.interface = interface;

        if (!did_make_sheet)
            makeSpritesheet();

        const frames = entity_sprite_sheet.getAnimation("entities_0").?.frames;
        const frame = frames[0];

        self.texture = entity_texture;
        self.draw_rect = delve.spatial.Rect.new(frame.offset, frame.size.scale(4.0));
        self.draw_tex_region = frame.region;
    }

    pub fn deinit(self: *SpriteComponent) void {
        _ = self;
    }

    pub fn tick(self: *SpriteComponent, delta: f32) void {
        _ = delta;
        // cache our final world position
        self.world_position = self.interface.getWorldPosition();
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

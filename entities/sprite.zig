const std = @import("std");
const delve = @import("delve");
const math = delve.math;
const graphics = delve.platform.graphics;
const entities = @import("../game/entities.zig");
const spritesheets = @import("../managers/spritesheets.zig");
const string = @import("../utils/string.zig");
const textures = @import("../managers/textures.zig");
const main = @import("../main.zig");

const RndGen = std.rand.DefaultPrng;
var rnd = RndGen.init(1);

pub const BillboardType = enum {
    XYZ,
    XZ,
    NONE,
};

pub const BlendMode = enum {
    OPAQUE,
    ALPHA,
};

pub const basic_lighting_fs_uniforms: []const delve.platform.graphics.MaterialUniformDefaults = &[_]delve.platform.graphics.MaterialUniformDefaults{ .CAMERA_POSITION, .COLOR_OVERRIDE, .ALPHA_CUTOFF, .AMBIENT_LIGHT, .DIRECTIONAL_LIGHT, .POINT_LIGHTS_16, .FOG_DATA };

const default_spritesheet: []const u8 = "sprites/entities";

pub const SpriteComponent = struct {
    // properties
    spritesheet: ?string.String = null,

    spritesheet_row: usize = 0,
    spritesheet_col: usize = 0,
    texture_path: ?string.String = null, // might have a set texture instead of a spritesheet
    material: ?graphics.Material = null, // might just have a material set

    position: math.Vec3,
    scale: f32 = 4.0,
    color: delve.colors.Color = delve.colors.white,
    position_offset: math.Vec3 = math.Vec3.zero,
    rotation_offset: math.Quaternion = math.Quaternion.identity,
    billboard_type: BillboardType = .XYZ,
    blend_mode: BlendMode = .OPAQUE,
    use_lighting: bool = true,

    reset_animation_when_done: bool = true,
    hide_when_done: bool = false,

    draw_rect: delve.spatial.Rect = .{ .x = 0, .y = 0, .width = 4.0, .height = 4.0 },
    draw_tex_region: delve.graphics.sprites.TextureRegion = .{},

    flash_timer: f32 = 0.0,

    attach_to_parent: bool = true,
    visible: bool = true,

    // interface
    owner: entities.Entity = entities.InvalidEntity,
    component_interface: entities.EntityComponent = undefined,

    // calculated
    world_position: math.Vec3 = undefined,
    animation: ?delve.graphics.sprites.PlayingAnimation = null,

    _spritesheet: ?*spritesheets.SpriteSheet = null,
    _first_tick: bool = true,
    _last_world_position: math.Vec3 = undefined,
    _img_size: math.Vec2 = math.Vec2.new(32, 32),

    pub fn init(self: *SpriteComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;
        self.component_interface = interface;

        // set our initial spritesheet if needed
        if (self._spritesheet == null) {
            if (self.spritesheet) |*s| {
                self._spritesheet = spritesheets.getSpriteSheet(s.str);
            } else {
                self._spritesheet = spritesheets.getSpriteSheet(default_spritesheet);
            }
        }

        self.tryInit() catch {
            delve.debug.log("Error initializing sprite!", .{});
        };

        // TODO: Clear animation when loading?
        self.animation = null;
    }

    pub fn tryInit(self: *SpriteComponent) !void {
        if (self.texture_path == null)
            return;

        const tex = textures.getOrLoadTexture(self.texture_path.?.str);
        const shader = main.render_instance.sprite_shader_lit;

        self.material = try graphics.Material.init(.{
            .shader = shader,
            .texture_0 = tex.texture,
            .samplers = &[_]graphics.FilterMode{.NEAREST},
            .default_fs_uniform_layout = basic_lighting_fs_uniforms,
        });

        self._img_size = tex.size;
        self.draw_rect = delve.spatial.Rect.new(delve.math.Vec2.new(0, 0), self._img_size.scale(0.01 * self.scale));
        self.draw_tex_region = delve.graphics.sprites.TextureRegion.default();
    }

    pub fn deinit(self: *SpriteComponent) void {
        if (self.material) |*mat| {
            mat.deinit();
        }

        if (self.spritesheet) |*s| {
            s.deinit();
        }
        if (self.texture_path) |*t| {
            t.deinit();
        }
    }

    pub fn tick(self: *SpriteComponent, delta: f32) void {
        // try to set a spritesheet if one was not set already
        if (self._spritesheet == null) {
            if (self.spritesheet) |*s| {
                self._spritesheet = spritesheets.getSpriteSheet(s.str);
            }
        }

        // play animation, and reset when done
        if (self.animation) |*anim| {
            anim.tick(delta);

            if (self.reset_animation_when_done and anim.isDonePlaying())
                self.animation = null;
        }

        // sometimes, hide when there is no animation
        if (self.hide_when_done and self.animation == null and self.visible) {
            self.visible = false;
        }

        // setup our draw rects
        if (self.material) |_| {
            // scale may have changed
            self.draw_rect = delve.spatial.Rect.new(delve.math.Vec2.new(0, 0), self._img_size.scale(0.01 * self.scale));
        } else if (self.animation) |*anim| {
            const cur_frame = anim.getCurrentFrame();
            self.draw_rect = delve.spatial.Rect.new(cur_frame.offset, cur_frame.size.scale(self.scale));
            self.draw_tex_region = cur_frame.region;
        } else {
            self.draw_rect = delve.spatial.Rect.new(delve.math.Vec2.zero, delve.math.Vec2.one.scale(self.scale));

            const spritesheet_opt = self._spritesheet;
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
        self.visible = true;
        if (self._spritesheet) |sheet| {
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

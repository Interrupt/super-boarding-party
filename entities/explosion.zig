const std = @import("std");
const delve = @import("delve");
const basics = @import("basics.zig");
const collision = @import("../utils/collision.zig");
const box_collision = @import("../entities/box_collision.zig");
const entities = @import("../game/entities.zig");
const player_components = @import("player.zig");
const inventory = @import("inventory.zig");
const weapons = @import("weapon.zig");
const stats = @import("actor_stats.zig");
const sprites = @import("sprite.zig");
const triggers = @import("triggers.zig");
const options = @import("../game/options.zig");
const string = @import("../utils/string.zig");

const math = delve.math;

pub const ExplosionState = enum {
    Activated,
    WaitingForTrigger,
    Done,
};

const default_explosion_sound: [:0]const u8 = "assets/audio/sfx/explode.mp3";

/// An explosion, which can damage actors and push them back
pub const ExplosionComponent = struct {
    state: ExplosionState = .Activated,

    damage: i32 = 35,
    range: f32 = 8.0,
    knockback: f32 = 30.0,
    fuse_timer: f32 = 0.0,
    destroy_owner: bool = true,
    position_offset: math.Vec3 = math.Vec3.zero,
    play_sound: bool = true,

    sprite_color: delve.colors.Color = delve.colors.white,
    sprite_scale: f32 = 2.75,
    sprite_anim_row: usize = 2,
    sprite_anim_col: usize = 0,
    sprite_anim_len: usize = 6,
    sprite_anim_speed: f32 = 20.0,

    instigator: ?entities.Entity = null,
    make_new_entity: bool = false,

    // interface
    owner: entities.Entity = entities.InvalidEntity,

    pub fn init(self: *ExplosionComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;
    }

    pub fn deinit(self: *ExplosionComponent) void {
        _ = self;
    }

    pub fn tick(self: *ExplosionComponent, delta: f32) void {
        if (self.state == .Done)
            return;

        if (self.state != .Activated)
            return;

        // Delay the explosion if we have a fuse timer
        if (self.fuse_timer > 0) {
            self.fuse_timer -= delta;
        }

        if (self.fuse_timer <= 0) {
            self.explode();
        }
    }

    /// When triggered, toggle light
    pub fn onTrigger(self: *ExplosionComponent, info: triggers.TriggerFireInfo) void {
        _ = info;
        self.state = .Activated;
        delve.debug.log("Triggered explosion!", .{});
    }

    pub fn explode(self: *ExplosionComponent) void {
        self.state = .Done;

        self.doDamage();
        self.spawnVfx() catch {
            delve.debug.warning("Could not spawn explosion vfx", .{});
        };

        if (self.play_sound) {
            _ = delve.platform.audio.playSound(default_explosion_sound, .{
                .volume = 1.0 * options.options.sfx_volume,
                .position = self.owner.getPosition(),
                .distance_rolloff = 0.1,
            });
        }

        if (self.destroy_owner) {
            if (self.make_new_entity) {
                self.owner.deinit();
            } else {
                _ = self.owner.createNewComponent(basics.LifetimeComponent, .{ .lifetime = 1.5 }) catch {};
            }
        }
    }

    pub fn doDamage(self: *ExplosionComponent) void {
        // do we do any damage?
        if (self.range <= 0.0)
            return;

        const pos = self.owner.getPosition();
        const size = math.Vec3.one.scale(self.range).scale(2.0);
        const bounds = delve.spatial.BoundingBox.init(pos, size);

        const found = box_collision.spatial_hash.getEntriesNear(bounds);
        for (found) |box| {
            if (self.owner.id.id == box.owner.id.id) {
                continue;
            }

            const check_bounds = box.getBoundingBox();
            if (bounds.intersects(check_bounds)) {
                // hit!
                if (box.owner.getComponent(stats.ActorStats)) |s| {
                    const attack_vec = box.owner.getPosition().sub(self.owner.getPosition());
                    const attack_dist = attack_vec.len();

                    // more fine grained check
                    if (attack_dist > self.range)
                        continue;

                    // check if anything is blocking this explosion
                    if (!self.checkLineOfSight(box.owner))
                        continue;

                    const distance_mod: f32 = (1.0 - (attack_dist / self.range));
                    const damage: f32 = @as(f32, @floatFromInt(self.damage)) * distance_mod;
                    const knockback: f32 = self.knockback * distance_mod;

                    s.takeDamage(.{
                        .dmg = @intFromFloat(damage),
                        .knockback = knockback,
                        .attack_normal = attack_vec.norm(),
                        .instigator = self.instigator,
                        .hit_pos = box.owner.getPosition(),
                        .hit_normal = attack_vec.norm(),
                    });
                }
            }
        }
    }

    pub fn checkLineOfSight(self: *ExplosionComponent, to_damage: entities.Entity) bool {
        const world = self.owner.getOwningWorld().?;
        const start = self.owner.getPosition();
        const end = to_damage.getPosition();
        const hit = collision.raySegmentCollidesWithMap(world, start, end, .{ .checking = self.owner });

        if (hit == null)
            return true;

        if (hit.?.entity) |e| {
            if (e.id.equals(to_damage.id))
                return true;
        }

        return false;
    }

    pub fn spawnVfx(self: *ExplosionComponent) !void {
        const world = self.owner.getOwningWorld().?;

        var attach_entity = if (self.make_new_entity) try world.createEntity(.{}) else self.owner;

        if (self.make_new_entity) {
            _ = try attach_entity.createNewComponent(basics.TransformComponent, .{ .position = self.owner.getPosition().add(self.position_offset) });
        }

        var sprite = try attach_entity.createNewComponent(sprites.SpriteComponent, .{
            .spritesheet = string.String.init("sprites/particles"),
            .position = math.Vec3.zero,
            .blend_mode = .ALPHA,
            .use_lighting = false,
            .color = self.sprite_color,
            .scale = self.sprite_scale,
            .hide_when_done = true,
        });

        sprite.playAnimation(self.sprite_anim_row, self.sprite_anim_col, self.sprite_anim_col + self.sprite_anim_len, false, self.sprite_anim_speed);
    }
};

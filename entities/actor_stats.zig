const std = @import("std");
const delve = @import("delve");
const entities = @import("../game/entities.zig");
const basics = @import("basics.zig");
const monster = @import("monster.zig");
const character = @import("character.zig");
const player = @import("player.zig");
const string = @import("../utils/string.zig");
const spritesheets = @import("../managers/spritesheets.zig");
const emitter = @import("particle_emitter.zig");

const math = delve.math;

pub const DamageInfo = struct {
    dmg: i32,
    knockback: f32 = 0.0,
    instigator: ?entities.Entity = null,
    attack_normal: ?math.Vec3 = null,
    hit_pos: ?math.Vec3 = null,
    hit_normal: ?math.Vec3 = null,
};

/// Adds stats like HP to this entity
pub const ActorStats = struct {
    // properties
    max_hp: i32 = 100,
    hp: i32 = 100,
    speed: f32 = 8.0,
    destroy_on_death: bool = false,

    // interface
    owner: entities.Entity = entities.InvalidEntity,

    // calculated
    is_alive: bool = true,

    pub fn init(self: *ActorStats, interface: entities.EntityComponent) void {
        self.owner = interface.owner;
        self.hp = @min(self.hp, self.max_hp);
    }

    pub fn deinit(self: *ActorStats) void {
        _ = self;
    }

    pub fn physics_tick(self: *ActorStats, delta: f32) void {
        _ = delta;

        // cache if we're alive
        self.is_alive = self.isAlive();

        if (self.owner.getComponent(character.CharacterMovementComponent)) |movement| {
            movement.move_speed = self.speed;
        }

        // destroy our entity if asked to
        if (!self.is_alive and self.destroy_on_death)
            self.owner.deinit();
    }

    pub fn isAlive(self: *ActorStats) bool {
        // we're alive if we still have HP left!
        return self.hp > 0;
    }

    pub fn takeDamage(self: *ActorStats, dmg_info: DamageInfo) void {
        // gib when we take too much damage!
        const do_gib: bool = dmg_info.dmg > self.max_hp * 3;

        // don't take more damage when already dead!
        if (!self.is_alive) {
            if (do_gib) self.doGib(dmg_info);
            return;
        }

        self.hp -= dmg_info.dmg;
        self.is_alive = self.isAlive();

        // apply knockback when given!
        if (dmg_info.attack_normal != null and dmg_info.knockback != 0.0) {
            self.knockback(dmg_info.knockback, dmg_info.attack_normal.?);
        }

        // monster hurt effects
        if (self.owner.getComponent(monster.MonsterController)) |m| {
            if (self.is_alive) {
                m.onHurt(dmg_info.dmg, dmg_info.instigator);
            } else {
                m.onDeath(dmg_info.dmg, dmg_info.instigator);
            }

            // If we have a hit location, play our blood vfx too!
            if (dmg_info.hit_pos != null and dmg_info.hit_normal != null) {
                if (do_gib) {
                    self.doGib(dmg_info);
                } else {
                    self.playHitEffects(dmg_info.hit_pos.?, dmg_info.hit_normal.?);
                }
            }
        }

        // player hurt effects
        if (self.owner.getComponent(player.PlayerController)) |c| {
            c.onHurt(dmg_info.dmg, dmg_info.instigator);
        }
    }

    pub fn doGib(self: *ActorStats, dmg_info: DamageInfo) void {
        self.playGibEffects(dmg_info.hit_pos.?, dmg_info.hit_normal.?);
        self.owner.deinit();
    }

    pub fn heal(self: *ActorStats, amount: i32) void {
        // don't heal when already dead!
        if (!self.is_alive)
            return;

        self.hp = @min(self.hp + amount, self.max_hp);
        self.is_alive = self.isAlive();

        if (self.owner.getComponent(player.PlayerController)) |c| {
            c.screen_flash_time = 0.3;
            c.screen_flash_timer = 0.3;
            c.screen_flash_color = delve.colors.Color.new(0.0, 1.0, 0.0, 0.2);
        }
    }

    pub fn knockback(self: *ActorStats, amount: f32, direction: math.Vec3) void {
        // Only characters can be knocked back
        if (self.owner.getComponent(character.CharacterMovementComponent)) |_| {
            const vel = self.owner.getVelocity();
            self.owner.setVelocity(vel.add(direction.scale(amount)));
        }
    }

    pub fn playHitEffects(self: *ActorStats, hit_pos: math.Vec3, hit_normal: math.Vec3) void {
        const world_opt = entities.getWorld(self.owner.id.world_id);
        if (world_opt == null)
            return;

        var world = world_opt.?;

        // make blood hit vfx!
        var hit_emitter = world.createEntity(.{}) catch {
            return;
        };
        _ = hit_emitter.createNewComponent(basics.TransformComponent, .{ .position = hit_pos.add(hit_normal.scale(0.5)) }) catch {
            return;
        };
        _ = hit_emitter.createNewComponent(emitter.ParticleEmitterComponent, .{
            .num = 8,
            .num_variance = 6,
            .spritesheet = string.String.init("sprites/blank"),
            .velocity = hit_normal.scale(5),
            .velocity_variance = math.Vec3.new(40.0, 40.0, 40.0),
            .color = delve.colors.red,
            .scale = 0.3125, // 1 / 32
        }) catch {
            return;
        };
        _ = hit_emitter.createNewComponent(emitter.ParticleEmitterComponent, .{
            .num = 2,
            .num_variance = 2,
            .spritesheet = string.String.init("sprites/particles"),
            .spritesheet_row = 3,
            .scale = 2.0,
            .end_scale = 2.0,
            .lifetime = 5.0,
            .velocity = hit_normal.scale(4),
            .velocity_variance = math.Vec3.new(20.0, 20.0, 20.0),
            .color = delve.colors.red,
            .position_offset = math.Vec3.new(0, 2.0, 0),
            .collides_world = false,
            .delete_owner_when_done = false,
        }) catch {
            return;
        };

        // blood mist (smoke!)
        _ = hit_emitter.createNewComponent(emitter.ParticleEmitterComponent, .{
            .num = 4,
            .num_variance = 5,
            ._spritesheet = spritesheets.getSpriteSheet("sprites/particles"),
            .spritesheet_row = 3,
            .spritesheet_col = 2,
            .lifetime = 26.0,
            .lifetime_variance = 3.0,
            // .velocity = math.Vec3.zero,
            .velocity = hit_normal.scale(0.3),
            .velocity_variance = math.Vec3.one.scale(0.4),
            .position_offset = hit_normal.scale(-0.3),
            .position_variance = math.Vec3.one.scale(0.2),
            .gravity = 0.001,
            .color = delve.colors.Color.new(1.0, 0.0, 0.0, 0.25),
            .end_color = delve.colors.Color.new(1.0, 0.0, 0.0, 0.0),
            .scale = 1.55,
            .end_scale = 1.75,
            .delete_owner_when_done = false,
            .use_lighting = true,
            .collides_world = false,
        }) catch {
            return;
        };
    }

    pub fn playGibEffects(self: *ActorStats, hit_pos: math.Vec3, hit_normal: math.Vec3) void {
        const world_opt = entities.getWorld(self.owner.id.world_id);
        if (world_opt == null)
            return;

        var world = world_opt.?;

        // make blood hit vfx!
        var hit_emitter = world.createEntity(.{}) catch {
            return;
        };
        _ = hit_emitter.createNewComponent(basics.TransformComponent, .{ .position = hit_pos.add(hit_normal.scale(0.5)) }) catch {
            return;
        };
        _ = hit_emitter.createNewComponent(emitter.ParticleEmitterComponent, .{
            .num = 20,
            .num_variance = 12,
            .spritesheet = string.String.init("sprites/blank"),
            .velocity = hit_normal.scale(40),
            .velocity_variance = math.Vec3.new(10.0, 10.0, 10.0),
            .color = delve.colors.red,
            .scale = 0.3125, // 1 / 32
        }) catch {
            return;
        };
        _ = hit_emitter.createNewComponent(emitter.ParticleEmitterComponent, .{
            .num = 8,
            .num_variance = 6,
            .spritesheet = string.String.init("sprites/particles"),
            .spritesheet_row = 3,
            .scale = 2.0,
            .end_scale = 2.0,
            .velocity = hit_normal.scale(40),
            .velocity_variance = math.Vec3.new(10.0, 10.0, 10.0),
            .color = delve.colors.red,
            .position_offset = math.Vec3.new(0, 2.0, 0),
            .collides_world = true,
            .lifetime = 0.5,
            .lifetime_variance = 1.0,
            .position_variance = math.Vec3.new(0.5, 2.0, 0.5),
            .delete_owner_when_done = false,
        }) catch {
            return;
        };

        // blood mist (smoke!)
        _ = hit_emitter.createNewComponent(emitter.ParticleEmitterComponent, .{
            .num = 4,
            .num_variance = 5,
            ._spritesheet = spritesheets.getSpriteSheet("sprites/particles"),
            .spritesheet_row = 3,
            .spritesheet_col = 2,
            .lifetime = 26.0,
            .lifetime_variance = 3.0,
            .velocity = hit_normal.scale(0.5),
            .velocity_variance = math.Vec3.one.scale(0.4),
            .position_offset = hit_normal.scale(-0.3),
            .position_variance = math.Vec3.one.scale(2.0),
            .gravity = 0.001,
            .color = delve.colors.Color.new(1.0, 0.0, 0.0, 0.25),
            .end_color = delve.colors.Color.new(1.0, 0.0, 0.0, 0.0),
            .scale = 2.35,
            .end_scale = 2.65,
            .delete_owner_when_done = false,
            .use_lighting = true,
            .collides_world = false,
        }) catch {
            return;
        };
    }
};

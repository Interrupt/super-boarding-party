const std = @import("std");
const delve = @import("delve");
const entities = @import("../game/entities.zig");
const character = @import("character.zig");
const box_collision = @import("box_collision.zig");
const sprite = @import("sprite.zig");
const stats = @import("actor_stats.zig");
const main = @import("../main.zig");
const options = @import("../game/options.zig");

const math = delve.math;

pub const MonsterState = enum {
    IDLE,
    ALERTED,
    DEAD,
};

pub const MonsterController = struct {
    // properties
    attack_cooldown: f32 = 1.0,
    attack_cooldown_timer: f32 = 0.0,
    hostile: bool = true,

    monster_state: MonsterState = .ALERTED,
    target: entities.Entity = entities.InvalidEntity,

    // interface
    owner: entities.Entity = entities.InvalidEntity,

    pub fn init(self: *MonsterController, interface: entities.EntityComponent) void {
        self.owner = interface.owner;
    }

    pub fn deinit(self: *MonsterController) void {
        _ = self;
    }

    pub fn physics_tick(self: *MonsterController, delta: f32) void {
        // do attack cooldown
        self.attack_cooldown_timer -= delta;
        self.attack_cooldown_timer = @max(0.0, self.attack_cooldown_timer);

        const player_opt = main.game_instance.player_controller;
        if (player_opt == null)
            return;

        const sprite_opt = self.owner.getComponent(sprite.SpriteComponent);
        const stats_opt = self.owner.getComponent(stats.ActorStats);

        // check our status
        var is_alive = true;
        if (stats_opt) |s| {
            is_alive = s.isAlive();
        }

        // AI state machine!
        switch (self.monster_state) {
            .IDLE => {
                const vec_to_player = player_opt.?.getPosition().sub(self.owner.getPosition());
                const distance_to_player = vec_to_player.len();

                if (self.hostile and distance_to_player <= 50.0) {
                    self.target = player_opt.?.owner;
                    self.monster_state = .ALERTED;
                }
            },
            else => {},
        }

        if (!self.target.isValid()) {
            self.monster_state = .IDLE;
        }

        const vec_to_target = self.target.getPosition().sub(self.owner.getPosition());
        const distance_to_target = vec_to_target.len();

        // delve.debug.log("Monster controller tick {d}!", .{self.owner.id.id});
        const movement_component_opt = self.owner.getComponent(character.CharacterMovementComponent);
        if (movement_component_opt) |movement_component| {
            // stupid AI: while alive, drive ourself towards the target
            if (is_alive and self.monster_state == .ALERTED) {
                movement_component.move_dir = vec_to_target.norm();
            } else {
                movement_component.move_dir = math.Vec3.zero;
            }

            // lerp our step up
            if (sprite_opt) |s| {
                const current_pos = movement_component.getPosition();
                const pos_after_step = movement_component.getStepLerpToHeight(current_pos.y);
                s.position_offset.y = pos_after_step - current_pos.y;
            }
        }

        // can stop here if we are dead
        if (!is_alive)
            return;

        // attack the target!
        if (distance_to_target <= 3.0 and self.attack_cooldown_timer <= 0.0) {
            self.attackTarget(self.target);
        }

        // play walk animation if nothing else is playing
        if (sprite_opt) |s| {
            if (s.animation == null) {
                s.playAnimation(0, 0, 2, true, 8.0);
            }
        }
    }

    pub fn attackTarget(self: *MonsterController, target: entities.Entity) void {
        // TODO: check if the target is in LOS
        self.attack_cooldown_timer = self.attack_cooldown;

        // target takes damage!
        const target_stats_opt = target.getComponent(stats.ActorStats);
        if (target_stats_opt) |target_stats| {
            target_stats.takeDamage(.{ .dmg = 5 });
        }

        // play attack animation
        const sprite_opt = self.owner.getComponent(sprite.SpriteComponent);
        if (sprite_opt) |s| {
            s.playAnimation(0, 2, 3, false, 4.0);
        }
    }

    pub fn getPosition(self: *MonsterController) delve.math.Vec3 {
        return self.owner.getPosition();
    }

    pub fn onHurt(self: *MonsterController, dmg: i32, instigator: ?entities.Entity) void {
        _ = dmg;

        // play flinch animation
        const sprite_opt = self.owner.getComponent(sprite.SpriteComponent);
        if (sprite_opt) |s| {
            s.playAnimation(0, 3, 4, false, 5.0);
            s.flash_timer = 0.075;
        }

        // play hurt sound
        var sound = delve.platform.audio.playSound("assets/audio/sfx/alien-alert1.mp3", .{ .volume = 0.4 * options.options.sfx_volume, .is_3d = true });
        if (sound) |*s| {
            const pos = self.owner.getPosition();
            s.setPosition(pos);
            s.setRangeRolloff(0.15);
        }

        // alert when we take damage!
        if (instigator != null) {
            self.monster_state = .ALERTED;
            self.target = instigator.?;
        }
    }

    pub fn onDeath(self: *MonsterController, dmg: i32, instigator: ?entities.Entity) void {
        _ = instigator;
        _ = dmg;

        // play death animation, and keep the last frame
        const sprite_opt = self.owner.getComponent(sprite.SpriteComponent);
        if (sprite_opt) |s| {
            s.reset_animation_when_done = false;
            s.playAnimation(0, 4, 6, false, 5.0);
        }

        // turn off collision for our corpse
        const collision_opt = self.owner.getComponent(box_collision.BoxCollisionComponent);
        if (collision_opt) |c| {
            c.collides_entities = false;
        }

        // death sound
        var sound = delve.platform.audio.playSound("assets/audio/sfx/alien-die2.mp3", .{ .volume = 0.8 * options.options.sfx_volume, .is_3d = true });
        if (sound) |*s| {
            const pos = self.owner.getPosition();
            s.setPosition(pos);
            s.setRangeRolloff(0.15);
        }

        // update our state!
        self.monster_state = .DEAD;
    }
};

pub fn getComponentStorage(world: *entities.World) *entities.ComponentStorage(MonsterController) {
    return world.components.getStorageForType(MonsterController) catch {
        delve.debug.fatal("Could not get MonsterController storage!", .{});
        return undefined;
    };
}

const std = @import("std");
const delve = @import("delve");
const entities = @import("../game/entities.zig");
const character = @import("character.zig");
const box_collision = @import("box_collision.zig");
const sprite = @import("sprite.zig");
const stats = @import("actor_stats.zig");
const main = @import("../main.zig");
const math = delve.math;

pub const MonsterController = struct {
    // properties
    attack_cooldown: f32 = 1.0,
    attack_cooldown_timer: f32 = 0.0,

    // interface
    owner: entities.Entity = entities.InvalidEntity,

    pub fn init(self: *MonsterController, interface: entities.EntityComponent) void {
        self.owner = interface.owner;
    }

    pub fn deinit(self: *MonsterController) void {
        _ = self;
    }

    pub fn tick(self: *MonsterController, delta: f32) void {

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

        const vec_to_player = player_opt.?.getPosition().sub(self.owner.getPosition());
        const distance_to_player = vec_to_player.len();

        // delve.debug.log("Monster controller tick {d}!", .{self.owner.id.id});
        const movement_component_opt = self.owner.getComponent(character.CharacterMovementComponent);
        if (movement_component_opt) |movement_component| {

            // stupid AI: while alive, drive ourselve towards the player!
            if (is_alive) {
                movement_component.move_dir = vec_to_player.norm();
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

        // attack the player!
        if (is_alive and distance_to_player <= 3.0 and self.attack_cooldown_timer <= 0.0) {
            delve.debug.log("Distance: {d:3}", .{distance_to_player});
            self.attack_cooldown_timer = self.attack_cooldown;

            // player takes damage!
            const player_stats_opt = player_opt.?.owner.getComponent(stats.ActorStats);
            if (player_stats_opt) |player_stats| {
                player_stats.takeDamage(.{ .dmg = 5 });
            }
        }

        // play walk animation if nothing is playing
        if (is_alive) {
            if (sprite_opt) |s| {
                if (s.animation == null) {
                    s.playAnimation(0, 0, 2, true, 8.0);
                }
            }
        }
    }

    pub fn getPosition(self: *MonsterController) delve.math.Vec3 {
        return self.owner.getPosition();
    }

    pub fn onHurt(self: *MonsterController, dmg: i32, instigator: ?entities.Entity) void {
        _ = instigator;
        _ = dmg;

        // play flinch animation
        const sprite_opt = self.owner.getComponent(sprite.SpriteComponent);
        if (sprite_opt) |s| {
            s.playAnimation(0, 2, 4, false, 5.0);
        }

        // play hurt sound
        var sound = delve.platform.audio.playSound("assets/audio/sfx/alien-alert1.mp3", 0.4);
        if (sound) |*s| {
            const pos = self.owner.getPosition();
            s.setPosition(.{ pos.x * 0.1, pos.y * 0.1, pos.z * 0.1 }, .{ 0.0, 1.0, 0.0 }, .{ 1.0, 0.0, 0.0 });
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
        var sound = delve.platform.audio.playSound("assets/audio/sfx/alien-die2.mp3", 0.8);
        if (sound) |*s| {
            const pos = self.owner.getPosition();
            s.setPosition(.{ pos.x * 0.1, pos.y * 0.1, pos.z * 0.1 }, .{ 0.0, 1.0, 0.0 }, .{ 1.0, 0.0, 0.0 });
        }
    }
};

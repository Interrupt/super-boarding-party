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
    owner: entities.Entity = entities.InvalidEntity,

    pub fn init(self: *MonsterController, interface: entities.EntityComponent) void {
        self.owner = interface.owner;
    }

    pub fn deinit(self: *MonsterController) void {
        _ = self;
    }

    pub fn tick(self: *MonsterController, delta: f32) void {
        _ = delta;

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

        // delve.debug.log("Monster controller tick {d}!", .{self.owner.id.id});
        const movement_component_opt = self.owner.getComponent(character.CharacterMovementComponent);
        if (movement_component_opt) |movement_component| {

            // stupid AI: while alive, drive ourselve towards the player!
            if (is_alive) {
                const vec_to_player = player_opt.?.getPosition().sub(movement_component.getPosition()).norm();
                movement_component.move_dir = vec_to_player;
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
        const sprite_opt = self.owner.getComponent(sprite.SpriteComponent);
        if (sprite_opt) |s| {
            s.playAnimation(0, 2, 4, false, 5.0);
        }
    }

    pub fn onDeath(self: *MonsterController, dmg: i32, instigator: ?entities.Entity) void {
        _ = instigator;
        _ = dmg;
        const sprite_opt = self.owner.getComponent(sprite.SpriteComponent);
        if (sprite_opt) |s| {
            s.reset_animation_when_done = false;
            s.playAnimation(0, 4, 6, false, 5.0);
        }

        const collision_opt = self.owner.getComponent(box_collision.BoxCollisionComponent);
        if (collision_opt) |c| {
            c.collides_entities = false;
        }
    }
};

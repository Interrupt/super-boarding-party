const std = @import("std");
const delve = @import("delve");
const entities = @import("../game/entities.zig");
const character = @import("character.zig");
const sprite = @import("sprite.zig");
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

        // delve.debug.log("Monster controller tick {d}!", .{self.owner.id.id});
        const movement_component_opt = self.owner.getComponent(character.CharacterMovementComponent);
        if (movement_component_opt) |movement_component| {

            // stupid AI: drive ourselve towards the player, always!
            const vec_to_player = player_opt.?.getPosition().sub(movement_component.getPosition()).norm();
            movement_component.move_dir = vec_to_player;

            // lerp our step up
            if (sprite_opt) |s| {
                const current_pos = movement_component.getPosition();
                const pos_after_step = movement_component.getStepLerpToHeight(current_pos.y);
                s.position_offset.y = pos_after_step - current_pos.y;
            }
        }

        // play walk animation if nothing is playing
        if (sprite_opt) |s| {
            if (s.animation == null) {
                s.playAnimation(0, 0, 2, true, 8.0);
            }
        }
    }

    pub fn getPosition(self: *MonsterController) delve.math.Vec3 {
        return self.owner.getPosition();
    }

    pub fn onHurt(self: *MonsterController, dmg: i32, instigator: entities.Entity) void {
        _ = instigator;
        _ = dmg;
        const sprite_opt = self.owner.getComponent(sprite.SpriteComponent);
        if (sprite_opt) |s| {
            s.playAnimation(0, 2, 4, true, 10.0);
        }
    }

    pub fn onDeath(self: *MonsterController) void {
        const sprite_opt = self.owner.getComponent(sprite.SpriteComponent);
        if (sprite_opt) |s| {
            s.playAnimation(0, 4, 6, true, 15.0);
        }
    }
};

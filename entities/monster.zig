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

        // delve.debug.log("Monster controller tick {d}!", .{self.owner.id.id});
        const movement_component_opt = self.owner.getComponent(character.CharacterMovementComponent);
        if (movement_component_opt) |movement_component| {

            // stupid AI: drive ourselve towards the player, always!
            const vec_to_player = player_opt.?.getPosition().sub(movement_component.getPosition()).norm();
            movement_component.move_dir = vec_to_player;

            // lerp our step up
            const sprite_opt = self.owner.getComponent(sprite.SpriteComponent);
            if (sprite_opt) |s| {
                const current_pos = movement_component.getPosition();
                const pos_after_step = movement_component.getStepLerpToHeight(current_pos.y);
                s.position_offset.y = pos_after_step - current_pos.y;
            }
        }
    }

    pub fn getPosition(self: *MonsterController) delve.math.Vec3 {
        return self.owner.getPosition();
    }
};

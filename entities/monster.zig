const std = @import("std");
const delve = @import("delve");
const entities = @import("../game/entities.zig");
const character = @import("character.zig");
const sprite = @import("sprite.zig");
const main = @import("../main.zig");
const math = delve.math;

pub const MonsterBrainComponent = struct {
    interface: entities.EntityComponent = undefined,

    pub fn init(self: *MonsterBrainComponent, interface: entities.EntityComponent) void {
        self.interface = interface;
    }

    pub fn deinit(self: *MonsterBrainComponent) void {
        _ = self;
    }

    pub fn tick(self: *MonsterBrainComponent, delta: f32) void {
        _ = delta;

        const player_opt = main.game_instance.player_controller;
        if (player_opt == null)
            return;

        const movement_component_opt = self.interface.owner.getComponent(character.CharacterMovementComponent);
        if (movement_component_opt) |movement_component| {
            const vec_to_player = player_opt.?.getPosition().sub(movement_component.getPosition()).norm().scale(4.0);
            movement_component.move_dir = vec_to_player;

            const sprite_opt = self.interface.owner.getComponent(sprite.SpriteComponent);
            if (sprite_opt) |s| {
                const current_pos = movement_component.getPosition();
                const pos_after_step = movement_component.getStepLerpToHeight(current_pos.y);
                s.position_offset.y = pos_after_step - current_pos.y;
            }
        }
    }
};

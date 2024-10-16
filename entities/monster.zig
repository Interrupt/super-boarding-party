const std = @import("std");
const delve = @import("delve");
const entities = @import("../game/entities.zig");
const character = @import("character.zig");
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

        const player = main.game_instance.player_controller;
        const movement_component_opt = self.interface.owner.getSceneComponent(character.CharacterMovementComponent);

        if (movement_component_opt) |movement_component| {
            const vec_to_player = player.?.getPosition().sub(movement_component.getPosition()).norm().scale(4.0);
            movement_component.move_dir = vec_to_player;
        }
    }
};

const std = @import("std");
const delve = @import("delve");
const entities = @import("../game/entities.zig");
const monster = @import("monster.zig");
const math = delve.math;

/// Adds stats like HP to this entity
pub const ActorStats = struct {
    // properties
    hp: i32 = 100,
    speed: f32 = 1.0,

    // interface
    owner: entities.Entity = entities.InvalidEntity,

    // calculated
    is_alive: bool = true,

    pub fn init(self: *ActorStats, interface: entities.EntityComponent) void {
        self.owner = interface.owner;
    }

    pub fn deinit(self: *ActorStats) void {
        _ = self;
    }

    pub fn tick(self: *ActorStats, delta: f32) void {
        _ = delta;

        // we're alive if we still have HP left!
        self.is_alive = self.hp > 0;
    }

    pub fn isAlive(self: *ActorStats) bool {
        return self.is_alive;
    }

    pub fn takeDamage(self: *ActorStats, dmg: i32, instigator: entities.Entity) void {
        self.hp -= dmg;
        if (self.owner.getComponent(monster.MonsterComponent)) |monster_comp| {
            monster_comp.onHurt(dmg, instigator);
        }
    }
};

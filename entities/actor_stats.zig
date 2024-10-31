const std = @import("std");
const delve = @import("delve");
const entities = @import("../game/entities.zig");
const monster = @import("monster.zig");
const character = @import("character.zig");
const math = delve.math;

/// Adds stats like HP to this entity
pub const ActorStats = struct {
    // properties
    hp: i32 = 100,
    speed: f32 = 8.0,

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

        // cache if we're alive
        self.is_alive = self.isAlive();

        if (self.owner.getComponent(character.CharacterMovementComponent)) |movement| {
            movement.move_speed = self.speed;
        }
    }

    pub fn isAlive(self: *ActorStats) bool {
        // we're alive if we still have HP left!
        return self.hp > 0;
    }

    pub fn takeDamage(self: *ActorStats, dmg: i32, instigator: ?entities.Entity) void {
        // don't take more damage when already dead!
        if (!self.is_alive)
            return;

        self.hp -= dmg;
        self.is_alive = self.isAlive();

        if (self.owner.getComponent(monster.MonsterController)) |m| {
            if (self.is_alive) {
                m.onHurt(dmg, instigator);
            } else {
                m.onDeath(dmg, instigator);
            }
        }
    }

    pub fn knockback(self: *ActorStats, amount: f32, direction: math.Vec3) void {
        const vel = self.owner.getVelocity();
        self.owner.setVelocity(vel.add(direction.scale(amount)));
    }
};

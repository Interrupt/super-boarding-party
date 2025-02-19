const std = @import("std");
const delve = @import("delve");
const basics = @import("basics.zig");
const entities = @import("../game/entities.zig");
const box_collision = @import("box_collision.zig");
const player_components = @import("player.zig");
const stats = @import("actor_stats.zig");
const collision = @import("../utils/collision.zig");
const emitter = @import("particle_emitter.zig");
const sprite = @import("sprite.zig");
const triggers = @import("triggers.zig");
const spritesheets = @import("../managers/spritesheets.zig");
const mover = @import("mover.zig");
const options = @import("../game/options.zig");
const string = @import("../utils/string.zig");
const weapons = @import("weapon.zig");

const math = delve.math;

pub const ProjectileComponent = struct {
    attack_info: weapons.AttackInfo = .{},
    instigator: entities.Entity,

    spritesheet_col: usize = 0,
    spritesheet_row: usize = 2,

    // interface
    owner: entities.Entity = entities.InvalidEntity,

    // calculated
    _projectile_sprite: ?*sprite.SpriteComponent = null,

    pub fn init(self: *ProjectileComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;

        self._projectile_sprite = self.owner.createNewComponent(
            sprite.SpriteComponent,
            .{
                .spritesheet = string.String.init("sprites/sprites"),
                .spritesheet_col = self.spritesheet_col,
                .spritesheet_row = self.spritesheet_row,
                .blend_mode = .ALPHA,
                .scale = 1.0,
                .color = delve.colors.cyan,
                .use_lighting = false,
                .position = delve.math.Vec3.new(0.0, -0.215, 0.0),
            },
        ) catch {
            delve.debug.warning("Could not projectile weapon sprite!", .{});
            return;
        };
    }

    pub fn deinit(self: *ProjectileComponent) void {
        _ = self;
    }

    pub fn tick(self: *ProjectileComponent, delta: f32) void {
        // TODO: Do we need a new physical object component?
        // This should be shared between all physical objects like characters and projectiles
        const vel = self.owner.getVelocity();
        const new_pos = self.owner.getPosition().add(vel.scale(delta));
        self.owner.setPosition(new_pos);
    }
};

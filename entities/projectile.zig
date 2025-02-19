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
    collides_world: bool = true,

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
        if (self.collides_world) {
            // setup our move data for collision checking
            var move = collision.MoveInfo{
                .pos = self.owner.getPosition(),
                .vel = self.owner.getVelocity(),
                .size = math.Vec3.one.scale(0.1),
                .checking = self.owner,
            };

            const world_opt = self.owner.getOwningWorld();
            if (world_opt == null)
                return;

            const movehit = collision.collidesWithMapWithVelocity(world_opt.?, move.pos, move.size, move.vel.scale(delta), move.checking, false);
            if (movehit) |hit| {
                const move_dir = move.vel;
                const reflect: math.Vec3 = move_dir.sub(hit.normal.scale(2 * move_dir.dot(hit.normal)));

                // back away from the hit a teeny bit to fix epsilon errors
                move.pos = hit.pos.add(hit.normal.scale(0.00001));

                self.owner.setVelocity(reflect);

                // self.owner.deinit();
                // return;
            }
        }

        const vel = self.owner.getVelocity();
        const new_pos = self.owner.getPosition().add(vel.scale(delta));
        self.owner.setPosition(new_pos);
    }
};

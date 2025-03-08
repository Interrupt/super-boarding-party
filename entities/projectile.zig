const std = @import("std");
const delve = @import("delve");
const basics = @import("basics.zig");
const entities = @import("../game/entities.zig");
const explosion = @import("explosion.zig");
const box_collision = @import("box_collision.zig");
const player_components = @import("player.zig");
const stats = @import("actor_stats.zig");
const collision = @import("../utils/collision.zig");
const emitter = @import("particle_emitter.zig");
const sprite = @import("sprite.zig");
const lights = @import("light.zig");
const triggers = @import("triggers.zig");
const spritesheets = @import("../managers/spritesheets.zig");
const mover = @import("mover.zig");
const solids = @import("quakesolids.zig");
const options = @import("../game/options.zig");
const string = @import("../utils/string.zig");
const weapons = @import("weapon.zig");

const math = delve.math;

pub const ExplosionType = enum {
    BigExplosion,
    PlasmaHit,
    BulletHit,
};

pub const ProjectileComponent = struct {
    attack_info: weapons.AttackInfo = .{},
    instigator: entities.Entity,
    spawn_dir: math.Vec3,
    speed: f32 = 40.0,
    collides_world: bool = true,
    bounces: bool = false,
    use_gravity: bool = false,
    gravity_amount: f32 = -25.0,
    color: delve.colors.Color = delve.colors.cyan,
    explosion_type: ExplosionType = .PlasmaHit,

    spritesheet_col: usize = 0,
    spritesheet_row: usize = 2,

    // interface
    owner: entities.Entity = entities.InvalidEntity,

    // calculated
    _projectile_sprite: ?*sprite.SpriteComponent = null,
    _in_water: bool = false,
    _first_tick: bool = true,

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
                .color = self.color,
                .use_lighting = false,
                .position = delve.math.Vec3.new(0.0, 0.0, 0.0),
            },
        ) catch {
            delve.debug.warning("Could not projectile weapon sprite!", .{});
            return;
        };

        _ = self.owner.createNewComponent(lights.LightComponent, .{
            .color = self.color,
            .brightness = 2.0,
            .radius = 2.0,
        }) catch {
            return;
        };

        self.owner.setVelocity(self.spawn_dir.scale(self.speed));
    }

    pub fn deinit(self: *ProjectileComponent) void {
        _ = self;
    }

    pub fn tick(self: *ProjectileComponent, delta: f32) void {
        // TODO: Do we need a new physical object component?
        // This should be shared between all physical objects like characters and projectiles

        defer self._first_tick = false;

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

            const movehit = collision.collidesWithMapWithVelocity(world_opt.?, move.pos, move.size, move.vel.scale(delta), move.checking, true);
            if (movehit) |hit| {
                // don't hit ourselves!
                const do_hit = hit.entity == null or !hit.entity.?.id.equals(self.instigator.id);

                if (do_hit) {
                    if (self.bounces) {
                        const move_dir = move.vel;
                        const reflect: math.Vec3 = move_dir.sub(hit.normal.scale(2 * move_dir.dot(hit.normal)));

                        // back away from the hit a teeny bit to fix epsilon errors
                        self.owner.setPosition(hit.pos.add(hit.normal.scale(0.00001)));
                        self.owner.setVelocity(reflect);
                        return;
                    }

                    if (hit.entity) |hit_entity| {
                        const stats_opt = hit_entity.getComponent(stats.ActorStats);
                        if (stats_opt) |s| {
                            s.takeDamage(.{
                                .dmg = self.attack_info.dmg,
                                .knockback = self.attack_info.knockback,
                                .instigator = self.instigator,
                                .attack_normal = self.owner.getVelocity().norm(),
                                .hit_pos = hit.pos,
                                .hit_normal = hit.normal,
                            });
                        }
                    }

                    self.doHitExplosion(hit.pos, hit.normal);
                    self.playWorldHitEffects(move.vel.norm(), hit.pos, hit.normal, hit.entity);

                    self.owner.deinit();
                    return;
                }
            }

            // are we in water now?
            const was_in_water = self._in_water;
            self._in_water = collision.collidesWithLiquid(world_opt.?, move.pos.add(move.vel.scale(delta)), move.size);

            // splash!
            if (!was_in_water and self._in_water and !self._first_tick) {
                playWeaponWaterHitEffects(world_opt.?, move.vel.norm(), move.pos, math.Vec3.y_axis);
            }
        }

        var vel = self.owner.getVelocity();
        if (self.use_gravity) {
            vel.y += self.gravity_amount * delta;
            self.owner.setVelocity(vel);
        }

        const new_pos = self.owner.getPosition().add(vel.scale(delta));
        self.owner.setPosition(new_pos);
    }

    pub fn doHitExplosion(self: *ProjectileComponent, hit_pos: math.Vec3, hit_norm: math.Vec3) void {
        const world = self.owner.getOwningWorld().?;
        var exp_entity = world.createEntity(.{}) catch {
            return;
        };

        _ = exp_entity.createNewComponent(basics.TransformComponent, .{ .position = hit_pos.add(hit_norm.scale(0.2)) }) catch {
            return;
        };

        var explosion_props: explosion.ExplosionComponent = switch (self.explosion_type) {
            .PlasmaHit => .{
                .sprite_color = self.color,
                .sprite_anim_row = 0,
                .sprite_anim_len = 4,
                .damage = 5,
                .knockback = 5.0,
                .range = 1.75,
                .play_sound = false,
                .light_radius = 3.0,
                .smoke_count = 2,
                .smoke_color = delve.colors.Color.new(1.0, 1.0, 1.0, 0.35),
            },
            .BulletHit => .{
                .sprite_color = delve.colors.yellow,
                .sprite_anim_row = 1,
                .sprite_anim_col = 1,
                .sprite_anim_len = 3,
                .range = 0.0,
                .play_sound = false,
                .light_radius = 3.0,
                .smoke_count = 2,
                .smoke_color = delve.colors.Color.new(1.0, 1.0, 1.0, 0.35),
            },
            else => .{ .light_color = delve.colors.orange },
        };
        explosion_props.instigator = self.instigator;

        _ = exp_entity.createNewComponent(explosion.ExplosionComponent, explosion_props) catch {
            return;
        };
    }

    pub fn playWorldHitEffects(self: *ProjectileComponent, attack_normal: math.Vec3, hit_pos: math.Vec3, hit_normal: math.Vec3, hit_entity: ?entities.Entity) void {
        // only some explosion types get world hit effects
        switch (self.explosion_type) {
            .BigExplosion => {
                return;
            },
            else => {},
        }

        if (hit_entity != null) {
            const solids_opt = hit_entity.?.getComponent(solids.QuakeSolidsComponent);
            if (solids_opt == null) {
                // Hit something other than the world!
                return;
            }
        }

        const world = self.owner.getOwningWorld().?;
        var reflect: math.Vec3 = attack_normal.sub(hit_normal.scale(2 * attack_normal.dot(hit_normal)));

        // play hit vfx
        var hit_emitter = world.createEntity(.{}) catch {
            return;
        };
        _ = hit_emitter.createNewComponent(basics.TransformComponent, .{ .position = hit_pos.add(hit_normal.scale(0.021)) }) catch {
            return;
        };
        // hit sparks
        _ = hit_emitter.createNewComponent(emitter.ParticleEmitterComponent, .{
            .num = 3,
            .num_variance = 3,
            ._spritesheet = spritesheets.getSpriteSheet("sprites/blank"),
            .lifetime = 0.2,
            .lifetime_variance = 0.2,
            .velocity = reflect.lerp(hit_normal, 0.5).scale(20),
            .velocity_variance = math.Vec3.one.scale(10.0),
            .gravity = -55,
            .color = self.color,
            .scale = 0.3125, // 1 / 32
            .delete_owner_when_done = false,
            .use_lighting = false,
        }) catch {
            return;
        };

        // hit debris
        _ = hit_emitter.createNewComponent(emitter.ParticleEmitterComponent, .{
            .num = 3,
            .num_variance = 10,
            ._spritesheet = spritesheets.getSpriteSheet("sprites/blank"),
            .lifetime = 2.0,
            .velocity = reflect.scale(10),
            .velocity_variance = math.Vec3.one.scale(15.0),
            .gravity = -55,
            .color = delve.colors.dark_grey,
            .scale = 0.3125, // 1 / 32
            .delete_owner_when_done = false,
        }) catch {
            return;
        };

        if (hit_entity) |hit| {
            // attach decal to world hit entities!
            _ = hit_emitter.createNewComponent(basics.AttachmentComponent, .{
                .attached_to = hit,
                .offset_position = hit_emitter.getPosition().sub(hit.getPosition()),
            }) catch {
                return;
            };

            // some things should activate on damage
            if (hit.getComponent(triggers.TriggerComponent)) |t| {
                if (t.trigger_on_damage) {
                    t.onTrigger(null);
                }
            } else if (hit.getComponent(mover.MoverComponent)) |m| {
                if (m.start_type == .WAIT_FOR_DAMAGE) {
                    m.onDamage(entities.InvalidEntity);
                }
            }
        }

        // TODO: move this into a helper!
        const dir = hit_normal;
        var transform = math.Mat4.identity;
        if (!(dir.x == 0 and dir.y == 1 and dir.z == 0)) {
            if (!(dir.x == 0 and dir.y == -1 and dir.z == 0)) {
                // only need to rotate when we're not already facing up
                transform = transform.mul(math.Mat4.direction(dir, math.Vec3.y_axis)).mul(math.Mat4.rotate(0, math.Vec3.x_axis));
            } else {
                // flip upside down!
                transform = transform.mul(math.Mat4.rotate(90, math.Vec3.x_axis));
            }
        } else {
            transform = math.Mat4.rotate(270, math.Vec3.x_axis);
        }

        // hit decal
        _ = hit_emitter.createNewComponent(sprite.SpriteComponent, .{
            .blend_mode = .ALPHA,
            ._spritesheet = spritesheets.getSpriteSheet("sprites/particles"),
            .spritesheet_row = 1,
            .scale = 2.0,
            .position = delve.math.Vec3.new(0, 0, 0),
            .billboard_type = .NONE,
            .rotation_offset = delve.math.Quaternion.fromMat4(transform),
        }) catch {
            return;
        };

        _ = hit_emitter.createNewComponent(basics.LifetimeComponent, .{
            .lifetime = 20.0,
        }) catch {
            return;
        };
    }
};

pub fn playWeaponWaterHitEffects(world: *entities.World, attack_normal: math.Vec3, hit_pos: math.Vec3, hit_normal: math.Vec3) void {
    _ = attack_normal;

    // play water hit vfx
    var hit_emitter = world.createEntity(.{}) catch {
        return;
    };
    _ = hit_emitter.createNewComponent(basics.TransformComponent, .{ .position = hit_pos.add(hit_normal.scale(0.021)) }) catch {
        return;
    };
    // splash droplet particles
    _ = hit_emitter.createNewComponent(emitter.ParticleEmitterComponent, .{
        .num = 6,
        .num_variance = 20,
        ._spritesheet = spritesheets.getSpriteSheet("sprites/blank"),
        .lifetime = 0.5,
        .lifetime_variance = 0.2,
        .velocity = hit_normal.scale(15),
        .velocity_variance = math.Vec3.one.scale(10.0),
        .gravity = -55,
        .color = delve.colors.cyan,
        .scale = 0.3125, // 1 / 32
        .delete_owner_when_done = true,
    }) catch {
        return;
    };
}

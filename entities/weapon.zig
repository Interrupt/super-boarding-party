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

const math = delve.math;

pub const WeaponType = enum {
    Melee,
    Pistol,
    Shotgun,
    AssaultRifle,
};

pub const AttackType = enum {
    SemiAuto,
    Auto,
};

pub const WeaponComponent = struct {
    weapon_type: WeaponType = .Pistol,
    attack_type: AttackType = .Auto,
    attack_delay_timer: f32 = 0.1,
    attack_range: f32 = 100.0,

    spritesheet_row: usize = 1,

    // interface
    owner: entities.Entity = entities.InvalidEntity,
    component_interface: entities.EntityComponent = undefined,

    lag_vert: f32 = 0.3333,
    lag_horiz: f32 = 1.0,

    // calculated
    _weapon_sprite: ?*sprite.SpriteComponent = null,

    pub fn init(self: *WeaponComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;
        self.component_interface = interface;

        self._weapon_sprite = self.owner.createNewComponentWithConfig(
            sprite.SpriteComponent,
            .{ .persists = false },
            .{
                .spritesheet = string.String.init("sprites/items"),
                .spritesheet_col = 1,
                .spritesheet_row = self.spritesheet_row,
                .scale = 0.185,
                .position = delve.math.Vec3.new(0, -0.215, 0.5),
            },
        ) catch {
            delve.debug.warning("Could not create weapon sprite!", .{});
            return;
        };

        delve.debug.log("Created weapon sprite", .{});
    }

    pub fn deinit(self: *WeaponComponent) void {
        _ = self;
    }

    pub fn tick(self: *WeaponComponent, delta: f32) void {
        if (self._weapon_sprite == null)
            return;

        if (self._weapon_sprite.?.animation == null) {
            if (self.attack_delay_timer > 0.0)
                self.attack_delay_timer -= delta;
        }

        self.applyCameraShake();
        self.applyWeaponLag();
    }

    pub fn attack(self: *WeaponComponent) void {
        switch (self.attack_type) {
            .SemiAuto => {
                // If we're semi-auto, wait between for the next trigger pull
                if (!delve.platform.input.isMouseButtonJustPressed(.LEFT)) {
                    return;
                }
            },
            else => {},
        }

        // const sprite_opt = self.owner.getComponent(sprite.SpriteComponent);
        // if (sprite_opt == null) {
        //     delve.debug.warning("No weapon sprite found!", .{});
        //     return;
        // }

        // Already attacking? Ignore.
        // self._weapon_sprite = sprite_opt.?;
        if (self._weapon_sprite.?.animation != null)
            return;

        if (self.attack_delay_timer > 0.0)
            return;

        // get our player
        const player_controller_opt = self.owner.getComponent(player_components.PlayerController);
        if (player_controller_opt == null) {
            delve.debug.warning("No player controller found!", .{});
            return;
        }

        // start the attack!
        var player = player_controller_opt.?;
        self.attack_delay_timer = 0.01;
        self._weapon_sprite.?.playAnimation(self._weapon_sprite.?.spritesheet_row, 2, 3, false, 40.0);

        const camera_ray = player.camera.direction;
        player.weapon_flash_timer = 0.0;
        player._camera_shake_amt = @max(player._camera_shake_amt, 0.1);

        // Test hitscan weapon!
        // Find where we hit the world first
        const world = entities.getWorld(self.owner.id.world_id).?;

        // check solid world collision
        const ray_did_hit = collision.rayCollidesWithMap(world, delve.spatial.Ray.init(player.camera.position, camera_ray), .{ .checking = self.owner });
        var world_hit_len = std.math.floatMax(f32);
        if (ray_did_hit) |hit_info| {
            world_hit_len = hit_info.pos.sub(player.camera.position).len();
        }

        // check water collision
        const ray_did_hit_water = collision.rayCollidesWithMap(world, delve.spatial.Ray.init(player.camera.position, camera_ray), .{ .checking = self.owner, .solids_custom_flag_filter = 1 });
        var water_hit_len = std.math.floatMax(f32);
        if (ray_did_hit_water) |hit_info| {
            water_hit_len = hit_info.pos.sub(player.camera.position).len();
        }

        // Now see if we hit an entity
        var hit_entity: bool = false;
        const ray_did_hit_entity = collision.checkRayEntityCollision(world, delve.spatial.Ray.init(player.camera.position, camera_ray), self.owner);
        if (ray_did_hit_entity) |hit_info| {
            const entity_hit_len = hit_info.pos.sub(player.camera.position).len();
            if (entity_hit_len <= world_hit_len) {
                hit_entity = true;
                if (hit_info.entity) |entity| {
                    // if we have stats, take damage!
                    const stats_opt = entity.getComponent(stats.ActorStats);
                    if (stats_opt) |s| {
                        s.takeDamage(.{
                            .dmg = 3,
                            .knockback = 30.0,
                            .instigator = self.owner,
                            .attack_normal = camera_ray,
                            .hit_pos = hit_info.pos,
                            .hit_normal = hit_info.normal,
                        });
                    }
                }
            }
        }

        // Do world hit vfx if needed!
        if (!hit_entity) {
            if (ray_did_hit) |hit_info| {
                playWeaponWorldHitEffects(world, camera_ray, hit_info.pos, hit_info.normal, hit_info.entity);

                // if the world hit has stats, also take damage!
                if (hit_info.entity) |entity| {
                    if (entity.getComponent(stats.ActorStats)) |s| {
                        s.takeDamage(.{
                            .dmg = 3,
                            .knockback = 0.0,
                            .instigator = self.owner,
                            .attack_normal = camera_ray,
                            .hit_pos = hit_info.pos,
                            .hit_normal = hit_info.normal,
                        });
                    }
                }
            }
            if (ray_did_hit_water) |hit_info| {
                if (water_hit_len <= world_hit_len)
                    playWeaponWaterHitEffects(world, camera_ray, hit_info.pos, hit_info.normal);
            }
        }

        // play attack sound!
        _ = delve.platform.audio.playSound("assets/audio/sfx/pistol-shot.mp3", .{ .volume = 0.8 * options.options.sfx_volume });
    }

    pub fn applyCameraShake(self: *WeaponComponent) void {
        const player_controller_opt = self.owner.getComponent(player_components.PlayerController);
        if (player_controller_opt == null)
            return;

        const player = player_controller_opt.?;
        const time = delve.platform.app.getTime();

        // calculate shake!
        var camera_shake: math.Vec3 = math.Vec3.zero;
        if (player._camera_shake_amt > 0.0) {
            const shake_x: f32 = @floatCast(@sin(time * 60.0) * player._camera_shake_amt);
            const shake_y: f32 = @floatCast(@cos(time * 65.25) * player._camera_shake_amt * 0.75);
            const shake_z: f32 = @floatCast(@sin(time * 57.25) * player._camera_shake_amt);
            camera_shake = math.Vec3.new(shake_x, shake_y, shake_z).scale(0.075);
        }

        // apply shake to weapon sprite
        var weapon_sprite = self._weapon_sprite.?;
        weapon_sprite.position_offset = player.camera.position.sub(player.getRenderPosition());
        weapon_sprite.position_offset = weapon_sprite.position_offset.add(camera_shake.scale(0.5));
    }

    pub fn applyWeaponLag(self: *WeaponComponent) void {
        if (self._weapon_sprite == null)
            return;

        const player_controller_opt = self.owner.getComponent(player_components.PlayerController);
        if (player_controller_opt == null)
            return;

        const player = player_controller_opt.?;
        const time = delve.platform.app.getTime();

        // add head bob
        var weapon_sprite = self._weapon_sprite.?;

        const head_bob_v: math.Vec3 = player.camera.up.scale(@as(f32, @floatCast(@abs(@sin(time * 10.0)))) * player.head_bob_amount * 0.5);
        const head_bob_h: math.Vec3 = player.camera.right.scale(@as(f32, @floatCast(@sin(time * 10.0))) * player.head_bob_amount * 1.0);
        weapon_sprite.position_offset = weapon_sprite.position_offset.add(head_bob_h).add(head_bob_v);

        // add camera view lag
        const cam_lag_v: math.Vec3 = player.camera.up.scale(player._cam_pitch_lag_amt * -0.005 * self.lag_vert);
        const cam_lag_h: math.Vec3 = player.camera.right.scale(player._cam_yaw_lag_amt * 0.005 * self.lag_horiz);
        weapon_sprite.position_offset = weapon_sprite.position_offset.add(cam_lag_h).add(cam_lag_v);
    }
};

pub fn playWeaponWorldHitEffects(world: *entities.World, attack_normal: math.Vec3, hit_pos: math.Vec3, hit_normal: math.Vec3, hit_entity: ?entities.Entity) void {
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
        .color = delve.colors.orange,
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

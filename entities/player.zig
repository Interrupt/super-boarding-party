const std = @import("std");
const delve = @import("delve");
const basics = @import("basics.zig");
const collision = @import("../utils/collision.zig");
const entities = @import("../game/entities.zig");
const box_collision = @import("box_collision.zig");
const character = @import("character.zig");
const quakemap = @import("quakemap.zig");
const sprite = @import("sprite.zig");
const spritesheets = @import("../managers/spritesheets.zig");
const mover = @import("mover.zig");
const triggers = @import("triggers.zig");
const emitter = @import("particle_emitter.zig");
const stats = @import("actor_stats.zig");
const string = @import("../utils/string.zig");
const lights = @import("light.zig");
const main = @import("../main.zig");
const options = @import("../game/options.zig");

const math = delve.math;
const interpolation = delve.utils.interpolation;

pub var jump_acceleration: f32 = 20.0;

var rand = std.rand.DefaultPrng.init(0);

pub const PlayerController = struct {
    name: string.String = string.empty,

    camera: delve.graphics.camera.Camera = undefined,
    eyes_in_water: bool = false,

    weapon_flash_timer: f32 = 0.1,
    weapon_flash_time: f32 = 0.1,

    screen_flash_color: ?delve.colors.Color = delve.colors.red,
    screen_flash_time: f32 = 0.0,
    screen_flash_timer: f32 = 0.0,

    did_init: bool = false,

    attack_delay_timer: f32 = 0.0,

    owner: entities.Entity = entities.InvalidEntity,

    _weapon_sprite: *sprite.SpriteComponent = undefined,
    _player_light: *lights.LightComponent = undefined,
    _msg_time: f32 = 0.0,

    _messages: std.ArrayList([]const u8) = undefined,
    _message: [128]u8 = std.mem.zeroes([128]u8),

    _camera_shake_amt: f32 = 0.0,
    _camera_shake_tilt: f32 = 0.0,
    _camera_shake_tilt_mod: f32 = 1.0,
    _camera_strafe_tilt: f32 = 0.0,

    _last_cam_yaw: f32 = 0.0,
    _last_cam_pitch: f32 = 0.0,
    _cam_yaw_lag_amt: f32 = 0.0,
    _cam_pitch_lag_amt: f32 = 0.0,

    _first_tick: bool = true,

    head_bob_amount: f32 = 0.0,

    pub fn init(self: *PlayerController, interface: entities.EntityComponent) void {
        self.owner = interface.owner;
        defer self.did_init = true;

        // Set a default player name, if none was given!
        if (self.name.len == 0)
            self.name = string.init("PlayerOne");

        if (self.did_init == false) {
            self.camera = delve.graphics.camera.Camera.init(90.0, 0.01, 512, math.Vec3.up);
        }

        delve.debug.log("Init new player controller for entity {d}", .{interface.owner.id.id});

        self._weapon_sprite = self.owner.createNewComponentWithConfig(
            sprite.SpriteComponent,
            .{ .persists = false },
            .{
                .spritesheet = string.String.init("sprites/items"),
                .spritesheet_col = 1,
                .spritesheet_row = 1,
                .scale = 0.185,
                .position = delve.math.Vec3.new(0, -0.215, 0.5),
            },
        ) catch {
            return;
        };

        self._player_light = self.owner.createNewComponentWithConfig(
            lights.LightComponent,
            .{ .persists = false },
            .{
                .color = delve.colors.yellow,
                .radius = 15.0,
                .position = delve.math.Vec3.new(0, 1.0, 0),
                .brightness = 0.8,
            },
        ) catch {
            return;
        };

        self._messages = std.ArrayList([]const u8).init(delve.mem.getAllocator());
    }

    pub fn deinit(self: *PlayerController) void {
        delve.debug.log("Deinitializing player controller: '{s}'", .{self.name.str});
        self.name.deinit();
    }

    pub fn tick(self: *PlayerController, delta: f32) void {
        const time = delve.platform.app.getTime();
        defer self._first_tick = false;

        // accelerate the player from input
        self.acceleratePlayer(delta);

        // set our basic camera position
        self.camera.position = self.owner.getRenderPosition();

        // camera shake!
        var camera_shake: math.Vec3 = math.Vec3.zero;
        if (self._camera_shake_amt > 0.0) {
            const shake_x: f32 = @floatCast(@sin(time * 60.0) * self._camera_shake_amt);
            const shake_y: f32 = @floatCast(@cos(time * 65.25) * self._camera_shake_amt * 0.75);
            const shake_z: f32 = @floatCast(@sin(time * 57.25) * self._camera_shake_amt);
            camera_shake = math.Vec3.new(shake_x, shake_y, shake_z).scale(0.075);
            self.camera.position = self.camera.position.add(camera_shake);
            self._camera_shake_amt -= delta * 0.5;
        }

        // add our damage tilt to the camera roll
        var cam_roll: f32 = 0.0;
        if (self._camera_shake_tilt > 0.0) {
            cam_roll += self._camera_shake_tilt * self._camera_shake_tilt_mod;
            self._camera_shake_tilt -= delta * 15.0;
        }

        // add our strafe velocity to the roll
        const velocity = self.owner.getVelocity();
        const strafe_vec = self.camera.right.mul(velocity);
        cam_roll += std.math.clamp(-0.125 * strafe_vec.dot(self.camera.right), -1.25, 1.25);

        self.camera.setRoll(cam_roll);

        if (self._msg_time > 0.0) {
            self._msg_time -= delta;
        } else {
            if (self._messages.items.len > 0) {
                self._messages.clearRetainingCapacity();
            }
        }

        // lerp our step up, and apply other held weapon bobbing
        const movement_component_opt = self.owner.getComponent(character.CharacterMovementComponent);
        if (movement_component_opt) |movement_component| {
            // smooth the camera when stepping up onto something
            self.camera.position.y = movement_component.getStepLerpToHeight(self.camera.position.y);
            const cam_diff = self.camera.position.y - movement_component.state.pos.y;

            // add eye height
            self.camera.position.y += movement_component.state.size.y * 0.35;

            // adjust weapon sprite to our eye height
            self._weapon_sprite.position_offset = self.camera.position.sub(self.getRenderPosition());

            doScreenShake(self, delta);
            doWeaponLag(self, cam_diff);

            // check if our eyes are under water
            self.eyes_in_water = movement_component.state.eyes_in_water;
        }

        // do mouse look
        self.camera.runSimpleCamera(0, 60 * delta, true);

        // Todo: Why is this backwards?
        const camera_ray = self.camera.direction;

        // set our owner's rotation to match our look direction
        const dir_mat = delve.math.Mat4.direction(camera_ray, delve.math.Vec3.y_axis);
        self.owner.setRotation(delve.math.Quaternion.fromMat4(dir_mat));

        // combat!
        if (delve.platform.input.isMouseButtonPressed(.LEFT)) {
            self.attack();

            // HACK: Why do we keep losing mouse focus on web?
            delve.platform.app.captureMouse(true);
        }

        // update weapon flash
        if (self.weapon_flash_timer < self.weapon_flash_time)
            self.weapon_flash_timer += delta;

        self._player_light.brightness = interpolation.EaseQuad.applyIn(1.0, 0.0, self.weapon_flash_timer / self.weapon_flash_time);

        // update screen flash
        if (self.screen_flash_timer > 0.0)
            self.screen_flash_timer = @max(0.0, self.screen_flash_timer - delta);

        // handle attack delay
        if (self._weapon_sprite.animation == null) {
            if(self.attack_delay_timer > 0.0)
                self.attack_delay_timer -= delta;
        }

        // update audio listener
        delve.platform.audio.setListenerPosition(self.camera.position);
        delve.platform.audio.setListenerDirection(camera_ray);
        delve.platform.audio.setListenerWorldUp(delve.math.Vec3.y_axis);
    }

    pub fn doScreenShake(self: *PlayerController, delta: f32) void {
        const time = delve.platform.app.getTime();

        // camera shake!
        var camera_shake: math.Vec3 = math.Vec3.zero;
        if (self._camera_shake_amt > 0.0) {
            const shake_x: f32 = @floatCast(@sin(time * 60.0) * self._camera_shake_amt);
            const shake_y: f32 = @floatCast(@cos(time * 65.25) * self._camera_shake_amt * 0.75);
            const shake_z: f32 = @floatCast(@sin(time * 57.25) * self._camera_shake_amt);
            camera_shake = math.Vec3.new(shake_x, shake_y, shake_z).scale(0.075);
            self.camera.position = self.camera.position.add(camera_shake);
            self._camera_shake_amt -= delta * 0.5;
        }

        if (self._camera_shake_tilt > 0.0) {
            self.camera.setRoll(self._camera_shake_tilt * self._camera_shake_tilt_mod);
            self._camera_shake_tilt -= delta * 15.0;
        }

        // weapon shake as well
        self._weapon_sprite.position_offset = self._weapon_sprite.position_offset.add(camera_shake.scale(0.5));
    }

    pub fn doWeaponLag(self: *PlayerController, cam_diff: f32) void {
        const time = delve.platform.app.getTime();

        // add weapon bob
        const head_bob_v: math.Vec3 = self.camera.up.scale(@as(f32, @floatCast(@abs(@sin(time * 10.0)))) * self.head_bob_amount * 0.5);
        const head_bob_h: math.Vec3 = self.camera.right.scale(@as(f32, @floatCast(@sin(time * 10.0))) * self.head_bob_amount * 1.0);
        self._weapon_sprite.position_offset = self._weapon_sprite.position_offset.add(head_bob_h).add(head_bob_v);

        // add turn lag to held weapon
        self._cam_yaw_lag_amt += self.camera.yaw_angle - self._last_cam_yaw;
        self._cam_pitch_lag_amt += self.camera.pitch_angle - self._last_cam_pitch;
        self._cam_yaw_lag_amt = self._cam_yaw_lag_amt * 0.9;
        self._cam_pitch_lag_amt = self._cam_pitch_lag_amt * 0.9;

        // add damage screen tilt to the held weapon as well
        self._cam_yaw_lag_amt += self._camera_shake_tilt * self._camera_shake_tilt_mod * 0.25;

        // add stepping up or falling lerp to our held weapon as well
        self._cam_pitch_lag_amt += cam_diff * -10.0;

        // clamp lag amount
        const max_lag = 15.0;
        self._cam_yaw_lag_amt = std.math.clamp(self._cam_yaw_lag_amt, -max_lag, max_lag);
        self._cam_pitch_lag_amt = std.math.clamp(self._cam_pitch_lag_amt, -max_lag, max_lag);

        const cam_lag_v: math.Vec3 = self.camera.up.scale(self._cam_pitch_lag_amt * -0.0015);
        const cam_lag_h: math.Vec3 = self.camera.right.scale(self._cam_yaw_lag_amt * 0.005);
        self._weapon_sprite.position_offset = self._weapon_sprite.position_offset.add(cam_lag_h).add(cam_lag_v);

        // keep track of current yaw and pitch for next time
        self._last_cam_yaw = self.camera.yaw_angle;
        self._last_cam_pitch = self.camera.pitch_angle;

        if (self._first_tick) {
            self.resetWeaponLag();
        }
    }

    pub fn resetWeaponLag(self: *PlayerController) void {
        self._last_cam_yaw = self.camera.yaw_angle;
        self._last_cam_pitch = self.camera.pitch_angle;
        self._cam_yaw_lag_amt = 0;
        self._cam_pitch_lag_amt = 0;
        self._weapon_sprite.position_offset = math.Vec3.zero;
    }

    pub fn getPosition(self: *PlayerController) delve.math.Vec3 {
        return self.owner.getPosition();
    }

    pub fn getRenderPosition(self: *PlayerController) delve.math.Vec3 {
        return self.owner.getRenderPosition();
    }

    pub fn acceleratePlayer(self: *PlayerController, delta: f32) void {
        const movement_component_opt = self.owner.getComponent(character.CharacterMovementComponent);
        if (movement_component_opt == null)
            return;

        const movement_component = movement_component_opt.?;

        // Collect move direction from input
        var move_dir: math.Vec3 = math.Vec3.zero;
        var cam_walk_dir = self.camera.direction;

        // ignore the camera facing up or down when not flying or swimming
        if (movement_component.state.move_mode == .WALKING and !movement_component.state.in_water)
            cam_walk_dir.y = 0.0;

        cam_walk_dir = cam_walk_dir.norm();

        if (delve.platform.input.isKeyPressed(.W)) {
            move_dir = move_dir.add(cam_walk_dir);
        }
        if (delve.platform.input.isKeyPressed(.S)) {
            move_dir = move_dir.sub(cam_walk_dir);
        }
        if (delve.platform.input.isKeyPressed(.D)) {
            const right_dir = self.camera.getRightDirection();
            move_dir = move_dir.add(right_dir);
        }
        if (delve.platform.input.isKeyPressed(.A)) {
            const right_dir = self.camera.getRightDirection();
            move_dir = move_dir.sub(right_dir);
        }

        // ignore vertical acceleration when walking
        if (movement_component.state.move_mode == .WALKING and !movement_component.state.in_water) {
            move_dir.y = 0;
        }

        // jump and swim!
        if (movement_component.state.move_mode == .WALKING) {
            if (delve.platform.input.isKeyJustPressed(.SPACE) and movement_component.state.on_ground) {
                const vel = self.owner.getVelocity();
                self.owner.setVelocity(math.Vec3.new(vel.x, jump_acceleration, vel.z));

                movement_component.state.on_ground = false;
            } else if (delve.platform.input.isKeyPressed(.SPACE) and movement_component.state.in_water) {
                if (movement_component.state.eyes_in_water) {
                    // if we're under water, just move us up
                    move_dir.y += 1.0;
                } else {
                    // if we're at the top of the water, jump!
                    const vel = self.owner.getVelocity();
                    self.owner.setVelocity(math.Vec3.new(vel.x, jump_acceleration, vel.z));
                }
            }

            // Do some head bob when walking on ground
            if (movement_component.state.on_ground) {
                self.head_bob_amount += 0.1 * delta * move_dir.len();
            }

            // ease the head bob
            self.head_bob_amount = self.head_bob_amount * 0.94;
        } else {
            // when flying, space will move us up
            if (delve.platform.input.isKeyPressed(.SPACE)) {
                move_dir.y += 1.0;
            }
        }

        // can now apply movement based on direction
        move_dir = move_dir.norm();
        movement_component.move_dir = move_dir;
    }

    pub fn attack(self: *PlayerController) void {
        // Already attacking? Ignore.
        if (self._weapon_sprite.animation != null)
            return;

        if(self.attack_delay_timer > 0.0)
            return;

        self.attack_delay_timer = 0.01;

        self._weapon_sprite.playAnimation(self._weapon_sprite.spritesheet_row, 2, 3, false, 40.0);
        self.weapon_flash_timer = 0.0;
        self._camera_shake_amt = @max(self._camera_shake_amt, 0.1);

        const camera_ray = self.camera.direction;

        // Test hitscan weapon!
        // Find where we hit the world first
        const world = entities.getWorld(self.owner.id.world_id).?;

        // check solid world collision
        const ray_did_hit = collision.rayCollidesWithMap(world, delve.spatial.Ray.init(self.camera.position, camera_ray), .{ .checking = self.owner });
        var world_hit_len = std.math.floatMax(f32);
        if (ray_did_hit) |hit_info| {
            world_hit_len = hit_info.pos.sub(self.camera.position).len();
        }

        // check water collision
        const ray_did_hit_water = collision.rayCollidesWithMap(world, delve.spatial.Ray.init(self.camera.position, camera_ray), .{ .checking = self.owner, .solids_custom_flag_filter = 1 });
        var water_hit_len = std.math.floatMax(f32);
        if (ray_did_hit_water) |hit_info| {
            water_hit_len = hit_info.pos.sub(self.camera.position).len();
        }

        // Now see if we hit an entity
        var hit_entity: bool = false;
        const ray_did_hit_entity = collision.checkRayEntityCollision(world, delve.spatial.Ray.init(self.camera.position, camera_ray), self.owner);
        if (ray_did_hit_entity) |hit_info| {
            const entity_hit_len = hit_info.pos.sub(self.camera.position).len();
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

    pub fn setMoveMode(self: *PlayerController, move_mode: character.CharacterMoveMode) void {
        const movement_component_opt = self.owner.getComponent(character.CharacterMovementComponent);
        if (movement_component_opt) |movement_component| {
            movement_component.state.move_mode = move_mode;
        }
    }

    pub fn getMoveMode(self: *PlayerController) character.CharacterMoveMode {
        const movement_component_opt = self.owner.getComponent(character.CharacterMovementComponent);
        if (movement_component_opt) |movement_component| {
            return movement_component.state.move_mode;
        }
        return .WALKING;
    }

    pub fn getSize(self: *PlayerController) math.Vec3 {
        if (self.owner.getComponent(box_collision.BoxCollisionComponent)) |c| {
            return c.size;
        }
        return math.Vec3.zero;
    }

    pub fn showMessage(self: *PlayerController, message: []const u8) void {
        defer self._msg_time = 3.0;

        // If this message is already shown, do nothing else
        if (self._msg_time >= 0.0 and std.mem.eql(u8, self._message[0..message.len], message))
            return;

        delve.debug.log("Showing message: {s}", .{message});

        for (0..self._message.len) |idx| {
            self._message[idx] = 0;
        }
        std.mem.copyForwards(u8, &self._message, message);
    }

    pub fn shakeCamera(self: *PlayerController, shake_amt: f32, tilt_amt: f32) void {
        self._camera_shake_amt = @max(shake_amt, self._camera_shake_amt);

        if (@abs(self._camera_shake_tilt) < @abs(tilt_amt)) {
            // randomize tilt direction each time!
            const random = rand.random();
            self._camera_shake_tilt = tilt_amt;
            self._camera_shake_tilt_mod = if (random.float(f32) > 0.5) 1.0 else -1.0;
        }
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

pub fn getComponentStorage(world: *entities.World) *entities.ComponentStorage(PlayerController) {
    return world.components.getStorageForType(PlayerController) catch {
        delve.debug.fatal("Could not get PlayerController storage!", .{});
        return undefined;
    };
}

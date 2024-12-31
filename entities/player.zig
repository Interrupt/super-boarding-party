const std = @import("std");
const delve = @import("delve");
const basics = @import("basics.zig");
const collision = @import("../utils/collision.zig");
const entities = @import("../game/entities.zig");
const box_collision = @import("box_collision.zig");
const character = @import("character.zig");
const quakemap = @import("quakemap.zig");
const sprite = @import("sprite.zig");
const mover = @import("mover.zig");
const triggers = @import("triggers.zig");
const emitter = @import("particle_emitter.zig");
const stats = @import("actor_stats.zig");
const lights = @import("light.zig");
const main = @import("../main.zig");
const options = @import("../game/options.zig");

const math = delve.math;
const interpolation = delve.utils.interpolation;

pub var jump_acceleration: f32 = 20.0;

pub const PlayerController = struct {
    name: []const u8 = "Player One",

    camera: delve.graphics.camera.Camera = undefined,
    eyes_in_water: bool = false,

    weapon_flash_timer: f32 = 0.1,
    weapon_flash_time: f32 = 0.1,

    screen_flash_color: ?delve.colors.Color = delve.colors.red,
    screen_flash_time: f32 = 0.0,
    screen_flash_timer: f32 = 0.0,

    owner: entities.Entity = entities.InvalidEntity,

    _weapon_sprite: *sprite.SpriteComponent = undefined,
    _player_light: *lights.LightComponent = undefined,
    _msg_time: f32 = 0.0,

    _messages: std.ArrayList([]const u8) = undefined,
    _message: [128]u8 = std.mem.zeroes([128]u8),

    pub fn init(self: *PlayerController, interface: entities.EntityComponent) void {
        self.owner = interface.owner;
        self.camera = delve.graphics.camera.Camera.init(90.0, 0.01, 512, math.Vec3.up);
        delve.debug.log("Init new player controller for entity {d}", .{interface.owner.id.id});

        self._weapon_sprite = self.owner.createNewComponent(sprite.SpriteComponent, .{
            .spritesheet = "sprites/items",
            .spritesheet_col = 1,
            .scale = 0.185,
            .position = delve.math.Vec3.new(0, -0.215, 0.5),
        }) catch {
            return;
        };

        self._player_light = self.owner.createNewComponent(lights.LightComponent, .{
            .color = delve.colors.yellow,
            .radius = 15.0,
            .position = delve.math.Vec3.new(0, 1.0, 0),
            .brightness = 0.8,
        }) catch {
            return;
        };

        self._messages = std.ArrayList([]const u8).init(delve.mem.getAllocator());
    }

    pub fn deinit(self: *PlayerController) void {
        _ = self;
    }

    pub fn tick(self: *PlayerController, delta: f32) void {

        // accelerate the player from input
        self.acceleratePlayer();

        // set our basic camera position
        self.camera.position = self.owner.getRenderPosition();

        if (self._msg_time > 0.0) {
            self._msg_time -= delta;
        } else {
            if (self._messages.items.len > 0) {
                self._messages.clearRetainingCapacity();
            }
        }

        // lerp our step up
        const movement_component_opt = self.owner.getComponent(character.CharacterMovementComponent);
        if (movement_component_opt) |movement_component| {
            // smooth the camera when stepping up onto something
            self.camera.position.y = movement_component.getStepLerpToHeight(self.camera.position.y);

            // add eye height
            self.camera.position.y += movement_component.state.size.y * 0.35;

            // adjust weapon sprite to our eye height
            self._weapon_sprite.position_offset.y = (self.camera.position.y - self.getRenderPosition().y);

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
        if (delve.platform.input.isMouseButtonJustPressed(.LEFT)) {
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

        // update audio listener
        delve.platform.audio.setListenerPosition(self.camera.position);
        delve.platform.audio.setListenerDirection(camera_ray);
        delve.platform.audio.setListenerWorldUp(delve.math.Vec3.y_axis);
    }

    pub fn getPosition(self: *PlayerController) delve.math.Vec3 {
        return self.owner.getPosition();
    }

    pub fn getRenderPosition(self: *PlayerController) delve.math.Vec3 {
        return self.owner.getRenderPosition();
    }

    pub fn acceleratePlayer(self: *PlayerController) void {
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

        self._weapon_sprite.playAnimation(0, 2, 3, false, 8.0);
        self.weapon_flash_timer = 0.0;

        const camera_ray = self.camera.direction;

        // Test hitscan weapon!
        // Find where we hit the world first
        const world = entities.getWorld(self.owner.id.world_id).?;

        const ray_did_hit = collision.rayCollidesWithMap(world, delve.spatial.Ray.init(self.camera.position, camera_ray), self.owner);
        var world_hit_len = std.math.floatMax(f32);
        if (ray_did_hit) |hit_info| {
            world_hit_len = hit_info.pos.sub(self.camera.position).len();
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
        .num_variance = 10,
        .spritesheet = "sprites/blank",
        .lifetime = 2.0,
        .velocity = reflect.scale(20),
        .velocity_variance = math.Vec3.one.scale(15.0),
        .gravity = -55,
        .color = delve.colors.orange,
        .scale = 0.3125, // 1 / 32
        .end_color = delve.colors.tan,
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
        .spritesheet = "sprites/particles",
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

pub fn getComponentStorage(world: *entities.World) *entities.ComponentStorage(PlayerController) {
    return world.components.getStorageForType(PlayerController) catch {
        delve.debug.fatal("Could not get PlayerController storage!", .{});
        return undefined;
    };
}

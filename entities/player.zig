const std = @import("std");
const delve = @import("delve");
const collision = @import("../utils/collision.zig");
const entities = @import("../game/entities.zig");
const character = @import("character.zig");
const quakemap = @import("quakemap.zig");
const sprite = @import("sprite.zig");
const stats = @import("actor_stats.zig");
const lights = @import("light.zig");
const main = @import("../main.zig");

const math = delve.math;
const interpolation = delve.utils.interpolation;

pub var jump_acceleration: f32 = 20.0;

pub const PlayerController = struct {
    name: []const u8 = "Player One",

    camera: delve.graphics.camera.Camera = undefined,
    eyes_in_water: bool = false,

    weapon_flash_timer: f32 = 0.0,
    weapon_flash_time: f32 = 0.1,

    owner: entities.Entity = entities.InvalidEntity,

    _weapon_sprite: *sprite.SpriteComponent = undefined,
    _player_light: *lights.LightComponent = undefined,

    pub fn init(self: *PlayerController, interface: entities.EntityComponent) void {
        self.owner = interface.owner;
        self.camera = delve.graphics.camera.Camera.init(90.0, 0.01, 512, math.Vec3.up);
        delve.debug.log("Init new player controller for entity {d}", .{interface.owner.id.id});

        self._weapon_sprite = self.owner.createNewComponent(sprite.SpriteComponent, .{
            .spritesheet = "sprites/items",
            .spritesheet_col = 1,
            .scale = 0.2,
            .position = delve.math.Vec3.new(0, -0.22, 0.5),
        }) catch {
            return;
        };

        self._player_light = self.owner.createNewComponent(lights.LightComponent, .{
            .color = delve.colors.yellow,
            .radius = 16.0,
            .position = delve.math.Vec3.new(0, 1.0, 0),
            .brightness = 0.1,
        }) catch {
            return;
        };
    }

    pub fn deinit(self: *PlayerController) void {
        _ = self;
    }

    pub fn tick(self: *PlayerController, delta: f32) void {

        // accelerate the player from input
        self.acceleratePlayer();

        // set our basic camera position
        self.camera.position = self.owner.getPosition();

        // lerp our step up
        const movement_component_opt = self.owner.getComponent(character.CharacterMovementComponent);
        if (movement_component_opt) |movement_component| {
            // smooth the camera when stepping up onto something
            self.camera.position.y = movement_component.getStepLerpToHeight(self.camera.position.y);

            // add eye height
            self.camera.position.y += movement_component.state.size.y * 0.35;

            // adjust weapon sprite to our eye height
            self._weapon_sprite.position_offset.y = (self.camera.position.y - self.getPosition().y);

            // check if our eyes are under water
            self.eyes_in_water = movement_component.state.eyes_in_water;
        }

        // do mouse look
        self.camera.runSimpleCamera(0, 60 * delta, true);

        // Todo: Why is this backwards?
        const camera_ray = self.camera.direction.scale(-1);

        // set our owner's rotation to match our look direction
        const dir_mat = delve.math.Mat4.direction(camera_ray, delve.math.Vec3.y_axis);
        self.owner.setRotation(delve.math.Quaternion.fromMat4(dir_mat));

        // combat!
        if (delve.platform.input.isMouseButtonJustPressed(.LEFT)) {
            self.attack();
        }

        // update weapon flash
        if (self.weapon_flash_timer < self.weapon_flash_time)
            self.weapon_flash_timer += delta;

        self._player_light.brightness = interpolation.EaseQuad.applyIn(1.0, 0.0, self.weapon_flash_timer / self.weapon_flash_time);

        // update audio listener
        delve.platform.audio.setListenerPosition(.{ self.camera.position.x * 0.1, self.camera.position.y * 0.1, self.camera.position.z * 0.1 });
        delve.platform.audio.setListenerDirection(.{ camera_ray.x, camera_ray.y, camera_ray.z });
        delve.platform.audio.setListenerWorldUp(.{ 0.0, 1.0, 0.0 });
    }

    pub fn getPosition(self: *PlayerController) delve.math.Vec3 {
        return self.owner.getPosition();
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
            move_dir = move_dir.sub(cam_walk_dir);
        }
        if (delve.platform.input.isKeyPressed(.S)) {
            move_dir = move_dir.add(cam_walk_dir);
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

        self.weapon_flash_timer = 0.0;
        self._weapon_sprite.playAnimation(0, 2, 3, false, 8.0);

        // Todo: Why is this backwards?
        const camera_ray = self.camera.direction.scale(-1);

        // Test hitscan weapon!
        // Find where we hit the world first
        const ray_did_hit = collision.rayCollidesWithMap(entities.getWorld(self.owner.id.world_id).?, delve.spatial.Ray.init(self.camera.position, camera_ray));
        var world_hit_len = std.math.floatMax(f32);
        if (ray_did_hit) |hit_info| {
            world_hit_len = hit_info.pos.sub(self.camera.position).len();
        }

        // Now see if we hit an entity
        const ray_did_hit_entity = collision.checkRayEntityCollision(entities.getWorld(self.owner.id.world_id).?, delve.spatial.Ray.init(self.camera.position, camera_ray), self.owner);
        if (ray_did_hit_entity) |hit_info| {
            const entity_hit_len = hit_info.pos.sub(self.camera.position).len();
            if (entity_hit_len <= world_hit_len) {
                if (hit_info.entity) |entity| {
                    // if we have stats, take damage!
                    const stats_opt = entity.getComponent(stats.ActorStats);
                    if (stats_opt) |s| {
                        s.takeDamage(3, self.owner);
                        s.knockback(30.0, camera_ray);
                    }
                }
            }
        }

        // play attack sound!
        var sound = delve.platform.audio.playSound("assets/audio/sfx/pistol-shot.mp3", 0.8);
        if (sound) |*s| {
            const player_dir = self.camera.direction.scale(-1);
            const player_pos = self.camera.position;
            s.setPosition(.{ player_pos.x * 0.1, player_pos.y * 0.1, player_pos.z * 0.1 }, .{ player_dir.x, player_dir.y, player_dir.z }, .{ 1.0, 0.0, 0.0 });
        }
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
};

pub fn getComponentStorage(world: *entities.World) *entities.ComponentStorage(PlayerController) {
    return world.components.getStorageForType(PlayerController) catch {
        delve.debug.fatal("Could not get PlayerController storage!", .{});
        return undefined;
    };
}

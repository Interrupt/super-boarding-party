const std = @import("std");
const delve = @import("delve");
const collision = @import("../utils/collision.zig");
const entities = @import("../game/entities.zig");
const character = @import("character.zig");
const quakemap = @import("quakemap.zig");
const sprite = @import("sprite.zig");
const main = @import("../main.zig");
const math = delve.math;

pub var jump_acceleration: f32 = 20.0;

pub const PlayerController = struct {
    name: []const u8 = "Player One",

    camera: delve.graphics.camera.Camera = undefined,
    eyes_in_water: bool = false,

    owner: entities.Entity = entities.InvalidEntity,

    _weapon_sprite: *sprite.SpriteComponent = undefined,

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

        self._weapon_sprite.playAnimation(0, 2, 3, false, 8.0);

        // Todo: Why is this backwards?
        const camera_ray = self.camera.direction.scale(-1);

        // Do a test world raycast!
        const ray_did_hit = collision.rayCollidesWithMap(entities.getWorld(self.owner.id.world_id).?, delve.spatial.Ray.init(self.camera.position, camera_ray));
        if (ray_did_hit) |hit_info| {
            main.render_instance.drawDebugTranslateGizmo(hit_info.pos, math.Vec3.one, hit_info.normal);
        }

        // Do a test entity raycast!
        const ray_did_hit_entity = collision.checkRayEntityCollision(entities.getWorld(self.owner.id.world_id).?, delve.spatial.Ray.init(self.camera.position, camera_ray), self.owner);
        if (ray_did_hit_entity) |hit_info| {
            main.render_instance.drawDebugTranslateGizmo(hit_info.pos, math.Vec3.one, hit_info.normal);

            // Test hitscan weapon!
            if (hit_info.entity) |entity| {
                entity.deinit();
            }
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

const std = @import("std");
const delve = @import("delve");
const collision = @import("../utils/collision.zig");
const entities = @import("../game/entities.zig");
const character = @import("character.zig");
const quakemap = @import("quakemap.zig");
const main = @import("../main.zig");
const math = delve.math;

pub var jump_acceleration: f32 = 20.0;

pub const PlayerControllerComponent = struct {
    time: f32 = 0.0,
    name: []const u8 = "Player One",

    camera: delve.graphics.camera.Camera = undefined,
    eyes_in_water: bool = false,

    owner: *entities.Entity = undefined,

    pub fn init(self: *PlayerControllerComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;
        self.camera = delve.graphics.camera.Camera.init(90.0, 0.01, 512, math.Vec3.up);
    }

    pub fn deinit(self: *PlayerControllerComponent) void {
        _ = self;
    }

    pub fn tick(self: *PlayerControllerComponent, delta: f32) void {
        self.time += delta;

        // accelerate the player from input
        self.acceleratePlayer();

        // set our basic position
        self.camera.position = self.owner.getPosition();

        // lerp our step up
        const movement_component_opt = self.owner.getComponent(character.CharacterMovementComponent);
        if (movement_component_opt) |movement_component| {
            // smooth the camera when stepping up onto something
            self.camera.position.y = movement_component.getStepLerpToHeight(self.camera.position.y);

            // add eye height
            self.camera.position.y += movement_component.state.size.y * 0.35;

            // check if our eyes are under water
            self.eyes_in_water = movement_component.state.eyes_in_water;
        }

        // do mouse look
        self.camera.runSimpleCamera(0, 60 * delta, true);
    }

    pub fn getPosition(self: *PlayerControllerComponent) delve.math.Vec3 {
        const movement_component_opt = self.owner.getComponent(character.CharacterMovementComponent);
        if (movement_component_opt) |movement_component| {
            return movement_component.getPosition();
        }
        return math.Vec3.zero;
    }

    pub fn getRotation(self: *PlayerControllerComponent) delve.math.Quaternion {
        _ = self;
        return delve.math.Quaternion.identity;
    }

    pub fn getBounds(self: *PlayerControllerComponent) delve.spatial.BoundingBox {
        return delve.spatial.BoundingBox.init(self.getPosition(), delve.math.Vec3.one);
    }

    pub fn acceleratePlayer(self: *PlayerControllerComponent) void {
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
                movement_component.state.vel.y = jump_acceleration;
                movement_component.state.on_ground = false;
            } else if (delve.platform.input.isKeyPressed(.SPACE) and movement_component.state.in_water) {
                if (movement_component.state.eyes_in_water) {
                    // if we're under water, just move us up
                    move_dir.y += 1.0;
                } else {
                    // if we're at the top of the water, jump!
                    movement_component.state.vel.y = jump_acceleration;
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
};

pub fn getComponentStorage(world: *entities.World) !*entities.ComponentStorage(PlayerControllerComponent) {
    const storage = try world.components.getStorageForType(PlayerControllerComponent);

    // convert type-erased storage to typed
    return storage.getStorage(entities.ComponentStorage(PlayerControllerComponent));
}

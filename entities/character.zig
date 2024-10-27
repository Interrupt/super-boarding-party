const std = @import("std");
const delve = @import("delve");
const basics = @import("basics.zig");
const collision = @import("../utils/collision.zig");
const entities = @import("../game/entities.zig");
const quakemap = @import("quakemap.zig");
const movers = @import("mover.zig");
const box_collision = @import("box_collision.zig");
const math = delve.math;

pub var gravity_amount: f32 = -75.0;
pub var ground_acceleration: f32 = 3.0;
pub var air_acceleration: f32 = 0.5;
pub var friction: f32 = 10.0;
pub var air_friction: f32 = 0.1;
pub var water_friction: f32 = 4.0;
pub var jump_acceleration: f32 = 20.0;

pub const CharacterMoveMode = enum {
    WALKING,
    FLYING,
    NOCLIP,
};

pub const MoveState = struct {
    move_mode: CharacterMoveMode = .WALKING,
    size: math.Vec3 = math.Vec3.one,
    pos: math.Vec3 = math.Vec3.zero,
    vel: math.Vec3 = math.Vec3.zero,
    on_ground: bool = true,
    on_entity: ?entities.Entity = null,
    in_water: bool = false,
    eyes_in_water: bool = false,

    step_lerp_timer: f32 = 1.0,
    step_lerp_amount: f32 = 0.0,
    step_lerp_startheight: f32 = 0.0,

    squish_timer: f32 = 0.0,
};

pub const CharacterMovementComponent = struct {
    time: f32 = 0.0,
    move_speed: f32 = 8.0,
    move_dir: math.Vec3 = math.Vec3.zero,
    max_slide_bumps: usize = 5,

    state: MoveState = .{},
    camera: delve.graphics.camera.Camera = undefined,

    // internal!
    quake_map_components: std.ArrayList(*quakemap.QuakeMapComponent) = undefined,

    owner: entities.Entity = entities.InvalidEntity,

    pub fn init(self: *CharacterMovementComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;

        self.camera = delve.graphics.camera.Camera.init(90.0, 0.01, 512, math.Vec3.up);

        // set start position
        self.state.pos = self.owner.getPosition();

        self.quake_map_components = std.ArrayList(*quakemap.QuakeMapComponent).init(delve.mem.getAllocator());
    }

    pub fn deinit(self: *CharacterMovementComponent) void {
        _ = self;
    }

    pub fn tick(self: *CharacterMovementComponent, delta: f32) void {
        self.time += delta;

        const world_opt = entities.getWorld(self.owner.getWorldId());
        if (world_opt == null)
            return;

        const world = world_opt.?;

        // get our starting info, and set it when we're done
        self.state.pos = self.owner.getPosition();
        self.state.vel = self.owner.getVelocity();

        // use our collision component size
        var has_collision: bool = false;
        if (self.owner.getComponent(box_collision.BoxCollisionComponent)) |box| {
            has_collision = true;
            self.state.size = box.size;
        }

        // if we started by standing on an entity, remember that
        const started_on_entity = self.state.on_entity;

        // update the step lerp timer
        self.state.step_lerp_timer += delta * 10.0;

        // first, check if we started in the water.
        // only count as being in water if the self.state.is mostly in water
        const water_check_height = math.Vec3.new(0, self.state.size.y * 0.45, 0);
        const water_bounding_box_size = math.Vec3.new(self.state.size.x, self.state.size.y * 0.5, self.state.size.z);

        self.state.in_water = collision.collidesWithLiquid(world, self.state.pos.add(water_check_height), water_bounding_box_size);

        // accelerate using our state's requested move_dir
        self.accelerate();

        // now apply gravity
        if (self.state.move_mode == .WALKING and !self.state.on_ground and !self.state.in_water) {
            self.state.vel.y += gravity_amount * delta;
        }

        // save the initial move position in case something bad happens
        const start_pos = self.state.pos;
        const start_vel = self.state.vel;
        const start_on_ground = self.state.on_ground;

        // setup our move data
        var move_info = collision.MoveInfo{
            .pos = self.state.pos,
            .vel = self.state.vel,
            .size = self.state.size,
            .step_lerp_timer = self.state.step_lerp_timer,
            .step_lerp_amount = self.state.step_lerp_amount,
            .step_lerp_startheight = self.state.step_lerp_startheight,
            .checking = self.owner,
        };

        // now we can try to move
        if (!has_collision or self.state.move_mode == .NOCLIP) {
            // ignore collision!
            self.state.pos = self.state.pos.add(self.state.vel.scale(delta));
            self.state.on_ground = false;
        } else if (self.state.move_mode == .WALKING) {
            // check normal walking, try to step up if we are on the ground or falling
            if ((self.state.on_ground or self.state.vel.y <= 0.001) and !self.state.in_water) {
                _ = collision.doStepSlideMove(world, &move_info, delta);
            } else {
                _ = collision.doSlideMove(world, &move_info, delta);
            }

            // check if we are on the ground now
            const ground_hit = collision.isOnGround(world, move_info);
            self.state.on_ground = ground_hit != null and !self.state.in_water;
            self.state.on_entity = if (ground_hit != null) ground_hit.?.entity else null;

            // if we were on ground before, check if we should stick to a slope
            if (start_on_ground and !self.state.on_ground) {
                if (collision.groundCheck(world, move_info, math.Vec3.new(0, -0.125, 0))) |hit| {
                    move_info.pos = hit.pos.add(delve.math.Vec3.new(0, 0.0001, 0));
                    self.state.on_ground = true;
                }
            }
        } else if (self.state.move_mode == .FLYING) {
            // when flying, just do the slide movement
            _ = collision.doSlideMove(world, &move_info, delta);
            self.state.on_ground = false;
        }

        // use our new positions from the move after resolving
        if (has_collision and self.state.move_mode != .NOCLIP) {
            self.state.pos = move_info.pos;
            self.state.vel = move_info.vel;

            // If we're encroaching something now, pop us out of it
            if (collision.collidesWithMap(world, self.state.pos, self.state.size, self.owner)) {
                self.state.pos = start_pos;
                self.state.vel = start_vel;

                if (collision.collidesWithMap(world, self.state.pos, self.state.size, self.owner)) {
                    // Uhoh, still in something! Move us out.
                    self.state.pos = self.state.pos.add(math.Vec3.new(0, 1.0 * delta, 0));
                    self.state.squish_timer += delta;
                }
            } else {
                // Not encroaching anything, no squish!
                self.state.squish_timer = 0;
            }
        }

        const ground_hit = collision.isOnGround(world, move_info);
        self.state.on_ground = ground_hit != null and !self.state.in_water;
        self.state.on_entity = if (ground_hit != null) ground_hit.?.entity else null;

        // slow down the self.state.based on what we are touching
        self.applyFriction(delta);

        // finally, position camera
        self.camera.position = self.state.pos;

        // add eye height
        self.camera.position.y += self.state.size.y * 0.35;

        // do mouse look
        self.camera.runSimpleCamera(0, 60 * delta, true);

        // keep track of our new step lerp
        self.state.step_lerp_timer = move_info.step_lerp_timer;
        self.state.step_lerp_amount = move_info.step_lerp_amount;
        self.state.step_lerp_startheight = move_info.step_lerp_startheight;

        // check if our eyes are under water
        self.state.eyes_in_water = collision.collidesWithLiquid(world, self.camera.position, math.Vec3.zero);

        // Since we moved, we need to update our spatial hash!
        const our_collision_box_opt = self.owner.getComponent(box_collision.BoxCollisionComponent);
        if (our_collision_box_opt) |box| {
            box.updateSpatialHash();
        }

        // track our new position and velocity
        self.owner.setPosition(self.state.pos);
        self.owner.setVelocity(self.state.vel);

        // handle riding on movers
        if (self.state.on_entity) |on| {
            const mover_opt = on.getComponent(movers.MoverComponent);
            if (mover_opt) |mover| {
                mover.addRider(self.owner);
            }
        } else {
            if (started_on_entity) |started_on| {
                const mover_opt = started_on.getComponent(movers.MoverComponent);
                if (mover_opt) |mover| {
                    mover.removeRider(self.owner);
                }
            }
        }
    }

    pub fn slideMove(self: *CharacterMovementComponent, amount: delve.math.Vec3, delta: f32) delve.math.Vec3 {
        const world_opt = entities.getWorld(self.owner.getWorldId());
        if (world_opt == null)
            return math.Vec3.zero;

        const world = world_opt.?;

        // get our starting info
        self.state.pos = self.owner.getPosition();
        const start_pos = self.state.pos;

        // use our collision component size
        var has_collision: bool = false;
        if (self.owner.getComponent(box_collision.BoxCollisionComponent)) |box| {
            has_collision = true;
            self.state.size = box.size;
        }

        // setup our move data
        var move_info = collision.MoveInfo{
            .pos = self.state.pos,
            .vel = amount,
            .size = self.state.size,
            .checking = self.owner,
        };

        // now we can try to move
        if (!has_collision or self.state.move_mode == .NOCLIP) {
            // ignore collision!
            self.state.pos = self.state.pos.add(amount);
        } else {
            _ = collision.doSlideMove(world, &move_info, delta);
        }

        // use our new positions from the move after resolving
        if (has_collision and self.state.move_mode != .NOCLIP) {
            self.state.pos = move_info.pos;

            // If we're encroaching something now, pop us out of it
            if (collision.collidesWithMap(world, self.state.pos, self.state.size, self.owner)) {
                self.state.pos = start_pos;
            }
        }

        // keep our new position
        self.owner.setPosition(self.state.pos);

        // Return how much leftover velocity we have!
        const moved_amount = start_pos.sub(self.state.pos).len();
        const wanted_to_move = amount.len();

        const close_enough_epsilon = 0.99999;
        if (moved_amount / wanted_to_move >= close_enough_epsilon)
            return delve.math.Vec3.zero;

        return move_info.vel.scale(1.0 - (moved_amount / wanted_to_move));
    }

    pub fn getPosition(self: *CharacterMovementComponent) delve.math.Vec3 {
        return self.state.pos;
    }

    pub fn getRotation(self: *CharacterMovementComponent) delve.math.Quaternion {
        _ = self;
        return delve.math.Quaternion.identity;
    }

    pub fn getBounds(self: *CharacterMovementComponent) delve.spatial.BoundingBox {
        return delve.spatial.BoundingBox.init(self.getPosition(), self.state.size);
    }

    pub fn accelerate(self: *CharacterMovementComponent) void {
        // can now apply self.state.movement based on direction
        const move_dir = self.move_dir.norm();

        // default to the basic ground acceleration
        var accel = ground_acceleration;

        // in walking mode, choose acceleration based on being in the air, ground, or water
        if (self.state.move_mode == .WALKING) {
            accel = if (self.state.on_ground and !self.state.in_water) ground_acceleration else air_acceleration;
        }

        // ignore vertical velocity when walking!
        var current_velocity = self.state.vel;
        if (self.state.move_mode == .WALKING and !self.state.in_water) {
            current_velocity.y = 0;
        }

        // accelerate up to the move speed
        if (current_velocity.len() < self.move_speed) {
            const new_velocity = current_velocity.add(move_dir.scale(accel));
            const use_vertical_accel = self.state.move_mode != .WALKING or self.state.in_water;

            if (new_velocity.len() < self.move_speed) {
                // under the max speed, can accelerate
                self.state.vel.x = new_velocity.x;
                self.state.vel.z = new_velocity.z;

                if (use_vertical_accel)
                    self.state.vel.y = new_velocity.y;
            } else {
                // clamp to max speed!
                const max_speed = new_velocity.norm().scale(self.move_speed);
                self.state.vel.x = max_speed.x;
                self.state.vel.z = max_speed.z;

                if (use_vertical_accel)
                    self.state.vel.y = max_speed.y;
            }
        }
    }

    pub fn applyFriction(self: *CharacterMovementComponent, delta: f32) void {
        const speed = self.state.vel.len();
        if (speed > 0) {
            var velocity_drop = speed * delta;
            var friction_amount = friction;

            if (self.state.move_mode == .WALKING) {
                friction_amount = if (self.state.on_ground) friction else if (self.state.in_water) water_friction else air_friction;
            }

            velocity_drop *= friction_amount;

            const newspeed = (speed - velocity_drop) / speed;
            self.state.vel = self.state.vel.scale(newspeed);
        }
    }

    pub fn getStepLerpToHeight(self: *CharacterMovementComponent, final_height: f32) f32 {
        if (self.state.step_lerp_timer < 1.0) {
            return delve.utils.interpolation.EaseQuad.applyOut(self.state.step_lerp_startheight, final_height, self.state.step_lerp_timer);
        }
        return final_height;
    }

    pub fn getStepLerpHeightOffset(self: *CharacterMovementComponent) f32 {
        if (self.state.step_lerp_timer <= 1.0) {
            return delve.utils.interpolation.EaseQuad.applyOut(self.state.step_lerp_amount, 0, self.state.step_lerp_timer);
        }
        return 0;
    }
};

pub fn getComponentStorage(world: *entities.World) !*entities.ComponentStorage(CharacterMovementComponent) {
    return world.components.getStorageForType(CharacterMovementComponent) catch {
        delve.debug.fatal("Could not get CharacterMovementController storage!", .{});
        return undefined;
    };
}

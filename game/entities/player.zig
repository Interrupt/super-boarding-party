const std = @import("std");
const delve = @import("delve");
const collision = @import("../../collision.zig");
const entities = @import("../entities.zig");
const quakeworld = @import("world.zig");
const main = @import("../../main.zig");
const math = delve.math;

pub var gravity_amount: f32 = -75.0;
pub var move_speed: f32 = 24.0;
pub var ground_acceleration: f32 = 3.0;
pub var air_acceleration: f32 = 0.5;
pub var friction: f32 = 10.0;
pub var air_friction: f32 = 0.1;
pub var water_friction: f32 = 4.0;
pub var jump_acceleration: f32 = 20.0;

pub const PlayerMoveMode = enum {
    WALKING,
    FLYING,
    NOCLIP,
};

pub const MoveState = struct {
    move_mode: PlayerMoveMode = .WALKING,
    size: math.Vec3 = math.Vec3.new(2, 3, 2),
    pos: math.Vec3 = math.Vec3.zero,
    vel: math.Vec3 = math.Vec3.zero,
    on_ground: bool = true,
    in_water: bool = false,
    eyes_in_water: bool = false,
};

pub const PlayerControllerComponent = struct {
    time: f32 = 0.0,
    name: []const u8,

    state: MoveState = .{},
    camera: delve.graphics.camera.Camera = undefined,

    // internal!
    quake_map_components: std.ArrayList(*quakeworld.QuakeMapComponent) = undefined,

    pub fn init(self: *PlayerControllerComponent, base: *entities.EntitySceneComponent) void {
        _ = base;
        self.camera = delve.graphics.camera.Camera.init(90.0, 0.01, 512, math.Vec3.up);

        // set start position
        self.state.pos.y = 30.0;

        delve.debug.log("Creating quake maps list!", .{});
        self.quake_map_components = std.ArrayList(*quakeworld.QuakeMapComponent).init(delve.mem.getAllocator());
    }

    pub fn deinit(self: *PlayerControllerComponent) void {
        _ = self;
    }

    pub fn tick(self: *PlayerControllerComponent, delta: f32) void {
        self.time += delta;
        self.quake_map_components.clearRetainingCapacity();

        // just use the first quake map for now
        for (main.game_instance.game_entities.items) |*e| {
            if (e.getSceneComponent(quakeworld.QuakeMapComponent)) |map| {
                self.quake_map_components.append(map) catch {};
            }
        }

        // delve.debug.log("Found nearby solids: {d}", .{num_solids});

        // delve.debug.log("Colliding against {d} quake maps", .{self.quake_maps.items.len});

        // setup the world to collide against
        const world = collision.WorldInfo{
            .quake_map_components = self.quake_map_components.items,
        };

        // const ray_solids = self.quake_map_components.items[0].solid_spatial_hash.getSolidsAlong(self.state.pos, self.state.pos.add(self.camera.direction.scale(10)));
        // delve.debug.log("Found rayhit solids: {d}", .{ray_solids.len});

        const ray_did_hit = collision.rayCollidesWithMap(&world, delve.spatial.Ray.init(self.camera.position, self.camera.direction));
        if (ray_did_hit) |hit_info| {
            // Draw a debug cube to see where we hit!
            // main.render_instance.drawDebugCube(hit_info.loc, math.Vec3.new(0.11, 2, 0.11), hit_info.plane.normal, delve.colors.red);
            // main.render_instance.drawDebugCube(hit_info.loc, math.Vec3.new(2, 0.1, 0.1), hit_info.plane.normal, delve.colors.green);
            // main.render_instance.drawDebugCube(hit_info.loc, math.Vec3.new(0.1, 0.1, 2), hit_info.plane.normal, delve.colors.blue);
            main.render_instance.drawDebugTranslateGizmo(hit_info.loc, math.Vec3.one, hit_info.plane.normal);
        }

        // first, check if we started in the water.
        // only count as being in water if the self.state.is mostly in water
        const water_check_height = math.Vec3.new(0, self.state.size.y * 0.45, 0);
        const water_bounding_box_size = math.Vec3.new(self.state.size.x, self.state.size.y * 0.5, self.state.size.z);

        self.state.in_water = collision.collidesWithLiquid(&world, self.state.pos.add(water_check_height), water_bounding_box_size);

        // accelerate the player from input
        self.acceleratePlayer();

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
        };

        // now we can try to move
        if (self.state.move_mode == .WALKING) {
            if ((self.state.on_ground or self.state.vel.y <= 0.001) and !self.state.in_water) {
                _ = collision.doStepSlideMove(&world, &move_info, delta);
            } else {
                _ = collision.doSlideMove(&world, &move_info, delta);
            }

            // check if we are on the ground now
            self.state.on_ground = collision.isOnGround(&world, move_info) and !self.state.in_water;

            // if we were on ground before, check if we should stick to a slope
            if (start_on_ground and !self.state.on_ground) {
                if (collision.groundCheck(&world, move_info, math.Vec3.new(0, -0.125, 0))) |pos| {
                    move_info.pos = pos.add(delve.math.Vec3.new(0, 0.0001, 0));
                    self.state.on_ground = true;
                }
            }
        } else if (self.state.move_mode == .FLYING) {
            // when flying, just do the slide movement
            _ = collision.doSlideMove(&world, &move_info, delta);
            self.state.on_ground = false;
        } else if (self.state.move_mode == .NOCLIP) {
            // in noclip mode, ignore collision!
            self.state.pos = self.state.pos.add(self.state.vel.scale(delta));
            self.state.on_ground = false;
        }

        // use our new positions from the move after resolving
        if (self.state.move_mode != .NOCLIP) {
            self.state.pos = move_info.pos;
            self.state.vel = move_info.vel;

            // If we're encroaching something now, pop us out of it
            if (collision.collidesWithMap(&world, self.state.pos, self.state.size)) {
                self.state.pos = start_pos;
                self.state.vel = start_vel;
            }
        }

        // slow down the self.state.based on what we are touching
        self.applyFriction(delta);

        // finally, position camera
        self.camera.position = self.state.pos;

        // smooth the camera when stepping up onto something
        if (collision.step_lerp_timer < 1.0) {
            collision.step_lerp_timer += delta * 10.0;
            self.camera.position.y = delve.utils.interpolation.EaseQuad.applyOut(collision.step_lerp_startheight, self.camera.position.y, collision.step_lerp_timer);
        }

        // add eye height
        self.camera.position.y += self.state.size.y * 0.35;

        // do mouse look
        self.camera.runSimpleCamera(0, 60 * delta, true);

        // check if our eyes are under water
        self.state.eyes_in_water = collision.collidesWithLiquid(&world, self.camera.position, math.Vec3.zero);
    }

    pub fn getPosition(self: *PlayerControllerComponent) delve.math.Vec3 {
        return self.state.pos;
    }

    pub fn getRotation(self: *PlayerControllerComponent) delve.math.Quaternion {
        _ = self;
        return delve.math.Quaternion.identity;
    }

    pub fn getBounds(self: *PlayerControllerComponent) delve.spatial.BoundingBox {
        return delve.spatial.BoundingBox.init(self.getPosition(), self.state.size);
    }

    pub fn acceleratePlayer(self: *PlayerControllerComponent) void {
        // Collect move direction from input
        var move_dir: math.Vec3 = math.Vec3.zero;
        var cam_walk_dir = self.camera.direction;

        // ignore the camera facing up or down when not flying or swimming
        if (self.state.move_mode == .WALKING and !self.state.in_water)
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
        if (self.state.move_mode == .WALKING and !self.state.in_water) {
            move_dir.y = 0;
        }

        // jump and swim!
        if (self.state.move_mode == .WALKING) {
            if (delve.platform.input.isKeyJustPressed(.SPACE) and self.state.on_ground) {
                self.state.vel.y = jump_acceleration;
                self.state.on_ground = false;
            } else if (delve.platform.input.isKeyPressed(.SPACE) and self.state.in_water) {
                if (self.state.eyes_in_water) {
                    // if we're under water, just move us up
                    move_dir.y += 1.0;
                } else {
                    // if we're at the top of the water, jump!
                    self.state.vel.y = jump_acceleration;
                }
            }
        } else {
            // when flying, space will move us up
            if (delve.platform.input.isKeyPressed(.SPACE)) {
                move_dir.y += 1.0;
            }
        }

        // can now apply self.state.movement based on direction
        move_dir = move_dir.norm();

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
        if (current_velocity.len() < move_speed) {
            const new_velocity = current_velocity.add(move_dir.scale(accel));
            const use_vertical_accel = self.state.move_mode != .WALKING or self.state.in_water;

            if (new_velocity.len() < move_speed) {
                // under the max speed, can accelerate
                self.state.vel.x = new_velocity.x;
                self.state.vel.z = new_velocity.z;

                if (use_vertical_accel)
                    self.state.vel.y = new_velocity.y;
            } else {
                // clamp to max speed!
                const max_speed = new_velocity.norm().scale(move_speed);
                self.state.vel.x = max_speed.x;
                self.state.vel.z = max_speed.z;

                if (use_vertical_accel)
                    self.state.vel.y = max_speed.y;
            }
        }
    }

    pub fn applyFriction(self: *PlayerControllerComponent, delta: f32) void {
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
};

const std = @import("std");
const delve = @import("delve");
const entities = @import("../game/entities.zig");
const main = @import("../main.zig");
const basics = @import("basics.zig");
const box_collision = @import("box_collision.zig");
const quakesolids = @import("quakesolids.zig");
const stats = @import("actor_stats.zig");
const character = @import("character.zig");
const collision = @import("../utils/collision.zig");

const math = delve.math;
const interpolation = delve.utils.interpolation;

pub var enable_debug_viz: bool = false;

pub const StartType = enum {
    IMMEDIATE,
    WAIT_FOR_BUMP,
    WAIT_FOR_TRIGGER,
};

pub const MoverType = enum {
    SLIDE,
};

pub const InterpolationType = enum {
    IN,
    OUT,
    IN_OUT,
};

pub const MoverState = enum {
    WAITING_START,
    MOVING,
    WAITING_END,
    RETURNING,
    IDLE,
};

pub fn flipMoverState(state: MoverState) MoverState {
    return switch (state) {
        .WAITING_START => .WAITING_END,
        .MOVING => .RETURNING,
        .WAITING_END => .WAITING_START,
        .RETURNING => .MOVING,
        .IDLE => .IDLE,
    };
}

/// Moves an entity! Doors, platforms, etc
pub const MoverComponent = struct {
    start_type: StartType = .IMMEDIATE,
    mover_type: MoverType = .SLIDE,
    move_amount: math.Vec3 = math.Vec3.y_axis.scale(6.0), // how far to move from the starting position
    returns: bool = true, // whether or not to return to the starting position
    move_speed: f32 = 6.0,
    move_time: f32 = 1.0, // how long it takes to move
    return_speed: f32 = 6.0,
    return_time: f32 = 2.0, // how long it takes to move back
    moving_interpolation: interpolation.Interpolation = interpolation.Lerp,
    returning_interpolation: interpolation.Interpolation = interpolation.Lerp,
    moving_interpolation_type: InterpolationType = .IN_OUT,
    returning_interpolation_type: InterpolationType = .IN_OUT,
    start_delay: f32 = 1.0, // how long to wait before starting to move
    returns_on_squish: bool = true, // whether or not to flip movement direction when stuck
    squish_dmg: i32 = 5.0, // how much damage to inflict when squishing
    squish_return_time: f32 = 1.0, // how long we've been squishing something
    return_delay_time: f32 = 1.0, // how long to wait to return at the end of a move
    transfer_velocity: bool = true, // whether we should transfer our velocity when detaching entities
    eject_at_end: bool = false, // whether we should kick entities at the end of a move (for springs!)

    owner: entities.Entity = entities.InvalidEntity,

    state: MoverState = .WAITING_START,
    timer: f32 = 0.0,
    squish_timer: f32 = 0.0,
    squish_dmg_time: f32 = 0.25,
    squish_dmg_timer: f32 = 0.0,
    attached: std.ArrayList(entities.Entity) = undefined,

    start_lowered: bool = false,

    start_at_target: ?[]const u8 = null,
    owned_start_at_target_buffer: [64]u8 = std.mem.zeroes([64]u8),
    owned_start_at_target: [:0]const u8 = undefined,

    _start_pos: ?math.Vec3 = null,
    _return_speed_mod: f32 = 1.0,
    _moved_already: std.ArrayList(entities.Entity) = undefined,

    move_offset: math.Vec3 = math.Vec3.zero,

    moving_to_path_corner: ?[]const u8 = null,

    pub fn init(self: *MoverComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;
        self.attached = std.ArrayList(entities.Entity).init(delve.mem.getAllocator());
        self._moved_already = std.ArrayList(entities.Entity).init(delve.mem.getAllocator());

        // Put in the waiting state if we are waiting to start
        if (self.start_type != .IMMEDIATE) {
            self.state = .IDLE;
        }

        if (self.start_at_target) |target| {
            // make sure we own our strings! could go out of scope after this
            @memcpy(self.owned_start_at_target_buffer[0..target.len], target);
            self.owned_start_at_target = self.owned_start_at_target_buffer[0..63 :0];
            self.start_at_target = self.owned_start_at_target;
        }
    }

    pub fn deinit(self: *MoverComponent) void {
        self.attached.deinit();
        self._moved_already.deinit();
    }

    pub fn tick(self: *MoverComponent, delta: f32) void {
        const start_time = self.timer;

        if (self.state != .IDLE)
            self.timer += if (self.state != .RETURNING) delta else delta * self._return_speed_mod;

        // keep track of our starting position, if not set already
        if (self._start_pos == null) {
            if (self.start_at_target) |target| {
                const world_opt = entities.getWorld(self.owner.getWorldId());
                if (world_opt == null)
                    return;

                const world = world_opt.?;
                if (world.named_entities.get(target)) |target_id| {
                    if (world.getEntity(target_id)) |path_target| {
                        const start_path_pos = path_target.getPosition();
                        self.move_offset = self.owner.getPosition().sub(start_path_pos);
                        self._start_pos = start_path_pos.add(self.move_offset);
                        delve.debug.log("Set mover start position from a target: {d:3} {d:3} {d:3}", .{ self._start_pos.?.x, self._start_pos.?.y, self._start_pos.?.z });
                    }
                }
            }

            if (self._start_pos == null) {
                if (self.start_lowered)
                    self.owner.setPosition(self.owner.getPosition().add(math.Vec3.y_axis.scale(-self.move_amount.y)));

                self._start_pos = self.owner.getPosition();
            }
        }

        const cur_pos = self.owner.getPosition();
        const start_vel = self.owner.getVelocity();

        // If moving, do our move logic
        if (self.state == .MOVING or self.state == .RETURNING) {
            const time = @min(self.timer, self.move_time);

            // get the next location at our current time
            const cur_move = if (self.state == .MOVING)
                self.getPosAtTime(time)
            else
                self.getPosAtTime(self.move_time - time);

            // find out how far this move actually moves
            const next_pos = self._start_pos.?.add(cur_move);
            const pos_diff = next_pos.sub(cur_pos);

            // do our move!
            const did_move = self.move(pos_diff, delta);

            // reset the squish timer
            if (self.squish_dmg_timer >= self.squish_dmg_time) {
                self.squish_dmg_timer = 0.0;
            }

            if (!did_move) {
                // didn't move! keep timer where we are
                self.timer = start_time;
                self.squish_timer += delta;
                self.squish_dmg_timer += delta;

                // If we've been squished too long, back up!
                if (self.squish_timer >= self.squish_return_time) {
                    self.state = flipMoverState(self.state);
                    self.timer = self.move_time - self.timer;
                    self.squish_timer = 0.0;
                    self.squish_dmg_timer = 0.0;
                }
            } else {
                self.squish_timer = 0.0;
                self.squish_dmg_timer = 0.0;
            }
        }

        // Run our state machine!
        if (self.state == .WAITING_START) {
            if (self.timer >= self.start_delay) {
                self.state = .MOVING;
                self.timer = 0;
            }
        }
        if (self.state == .MOVING) {
            if (self.timer >= self.move_time) {
                self.state = .WAITING_END;
                self.timer = 0;

                self.onDoneMoving();

                if (self.eject_at_end)
                    self.removeAllRiders(start_vel); // use our last velocity, was probably a full move and not a fractional one

                self.owner.setVelocity(delve.math.Vec3.zero);
            }
        }
        if (self.state == .WAITING_END) {
            if (self.returns) {
                if (self.timer >= self.return_delay_time) {
                    self.state = .RETURNING;
                    self.timer = 0;
                    self._return_speed_mod = self.move_time / self.return_time;
                }
            } else {
                self.timer = 0;
            }
        }
        if (self.state == .RETURNING) {
            if (self.timer >= self.move_time) {
                self.state = if (self.start_type == .IMMEDIATE) .WAITING_START else .IDLE;
                self.timer = 0;

                self.onDoneReturning();

                if (self.eject_at_end)
                    self.removeAllRiders(start_vel);

                self.owner.setVelocity(delve.math.Vec3.zero);
            }
        }

        // render debug views!
        if (enable_debug_viz) {
            const collision_opt = self.owner.getComponent(box_collision.BoxCollisionComponent);
            if (collision_opt) |col| {
                col.renderDebug();
            }

            const quakesolids_opt = self.owner.getComponent(quakesolids.QuakeSolidsComponent);
            if (quakesolids_opt) |brush| {
                brush.renderDebug();
            }
        }
    }

    pub fn getPosAtTime(self: *MoverComponent, time: f32) math.Vec3 {
        var move_factor = time / self.move_time;

        // flip when returning
        if (self.state == .RETURNING) move_factor = 1.0 - move_factor;

        const interpolation_func = if (self.state == .MOVING) self.moving_interpolation else self.returning_interpolation;
        const interpolation_type = if (self.state == .MOVING) self.moving_interpolation_type else self.returning_interpolation_type;
        var t: f32 = switch (interpolation_type) {
            .IN => interpolation_func.applyIn(0.0, 1.0, move_factor),
            .OUT => interpolation_func.applyOut(0.0, 1.0, move_factor),
            .IN_OUT => interpolation_func.applyInOut(0.0, 1.0, move_factor),
        };

        // flip back when returning
        if (self.state == .RETURNING) t = 1.0 - t;

        return switch (self.mover_type) {
            .SLIDE => self.move_amount.scale(t),
        };
    }

    pub fn tryCollisionBoxMove(self: *MoverComponent, next_pos: math.Vec3, move_amount: math.Vec3, world: *entities.World, delta: f32) bool {
        const collision_opt = self.owner.getComponent(box_collision.BoxCollisionComponent);
        if (collision_opt != null) {
            const hit_entity = collision.checkEntityCollision(world, next_pos, collision_opt.?.size, self.owner);
            if (hit_entity != null) {
                // push our encroached entity out of the way
                collision_opt.?.collides_entities = false;
                pushEntity(hit_entity.?, move_amount.scale(1.0 / delta), delta);
                collision_opt.?.collides_entities = true;

                // are we clear now?
                const post_push_hit = collision.checkEntityCollision(world, next_pos, collision_opt.?.size, self.owner);
                if (post_push_hit != null) {
                    self.squishing(post_push_hit.?);
                    return false;
                }

                // track that we already moved this entity
                self._moved_already.append(hit_entity.?) catch {
                    return false;
                };
            }
        }

        return true;
    }

    pub fn tryQuakeSolidsMove(self: *MoverComponent, next_pos: math.Vec3, move_amount: math.Vec3, world: *entities.World, delta: f32) bool {
        _ = world;
        _ = next_pos;
        const quakesolid_opt = self.owner.getComponent(quakesolids.QuakeSolidsComponent);
        if (quakesolid_opt) |solids| {
            // we need to adjust our check position based on how far we are moving
            const hit_entity = solids.checkEntityCollision(move_amount, self.owner);
            if (hit_entity != null) {
                // push our encroached entity out of the way
                solids.collides_entities = false;
                pushEntity(hit_entity.?, move_amount.scale(1.0 / delta), delta);
                solids.collides_entities = true;

                // are we clear now?
                const post_push_hit = solids.checkEntityCollision(move_amount, self.owner);
                if (post_push_hit != null) {
                    self.squishing(post_push_hit.?);
                    return false;
                }

                // track that we already moved this entity
                self._moved_already.append(hit_entity.?) catch {
                    return false;
                };
            }
        }

        return true;
    }

    /// Callback for when an entity bumps us
    pub fn onBump(self: *MoverComponent, touching: entities.Entity) void {
        _ = touching;
        if (self.start_type == .WAIT_FOR_BUMP and self.state == .IDLE) {
            self.state = .WAITING_START;
        }
    }

    pub fn squishing(self: *MoverComponent, squished: entities.Entity) void {
        if (self.squish_dmg_timer >= self.squish_dmg_time) {
            // squish timer triggered, can take damage now!
            const target_stats_opt = squished.getComponent(stats.ActorStats);
            if (target_stats_opt) |target_stats| {
                target_stats.takeDamage(.{ .dmg = self.squish_dmg });
            }
        }
    }

    pub fn move(self: *MoverComponent, move_amount: math.Vec3, delta: f32) bool {
        const world_opt = entities.getWorld(self.owner.getWorldId());
        if (world_opt == null)
            return false;

        const world = world_opt.?;
        const cur_pos = self.owner.getPosition();
        const next_pos = cur_pos.add(move_amount);
        const vel = move_amount.scale(1.0 / delta);

        // Push entities out of the way!
        var can_move = true;

        // start by checking collision box components
        can_move = self.tryCollisionBoxMove(next_pos, move_amount, world, delta);

        // also check elevators and doors and stuff
        if (can_move)
            can_move = self.tryQuakeSolidsMove(next_pos, move_amount, world, delta);

        if (can_move) {
            // set our new position, and our current velocity
            self.owner.setPosition(next_pos);
            self.owner.setVelocity(vel);

            // Move all of the things riding on us!
            for (self.attached.items) |attached| {
                var _moved_already = false;
                for (self._moved_already.items) |already| {
                    if (attached.id.equals(already.id)) {
                        _moved_already = true;
                        break;
                    }
                }

                if (!_moved_already) {
                    pushEntity(attached, move_amount.scale(1.0 / delta), delta);
                }
            }
        } else {
            self.owner.setVelocity(delve.math.Vec3.zero);
        }

        self._moved_already.clearRetainingCapacity();

        return can_move;
    }

    pub fn onDoneMoving(self: *MoverComponent) void {
        delve.debug.log("Mover is done moving", .{});
        // If we have a trigger to fire, do it now!
        if (self.owner.getComponent(basics.TriggerComponent)) |trigger| {
            delve.debug.log("Mover firing owned trigger with target {s}", .{trigger.target});
            trigger.fire(null);
        }
    }

    pub fn onDoneReturning(self: *MoverComponent) void {
        _ = self;
    }

    /// When triggered, start moving
    pub fn onTrigger(self: *MoverComponent, info: basics.TriggerFireInfo) void {
        delve.debug.log("Mover with state {any} triggered with value '{s}', from_path_node: {any}", .{ self.state, info.value, info.from_path_node });

        if (info.from_path_node) {
            if (self.owner.getComponent(basics.TriggerComponent)) |trigger| {
                _ = trigger;
                self.followPath(info.value);
            }
            delve.debug.log("Mover triggered from path node! '{s}'", .{info.value});
            return;
        }

        if (info.value[0] != 0) {
            if (self.owner.getComponent(basics.TriggerComponent)) |trigger| {
                _ = trigger;
                delve.debug.log("Mover starting out! '{s}'", .{info.value});
                self.followPath(info.value);
            }
        } else {
            if (self.owner.getComponent(basics.TriggerComponent)) |trigger| {
                delve.debug.log("Mover has trigger '{s}'", .{trigger.target});
                self.followPath(trigger.target);
            } else {
                // If no trigger or path value, just start moving if we are idle
                if (self.state == .IDLE) {
                    self.state = .WAITING_START;
                }
            }
        }
    }

    pub fn addRider(self: *MoverComponent, entity: entities.Entity) void {
        var attached_already = false;
        for (self.attached.items) |existing| {
            if (existing.id.equals(entity.id)) {
                attached_already = true;
                break;
            }
        }

        if (attached_already)
            return;

        self.attached.append(entity) catch {
            return;
        };
    }

    pub fn removeRider(self: *MoverComponent, entity: entities.Entity) void {
        for (0..self.attached.items.len) |idx| {
            if (self.attached.items[idx].id.equals(entity.id)) {
                _ = self.attached.swapRemove(idx);

                // persist our velocity to this entity when they leave!
                if (self.transfer_velocity)
                    entity.setVelocity(entity.getVelocity().add(self.owner.getVelocity()));

                return;
            }
        }
    }

    pub fn removeAllRiders(self: *MoverComponent, kick_velocity: math.Vec3) void {
        for (self.attached.items) |entity| {
            // persist our velocity to this entity when they leave!
            if (self.transfer_velocity)
                entity.setVelocity(entity.getVelocity().add(kick_velocity));
        }
    }

    pub fn followPath(self: *MoverComponent, path_name: []const u8) void {
        const world_opt = entities.getWorld(self.owner.getWorldId());
        if (world_opt == null)
            return;

        const world = world_opt.?;
        var move_to_path: ?math.Vec3 = null;

        if (world.named_entities.get(path_name)) |path_entity_id| {
            if (world.getEntity(path_entity_id)) |path_entity| {
                delve.debug.log("Mover setting move target to {s}", .{path_name});
                move_to_path = path_entity.getPosition();
            }
        }

        if (move_to_path) |p| {
            if (self.owner.getComponent(basics.TriggerComponent)) |trigger| {
                // Set our target to be the path we are moving to
                trigger.target = path_name;
                delve.debug.log("Mover set next trigger target to {s}", .{path_name});
            }

            if (self.state == .IDLE) {
                delve.debug.log("Mover moving to next path point {s}", .{path_name});
                const to_next_path_move_amount = p.sub(self._start_pos.?);
                self.move_amount = to_next_path_move_amount.add(self.move_offset);
                self.move_time = self.move_amount.len() / self.move_speed;
                self.state = .WAITING_START;
            } else if (self.state == .WAITING_END) {
                self._start_pos = self.owner.getPosition();
                const to_next_path_move_amount = p.sub(self._start_pos.?);
                self.move_amount = to_next_path_move_amount.add(self.move_offset);
                self.move_time = self.move_amount.len() / self.move_speed;
                self.state = .WAITING_START;
            } else {
                delve.debug.log("Mover can not move to path, still moving! {any}", .{self.state});
            }
        }
    }
};

pub fn getComponentStorage(world: *entities.World) *entities.ComponentStorage(MoverComponent) {
    return world.components.getStorageForType(MoverComponent) catch {
        delve.debug.fatal("Could not get MoverComponent storage!", .{});
        return undefined;
    };
}

pub fn pushEntity(entity: entities.Entity, amount: delve.math.Vec3, delta: f32) void {
    const movement_opt = entity.getComponent(character.CharacterMovementComponent);
    if (movement_opt) |movement| {
        _ = movement.slideMove(amount, delta);
    }
}

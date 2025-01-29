const std = @import("std");
const delve = @import("delve");
const entities = @import("../game/entities.zig");
const options = @import("../game/options.zig");
const main = @import("../main.zig");
const audio = @import("audio.zig");
const basics = @import("basics.zig");
const triggers = @import("triggers.zig");
const box_collision = @import("box_collision.zig");
const quakesolids = @import("quakesolids.zig");
const stats = @import("actor_stats.zig");
const string = @import("../utils/string.zig");
const character = @import("character.zig");
const collision = @import("../utils/collision.zig");

const math = delve.math;
const interpolation = delve.utils.interpolation;

pub var enable_debug_viz: bool = false;

pub const StartType = enum {
    IMMEDIATE,
    WAIT_FOR_BUMP,
    WAIT_FOR_TRIGGER,
    WAIT_FOR_DAMAGE,
    WAIT_FOR_KEY,
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
    IDLE_REVERSED,
};

pub fn flipMoverState(state: MoverState) MoverState {
    return switch (state) {
        .WAITING_START => .WAITING_END,
        .MOVING => .RETURNING,
        .WAITING_END => .WAITING_START,
        .RETURNING => .MOVING,
        .IDLE => .IDLE,
        .IDLE_REVERSED => .IDLE_REVERSED,
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
    starts_overlapping_movers: bool = false, // whether to start any overlapping movers (by bounding box) when we start
    message: string.String = string.empty, // message to show when interacted with and locked
    play_end_sound: bool = true,

    owner: entities.Entity = entities.InvalidEntity,

    state: MoverState = .WAITING_START,
    timer: f32 = 0.0,
    squish_timer: f32 = 0.0,
    squish_dmg_time: f32 = 0.25,
    squish_dmg_timer: f32 = 0.0,

    start_lowered: bool = false,
    start_moved: bool = false,

    start_at_target: ?string.String = null,

    _attached: std.ArrayList(entities.Entity) = undefined,
    _start_pos: ?math.Vec3 = null,
    _return_speed_mod: f32 = 1.0,
    _moved_already: std.ArrayList(entities.Entity) = undefined,
    _playing_sound: bool = false,

    move_offset: math.Vec3 = math.Vec3.zero,

    lookup_path_on_start: bool = false,

    pub fn init(self: *MoverComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;
        self._attached = std.ArrayList(entities.Entity).init(delve.mem.getAllocator());
        self._moved_already = std.ArrayList(entities.Entity).init(delve.mem.getAllocator());

        // Put in the waiting state if we are waiting to start
        if (self.start_type != .IMMEDIATE) {
            self.state = .IDLE;
        }
    }

    pub fn deinit(self: *MoverComponent) void {
        self._attached.deinit();
        self._moved_already.deinit();

        // free strings
        self.message.deinit();
        if (self.start_at_target) |*start_at| {
            start_at.deinit();
        }
    }

    pub fn physics_tick(self: *MoverComponent, delta: f32) void {
        const start_time = self.timer;

        if (self.state != .IDLE and self.state != .IDLE_REVERSED)
            self.timer += if (self.state != .RETURNING) delta else delta * self._return_speed_mod;

        // keep track of our starting position, if not set already
        if (self._start_pos == null) {
            if (self.start_at_target) |target| {
                const world_opt = entities.getWorld(self.owner.getWorldId());
                if (world_opt == null)
                    return;

                const world = world_opt.?;
                if (world.getEntityByName(target.str)) |path_target| {
                    const start_path_pos = path_target.getPosition();
                    self.move_offset = self.owner.getPosition().sub(start_path_pos);
                    self._start_pos = start_path_pos.add(self.move_offset);
                } else {
                    delve.debug.warning("Could not find mover start at target! '{s}'", .{target.str});
                }
            }

            if (self._start_pos == null) {
                if (self.start_lowered)
                    self.owner.setPosition(self.owner.getPosition().add(math.Vec3.y_axis.scale(-self.move_amount.y)));

                self._start_pos = self.owner.getPosition();

                if (self.start_moved) {
                    const moved_pos = self.getPosAtTime(self.move_time);
                    self.owner.setPosition(self._start_pos.?.add(moved_pos));
                    self.state = .IDLE_REVERSED;
                }
            }

            // Check if we need to find our starting path position
            if (self.lookup_path_on_start) {
                if (self.owner.getComponent(triggers.TriggerComponent)) |trigger| {
                    const start_state = self.state;
                    self.followPath(trigger.target.str);
                    self.state = start_state;
                }
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
                if (self.returns_on_squish and self.squish_timer >= self.squish_return_time) {
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

                if (self.starts_overlapping_movers)
                    self.startOverlappingMovers();
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

        self.updateSoundState();

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
        } else if (self.start_type == .WAIT_FOR_BUMP and self.state == .IDLE_REVERSED) {
            self.state = .WAITING_END;
        } else {
            // Show locked message
            if (self.state == .IDLE and self.message.len > 0) {
                if (main.game_instance.player_controller) |player| {
                    if (self.message.len > 0)
                        player.showMessage(self.message.str);
                }
            }
        }
    }

    /// Callback for when we are shot
    pub fn onDamage(self: *MoverComponent, touching: entities.Entity) void {
        _ = touching;
        if (self.start_type == .WAIT_FOR_DAMAGE and self.state == .IDLE) {
            self.state = .WAITING_START;
        } else if (self.start_type == .WAIT_FOR_DAMAGE and self.state == .IDLE_REVERSED) {
            self.state = .WAITING_END;
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
            for (self._attached.items) |attached| {
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
        // If we have a trigger to fire, do it now!
        if (self.owner.getComponent(triggers.TriggerComponent)) |trigger| {
            delve.debug.info("Mover triggering owned trigger with target {s}", .{trigger.target.str});
            trigger.onTrigger(null);
        }

        // not moving, zero out predicted ride velocity
        for (self._attached.items) |entity| {
            // zero out our predicted ride velocity too
            if (entity.getComponent(basics.TransformComponent)) |transform| {
                transform.ride_velocity = math.Vec3.zero;
            }
        }

        if (!self.play_end_sound)
            return;

        _ = delve.platform.audio.playSound("assets/audio/sfx/mover-end.mp3", .{
            .volume = 1.0 * options.options.sfx_volume,
            .position = self.owner.getPosition(),
            .distance_rolloff = 0.1,
        });
    }

    pub fn onDoneReturning(self: *MoverComponent) void {
        // not moving, zero out predicted ride velocity
        for (self._attached.items) |entity| {
            // zero out our predicted ride velocity too
            if (entity.getComponent(basics.TransformComponent)) |transform| {
                transform.ride_velocity = math.Vec3.zero;
            }
        }

        if (!self.play_end_sound)
            return;

        _ = delve.platform.audio.playSound("assets/audio/sfx/mover-end.mp3", .{
            .volume = 1.0 * options.options.sfx_volume,
            .position = self.owner.getPosition(),
            .distance_rolloff = 0.1,
        });
    }

    /// When triggered, start moving
    pub fn onTrigger(self: *MoverComponent, info: triggers.TriggerFireInfo) void {
        delve.debug.info("Mover with state {any} triggered with value '{s}', from_path_node: {any}", .{ self.state, info.value, info.from_path_node });

        if (info.from_path_node) {
            if (self.owner.getComponent(triggers.TriggerComponent)) |trigger| {
                _ = trigger;
                self.followPath(info.value);
            }
            return;
        }

        if (info.value.len > 0 and info.value[0] != 0) {
            if (self.owner.getComponent(triggers.TriggerComponent)) |trigger| {
                _ = trigger;
                self.followPath(info.value);
                return;
            }
        } else {
            if (self.owner.getComponent(triggers.TriggerComponent)) |trigger| {
                self.followPath(trigger.target.str);
                return;
            }
        }

        // If no trigger or path value, just start moving if we are idle
        if (self.state == .IDLE) {
            self.state = .WAITING_START;
        } else if (self.returns and self.state == .WAITING_END) {
            self.state = .RETURNING;
        } else if (self.state == .IDLE_REVERSED) {
            self.state = .RETURNING;
        }
    }

    pub fn addRider(self: *MoverComponent, entity: entities.Entity) void {
        var attached_already = false;
        for (self._attached.items) |existing| {
            if (existing.id.equals(entity.id)) {
                attached_already = true;
                break;
            }
        }

        if (attached_already)
            return;

        self._attached.append(entity) catch {
            return;
        };
    }

    pub fn removeRider(self: *MoverComponent, entity: entities.Entity) void {
        for (0..self._attached.items.len) |idx| {
            if (self._attached.items[idx].id.equals(entity.id)) {
                _ = self._attached.swapRemove(idx);

                // persist our velocity to this entity when they leave!
                if (self.transfer_velocity)
                    entity.setVelocity(entity.getVelocity().add(self.owner.getVelocity()));

                // zero out our predicted ride velocity too
                if (entity.getComponent(basics.TransformComponent)) |transform| {
                    transform.ride_velocity = math.Vec3.zero;
                }

                return;
            }
        }
    }

    pub fn removeAllRiders(self: *MoverComponent, kick_velocity: math.Vec3) void {
        for (self._attached.items) |entity| {
            // persist our velocity to this entity when they leave!
            if (self.transfer_velocity)
                entity.setVelocity(entity.getVelocity().add(kick_velocity));

            // zero out our predicted ride velocity too
            if (entity.getComponent(basics.TransformComponent)) |transform| {
                transform.ride_velocity = math.Vec3.zero;
            }
        }
    }

    pub fn followPath(self: *MoverComponent, path_name: []const u8) void {
        const world_opt = entities.getWorld(self.owner.getWorldId());
        if (world_opt == null)
            return;

        const world = world_opt.?;
        var move_to_path: ?math.Vec3 = null;

        if (world.getEntityByName(path_name)) |path_entity| {
            move_to_path = path_entity.getPosition();
        }

        if (move_to_path) |p| {
            if (self.owner.getComponent(triggers.TriggerComponent)) |trigger| {
                // Set our target to be the path we are moving to
                trigger.target.set(path_name);
            }

            if (self.state == .IDLE or self.state == .WAITING_START) {
                const to_next_path_move_amount = p.sub(self._start_pos.?);
                self.move_amount = to_next_path_move_amount.add(self.move_offset);
                self.move_time = self.move_amount.len() / self.move_speed;
                self.state = .MOVING;
            } else if (self.state == .WAITING_END) {
                self._start_pos = self.owner.getPosition();
                const to_next_path_move_amount = p.sub(self._start_pos.?);
                self.move_amount = to_next_path_move_amount.add(self.move_offset);
                self.move_time = self.move_amount.len() / self.move_speed;
                self.state = .MOVING;
            } else {
                delve.debug.log("Mover can not move to path, still moving! {any}", .{self.state});
            }
        }
    }

    pub fn updateSoundState(self: *MoverComponent) void {
        const play_sound: bool = switch (self.state) {
            .MOVING => true,
            .RETURNING => true,
            else => false,
        };

        if (self.owner.getComponent(audio.LoopingSoundComponent)) |s| {
            if (play_sound) {
                s.start();
            } else {
                s.stop();
            }
        }
    }

    pub fn startOverlappingMovers(self: *MoverComponent) void {
        const world_opt = entities.getWorld(self.owner.getWorldId());
        if (world_opt == null)
            return;
        const world = world_opt.?;

        // Get our bounds from our solid
        const solids_opt = self.owner.getComponent(quakesolids.QuakeSolidsComponent);
        if (solids_opt == null)
            return;

        const bounds = solids_opt.?.bounds;

        // Look for any other overlapping doors, to open double doors in unison
        var it = getComponentStorage(world).iterator();
        while (it.next()) |mover| {
            if (self == mover)
                continue;

            // Only open doors that could start other doors themselves
            if (!mover.starts_overlapping_movers)
                continue;

            // Ignore doors that are already moving
            if (!((mover.state == .IDLE) or (mover.state == .WAITING_START)))
                continue;

            const other_solids_opt = mover.owner.getComponent(quakesolids.QuakeSolidsComponent);
            if (other_solids_opt == null) {
                return;
            }

            const other_bounds = other_solids_opt.?.bounds;
            if (bounds.inflate(0.00001).intersects(other_bounds)) {
                mover.state = .MOVING;
                mover.timer = 0;
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

        if (entity.getComponent(basics.TransformComponent)) |transform| {
            transform.ride_velocity = amount;
        }
    }
}

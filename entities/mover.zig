const std = @import("std");
const delve = @import("delve");
const entities = @import("../game/entities.zig");
const main = @import("../main.zig");
const basics = @import("basics.zig");
const box_collision = @import("box_collision.zig");
const character = @import("character.zig");
const collision = @import("../utils/collision.zig");

const math = delve.math;

pub const MoverType = enum {
    SLIDE,
};

pub const MoverState = enum {
    WAITING_START,
    MOVING,
    WAITING_END,
    RETURNING,
};

pub fn flipMoverState(state: MoverState) MoverState {
    return switch (state) {
        .WAITING_START => .WAITING_END,
        .MOVING => .RETURNING,
        .WAITING_END => .WAITING_START,
        .RETURNING => .MOVING,
    };
}

/// Moves an entity! Doors, platforms, etc
pub const MoverComponent = struct {
    mover_type: MoverType = .SLIDE,
    move_amount: math.Vec3 = math.Vec3.y_axis.scale(6.0), // how far to move from the starting position
    move_time: f32 = 1.0, // how long it takes to move
    start_delay: f32 = 1.0, // how long to wait before starting to move
    returns: bool = true, // whether or not to return to the starting position
    return_speed_mod: f32 = 2.0, // how much to scale the move_time by when returning
    returns_on_squish: bool = true, // whether or not to flip movement direction when stuck
    squish_return_time: f32 = 1.0, // how long we've been squishing something
    return_delay_time: f32 = 1.0, // how long to wait to return at the end of a move
    transfer_velocity: bool = true, // whether we should transfer our velocity when detaching entities
    eject_at_end: bool = false, // whether we should kick entities at the end of a move (for springs!)

    owner: entities.Entity = entities.InvalidEntity,

    state: MoverState = .WAITING_START,
    timer: f32 = 0.0,
    squish_timer: f32 = 0.0,

    start_pos: ?math.Vec3 = null,

    attached: std.ArrayList(entities.Entity) = undefined,
    moved_already: std.ArrayList(entities.Entity) = undefined,

    pub fn init(self: *MoverComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;
        self.attached = std.ArrayList(entities.Entity).init(delve.mem.getAllocator());
        self.moved_already = std.ArrayList(entities.Entity).init(delve.mem.getAllocator());
    }

    pub fn deinit(self: *MoverComponent) void {
        self.attached.deinit();
        self.moved_already.deinit();
    }

    pub fn tick(self: *MoverComponent, delta: f32) void {
        const start_time = self.timer;

        self.timer += if (self.state != .RETURNING) delta else delta * self.return_speed_mod;

        const cur_pos = self.owner.getPosition();
        if (self.start_pos == null) {
            self.start_pos = cur_pos;
        }

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
            const next_pos = self.start_pos.?.add(cur_move);
            const pos_diff = next_pos.sub(cur_pos);

            // do our move!
            const did_move = self.move(pos_diff, delta);

            if (!did_move) {
                // didn't move! keep timer where we are
                self.timer = start_time;
                self.squish_timer += delta;

                // If we've been squished too long, back up!
                if (self.squish_timer >= self.squish_return_time) {
                    self.state = flipMoverState(self.state);
                    self.timer = self.move_time - self.timer;
                    self.squish_timer = 0.0;
                }
            } else {
                self.squish_timer = 0.0;
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
                }
            } else {
                self.timer = 0;
            }
        }
        if (self.state == .RETURNING) {
            if (self.timer >= self.move_time) {
                self.state = .WAITING_START;
                self.timer = 0;

                if (self.eject_at_end)
                    self.removeAllRiders(start_vel);

                self.owner.setVelocity(delve.math.Vec3.zero);
            }
        }

        // render debug box!
        const collision_opt = self.owner.getComponent(box_collision.BoxCollisionComponent);
        if (collision_opt) |col| {
            col.renderDebug();
        }
    }

    pub fn getPosAtTime(self: *MoverComponent, time: f32) math.Vec3 {
        return switch (self.mover_type) {
            .SLIDE => self.move_amount.scale(@min(time / self.move_time, 1.0)),
        };
    }

    pub fn move(self: *MoverComponent, move_amount: math.Vec3, delta: f32) bool {
        const world_opt = entities.getWorld(self.owner.getWorldId());
        if (world_opt == null)
            return false;

        const collision_opt = self.owner.getComponent(box_collision.BoxCollisionComponent);

        const world = world_opt.?;
        const cur_pos = self.owner.getPosition();
        const next_pos = cur_pos.add(move_amount);
        const vel = move_amount.scale(1.0 / delta);

        // Push entities out of the way!
        var can_move = true;
        if (collision_opt != null) {
            const hit_entity = collision.checkEntityCollision(world, next_pos, collision_opt.?.size, self.owner);
            if (hit_entity != null) {
                // push our encroached entity out of the way
                collision_opt.?.disable_collision = true;
                pushEntity(hit_entity.?, move_amount.scale(1.0 / delta), delta);
                collision_opt.?.disable_collision = false;

                // are we clear now?
                const post_push_hit = collision.checkEntityCollision(world, next_pos, collision_opt.?.size, self.owner);
                if (post_push_hit != null)
                    can_move = false;

                // track that we already moved this entity
                self.moved_already.append(hit_entity.?) catch {
                    return false;
                };
            }
        }

        if (can_move) {
            // set our new position, and our current velocity
            self.owner.setPosition(next_pos);
            self.owner.setVelocity(vel);

            // Move all of the things riding on us!
            for (self.attached.items) |attached| {
                var moved_already = false;
                for (self.moved_already.items) |already| {
                    if (attached.id.equals(already.id)) {
                        moved_already = true;
                        break;
                    }
                }

                if (!moved_already) {
                    pushEntity(attached, move_amount.scale(1.0 / delta), delta);
                }
            }
        } else {
            self.owner.setVelocity(delve.math.Vec3.zero);
        }

        self.moved_already.clearRetainingCapacity();

        return can_move;
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

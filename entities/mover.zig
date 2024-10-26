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
    SIN_WAVE,
};

/// Moves an entity! Doors, platforms, etc
pub const MoverComponent = struct {
    move_amount: math.Vec3 = math.Vec3.one.scale(6.0),
    move_speed: f32 = 1.0,
    transfer_velocity: bool = true,

    owner: entities.Entity = entities.InvalidEntity,
    time: f32 = 0.0,
    start_pos: ?math.Vec3 = null,
    next_pos: ?math.Vec3 = null,

    attached: std.ArrayList(entities.Entity) = undefined,
    moved_already: std.ArrayList(entities.Entity) = undefined,

    pub fn init(self: *MoverComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;
        self.attached = std.ArrayList(entities.Entity).init(delve.mem.getAllocator());
        self.moved_already = std.ArrayList(entities.Entity).init(delve.mem.getAllocator());
    }

    pub fn deinit(self: *MoverComponent) void {
        _ = self;
    }

    pub fn tick(self: *MoverComponent, delta: f32) void {
        const start_time = self.time;
        self.time += delta;

        const cur_pos = self.owner.getPosition();
        if (self.start_pos == null) {
            self.start_pos = cur_pos;
        }

        const cur_move = self.move_amount.scale(std.math.sin(self.time * self.move_speed));
        const next_pos = self.start_pos.?.add(cur_move);
        const pos_diff = next_pos.sub(cur_pos);

        const did_move = self.move(pos_diff, delta);
        if (!did_move) {
            // didn't move! keep timer where we are
            self.time = start_time;
        }

        // render debug box!
        const collision_opt = self.owner.getComponent(box_collision.BoxCollisionComponent);
        if (collision_opt) |col| {
            col.renderDebug();
        }
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
                _ = slideMove(hit_entity.?, move_amount);
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
                    _ = slideMove(attached, move_amount);
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
};

pub fn getComponentStorage(world: *entities.World) *entities.ComponentStorage(MoverComponent) {
    return world.components.getStorageForType(MoverComponent) catch {
        delve.debug.fatal("Could not get MoverComponent storage!", .{});
        return undefined;
    };
}

pub fn slideMove(entity: entities.Entity, amount: delve.math.Vec3) math.Vec3 {
    const movement_opt = entity.getComponent(character.CharacterMovementComponent);
    if (movement_opt) |movement| {
        return movement.slideMove(amount);
    }
    return math.Vec3.zero;
}

const std = @import("std");
const delve = @import("delve");
const entities = @import("../game/entities.zig");
const main = @import("../main.zig");
const basics = @import("basics.zig");
const box_collision = @import("box_collision.zig");

const math = delve.math;

pub const MoverType = enum {
    SIN_WAVE,
};

/// Moves an entity! Doors, platforms, etc
pub const MoverComponent = struct {
    move_amount: math.Vec3 = math.Vec3.x_axis.scale(6.0),
    move_vel: math.Vec3 = math.Vec3.zero,

    owner: entities.Entity = entities.InvalidEntity,
    time: f32 = 0.0,
    move_speed: f32 = 6.0,

    start_pos: ?math.Vec3 = null,
    next_pos: ?math.Vec3 = null,

    attached: std.ArrayList(entities.Entity) = undefined,

    pub fn init(self: *MoverComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;
        self.attached = std.ArrayList(entities.Entity).init(delve.mem.getAllocator());
    }

    pub fn deinit(self: *MoverComponent) void {
        _ = self;
    }

    pub fn tick(self: *MoverComponent, delta: f32) void {
        self.time += delta;
        self.move_vel = self.move_amount.scale(std.math.sin(self.time * self.move_speed));

        const cur_pos = self.owner.getPosition();

        if (self.start_pos == null) {
            self.start_pos = cur_pos;
        }
        const cur_move = self.move_amount.scale(std.math.sin(self.time * self.move_speed));
        const next_pos = self.start_pos.?.add(cur_move);
        const diff = next_pos.sub(cur_pos);
        const vel = diff.scale(1.0 / delta);

        // set our new position, and our current velocity
        self.owner.setPosition(next_pos);
        self.owner.setVelocity(vel);

        // Move all of the things riding on us!
        for (self.attached.items) |attached| {
            const pos = attached.getPosition();
            attached.setPosition(pos.add(diff));
        }

        const collision_opt = self.owner.getComponent(box_collision.BoxCollisionComponent);
        if (collision_opt) |collision| {
            collision.renderDebug();
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

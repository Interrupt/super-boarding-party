const std = @import("std");
const delve = @import("delve");
const entities = @import("../game/entities.zig");
const box_collision = @import("box_collision.zig");
const player_components = @import("player.zig");
const stats = @import("actor_stats.zig");

const math = delve.math;

pub const ItemType = enum {
    Medkit,
    Ammo,
    Weapon,
};

pub const PickupType = enum {
    OnTouch,
};

/// Makes the entity pickupable when walked over
pub const ItemComponent = struct {
    pickup_type: PickupType = .OnTouch,
    item_type: ItemType = .Medkit,

    // interface
    owner: entities.Entity = entities.InvalidEntity,

    pub fn init(self: *ItemComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;
    }

    pub fn deinit(self: *ItemComponent) void {
        _ = self;
    }

    pub fn tick(self: *ItemComponent, delta: f32) void {
        _ = delta;

        // Check if any players are colliding
        if (self.pickup_type == .OnTouch) {
            var player_it = player_components.getComponentStorage(self.owner.getOwningWorld().?).iterator();

            const our_collision_box_opt = self.owner.getComponent(box_collision.BoxCollisionComponent);
            if (our_collision_box_opt == null)
                return;

            const our_aabb = our_collision_box_opt.?.getBoundingBox();

            while (player_it.next()) |p| {
                const player_collision_box_opt = p.owner.getComponent(box_collision.BoxCollisionComponent);
                if (player_collision_box_opt == null)
                    continue;

                if (our_aabb.intersects(player_collision_box_opt.?.getBoundingBox())) {
                    delve.debug.log("Picked up item!", .{});

                    switch (self.item_type) {
                        .Medkit => {
                            const target_stats_opt = p.owner.getComponent(stats.ActorStats);
                            if (target_stats_opt) |target_stats| {
                                target_stats.heal(25);
                            }
                        },
                        else => |t| {
                            delve.debug.log("Item type {any} not implemented!", .{t});
                        },
                    }

                    // Remove ourselves when picked up!
                    self.owner.deinit();
                }
            }
        }
    }
};

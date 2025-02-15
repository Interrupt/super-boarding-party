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
            while (player_it.next()) |p| {
                if (p.owner.getComponent(box_collision.BoxCollisionComponent)) |c| {
                    if (c.getBoundingBox().inflate(0.2).contains(self.owner.getPosition())) {
                        delve.debug.log("Picked up item!", .{});

                        // flash screen!
                        // p.screen_flash_time = 0.3;
                        // p.screen_flash_timer = 0.3;
                        // p.screen_flash_color = delve.colors.Color.new(0.0, 1.0, 1.0, 0.2);

                        const target_stats_opt = p.owner.getComponent(stats.ActorStats);
                        if (target_stats_opt) |target_stats| {
                            target_stats.heal(25);
                        }

                        self.owner.deinit();
                    }
                }
            }
        }
    }
};

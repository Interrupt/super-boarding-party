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
    item_id: []const u8 = "", // eg: weapon.RocketLauncher

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
                    self.doPickup(p);
                    return;
                }
            }
        }
    }

    pub fn doPickup(self: *ItemComponent, player: *player_components.PlayerController) void {
        // flash the screen!
        player.screen_flash_time = 0.3;
        player.screen_flash_timer = 0.3;
        player.screen_flash_color = delve.colors.Color.new(1.0, 1.0, 1.0, 0.2);

        switch (self.item_type) {
            .Medkit => {
                const target_stats_opt = player.owner.getComponent(stats.ActorStats);
                if (target_stats_opt) |target_stats| {
                    target_stats.heal(25);
                }
            },
            .Weapon => {
                player.switchWeapon(3);
            },
            else => |t| {
                delve.debug.log("Item type {any} not implemented!", .{t});
            },
        }

        // Remove ourselves when picked up!
        self.owner.deinit();
    }
};

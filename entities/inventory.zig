const std = @import("std");
const delve = @import("delve");
const basics = @import("basics.zig");
const entities = @import("../game/entities.zig");
const player_components = @import("player.zig");
const weapons = @import("weapon.zig");
const string = @import("../utils/string.zig");

const math = delve.math;

pub const WeaponSlot = struct {
    weapon_type: weapons.WeaponType = .Melee,
    picked_up: bool = false,
    weapon_pickup_ammo: usize = 5,
};

pub const AmmoSlot = struct {
    ammo_type: weapons.AmmoType = .PistolBullets,
    ammo_count: usize = 0,
};

pub const InventoryComponent = struct {
    // interface
    owner: entities.Entity = entities.InvalidEntity,

    // basic player inventory: holds weapon slots and ammo
    weapon_slots: [4]WeaponSlot = .{
        .{ .weapon_type = .Pistol, .picked_up = true, .weapon_pickup_ammo = 10 },
        .{ .weapon_type = .AssaultRifle, .weapon_pickup_ammo = 40 },
        .{ .weapon_type = .RocketLauncher, .weapon_pickup_ammo = 5 },
        .{ .weapon_type = .PlasmaRifle, .weapon_pickup_ammo = 25 },
    },

    ammo_slots: [4]AmmoSlot = .{
        .{ .ammo_type = .PistolBullets, .ammo_count = 40 },
        .{ .ammo_type = .RifleBullets },
        .{ .ammo_type = .Rockets },
        .{ .ammo_type = .BatteryCells },
    },

    pub fn init(self: *InventoryComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;
    }

    pub fn deinit(self: *InventoryComponent) void {
        _ = self;
    }

    pub fn hasWeapon(self: *InventoryComponent, weapon_type: weapons.WeaponType) bool {
        for (&self.weapon_slots) |*slot| {
            if (slot.weapon_type == weapon_type) {
                return slot.picked_up;
            }
        }
        return false;
    }

    pub fn addWeapon(self: *InventoryComponent, weapon_type: weapons.WeaponType) void {
        for (&self.weapon_slots) |*slot| {
            if (slot.weapon_type == weapon_type) {
                slot.picked_up = true;
                const ammo_type = weapons.getAmmoTypeForWeaponType(slot.weapon_type);
                self.addAmmo(ammo_type, slot.weapon_pickup_ammo);
                return;
            }
        }
    }

    pub fn getAmmoCount(self: *InventoryComponent, ammo_type: weapons.AmmoType) usize {
        for (&self.ammo_slots) |*slot| {
            if (slot.ammo_type == ammo_type) {
                return slot.ammo_count;
            }
        }
        return 0;
    }

    pub fn consumeAmmo(self: *InventoryComponent, ammo_type: weapons.AmmoType, amount: usize) bool {
        for (&self.ammo_slots) |*slot| {
            if (slot.ammo_type == ammo_type) {
                if (slot.ammo_count < amount)
                    return false;

                slot.ammo_count -= amount;
                return true;
            }
        }
        return false;
    }

    pub fn addAmmo(self: *InventoryComponent, ammo_type: weapons.AmmoType, amount: usize) void {
        for (&self.ammo_slots) |*slot| {
            if (slot.ammo_type == ammo_type) {
                slot.ammo_count += amount;
                return;
            }
        }
    }
};

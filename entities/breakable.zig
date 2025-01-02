const std = @import("std");
const delve = @import("delve");
const entities = @import("../game/entities.zig");
const triggers = @import("triggers.zig");
const stats = @import("actor_stats.zig");
const debug = delve.debug;
const graphics = delve.platform.graphics;
const math = delve.math;

pub const BreakableComponent = struct {
    // properties
    breaks_on_trigger: bool = true,

    // interface
    owner: entities.Entity = entities.InvalidEntity,

    pub fn init(self: *BreakableComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;
    }

    pub fn deinit(self: *BreakableComponent) void {
        _ = self;
    }

    pub fn tick(self: *BreakableComponent, delta: f32) void {
        _ = delta;

        if (self.owner.getComponent(stats.ActorStats)) |s| {
            if (!s.isAlive())
                self.doBreak();
        }
    }

    /// When triggered, break
    pub fn onTrigger(self: *BreakableComponent, info: triggers.TriggerFireInfo) void {
        _ = info;

        if (self.breaks_on_trigger)
            self.doBreak();
    }

    pub fn doBreak(self: *BreakableComponent) void {
        // TODO: play vfx/sfx here!

        // broken, destroy self!
        self.owner.deinit();
    }
};

pub fn getComponentStorage(world: *entities.World) *entities.ComponentStorage(BreakableComponent) {
    return world.components.getStorageForType(BreakableComponent) catch {
        delve.debug.fatal("Could not get BreakableComponent storage!", .{});
        return undefined;
    };
}

const std = @import("std");
const delve = @import("delve");
const entities = @import("../game/entities.zig");
const basics = @import("basics.zig");
const triggers = @import("triggers.zig");
const emitter = @import("particle_emitter.zig");
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
            // when our health drops to 0, break!
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
        self.playBreakVfx();

        // If we have a trigger, fire it when we break!
        if (self.owner.getComponent(triggers.TriggerComponent)) |trigger| {
            trigger.fire(.{ .instigator = self.owner });
        }

        // broken, destroy self!
        self.owner.deinit();
    }

    pub fn playBreakVfx(self: *BreakableComponent) void {
        const world = entities.getWorld(self.owner.id.world_id).?;

        // play break vfx
        var vfx = world.createEntity(.{}) catch {
            return;
        };
        _ = vfx.createNewComponent(basics.TransformComponent, .{ .position = self.owner.getPosition() }) catch {
            return;
        };
        _ = vfx.createNewComponent(emitter.ParticleEmitterComponent, .{
            .num = 6,
            .num_variance = 10,
            .spritesheet = "sprites/blank",
            .lifetime = 15.0,
            .position_variance = math.Vec3.one.scale(2.5),
            .velocity = math.Vec3.zero,
            .velocity_variance = math.Vec3.one.scale(10.0),
            .gravity = -55,
            .color = delve.colors.white,
            .scale = 0.3125, // 1 / 32
            .end_color = delve.colors.white,
            .delete_owner_when_done = true,
        }) catch {
            return;
        };
    }
};

pub fn getComponentStorage(world: *entities.World) *entities.ComponentStorage(BreakableComponent) {
    return world.components.getStorageForType(BreakableComponent) catch {
        delve.debug.fatal("Could not get BreakableComponent storage!", .{});
        return undefined;
    };
}

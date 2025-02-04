const std = @import("std");
const delve = @import("delve");
const entities = @import("../game/entities.zig");
const basics = @import("basics.zig");
const triggers = @import("triggers.zig");
const emitter = @import("particle_emitter.zig");
const stats = @import("actor_stats.zig");
const string = @import("../utils/string.zig");
const quakesolids = @import("quakesolids.zig");
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

        delve.debug.log("Breakable Triggered!", .{});

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
        var size: math.Vec3 = math.Vec3.one.scale(2.5);

        // If we have a quake solid, use that for the size
        if (self.owner.getComponent(quakesolids.QuakeSolidsComponent)) |brush| {
            const bounds = brush.getBounds();
            size = bounds.max.sub(bounds.min);
        }

        // Use the size to figure out how many particles to make
        var num: u32 = @intFromFloat(size.x * size.y * size.z);
        num = @max(num, 1) * 8;
        num = @min(num, 100);

        // make break vfx particle emitter
        var vfx = world.createEntity(.{}) catch {
            return;
        };
        _ = vfx.createNewComponent(basics.TransformComponent, .{ .p_position = self.owner.getPosition() }) catch {
            return;
        };

        _ = vfx.createNewComponent(emitter.ParticleEmitterComponent, .{
            .num = num,
            .num_variance = num,
            .spritesheet = string.String.init("sprites/blank"),
            .lifetime = 15.0,
            .position_variance = size,
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

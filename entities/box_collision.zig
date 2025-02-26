const std = @import("std");
const delve = @import("delve");
const entities = @import("../game/entities.zig");
const spatialhash = @import("../utils/spatial_hash.zig");
const main = @import("../main.zig");

const colors = delve.colors;
const math = delve.math;
const spatial = delve.spatial;

pub var spatial_hash: spatialhash.SpatialHash(BoxCollisionComponent) = undefined;

// when drawing debug boxes, use a variety of colors
const debug_colors: [10]colors.Color = [_]colors.Color{
    colors.red,
    colors.blue,
    colors.green,
    colors.olive,
    colors.purple,
    colors.orange,
    colors.yellow,
    colors.cyan,
    colors.magenta,
    colors.tan,
};

pub var enable_debug_viz: bool = false;

/// Gives a physical collision AABB to an Entity
pub const BoxCollisionComponent = struct {
    size: math.Vec3 = math.Vec3.new(1.0, 1.8288, 1.0),
    can_step_up_on: bool = false,
    collides_world: bool = true,
    collides_entities: bool = true,

    owner: entities.Entity = entities.InvalidEntity,

    pub fn init(self: *BoxCollisionComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;
    }

    pub fn deinit(self: *BoxCollisionComponent) void {
        _ = self;
    }

    pub fn tick(self: *BoxCollisionComponent, delta: f32) void {
        _ = delta;

        if (enable_debug_viz)
            self.renderDebug();
    }

    pub fn renderDebug(self: *BoxCollisionComponent) void {
        const next_debug_color = @mod(self.owner.id.id, debug_colors.len);
        main.render_instance.drawDebugWireframeCube(self.owner.getPosition(), delve.math.Vec3.zero, self.size, delve.math.Vec3.y_axis, debug_colors[next_debug_color]);
    }

    pub fn getBoundingBox(self: *BoxCollisionComponent) spatial.BoundingBox {
        return delve.spatial.BoundingBox.init(self.owner.getPosition(), self.size);
    }

    pub fn updateSpatialHash(self: *BoxCollisionComponent) void {
        spatial_hash.addEntry(self, self.getBoundingBox(), true) catch {
            return;
        };
    }
};

pub fn getComponentStorage(world: *entities.World) *entities.ComponentStorage(BoxCollisionComponent) {
    return world.components.getStorageForType(BoxCollisionComponent) catch {
        delve.debug.fatal("Could not get BoxCollisionComponent storage!", .{});
        return undefined;
    };
}

pub fn updateSpatialHash(world: *entities.World) void {
    spatial_hash.clear();
    var it = getComponentStorage(world).iterator();
    while (it.next()) |c| {
        spatial_hash.addEntry(c, c.getBoundingBox(), false) catch {
            continue;
        };
    }
}

pub fn init() void {
    spatial_hash = spatialhash.SpatialHash(BoxCollisionComponent).init(4.0, delve.mem.getAllocator());
}

pub fn deinit() void {
    spatial_hash.deinit();
}

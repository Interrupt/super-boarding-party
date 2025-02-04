const std = @import("std");
const delve = @import("delve");
const entities = @import("../game/entities.zig");
const main = @import("../main.zig");
const mover = @import("mover.zig");
const lights = @import("light.zig");
const quakesolids = @import("quakesolids.zig");
const box_collision = @import("box_collision.zig");
const string = @import("../utils/string.zig");
const math = delve.math;

/// Properties are wrappers for types with added functionality for serialization and netplay
pub fn Property(comptime T: type) type {
    return struct {
        val: T,

        // TODO: Add some config options for serialization and replication

        const Self = @This();

        pub fn new(val: T) Self {
            return Self{ .val = val };
        }

        pub fn get(self: *const Self) T {
            return self.val;
        }

        pub fn set(self: *Self, val: T) void {
            self.val = val;
        }

        pub fn jsonStringify(self: *const Self, out: anytype) !void {
            // Just write our wrapped value
            try out.write(self.val);
        }

        pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Self {
            // Read the wrapped value
            const v = try std.json.innerParse(T, allocator, source, options);
            return Self{ .val = v };
        }

        // Maybe we can use std.meta.hasFn to check whether a type is a property when parsing
        pub fn shouldPersist() bool {
            return true;
        }
    };
}

pub fn newProperty(val: anytype) Property(@TypeOf(val)) {
    return Property(@TypeOf(val)).new(val);
}

/// The EntityComponent that gives a world location and rotation to an Entity
pub const TransformComponent = struct {
    // properties
    position: math.Vec3 = math.Vec3.zero,
    rotation: math.Quaternion = math.Quaternion.identity,
    scale: math.Vec3 = math.Vec3.one,
    velocity: math.Vec3 = math.Vec3.zero,
    ride_velocity: math.Vec3 = math.Vec3.zero,

    // just testing out a property
    test_property: Property(bool) = newProperty(false),

    _fixed_tick_position: math.Vec3 = math.Vec3.zero,
    _fixed_tick_rotation: math.Quaternion = math.Quaternion.identity,
    _fixed_tick_delta: f32 = 0.0,
    _first_tick: bool = true,

    pub fn init(self: *TransformComponent, interface: entities.EntityComponent) void {
        _ = self;
        _ = interface;
    }

    pub fn physics_tick(self: *TransformComponent, delta: f32) void {
        // keep our transform values to lerp to between fixed physics ticks
        self._fixed_tick_delta = delta;
        self._fixed_tick_position = self.position;
        self._fixed_tick_rotation = self.rotation;
        self._first_tick = false;
    }

    pub fn getPosition(self: *TransformComponent) math.Vec3 {
        return self.position;
    }

    pub fn getRenderPosition(self: *TransformComponent) math.Vec3 {
        if (self._first_tick)
            return self.position;

        // extrapolate out where we will probably be based on our last physics tick position
        const predicted_velocity = self.velocity.add(self.ride_velocity).scale(self._fixed_tick_delta);
        const predicted_next_position = self._fixed_tick_position.add(predicted_velocity);

        // lerp from our last physics tick position to our predicted one
        const fixed_timestep_lerp = delve.platform.app.getFixedTimestepLerp(false);
        return math.Vec3.lerp(self._fixed_tick_position, predicted_next_position, fixed_timestep_lerp);
    }

    pub fn deinit(self: *TransformComponent) void {
        _ = self;
    }
};

/// Removes an Entity after a given time
pub const LifetimeComponent = struct {
    // properties
    lifetime: f32,

    // interface
    owner: entities.Entity = entities.InvalidEntity,

    // calculated
    starting_lifetime: f32 = undefined,

    pub fn init(self: *LifetimeComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;
        self.starting_lifetime = self.lifetime;
    }

    pub fn deinit(self: *LifetimeComponent) void {
        _ = self;
    }

    pub fn tick(self: *LifetimeComponent, delta: f32) void {
        self.lifetime -= delta;
        if (self.lifetime <= 0.0) {
            self.owner.deinit();
        }
    }

    pub fn getAlpha(self: *LifetimeComponent) f32 {
        return self.lifetime / self.starting_lifetime;
    }
};

/// Attach one entity to another
pub const AttachmentComponent = struct {

    // properties
    attached_to: entities.Entity,
    offset_position: math.Vec3,

    // interface
    owner: entities.Entity = entities.InvalidEntity,

    pub fn init(self: *AttachmentComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;
    }

    pub fn deinit(self: *AttachmentComponent) void {
        _ = self;
    }

    pub fn tick(self: *AttachmentComponent, delta: f32) void {
        _ = delta;

        // check if we still have a parent, if not remove us as well
        const world = entities.getWorld(self.attached_to.id.world_id).?;
        const attached_entity_opt = world.entities.getPtr(self.attached_to.id);
        if (attached_entity_opt == null) {
            self.owner.deinit();
            return;
        }

        self.owner.setPosition(self.attached_to.getPosition().add(self.offset_position));
    }
};

/// Allows this entity to be looked up by name
pub const NameComponent = struct {
    // properties
    name: string.String,

    // interface
    owner: entities.Entity = entities.InvalidEntity,

    pub fn init(self: *NameComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;

        // Empty name? Weird
        if (self.name.str.len == 0)
            return;

        const world_opt = entities.getWorld(self.owner.getWorldId());
        if (world_opt == null)
            return;

        const world = world_opt.?;

        // Keep track of this entity
        delve.debug.info("Creating named entity '{s}' {d}", .{ self.name.str, self.owner.id.id });
        if (!world.named_entities.contains(self.name.str)) {
            // If there is no list for this name yet, make one
            const allocator = delve.mem.getAllocator();
            const owned_name = self.name.toOwnedString(allocator) catch {
                return;
            };

            delve.debug.log("Created name list for entity '{s}'", .{self.name.str});
            world.named_entities.put(owned_name, std.ArrayList(entities.EntityId).init(allocator)) catch {
                return;
            };
        }

        // List exists now, put our entity ID into it
        if (world.named_entities.getPtr(self.name.str)) |entity_list| {
            entity_list.append(self.owner.id) catch {
                return;
            };
        }
    }

    pub fn deinit(self: *NameComponent) void {
        const world_opt = entities.getWorld(self.owner.getWorldId());
        if (world_opt == null)
            return;

        const world = world_opt.?;
        _ = world;

        defer self.name.deinit();

        // TODO: Fix this back up! Is causing an assert on error
        // delve.debug.log("Removing ourselves from named entity list: {s}", .{self.name.str});
        //
        // // find and remove our owner ID from the name list
        // if (world.named_entities.getPtr(self.name.str)) |entity_list| {
        //     for (entity_list.items, 0..) |item, idx| {
        //         if (item.equals(self.owner.id)) {
        //             _ = entity_list.swapRemove(idx);
        //             return;
        //         }
        //     }
        // } else {
        //     delve.debug.warning("Could not find named entity list for '{s}' during NameComponent deinit", .{self.name.str});
        // }
    }
};

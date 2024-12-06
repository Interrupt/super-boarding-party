const std = @import("std");
const delve = @import("delve");
const entities = @import("../game/entities.zig");
const main = @import("../main.zig");
const mover = @import("mover.zig");
const lights = @import("light.zig");
const quakesolids = @import("quakesolids.zig");
const box_collision = @import("box_collision.zig");
const math = delve.math;

/// The EntityComponent that gives a world location and rotation to an Entity
pub const TransformComponent = struct {
    // properties
    position: math.Vec3 = math.Vec3.zero,
    rotation: math.Quaternion = math.Quaternion.identity,
    scale: math.Vec3 = math.Vec3.one,
    velocity: math.Vec3 = math.Vec3.zero,
    ride_velocity: math.Vec3 = math.Vec3.zero,

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
        self.owner.setPosition(self.attached_to.getPosition().add(self.offset_position));
    }
};

/// Allows this entity to be looked up by name
pub const NameComponent = struct {
    // properties
    name: []const u8,

    // calculated
    owned_name_buffer: [64]u8 = std.mem.zeroes([64]u8),
    owned_name: [:0]const u8 = undefined,

    // interface
    owner: entities.Entity = entities.InvalidEntity,

    pub fn init(self: *NameComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;

        // make sure we own our name string! could go out of scope after this
        @memcpy(self.owned_name_buffer[0..self.name.len], self.name);
        self.owned_name = self.owned_name_buffer[0..63 :0];
        self.name = self.owned_name;

        const world_opt = entities.getWorld(self.owner.getWorldId());
        if (world_opt == null)
            return;

        const world = world_opt.?;

        // Keep track of this entity
        delve.debug.info("Creating named entity '{s}' {d}", .{ self.owned_name, self.owner.id.id });
        if (!world.named_entities.contains(self.owned_name)) {
            // If there is no list for this name yet, make one
            world.named_entities.put(self.owned_name, std.ArrayList(entities.EntityId).init(delve.mem.getAllocator())) catch {
                return;
            };
        }

        // List exists now, put our entity ID into it
        if (world.named_entities.getPtr(self.owned_name)) |entity_list| {
            entity_list.append(self.owner.id) catch {
                return;
            };
        }
    }

    pub fn deinit(self: *NameComponent) void {
        _ = self;
    }
};

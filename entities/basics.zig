const std = @import("std");
const delve = @import("delve");
const entities = @import("../game/entities.zig");
const mover = @import("mover.zig");
const math = delve.math;

/// The EntityComponent that gives a world location and rotation to an Entity
pub const TransformComponent = struct {
    // properties
    position: math.Vec3 = math.Vec3.zero,
    rotation: math.Quaternion = math.Quaternion.identity,
    scale: math.Vec3 = math.Vec3.one,
    velocity: math.Vec3 = math.Vec3.zero,

    pub fn init(self: *TransformComponent, interface: entities.EntityComponent) void {
        _ = self;
        _ = interface;
    }

    pub fn deinit(self: *TransformComponent) void {
        _ = self;
    }

    pub fn tick(self: *TransformComponent, delta: f32) void {
        _ = self;
        _ = delta;
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
        delve.debug.log("Creating named entity '{s}' {d}", .{ self.owned_name, self.owner.id.id });
        world.named_entities.put(self.owned_name, self.owner.id) catch {
            return;
        };
    }

    pub fn deinit(self: *NameComponent) void {
        _ = self;
    }

    pub fn tick(self: *NameComponent, delta: f32) void {
        _ = self;
        _ = delta;
    }
};

pub const TriggerFireInfo = struct {
    value: []const u8 = "",
    instigator: ?entities.Entity,
    from_path_node: bool = false,
};

/// Allows this entity to trigger others
pub const TriggerComponent = struct {
    // properties
    target: []const u8,
    value: []const u8 = "",
    is_path_node: bool = false,

    // calculated
    owned_target_buffer: [64]u8 = std.mem.zeroes([64]u8),
    owned_target: [:0]const u8 = undefined,

    owned_value_buffer: [64]u8 = std.mem.zeroes([64]u8),
    owned_value: [:0]const u8 = undefined,

    // interface
    owner: entities.Entity = entities.InvalidEntity,

    pub fn init(self: *TriggerComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;

        // make sure we own our strings! could go out of scope after this
        @memcpy(self.owned_target_buffer[0..self.target.len], self.target);
        self.owned_target = self.owned_target_buffer[0..63 :0];
        self.target = self.owned_target;

        @memcpy(self.owned_value_buffer[0..self.value.len], self.value);
        self.owned_value = self.owned_value_buffer[0..63 :0];
        self.value = self.owned_value;

        delve.debug.log("Creating trigger targeting '{s}' with value '{s}'", .{ self.target, self.value });
    }

    pub fn deinit(self: *TriggerComponent) void {
        _ = self;
    }

    pub fn tick(self: *TriggerComponent, delta: f32) void {
        _ = self;
        _ = delta;
    }

    pub fn fire(self: *TriggerComponent, triggered_by: ?TriggerFireInfo) void {
        const world_opt = entities.getWorld(self.owner.getWorldId());
        if (world_opt == null)
            return;

        const world = world_opt.?;
        var value = self.value;

        // If we are a path node, pass on the entity that triggered us
        if (self.is_path_node and triggered_by != null and triggered_by.?.instigator != null) {
            delve.debug.log("Path Node triggered, path node has value '{s}'", .{value});

            if (value[0] == 0)
                value = self.target;

            if (triggered_by.?.instigator) |instigator| {
                delve.debug.log("Path Node has an instigator, it has value '{s}'", .{value});

                // Check for any components that can trigger
                if (instigator.getComponent(mover.MoverComponent)) |mc| {
                    mc.onTrigger(.{ .value = value, .instigator = self.owner, .from_path_node = true });
                } else if (instigator.getComponent(TriggerComponent)) |tc| {
                    tc.onTrigger(.{ .value = value, .instigator = self.owner, .from_path_node = true });
                }
                return;
            }
        }

        // If we were triggered by something else, pass on that value instead
        // For func_elevator!
        if (triggered_by != null)
            value = triggered_by.?.value;

        // Get our target entity!
        if (world.named_entities.get(self.target)) |found_entity_id| {
            if (world.getEntity(found_entity_id)) |to_trigger| {
                // Check for any components that can trigger
                if (to_trigger.getComponent(mover.MoverComponent)) |mc| {
                    mc.onTrigger(.{ .value = value, .instigator = self.owner, .from_path_node = self.is_path_node });
                } else if (to_trigger.getComponent(TriggerComponent)) |tc| {
                    tc.onTrigger(.{ .value = value, .instigator = self.owner, .from_path_node = self.is_path_node });
                }
            }
        }
    }

    pub fn onTrigger(self: *TriggerComponent, info: TriggerFireInfo) void {
        delve.debug.log("Trigger triggered with value '{s}'", .{info.value});

        self.fire(info);
    }
};

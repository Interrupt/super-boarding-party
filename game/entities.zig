const std = @import("std");
const delve = @import("delve");
const basics = @import("../entities/basics.zig");
const Allocator = std.mem.Allocator;

const Vec3 = delve.math.Vec3;
const BoundingBox = delve.spatial.BoundingBox;

pub const EntityId = packed struct {
    id: u24,
    world_id: u8,

    pub fn equals(self: EntityId, other: EntityId) bool {
        return self.id == other.id and self.world_id == other.world_id;
    }
};

pub const ComponentId = packed struct {
    id: u32,
    entity_id: EntityId,

    pub fn equals(self: ComponentId, other: ComponentId) bool {
        return self.id == other.id and self.entity_id == other.entity_id;
    }
};

/// Our global list of worlds
var worlds: [255]?World = [_]?World{null} ** 255;

/// Stores lists of components, by type
pub const ComponentArchetypeStorage = struct {
    archetypes: std.StringHashMap(ComponentStorageTypeErased),
    allocator: Allocator,

    pub fn init(allocator: Allocator) ComponentArchetypeStorage {
        return .{
            .allocator = allocator,
            .archetypes = std.StringHashMap(ComponentStorageTypeErased).init(allocator),
        };
    }

    pub fn getStorageForType(self: *ComponentArchetypeStorage, comptime ComponentType: type) !*ComponentStorage(ComponentType) {
        const typename = @typeName(ComponentType);
        if (self.archetypes.getPtr(typename)) |storage| {
            return storage.getStorage(ComponentStorage(ComponentType)); // convert from type erased
        }

        delve.debug.log("Creating storage for component archetype: {s}", .{@typeName(ComponentType)});
        try self.archetypes.put(typename, .{
            .typename = @typeName(ComponentType),
            .ptr = try ComponentStorage(ComponentType).init(self.allocator),
            .tick = (struct {
                pub fn tick(in_self: *ComponentStorageTypeErased, delta: f32) void {
                    var it = in_self.getStorage(ComponentStorage(ComponentType)).iterator(); // convert from type erased
                    while (it.next()) |c| {
                        c.tick(delta);
                    }
                }
            }).tick,
        });

        const added = self.archetypes.getPtr(typename);
        return added.?.getStorage(ComponentStorage(ComponentType)); // convert from type erased
    }
};

/// Stores a generic pointer to an actual ComponentStorage implementation
pub const ComponentStorageTypeErased = struct {
    ptr: *anyopaque,
    typename: []const u8,
    tick: *const fn (self: *ComponentStorageTypeErased, delta: f32) void,

    pub fn getStorage(self: *ComponentStorageTypeErased, comptime StorageType: type) *StorageType {
        const ptr: *StorageType = @ptrCast(@alignCast(self.ptr));
        return ptr;
    }
};

pub fn ComponentStorage(comptime ComponentType: type) type {
    const StorageEntry = struct {
        val: ?ComponentType,
        id: u32,
    };

    const storage_type = std.SegmentedList(StorageEntry, 64);

    const Iterator = struct {
        base_iterator: storage_type.Iterator,

        pub fn next(it: *@This()) ?*ComponentType {
            // find the next non-null entry
            while (it.base_iterator.next()) |entry| {
                if (entry.val != null)
                    return &entry.val.?;
            }
            return null;
        }
    };

    return struct {
        data: storage_type,
        allocator: Allocator,

        const Self = @This();

        pub fn init(allocator: Allocator) !*Self {
            const new_storage = try allocator.create(Self);
            new_storage.* = .{
                .data = .{},
                .allocator = allocator,
            };

            return new_storage;
        }

        pub fn deinit(storage: *Self) void {
            storage.allocator.free(storage.data);
            storage.allocator.destroy(storage);
        }

        pub fn iterator(storage: *Self) Iterator {
            return .{
                .base_iterator = storage.data.iterator(0),
            };
        }

        pub fn getFreeEntry(storage: *Self) !*StorageEntry {
            // find the next non-null entry
            var it = storage.data.iterator(0);
            var found_entry: ?*StorageEntry = null;
            while (it.next()) |entry| {
                if (entry.val == null) {
                    found_entry = entry;
                    break;
                }
            }

            // found a free entry, let's use that one!
            if (found_entry) |entry| {
                return entry;
            }

            // no free entry found, make a new one
            const new_component_ptr = try storage.data.addOne(storage.allocator);
            return new_component_ptr;
        }

        pub fn removeEntry(storage: *Self, id: u32) bool {
            // find the asked for component
            var it = storage.data.iterator(0);

            while (it.next()) |entry| {
                if (entry.id == id) {
                    // clear out the found entry!
                    entry.val = null;
                    entry.id = 0;
                    return true;
                }
            }

            return false;
        }
    };
}

// EntityComponent creation options
pub const ComponentConfig = struct {
    persists: bool = true,
    replicated: bool = true,
};

// Basic entity component, logic only
pub const EntityComponent = struct {
    id: ComponentId,
    impl_ptr: *anyopaque, // Pointer to the actual Entity Component struct
    typename: []const u8,
    owner: Entity,
    persists: bool = true, // whether to keep this in saves
    replicated: bool = true, // whether to replicate this component in multiplayer

    // entity component interface methods
    _comp_interface_init: *const fn (self: *EntityComponent) void,
    _comp_interface_tick: *const fn (self: *EntityComponent, delta: f32) void,
    _comp_interface_deinit: *const fn (self: *EntityComponent) void,

    pub fn init(self: *EntityComponent) void {
        self._comp_interface_init(self);
    }

    pub fn tick(self: *EntityComponent, owner: Entity, delta: f32) void {
        _ = owner;
        self._comp_interface_tick(self, delta);
    }

    pub fn deinit(self: *EntityComponent) void {
        self._comp_interface_deinit(self);
    }

    pub fn createComponent(comptime ComponentType: type, owner: Entity, props: ComponentType, cfg: ComponentConfig) !EntityComponent {
        const world = getWorld(owner.id.world_id).?;
        const storage = try world.components.getStorageForType(ComponentType);

        defer world.next_component_id += 1;
        const id: ComponentId = .{ .entity_id = owner.id, .id = world.next_component_id };

        const new_component_ptr = try storage.getFreeEntry();
        new_component_ptr.val = props;
        new_component_ptr.id = id.id;

        delve.debug.info("Creating component {s} under entity id {d}", .{ @typeName(ComponentType), owner.id.id });

        return EntityComponent{
            .id = id,
            .impl_ptr = &new_component_ptr.val.?,
            .typename = @typeName(ComponentType),
            .owner = owner,
            .persists = cfg.persists,
            .replicated = cfg.replicated,
            ._comp_interface_init = (struct {
                pub fn init(self: *EntityComponent) void {
                    var ptr: *ComponentType = @ptrCast(@alignCast(self.impl_ptr));
                    ptr.init(self.*);
                }
            }).init,
            ._comp_interface_tick = (struct {
                pub fn tick(self: *EntityComponent, in_delta: f32) void {
                    var ptr: *ComponentType = @ptrCast(@alignCast(self.impl_ptr));
                    ptr.tick(in_delta);
                }
            }).tick,
            ._comp_interface_deinit = (struct {
                pub fn deinit(self: *EntityComponent) void {
                    var ptr: *ComponentType = @ptrCast(@alignCast(self.impl_ptr));
                    ptr.deinit();

                    // also remove this from our component storage list
                    const cur_world = getWorld(self.owner.id.world_id).?;
                    const cur_storage = cur_world.components.getStorageForType(ComponentType) catch {
                        return;
                    };
                    if (!cur_storage.removeEntry(self.id.id)) {
                        delve.debug.log("Could not find component {d} to remove from storage!", .{self.id.id});
                    }
                }
            }).deinit,
        };
    }

    pub fn cast(self: *EntityComponent, comptime ComponentType: type) ?*ComponentType {
        const ptr: *ComponentType = @ptrCast(@alignCast(self.ptr));
        if (std.mem.eql(u8, self.typename, @typeName(ComponentType))) {
            return ptr;
        }
        return null;
    }
};

pub const EntityComponentIterator = struct {
    list: []EntityComponent,
    component_typename: []const u8,

    index: usize = 0,

    pub fn next(self: *EntityComponentIterator) ?*EntityComponent {
        // search for the next component of this type
        while (self.index < self.list.len) {
            defer self.index += 1;
            if (std.mem.eql(u8, self.component_typename, self.list[self.index].typename)) {
                return &self.list[self.index];
            }
        }

        return null;
    }
};

pub const World = struct {
    allocator: Allocator,
    id: u8,
    name: []const u8,
    entities: std.AutoHashMap(EntityId, Entity),
    entity_components: std.AutoHashMap(EntityId, std.ArrayList(EntityComponent)),
    components: ComponentArchetypeStorage,
    time: f64 = 0.0,

    // worlds also keep track of their own ID space for entities and components
    next_entity_id: u24 = 1, // 0 is saved for invalid
    next_component_id: u32 = 1, // 0 is saved for invalid

    var next_world_id: u8 = 0;

    /// Creates a new world for entities
    pub fn init(name: []const u8, allocator: Allocator) *World {
        defer next_world_id += 1;

        const world_idx: usize = @intCast(next_world_id);

        worlds[world_idx] = .{
            .allocator = allocator,
            .id = next_world_id,
            .name = name,
            .entities = std.AutoHashMap(EntityId, Entity).init(allocator),
            .entity_components = std.AutoHashMap(EntityId, std.ArrayList(EntityComponent)).init(allocator),
            .components = ComponentArchetypeStorage.init(allocator),
        };

        return &worlds[world_idx].?;
    }

    /// Ticks the world
    pub fn tick(self: *World, delta: f32) void {
        self.time += @floatCast(delta);

        // now tick all components!
        // components are stored in a list per-type
        var comp_it = self.components.archetypes.valueIterator();
        while (comp_it.next()) |v| {
            v.tick(v, delta);
        }
    }

    /// Tears down the world's entities
    pub fn deinit(self: *World) void {
        _ = self;
        // var it = self.entities.iterator(0);
        // while (it.next()) |e| {
        //     e.deinit();
        // }
        // self.entities.deinit(self.allocator);
    }

    /// Returns a new entity, which is added to the world's entities list
    pub fn createEntity(self: *World, cfg: EntityConfig) !Entity {
        const new_entity = Entity.init(self, cfg);
        try self.entities.put(new_entity.id, new_entity);
        return new_entity;
    }

    pub fn getEntity(self: *World, entity_id: EntityId) ?Entity {
        const entity_opt = self.entities.getPtr(entity_id);
        if (entity_opt) |e| {
            return e.*;
        }
        return null;
    }
};

pub const InvalidEntity: Entity = .{ .id = .{
    .id = 0,
    .world_id = 0,
} };

pub const EntityConfig = struct {
    persists: bool = true, // whether to keep this entity in saves
    replicated: bool = true, // whether to replicate this entity in multiplayer
};

pub const Entity = struct {
    id: EntityId,
    config: EntityConfig = .{},

    pub fn init(world: *World, cfg: EntityConfig) Entity {
        defer world.next_entity_id += 1;
        return Entity{
            .id = .{ .id = world.next_entity_id, .world_id = world.id },
            .config = cfg,
        };
    }

    pub fn deinit(self: Entity) void {
        const world = getWorld(self.id.world_id).?;
        const entity_components_opt = world.entity_components.getPtr(self.id);

        if (entity_components_opt) |components| {
            // deinit all the components
            for (components.items) |*c| {
                c.deinit();
            }

            // now clear our components array
            components.deinit();
        }

        // can remove our entity components and ourself from the world lists
        _ = world.entity_components.remove(self.id);
        _ = world.entities.remove(self.id);
    }

    pub fn createNewComponent(self: Entity, comptime ComponentType: type, props: ComponentType, cfg: ComponentConfig) !*ComponentType {
        const world = getWorld(self.id.world_id).?;
        const component = try EntityComponent.createComponent(ComponentType, self, props, cfg);

        // init new component
        const comp_ptr: *ComponentType = @ptrCast(@alignCast(component.impl_ptr));

        // first, get or create our entity component list
        const v = try world.entity_components.getOrPut(component.id.entity_id);
        if (!v.found_existing) {
            v.value_ptr.* = std.ArrayList(EntityComponent).init(world.allocator);
        }

        // now, put our entity component into the list
        try v.value_ptr.append(component);

        // Now init the type-erased component that is in the entities components list
        const component_interface_ptr = &v.value_ptr.items[v.value_ptr.items.len - 1];
        component_interface_ptr.init();

        delve.debug.info("Added component {d} of type {s} to entity {d}", .{ component.id.id, @typeName(ComponentType), self.id.id });

        return comp_ptr;
    }

    pub fn getComponent(self: Entity, comptime ComponentType: type) ?*ComponentType {
        const world = getWorld(self.id.world_id).?;
        const components_opt = world.entity_components.getPtr(self.id);
        const check_typename = @typeName(ComponentType);

        if (components_opt) |components| {
            for (components.items) |*c| {
                if (std.mem.eql(u8, check_typename, c.typename)) {
                    const ptr: *ComponentType = @ptrCast(@alignCast(c.impl_ptr));
                    return ptr;
                }
            }
        }

        return null;
    }

    pub fn getComponentById(self: Entity, comptime ComponentType: type, id: ComponentId) ?*ComponentType {
        const world = getWorld(self.id.world_id).?;
        const components_opt = world.entity_components.getPtr(self.id);
        const check_typename = @typeName(ComponentType);

        if (components_opt) |components| {
            for (components.items) |*c| {
                if (id.equals(c.id) and std.mem.eql(u8, check_typename, c.typename)) {
                    const ptr: *ComponentType = @ptrCast(@alignCast(c.impl_ptr));
                    return ptr;
                }
            }
        }

        return null;
    }

    pub fn getComponents(self: Entity, comptime ComponentType: type) EntityComponentIterator {
        const world = getWorld(self.id.world_id).?;
        const components_opt = world.entity_components.getPtr(self.id);
        const check_typename = @typeName(ComponentType);

        if (components_opt) |components| {
            return .{
                .component_typename = check_typename,
                .list = components.items,
            };
        }

        delve.debug.log("No components list for entity {d}!", .{self.id.id});

        return .{
            .component_typename = check_typename,
            .list = []EntityComponent{},
        };
    }

    pub fn getPosition(self: Entity) delve.math.Vec3 {
        // Entities only have a position via the TransformComponent
        const transform_opt = self.getComponent(basics.TransformComponent);
        if (transform_opt) |t| {
            return t.position;
        }

        return delve.math.Vec3.zero;
    }

    pub fn setPosition(self: Entity, position: delve.math.Vec3) void {
        // Entities only have a position via the TransformComponent
        const transform_opt = self.getComponent(basics.TransformComponent);
        if (transform_opt) |t| {
            t.position = position;
        } else {
            delve.debug.info("Can't set position when there is no TransformComponent!", .{});
        }
    }

    pub fn getRotation(self: Entity) delve.math.Quaternion {
        // Entities only have a rotation via the TransformComponent
        const transform_opt = self.getComponent(basics.TransformComponent);
        if (transform_opt) |t| {
            return t.rotation;
        }

        return delve.math.Quaternion.identity;
    }

    pub fn setRotation(self: Entity, rotation: delve.math.Quaternion) void {
        // Entities only have a rotation via the TransformComponent
        const transform_opt = self.getComponent(basics.TransformComponent);
        if (transform_opt) |t| {
            t.rotation = rotation;
        } else {
            delve.debug.info("Can't set rotation when there is no TransformComponent!", .{});
        }
    }

    pub fn getVelocity(self: Entity) delve.math.Vec3 {
        // Entities only have a position via the TransformComponent
        const transform_opt = self.getComponent(basics.TransformComponent);
        if (transform_opt) |t| {
            return t.velocity;
        }

        delve.debug.log("Can't get position when there is no TransformComponent!", .{});
        return delve.math.Vec3.zero;
    }

    pub fn setVelocity(self: Entity, velocity: delve.math.Vec3) void {
        // Entities only have a position via the TransformComponent
        const transform_opt = self.getComponent(basics.TransformComponent);
        if (transform_opt) |t| {
            t.velocity = velocity;
        } else {
            delve.debug.log("Can't set position when there is no TransformComponent!", .{});
        }
    }

    pub fn getWorldId(self: *Entity) u8 {
        return self.id.world_id;
    }

    pub fn isAlive(self: *Entity) bool {
        const world = getWorld(self.id.world_id).?;
        return self.isValid() and world.entities.contains(self.id.id);
    }

    pub fn isValid(self: *Entity) bool {
        return self.id != 0;
    }
};

/// Global function to get a World by ID
pub fn getWorld(world_id: u8) ?*World {
    if (worlds[@intCast(world_id)]) |*world| {
        return world;
    }
    return null;
}

/// Global function to get an Entity by ID
pub fn getEntity(world_id: u8, entity_id: u24) ?Entity {
    if (getWorld(world_id)) |world| {
        return world.getEntity(entity_id);
    }
}

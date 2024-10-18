const std = @import("std");
const delve = @import("delve");
const basics = @import("../entities/basics.zig");
const Allocator = std.mem.Allocator;

const Vec3 = delve.math.Vec3;
const BoundingBox = delve.spatial.BoundingBox;

pub const EntityId = packed struct {
    id: u24,
    world_id: u8,
};

pub const ComponentId = packed struct {
    id: u32,
    entity_id: EntityId,
};

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
    const storage_type = std.SegmentedList(ComponentType, 64);
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

        pub fn iterator(storage: *Self) storage_type.Iterator {
            return storage.data.iterator(0);
        }
    };
}

// Basic entity component, logic only
pub const EntityComponent = struct {
    id: ComponentId,
    ptr: *anyopaque,
    allocator: Allocator,
    typename: []const u8,
    owner: Entity,
    is_alive: bool = true,

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

    pub fn createComponent(allocator: Allocator, comptime ComponentType: type, owner: Entity, props: ComponentType) !EntityComponent {
        const world = getWorld(owner.id.world_id).?;
        const storage = try world.components.getStorageForType(ComponentType);

        const new_component_ptr = try storage.data.addOne(storage.allocator);
        new_component_ptr.* = props;

        defer world.next_component_id += 1;

        delve.debug.info("Creating component {s} under entity id {d}", .{ @typeName(ComponentType), owner.id.id });

        return EntityComponent{
            .id = .{ .entity_id = owner.id, .id = world.next_component_id },
            .ptr = new_component_ptr,
            .allocator = allocator,
            .typename = @typeName(ComponentType),
            .owner = owner,
            ._comp_interface_init = (struct {
                pub fn init(self: *EntityComponent) void {
                    var ptr: *ComponentType = @ptrCast(@alignCast(self.ptr));
                    ptr.init(self.*);
                }
            }).init,
            ._comp_interface_tick = (struct {
                pub fn tick(self: *EntityComponent, in_delta: f32) void {
                    delve.debug.log("Ticking component on entity {d}", .{self.id.entity_id.id});
                    var ptr: *ComponentType = @ptrCast(@alignCast(self.ptr));
                    ptr.tick(in_delta);
                }
            }).tick,
            ._comp_interface_deinit = (struct {
                pub fn deinit(self: *EntityComponent) void {
                    var ptr: *ComponentType = @ptrCast(@alignCast(self.ptr));
                    ptr.deinit();
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

var worlds: [255]?World = [_]?World{null} ** 255;

pub fn getWorld(world_id: u8) ?*World {
    if (worlds[@intCast(world_id)]) |*world| {
        return world;
    }
    return null;
}

pub fn getEntity(world_id: u8, entity_id: u24) ?Entity {
    if (getWorld(world_id)) |world| {
        return world.getEntity(entity_id);
    }
}

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
    pub fn createEntity(self: *World) !Entity {
        const new_entity = Entity.init(self);
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

pub const Entity = struct {
    id: EntityId,

    pub fn init(world: *World) Entity {
        defer world.next_entity_id += 1;
        return Entity{
            .id = .{ .id = world.next_entity_id, .world_id = world.id },
        };
    }

    pub fn deinit(self: *Entity) void {
        const world = getWorld(self.id.world_id).?;
        const entity_components_opt = try world.entity_components.getPtr(self.id.id);

        if (entity_components_opt) |components| {
            // deinit all the components
            for (components.items) |*c| {
                c.deinit();
            }

            // now clear our components array
            components.freeAndClear();
        }

        // can remove our entity components and ourself from the world lists
        world.entity_components.remove(self.id.id);
        world.entities.remove(self.id.id);
    }

    pub fn createNewComponent(self: *Entity, comptime ComponentType: type, props: ComponentType) !*ComponentType {
        const world = getWorld(self.id.world_id).?;
        const component = try EntityComponent.createComponent(world.allocator, ComponentType, self.*, props);

        // init new component
        const comp_ptr: *ComponentType = @ptrCast(@alignCast(component.ptr));

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

    pub fn getComponent(self: *Entity, comptime ComponentType: type) ?*ComponentType {
        const world = getWorld(self.id.world_id).?;
        const components_opt = world.entity_components.getPtr(self.id);
        const check_typename = @typeName(ComponentType);

        if (components_opt) |components| {
            for (components.items) |*c| {
                if (std.mem.eql(u8, check_typename, c.typename)) {
                    const ptr: *ComponentType = @ptrCast(@alignCast(c.ptr));
                    return ptr;
                }
            }
        }

        return null;
    }

    pub fn getComponents(self: *Entity, comptime ComponentType: type) EntityComponentIterator {
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

    pub fn getPosition(self: *Entity) delve.math.Vec3 {
        // Entities only have a position via the TransformComponent
        const transform_opt = self.getComponent(basics.TransformComponent);
        if (transform_opt) |t| {
            return t.position;
        }

        return delve.math.Vec3.zero;
    }

    pub fn setPosition(self: *Entity, position: delve.math.Vec3) void {
        // Entities only have a position via the TransformComponent
        const transform_opt = self.getComponent(basics.TransformComponent);
        if (transform_opt) |t| {
            t.position = position;
        } else {
            delve.debug.info("Can't set position when there is no TransformComponent!", .{});
        }
    }

    pub fn getWorldId(self: *Entity) u8 {
        return self.id.world_id;
    }

    pub fn isAlive(self: *Entity) bool {
        const world = getWorld(self.id.world_id).?;
        return world.entities.contains(self.id.id);
    }
};

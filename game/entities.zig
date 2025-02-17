const std = @import("std");
const delve = @import("delve");
const basics = @import("../entities/basics.zig");
const movers = @import("../entities/mover.zig");
const characters = @import("../entities/character.zig");
const string = @import("../utils/string.zig");
const component_serializer = @import("../utils/component_serializer.zig");

const Allocator = std.mem.Allocator;

const Vec3 = delve.math.Vec3;
const BoundingBox = delve.spatial.BoundingBox;

pub const EntityId = packed struct(u32) {
    id: u24,
    world_id: u8,

    pub fn equals(self: EntityId, other: EntityId) bool {
        return self.id == other.id and self.world_id == other.world_id;
    }

    pub fn toInt(self: *const EntityId) u32 {
        const as_int: *u32 = @ptrCast(@constCast(self));
        return as_int.*;
    }

    pub fn fromInt(in_id: u32) EntityId {
        const as_id: *EntityId = @ptrCast(@constCast(&in_id));
        return as_id.*;
    }

    pub fn jsonStringify(self: *const EntityId, out: anytype) !void {
        try out.write(self.toInt());
    }

    pub fn jsonParse(allocator: Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
        const id_int = try std.json.innerParse(u32, allocator, source, options);
        return fromInt(id_int);
    }

    pub fn toOwnedString(self: *const EntityId, allocator: Allocator) []const u8 {
        return std.fmt.allocPrint(allocator, "{s}", .{self.toInt()}) catch unreachable;
    }

    comptime {
        std.debug.assert(@sizeOf(@This()) == @sizeOf(u32));
        std.debug.assert(@bitSizeOf(@This()) == @bitSizeOf(u32));
    }
};

pub const ComponentId = packed struct(u64) {
    id: u32,
    entity_id: EntityId,

    pub fn equals(self: ComponentId, other: ComponentId) bool {
        return self.id == other.id and self.entity_id.equals(other.entity_id);
    }

    pub fn toInt(self: *const ComponentId) u32 {
        const as_int: *u32 = @ptrCast(@constCast(self));
        return as_int.*;
    }

    pub fn jsonStringify(self: *const ComponentId, out: anytype) !void {
        try out.write(self.toInt());
    }

    comptime {
        std.debug.assert(@sizeOf(@This()) == @sizeOf(u64));
        std.debug.assert(@bitSizeOf(@This()) == @bitSizeOf(u64));
    }
};

/// Our global list of worlds
var worlds: [255]?World = [_]?World{null} ** 255;

/// Stores lists of components, by type
pub const ComponentArchetypeStorage = struct {
    archetypes: std.StringArrayHashMap(ComponentStorageTypeErased),
    allocator: Allocator,
    is_iterator_valid: bool = true,

    pub fn init(allocator: Allocator) ComponentArchetypeStorage {
        return .{
            .allocator = allocator,
            .archetypes = std.StringArrayHashMap(ComponentStorageTypeErased).init(allocator),
        };
    }

    pub fn deinit(self: *ComponentArchetypeStorage) void {
        delve.debug.log("ComponentArchetypeStorage deinit!", .{});
        var it = self.archetypes.iterator();
        while (it.next()) |a| {
            // delve.debug.log("  deiniting {s} storage", .{a.key_ptr.*});
            a.value_ptr.deinit(a.value_ptr);
        }
        self.archetypes.deinit();
    }

    pub fn getStorageForType(self: *ComponentArchetypeStorage, comptime ComponentType: type) !*ComponentStorage(ComponentType) {
        const typename = @typeName(ComponentType);
        if (self.archetypes.getPtr(typename)) |storage| {
            return storage.getStorage(ComponentStorage(ComponentType)); // convert from type erased
        }

        delve.debug.info("Creating storage for component archetype: {s}", .{@typeName(ComponentType)});
        self.is_iterator_valid = false;

        try self.archetypes.put(typename, .{
            .typename = @typeName(ComponentType),
            .typename_hash = string.hashString(@typeName(ComponentType)),
            .ptr = try ComponentStorage(ComponentType).init(self.allocator),
            .tick = (struct {
                pub fn tick(in_self: *ComponentStorageTypeErased, delta: f32) void {
                    var storage = in_self.getStorage(ComponentStorage(ComponentType)); // convert from type erased
                    var it = storage.iterator(); // convert from type erased
                    if (std.meta.hasFn(ComponentType, "tick")) {
                        while (it.next()) |c| {
                            c.tick(delta);
                        }
                    }
                }
            }).tick,
            .physics_tick = (struct {
                pub fn physics_tick(in_self: *ComponentStorageTypeErased, delta: f32) void {
                    var it = in_self.getStorage(ComponentStorage(ComponentType)).iterator(); // convert from type erased
                    if (std.meta.hasFn(ComponentType, "physics_tick")) {
                        while (it.next()) |c| {
                            c.physics_tick(delta);
                        }
                    }
                }
            }).physics_tick,
            .deinit = (struct {
                pub fn deinit(in_self: *ComponentStorageTypeErased) void {
                    delve.debug.info("Clearing components for {s}", .{typename});
                    var it = in_self.getStorage(ComponentStorage(ComponentType)).iterator(); // convert from type erased
                    while (it.next()) |c| {
                        c.deinit();
                    }
                    in_self.getStorage(ComponentStorage(ComponentType)).deinit(); // convert from type erased
                }
            }).deinit,
        });

        const added = self.archetypes.getPtr(typename);
        if (added == null) {
            delve.debug.log("Could not find storage for archetype! {s}", .{@typeName(ComponentType)});
        }

        return added.?.getStorage(ComponentStorage(ComponentType)); // convert from type erased
    }
};

/// Stores a generic pointer to an actual ComponentStorage implementation
pub const ComponentStorageTypeErased = struct {
    ptr: *anyopaque,
    typename: []const u8,
    typename_hash: u32,
    tick: *const fn (self: *ComponentStorageTypeErased, delta: f32) void,
    physics_tick: *const fn (self: *ComponentStorageTypeErased, delta: f32) void,
    deinit: *const fn (self: *ComponentStorageTypeErased) void,

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
            storage.data.deinit(storage.allocator);
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

pub const EntityComponentConfig = struct {
    persists: bool = true, // whether to keep this component in saves
    replicated: bool = true, // whether to replicate this component in multiplayer
};

// Basic entity component, logic only
pub const EntityComponent = struct {
    id: ComponentId,
    impl_ptr: *anyopaque, // Pointer to the actual Entity Component struct
    typename: []const u8,
    typename_hash: u32,
    owner: Entity,

    // entity component config settings
    config: EntityComponentConfig = .{},

    // entity component interface methods
    _comp_interface_init: *const fn (self: *EntityComponent) void,
    _comp_interface_post_load: *const fn (self: *EntityComponent) void,
    _comp_interface_tick: *const fn (self: *EntityComponent, delta: f32) void,
    _comp_interface_physics_tick: *const fn (self: *EntityComponent, delta: f32) void,
    _comp_interface_deinit: *const fn (self: *EntityComponent) void,

    pub fn init(self: *EntityComponent) void {
        self._comp_interface_init(self);
    }

    pub fn post_load(self: *EntityComponent) void {
        self._comp_interface_post_load(self);
    }

    pub fn tick(self: *EntityComponent, owner: Entity, delta: f32) void {
        _ = owner;
        self._comp_interface_tick(self, delta);
    }

    pub fn physics_tick(self: *EntityComponent, owner: Entity, delta: f32) void {
        _ = owner;
        self._comp_interface_phsyics_tick(self, delta);
    }

    pub fn deinit(self: *EntityComponent) void {
        self._comp_interface_deinit(self);
    }

    pub fn createComponent(comptime ComponentType: type, owner: Entity, props: ComponentType, config: EntityComponentConfig) !EntityComponent {
        const world = getWorld(owner.id.world_id).?;
        const storage = try world.components.getStorageForType(ComponentType);

        defer world.next_component_id += 1;
        const id: ComponentId = .{ .entity_id = owner.id, .id = world.next_component_id };

        const new_component_ptr = try storage.getFreeEntry();
        new_component_ptr.val = props;
        new_component_ptr.id = id.id;

        // delve.debug.info("Creating component {s} under entity id {d}", .{ @typeName(ComponentType), owner.id.id });

        return EntityComponent{
            .id = id,
            .impl_ptr = &new_component_ptr.val.?,
            .typename = @typeName(ComponentType),
            .typename_hash = string.hashString(@typeName(ComponentType)),
            .owner = owner,
            .config = config,
            ._comp_interface_init = (struct {
                pub fn init(self: *EntityComponent) void {
                    var ptr: *ComponentType = @ptrCast(@alignCast(self.impl_ptr));
                    ptr.init(self.*);
                }
            }).init,
            ._comp_interface_post_load = (struct {
                pub fn post_load(self: *EntityComponent) void {
                    if (std.meta.hasFn(ComponentType, "post_load")) {
                        var ptr: *ComponentType = @ptrCast(@alignCast(self.impl_ptr));
                        ptr.post_load();
                    }
                }
            }).post_load,
            ._comp_interface_tick = (struct {
                pub fn tick(self: *EntityComponent, in_delta: f32) void {
                    if (std.meta.hasFn(ComponentType, "tick")) {
                        var ptr: *ComponentType = @ptrCast(@alignCast(self.impl_ptr));
                        ptr.tick(in_delta);
                    }
                }
            }).tick,
            ._comp_interface_physics_tick = (struct {
                pub fn physics_tick(self: *EntityComponent, in_delta: f32) void {
                    if (std.meta.hasFn(ComponentType, "physics_tick")) {
                        var ptr: *ComponentType = @ptrCast(@alignCast(self.impl_ptr));
                        ptr.physics_tick(in_delta);
                    }
                }
            }).physics_tick,
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

                    // remove the component from the entity's component list if it's still there
                    const components_opt = cur_world.entity_components.getPtr(self.id.entity_id);
                    if (components_opt) |components| {
                        for (components.items, 0..) |*c, idx| {
                            if (c.id.equals(self.id)) {
                                _ = components.swapRemove(idx);
                                break;
                            }
                        }
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

    pub fn jsonStringify(self: *const EntityComponent, out: anytype) !void {
        try component_serializer.writeComponent(self, out);
    }

    pub var entity_being_read: Entity = undefined;
    pub fn jsonParse(allocator: Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
        const start_token = try source.next();
        if (.object_begin != start_token) {
            delve.debug.log("Expected to find an object begin token! {any}", .{start_token});
            return error.UnexpectedToken;
        }

        const typename_token = try source.next();
        switch (typename_token) {
            .string, .allocated_string => |k| {
                if (!std.mem.eql(u8, k, "typename")) {
                    delve.debug.log("Expected to find a 'typename' token! {any}", .{typename_token});
                    return error.UnexpectedToken;
                }
            },
            else => {},
        }

        var typename: []const u8 = undefined;
        const token = try source.next();
        switch (token) {
            .string, .allocated_string => |k| {
                typename = k;
            },
            else => {},
        }

        const state_token = try source.next();
        switch (state_token) {
            .string, .allocated_string => |k| {
                if (!std.mem.eql(u8, k, "state")) {
                    delve.debug.log("Expected to find a 'state' token! {any}", .{state_token});
                    return error.UnexpectedToken;
                }
            },
            else => {},
        }

        const read_comp = try component_serializer.readComponent(typename, allocator, source, options, entity_being_read);

        const end_token = try source.next();
        if (.object_end != end_token) {
            delve.debug.log("Expected object end token after component! {any}", .{end_token});
            return error.UnexpectedToken;
        }

        return read_comp;
    }
};

pub const EntityComponentIterator = struct {
    list: []EntityComponent,
    component_typename_hash: u32 = 0,

    index: usize = 0,

    pub fn next(self: *EntityComponentIterator) ?*EntityComponent {
        // search for the next component of this type
        while (self.index < self.list.len) {
            defer self.index += 1;

            // easy case, no filter
            if (self.component_typename_hash == 0)
                return &self.list[self.index];

            // harder case, check if we match
            if (self.component_typename_hash == self.list[self.index].typename_hash) {
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

    // also keep a list of names to entities
    named_entities: std.StringHashMap(std.ArrayList(EntityId)),

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
            .named_entities = std.StringHashMap(std.ArrayList(EntityId)).init(allocator),
        };

        const world = &worlds[world_idx].?;

        // Ensure Movers tick first
        // TODO: Need some kind of component priority!
        _ = if (world.components.getStorageForType(characters.CharacterMovementComponent)) |_| {} else |_| {};
        _ = if (world.components.getStorageForType(movers.MoverComponent)) |_| {} else |_| {};
        _ = if (world.components.getStorageForType(basics.AttachmentComponent)) |_| {} else |_| {};

        return world;
    }

    /// Ticks the world
    pub fn tick(self: *World, delta: f32) void {
        self.time += @floatCast(delta);

        // now tick all components!
        // components are stored in a list per-type
        var arch_it = self.components.archetypes.iterator();
        self.components.is_iterator_valid = true;

        while (arch_it.next()) |i| {
            if (!self.components.is_iterator_valid) {
                delve.debug.info("Resetting component iterator!", .{});

                const idx = arch_it.index;
                arch_it = self.components.archetypes.iterator();
                arch_it.index = idx - 1; // put us back to this index again

                self.components.is_iterator_valid = true;
                continue;
            }

            var val = i.value_ptr;
            val.tick(val, delta);
        }
    }

    pub fn physics_tick(self: *World, delta: f32) void {
        // tick all components for physics!
        // components are stored in a list per-type
        var arch_it = self.components.archetypes.iterator();
        self.components.is_iterator_valid = true;

        while (arch_it.next()) |i| {
            if (!self.components.is_iterator_valid) {
                delve.debug.info("Resetting component iterator!", .{});

                const idx = arch_it.index;
                arch_it = self.components.archetypes.iterator();
                arch_it.index = idx - 1; // put us back to this index again

                self.components.is_iterator_valid = true;
                continue;
            }

            var val = i.value_ptr;
            val.physics_tick(val, delta);
        }
    }

    /// Tears down the world's entities
    pub fn deinit(self: *World) void {
        delve.debug.log("World tearing down", .{});
        const allocator = delve.mem.getAllocator();

        delve.debug.log("  Deinitializing entities", .{});
        var e_it = self.entities.valueIterator();
        while (e_it.next()) |e| {
            // delve.debug.log("   deinit entity {any}", .{e.id});
            e.deinit();
        }
        self.entities.deinit();

        delve.debug.log("  Deinitializing named entities", .{});
        var ne_it = self.named_entities.iterator();
        while (ne_it.next()) |e| {
            e.value_ptr.deinit();
            allocator.free(e.key_ptr.*);
        }
        self.named_entities.deinit();

        delve.debug.log("  Clearing component storage", .{});
        // clear component archetypes
        self.components.deinit();

        delve.debug.log("  Clearing entity components", .{});
        // should be empty by now
        var ec_it = self.entity_components.iterator();
        while (ec_it.next()) |ec| {
            delve.debug.warning("Leaked entity {any} on deinit", .{ec.key_ptr.*});
            ec.value_ptr.*.deinit();
        }
        self.entity_components.deinit();
    }

    /// Returns a new entity, which is added to the world's entities list
    pub fn createEntity(self: *World, cfg: EntityConfig) !Entity {
        const new_entity = Entity.init(self, cfg);
        try self.entities.put(new_entity.id, new_entity);
        return new_entity;
    }

    /// Searches for an entity by EntityId
    pub fn getEntity(self: *World, entity_id: EntityId) ?Entity {
        const entity_opt = self.entities.getPtr(entity_id);
        if (entity_opt) |e| {
            return e.*;
        }
        return null;
    }

    pub fn clearEntities(self: *World) void {
        delve.debug.log("Clearing entities in world", .{});
        var e_it = self.entities.valueIterator();
        while (e_it.next()) |e| {
            e.deinit();
        }
        self.entities.clearRetainingCapacity();
    }

    /// Searches for an entity by a name
    pub fn getEntityByName(self: *World, name: []const u8) ?Entity {
        if (self.named_entities.get(name)) |found_entities| {
            if (found_entities.items.len > 0)
                return self.getEntity(found_entities.items[0]);
        }
        return null;
    }

    /// Searches for entities by a name
    pub fn getEntitiesByName(self: *World, name: []const u8) ?std.ArrayList(EntityId) {
        if (self.named_entities.get(name)) |found_entities| {
            return found_entities;
        }
        delve.debug.log("Could not find any entities by name for '{s}'", .{name});
        return null;
    }

    pub fn jsonStringify(self: *const World, out: anytype) !void {
        try out.beginObject();

        // world ID
        try out.objectField("id");
        try out.write(self.id);

        // entities
        try out.objectField("entities");
        try out.beginArray();

        var it = self.entities.iterator();
        while (it.next()) |*e| {
            try out.write(e.value_ptr);
        }

        try out.endArray();
        try out.endObject();
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

    pub fn post_load(self: Entity) void {
        const entity_id = self.id;

        const world = getWorld(entity_id.world_id).?;
        const entity_components_opt = world.entity_components.getPtr(entity_id);

        if (entity_components_opt) |components| {
            for (components.items) |*c| {
                c.post_load();
            }
        }
    }

    pub fn deinit(self: Entity) void {
        const entity_id = self.id;

        const world = getWorld(entity_id.world_id).?;
        const entity_components_opt = world.entity_components.getPtr(entity_id);

        // delve.debug.log("Removing entity {any}", .{entity_id});

        if (entity_components_opt) |components| {
            // deinit all the components
            for (components.items) |*c| {
                c.deinit();
            }

            // now clear our components array
            components.deinit();
        }

        // can remove our entity components and ourself from the world lists
        const removed_entity = world.entities.remove(entity_id);
        const removed_comps = world.entity_components.remove(entity_id);

        if (!removed_entity) delve.debug.warning("Could not find entity to remove during entity deinit! {any}", .{entity_id});
        if (!removed_comps) delve.debug.warning("Could not find component list to remove during entity deinit! {any}", .{entity_id});
    }

    pub fn createNewComponent(self: Entity, comptime ComponentType: type, props: ComponentType) !*ComponentType {
        const component = try self.attachNewComponent(ComponentType, .{}, props);
        const comp_ptr: *ComponentType = @ptrCast(@alignCast(component.impl_ptr));
        return comp_ptr;
    }

    pub fn createNewComponentWithConfig(self: Entity, comptime ComponentType: type, config: EntityComponentConfig, props: ComponentType) !*ComponentType {
        const component = try self.attachNewComponent(ComponentType, config, props);
        const comp_ptr: *ComponentType = @ptrCast(@alignCast(component.impl_ptr));
        return comp_ptr;
    }

    /// Creates a new component, returning the EntityComponent
    pub fn attachNewComponent(self: Entity, comptime ComponentType: type, config: EntityComponentConfig, props: ComponentType) !EntityComponent {
        const world = getWorld(self.id.world_id).?;
        const component = try EntityComponent.createComponent(ComponentType, self, props, config);

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

        // delve.debug.log("Attached component {d} of type {s} to entity {d}", .{ component.id.id, @typeName(ComponentType), self.id.id });
        return component;
    }

    pub fn getComponent(self: Entity, comptime ComponentType: type) ?*ComponentType {
        const world = getWorld(self.id.world_id).?;
        const components_opt = world.entity_components.getPtr(self.id);
        const check_typename_hash = string.hashString(@typeName(ComponentType));

        if (components_opt) |components| {
            for (components.items) |*c| {
                if (check_typename_hash == c.typename_hash) {
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
        const check_typename_hash = string.hashString(@typeName(ComponentType));

        if (components_opt) |components| {
            for (components.items) |*c| {
                if (id.equals(c.id) and check_typename_hash == c.typename_hash) {
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
        const check_typename_hash = string.hashString(@typeName(ComponentType));

        if (components_opt) |components| {
            return .{
                .component_typename_hash = check_typename_hash,
                .list = components.items,
            };
        }

        delve.debug.log("No components list for entity {d}!", .{self.id.id});

        return .{
            .component_typename_hash = check_typename_hash,
            .list = &[_]EntityComponent{},
        };
    }

    pub fn getAllComponents(self: Entity) EntityComponentIterator {
        const world = getWorld(self.id.world_id).?;
        const components_opt = world.entity_components.getPtr(self.id);

        if (components_opt) |components| {
            return .{
                .list = components.items,
            };
        }

        delve.debug.log("No components list for entity {d}!", .{self.id.id});

        return .{
            .list = &[_]EntityComponent{},
        };
    }

    pub fn removeComponent(self: Entity, comptime ComponentType: type) bool {
        const world = getWorld(self.id.world_id).?;
        const components_opt = world.entity_components.getPtr(self.id);
        const check_typename_hash = string.hashString(@typeName(ComponentType));

        // Find our component to remove
        var found: ?EntityComponent = null;
        if (components_opt) |components| {
            for (components.items, 0..) |*c, idx| {
                if (check_typename_hash == c.typename_hash) {
                    found = components.items[idx];
                    break;
                }
            }
        }

        if (found == null) {
            delve.debug.warning("Could not find component {any} to remove", .{ComponentType});
            return false;
        }

        found.?.deinit();
        return true;
    }

    pub fn getPosition(self: Entity) delve.math.Vec3 {
        // Entities only have a position via the TransformComponent
        const transform_opt = self.getComponent(basics.TransformComponent);
        if (transform_opt) |t| {
            return t.getPosition();
        }

        return delve.math.Vec3.zero;
    }

    pub fn getRenderPosition(self: Entity) delve.math.Vec3 {
        // Entities only have a position via the TransformComponent
        const transform_opt = self.getComponent(basics.TransformComponent);
        if (transform_opt) |t| {
            return t.getRenderPosition();
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
        return self.id.id != 0;
    }

    pub fn jsonStringify(self: *const Entity, out: anytype) !void {
        // Skip persisting entities that should not
        if (!self.config.persists)
            return;

        var components_it = self.getAllComponents();

        try out.beginObject();

        // write id
        try out.objectField("id");
        try out.write(self.id);

        // write components
        try out.objectField("components");
        try out.beginArray();

        while (components_it.next()) |c| {
            try out.write(c);
        }

        try out.endArray();
        try out.endObject();
    }

    pub fn getOwningWorld(self: *const Entity) ?*World {
        return getWorld(self.id.world_id).?;
    }
};

/// Global function to get a World by ID
pub fn getWorld(world_id: u8) ?*World {
    if (worlds[@intCast(world_id)]) |*world| {
        return world;
    }
    delve.debug.warning("Could not find world {any}", .{world_id});
    return null;
}

/// Global function to get an Entity by ID
pub fn getEntity(world_id: u8, entity_id: u24) ?Entity {
    if (getWorld(world_id)) |world| {
        return world.getEntity(entity_id);
    }
}

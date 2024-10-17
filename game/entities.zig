const std = @import("std");
const delve = @import("delve");
const basics = @import("../entities/basics.zig");
const Allocator = std.mem.Allocator;

const Vec3 = delve.math.Vec3;
const BoundingBox = delve.spatial.BoundingBox;

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

    pub fn getStorageForType(self: *ComponentArchetypeStorage, comptime ComponentType: type) !*ComponentStorageTypeErased {
        const typename = @typeName(ComponentType);
        if (self.archetypes.getPtr(typename)) |storage| {
            return storage;
        }

        delve.debug.log("Creating storage for component archetype: {s}", .{@typeName(ComponentType)});
        try self.archetypes.put(typename, .{
            .typename = @typeName(ComponentType),
            .ptr = try ComponentStorage(ComponentType).init(self.allocator),
        });

        const added = self.archetypes.getPtr(typename);
        return added.?;
    }
};

/// Stores a generic pointer to an actual ComponentStorage implementation
pub const ComponentStorageTypeErased = struct {
    ptr: *anyopaque,
    typename: []const u8,

    pub fn getStorage(self: *ComponentStorageTypeErased, comptime ComponentType: type) *ComponentType {
        const ptr: *ComponentType = @ptrCast(@alignCast(self.ptr));
        return ptr;
    }
};

pub fn ComponentStorage(comptime ComponentType: type) type {
    return struct {
        data: std.SegmentedList(ComponentType, 64),
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
    };
}

// Basic entity component, logic only
pub const EntityComponent = struct {
    ptr: *anyopaque,
    allocator: Allocator,
    typename: []const u8,
    owner: *Entity,

    // entity component interface methods
    _comp_interface_init: *const fn (self: *EntityComponent) void,
    _comp_interface_tick: *const fn (self: *EntityComponent, delta: f32) void,
    _comp_interface_deinit: *const fn (self: *EntityComponent) void,

    pub fn init(self: *EntityComponent) void {
        self._comp_interface_init(self);
    }

    pub fn tick(self: *EntityComponent, owner: *Entity, delta: f32) void {
        _ = owner;
        self._comp_interface_tick(self, delta);
    }

    pub fn deinit(self: *EntityComponent) void {
        self._comp_interface_deinit(self);
    }

    pub fn createComponent(allocator: Allocator, comptime ComponentType: type, owner: *Entity, props: ComponentType) !EntityComponent {
        const storage = try owner.world.components.getStorageForType(ComponentType);
        const final_store = storage.getStorage(ComponentStorage(ComponentType));

        const new_component_ptr = try final_store.data.addOne(final_store.allocator);
        new_component_ptr.* = props;

        return EntityComponent{
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

pub const World = struct {
    allocator: Allocator,
    name: []const u8,
    entities: std.SegmentedList(Entity, 256),
    components: ComponentArchetypeStorage,
    time: f64 = 0.0,

    /// Creates a new world for entities
    pub fn init(name: []const u8, allocator: Allocator) World {
        return .{
            .allocator = allocator,
            .name = name,
            .entities = .{},
            .components = ComponentArchetypeStorage.init(allocator),
        };
    }

    /// Ticks the world's entities
    pub fn tick(self: *World, delta: f32) void {
        self.time += @floatCast(delta);

        var it = self.entities.iterator(0);
        while (it.next()) |e| {
            e.tick(delta);
        }
    }

    /// Tears down the world's entities
    pub fn deinit(self: *World) void {
        var it = self.entities.iterator(0);
        while (it.next()) |e| {
            e.deinit();
        }
        self.entities.deinit(self.allocator);
    }

    /// Returns a new entity, which is added to the world's entities list
    pub fn createEntity(self: *World) !*Entity {
        const new_entity_ptr = try self.entities.addOne(self.allocator);
        new_entity_ptr.* = Entity.init(self);
        return new_entity_ptr;
    }
};

pub const Entity = struct {
    allocator: Allocator,
    world: *World,
    components: std.ArrayList(EntityComponent), // components that only run logic

    pub fn init(world: *World) Entity {
        return Entity{
            .allocator = world.allocator,
            .world = world,
            .components = std.ArrayList(EntityComponent).init(world.allocator),
        };
    }

    pub fn deinit(self: *Entity) void {
        for (self.components.items) |*c| {
            c.deinit();
        }
        self.components.deinit();
    }

    pub fn createNewComponent(self: *Entity, comptime ComponentType: type, props: ComponentType) !*ComponentType {
        const component = try EntityComponent.createComponent(self.allocator, ComponentType, self, props);

        // init new component
        const comp_ptr: *ComponentType = @ptrCast(@alignCast(component.ptr));

        try self.components.append(component);
        const component_in_list_ptr = &self.components.items[self.components.items.len - 1];

        component_in_list_ptr.init();
        return comp_ptr;
    }

    pub fn getComponent(self: *Entity, comptime ComponentType: type) ?*ComponentType {
        const check_typename = @typeName(ComponentType);
        for (self.components.items) |*c| {
            if (std.mem.eql(u8, check_typename, c.typename)) {
                const ptr: *ComponentType = @ptrCast(@alignCast(c.ptr));
                return ptr;
            }
        }
        return null;
    }

    pub fn getComponents(self: *Entity, comptime ComponentType: type) EntityComponentIterator {
        const check_typename = @typeName(ComponentType);
        return .{
            .component_typename = check_typename,
            .list = self.components.items,
        };
    }

    pub fn tick(self: *Entity, delta: f32) void {
        for (self.components.items) |*c| {
            c.tick(self, delta);
        }
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
            delve.debug.log("Can't set position when there is no TransformComponent!", .{});
        }
    }
};

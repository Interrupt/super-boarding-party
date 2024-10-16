const std = @import("std");
const delve = @import("delve");
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

    // lifecycle entity component methods
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
        const component = try allocator.create(ComponentType);
        component.* = props;

        return EntityComponent{
            .ptr = component,
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

// EntitySceneComponents are entity components that have a visual representation
pub const EntitySceneComponent = struct {
    ptr: *anyopaque,
    allocator: Allocator,
    typename: []const u8,
    owner: *Entity,

    // lifecycle entity component interface methods
    _comp_interface_init: *const fn (self: *EntitySceneComponent) void,
    _comp_interface_tick: *const fn (self: *EntitySceneComponent, delta: f32) void,
    _comp_interface_deinit: *const fn (self: *EntitySceneComponent) void,

    // scene component interface
    _scomp_interface_getPosition: *const fn (self: *EntitySceneComponent) delve.math.Vec3,
    _scomp_interface_getRotation: *const fn (self: *EntitySceneComponent) delve.math.Quaternion,
    _scomp_interface_getBounds: *const fn (self: *EntitySceneComponent) delve.spatial.BoundingBox,

    pub fn init(self: *EntitySceneComponent) void {
        self._comp_interface_init(self);
    }

    pub fn tick(self: *EntitySceneComponent, owner: *Entity, delta: f32) void {
        self.owner = owner; // fixup the owner every tick! could have moved.
        self._comp_interface_tick(self, delta);
    }

    pub fn deinit(self: *EntitySceneComponent) void {
        self._comp_interface_deinit(self);
    }

    pub fn getPosition(self: *EntitySceneComponent) delve.math.Vec3 {
        return self._scomp_interface_getPosition(self);
    }

    pub fn getBounds(self: *EntitySceneComponent) delve.spatial.BoundingBox {
        return self._scomp_interface_getBounds(self);
    }

    pub fn getRotation(self: *EntitySceneComponent) delve.math.Quaternion {
        return self._scomp_interface_getRotation(self);
    }

    /// Gets the world position of the scene component (owner position + our relative position)
    pub fn getWorldPosition(self: *EntitySceneComponent) delve.math.Vec3 {
        if (self.owner.getRootSceneComponent()) |root| {
            if (root.ptr == self.ptr)
                return self.getPosition();

            return root.getPosition().add(self.getPosition());
        }

        return self.getPosition();
    }

    /// Gets the world position of the scene component (owner rotation + our relative rotation)
    pub fn getWorldRotation(self: *EntitySceneComponent) delve.math.Quaternion {
        if (self.owner.getRootSceneComponent()) |root| {
            if (root == self)
                return self.getRotation();

            return root.getRotation().add(self.getRotation());
        }
        return self.getRotation();
    }

    pub fn createSceneComponent(allocator: Allocator, comptime ComponentType: type, owner: *Entity, props: ComponentType) !EntitySceneComponent {
        const storage = try owner.world.components.getStorageForType(ComponentType);
        const final_store = storage.getStorage(ComponentStorage(ComponentType));

        const new_component_ptr = try final_store.data.addOne(final_store.allocator);
        new_component_ptr.* = props;

        return EntitySceneComponent{
            .ptr = new_component_ptr,
            .allocator = allocator,
            .typename = @typeName(ComponentType),
            .owner = owner,
            ._comp_interface_init = (struct {
                pub fn init(self: *EntitySceneComponent) void {
                    var ptr: *ComponentType = @ptrCast(@alignCast(self.ptr));
                    ptr.init(self.*);
                }
            }).init,
            ._comp_interface_tick = (struct {
                pub fn tick(self: *EntitySceneComponent, in_delta: f32) void {
                    var ptr: *ComponentType = @ptrCast(@alignCast(self.ptr));
                    ptr.tick(in_delta);
                }
            }).tick,
            ._comp_interface_deinit = (struct {
                pub fn deinit(self: *EntitySceneComponent) void {
                    var ptr: *ComponentType = @ptrCast(@alignCast(self.ptr));
                    ptr.deinit();
                }
            }).deinit,
            ._scomp_interface_getPosition = (struct {
                pub fn getPosition(self: *EntitySceneComponent) delve.math.Vec3 {
                    const ptr: *ComponentType = @ptrCast(@alignCast(self.ptr));
                    return ptr.getPosition();
                }
            }).getPosition,
            ._scomp_interface_getRotation = (struct {
                pub fn getRotation(self: *EntitySceneComponent) delve.math.Quaternion {
                    const ptr: *ComponentType = @ptrCast(@alignCast(self.ptr));
                    return ptr.getRotation();
                }
            }).getRotation,
            ._scomp_interface_getBounds = (struct {
                pub fn getBounds(self: *EntitySceneComponent) delve.spatial.BoundingBox {
                    const ptr: *ComponentType = @ptrCast(@alignCast(self.ptr));
                    return ptr.getBounds();
                }
            }).getBounds,
        };
    }

    pub fn cast(self: *EntitySceneComponent, comptime ComponentType: type) ?*ComponentType {
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

pub const EntitySceneComponentIterator = struct {
    list: []EntitySceneComponent,
    component_typename: []const u8,

    index: usize = 0,

    pub fn next(self: *EntitySceneComponentIterator) ?*EntitySceneComponent {
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
        var it = self.entities.iterator(0);
        while (it.next()) |e| {
            e.tick(delta);
        }
        // for (self.entities.items) |*e| {
        //     e.tick(delta);
        // }
    }

    /// Tears down the world's entities
    pub fn deinit(self: *World) void {
        var it = self.entities.iterator(0);
        while (it.next()) |e| {
            e.deinit();
        }

        // for (self.entities.items) |*e| {
        //     e.deinit();
        // }
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
    scene_components: std.ArrayList(EntitySceneComponent), // components that can be drawn
    root_scene_component_idx: usize = 0, // which scene component is the root

    pub fn init(world: *World) Entity {
        return Entity{
            .allocator = world.allocator,
            .world = world,
            .components = std.ArrayList(EntityComponent).init(world.allocator),
            .scene_components = std.ArrayList(EntitySceneComponent).init(world.allocator),
        };
    }

    pub fn deinit(self: *Entity) void {
        for (self.components.items) |*c| {
            c.deinit();
        }
        for (self.scene_components.items) |*c| {
            c.deinit();
        }
        self.components.deinit();
        self.scene_components.deinit();
    }

    pub fn getRootSceneComponent(self: *Entity) ?*EntitySceneComponent {
        if (self.scene_components.items.len <= self.root_scene_component_idx)
            return null;

        return &self.scene_components.items[self.root_scene_component_idx];
    }

    pub fn isRootSceneComponent(self: *Entity, check_component_ptr: *anyopaque) bool {
        const root_opt = self.getRootSceneComponent();
        if (root_opt) |root| {
            return root.ptr == check_component_ptr;
        }
        return false;
    }

    pub fn createNewComponent(self: *Entity, comptime ComponentType: type, props: ComponentType) !*ComponentType {
        const component = try EntityComponent.createComponent(self.allocator, ComponentType, self, props);

        // init new component
        const comp_ptr: *ComponentType = @ptrCast(@alignCast(component.ptr));
        // comp_ptr.init(self);

        try self.components.append(component);
        const component_in_list_ptr = &self.components.items[self.components.items.len - 1];

        component_in_list_ptr.init();
        return comp_ptr;
    }

    pub fn createNewSceneComponent(self: *Entity, comptime ComponentType: type, props: ComponentType) !*ComponentType {
        const component = try EntitySceneComponent.createSceneComponent(self.allocator, ComponentType, self, props);

        // init new component
        const comp_ptr: *ComponentType = @ptrCast(@alignCast(component.ptr));

        try self.scene_components.append(component);
        const component_in_list_ptr = &self.scene_components.items[self.scene_components.items.len - 1];

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

    pub fn getSceneComponent(self: *Entity, comptime ComponentType: type) ?*ComponentType {
        const check_typename = @typeName(ComponentType);
        for (self.scene_components.items) |*c| {
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

    pub fn getSceneComponents(self: *Entity, comptime ComponentType: type) EntitySceneComponentIterator {
        const check_typename = @typeName(ComponentType);
        return .{
            .component_typename = check_typename,
            .list = self.scene_components.items,
        };
    }

    pub fn tick(self: *Entity, delta: f32) void {
        // tick scene components after regular components, so draw state can update based on logic state
        for (self.components.items) |*c| {
            c.tick(self, delta);
        }
        for (self.scene_components.items) |*c| {
            c.tick(self, delta);
        }
    }
};

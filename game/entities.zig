const std = @import("std");
const delve = @import("delve");
const Allocator = std.mem.Allocator;

const Vec3 = delve.math.Vec3;
const BoundingBox = delve.spatial.BoundingBox;

// Basic entity component, logic only
pub const EntityComponent = struct {
    ptr: *anyopaque,
    allocator: Allocator,
    typename: []const u8,
    owner: *Entity,

    // lifecycle entity component methods
    _comp_interface_init: *const fn (component: *anyopaque) void,
    _comp_interface_tick: *const fn (component: *anyopaque, delta: f32) void,
    _comp_interface_deinit: *const fn (component: *anyopaque, allocator: Allocator) void,

    pub fn init(self: *EntityComponent) void {
        self._comp_interface_init(self);
    }

    pub fn tick(self: *EntityComponent, owner: *Entity, delta: f32) void {
        self.owner = owner; // fixup the owner every tick! could have moved.
        self._comp_interface_tick(self, delta);
    }

    pub fn deinit(self: *EntityComponent, allocator: Allocator) void {
        self._comp_interface_deinit(self, allocator);
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
                pub fn init(ec_ptr: *anyopaque) void {
                    var ptr: *ComponentType = @ptrCast(@alignCast(ec_ptr));
                    ptr.init();
                }
            }).init,
            ._comp_interface_tick = (struct {
                pub fn tick(ec_ptr: *anyopaque, in_delta: f32) void {
                    var ptr: *ComponentType = @ptrCast(@alignCast(ec_ptr));
                    ptr.tick(in_delta);
                }
            }).tick,
            ._comp_interface_deinit = (struct {
                pub fn deinit(ec_ptr: *anyopaque, in_allocator: Allocator) void {
                    var ptr: *ComponentType = @ptrCast(@alignCast(ec_ptr));
                    ptr.deinit();
                    in_allocator.destroy(ptr);
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
    _comp_interface_deinit: *const fn (self: *EntitySceneComponent, allocator: Allocator) void,

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

    pub fn deinit(self: *EntitySceneComponent, allocator: Allocator) void {
        self._comp_interface_deinit(self, allocator);
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
        if(self.owner.root_scene_component) |root| {
            if(root == self)
                return self.getPosition();

            return root.getPosition().add(self.getPosition());
        }
        return self.getPosition();
    }

    /// Gets the world position of the scene component (owner rotation + our relative rotation)
    pub fn getWorldRotation(self: *EntitySceneComponent) delve.math.Quaternion {
        if(self.owner.root_scene_component) |root| {
            if(root == self)
                return self.getRotation();

            return root.getRotation().add(self.getRotation());
        }
        return self.getRotation();
    }

    pub fn createSceneComponent(allocator: Allocator, comptime ComponentType: type, owner: *Entity, props: ComponentType) !EntitySceneComponent {
        const component = try allocator.create(ComponentType);
        component.* = props;

        return EntitySceneComponent{
            .ptr = component,
            .allocator = allocator,
            .typename = @typeName(ComponentType),
            .owner = owner,
            ._comp_interface_init = (struct {
                pub fn init(self: *EntitySceneComponent) void {
                    var ptr: *ComponentType = @ptrCast(@alignCast(self.ptr));
                    ptr.init(self);
                }
            }).init,
            ._comp_interface_tick = (struct {
                pub fn tick(self: *EntitySceneComponent, in_delta: f32) void {
                    var ptr: *ComponentType = @ptrCast(@alignCast(self.ptr));
                    ptr.tick(in_delta);
                }
            }).tick,
            ._comp_interface_deinit = (struct {
                pub fn deinit(self: *EntitySceneComponent, in_allocator: Allocator) void {
                    var ptr: *ComponentType = @ptrCast(@alignCast(self.ptr));
                    ptr.deinit();
                    in_allocator.destroy(ptr);
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

pub const Entity = struct {
    allocator: Allocator,
    components: std.ArrayList(EntityComponent), // components that only run logic
    scene_components: std.ArrayList(EntitySceneComponent), // components that can be drawn

    root_scene_component: ?*EntitySceneComponent = null,

    pub fn init(allocator: Allocator) !Entity {
        return Entity{
            .allocator = allocator,
            .components = std.ArrayList(EntityComponent).init(allocator),
            .scene_components = std.ArrayList(EntitySceneComponent).init(allocator),
        };
    }

    pub fn deinit(self: *Entity) void {
        for (self.components.items) |*c| {
            c.deinit(self.allocator);
        }
        for (self.scene_components.items) |*c| {
            c.deinit(self.allocator);
        }
        self.components.deinit();
        self.scene_components.deinit();
    }

    pub fn createNewComponent(self: *Entity, comptime ComponentType: type, props: ComponentType) !*ComponentType {
        const component = try EntityComponent.createComponent(self.allocator, ComponentType, self, props);

        // init new component
        const comp_ptr: *ComponentType = @ptrCast(@alignCast(component.ptr));
        comp_ptr.init();

        try self.components.append(component);
        return comp_ptr;
    }

    pub fn createNewSceneComponent(self: *Entity, comptime ComponentType: type, props: ComponentType) !*ComponentType {
        var component = try EntitySceneComponent.createSceneComponent(self.allocator, ComponentType, self, props);

        // init new component
        const comp_ptr: *ComponentType = @ptrCast(@alignCast(component.ptr));
        comp_ptr.init(&component);

        try self.scene_components.append(component);

        // set the root scene component if not set already
        if(self.root_scene_component == null)
            self.root_scene_component = &self.scene_components.items[self.scene_components.items.len - 1];

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

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
    init: *const fn (component: *anyopaque) void,
    tick: *const fn (component: *anyopaque, delta: f32) void,
    deinit: *const fn (component: *anyopaque, allocator: Allocator) void,

    pub fn createComponent(allocator: Allocator, comptime ComponentType: type, owner: *Entity, props: ComponentType) !EntityComponent {
        const component = try allocator.create(ComponentType);
        component.* = props;

        return EntityComponent{
            .ptr = component,
            .allocator = allocator,
            .typename = @typeName(ComponentType),
            .owner = owner,
            .init = (struct {
                pub fn init(ec_ptr: *anyopaque) void {
                    var ptr: *ComponentType = @ptrCast(@alignCast(ec_ptr));
                    ptr.init();
                }
            }).init,
            .tick = (struct {
                pub fn tick(ec_ptr: *anyopaque, in_delta: f32) void {
                    var ptr: *ComponentType = @ptrCast(@alignCast(ec_ptr));
                    ptr.tick(in_delta);
                }
            }).tick,
            .deinit = (struct {
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

    // lifecycle entity component methods
    init: *const fn (self: *EntitySceneComponent) void,
    tick: *const fn (self: *EntitySceneComponent, delta: f32) void,
    deinit: *const fn (self: *EntitySceneComponent, allocator: Allocator) void,

    // scene component interface
    getPosition: *const fn (self: *EntitySceneComponent) delve.math.Vec3,
    getBounds: *const fn (self: *EntitySceneComponent) delve.spatial.BoundingBox,

    /// Gets the world position of the scene component (owner position + our relative position)
    pub fn getWorldPosition(self: *EntitySceneComponent) delve.math.Vec3 {
        return self.owner.position.add(self.getPosition(self));
    }

    pub fn createSceneComponent(allocator: Allocator, comptime ComponentType: type, owner: *Entity, props: ComponentType) !EntitySceneComponent {
        const component = try allocator.create(ComponentType);
        component.* = props;

        return EntitySceneComponent{
            .ptr = component,
            .allocator = allocator,
            .typename = @typeName(ComponentType),
            .owner = owner,
            .init = (struct {
                pub fn init(self: *EntitySceneComponent) void {
                    var ptr: *ComponentType = @ptrCast(@alignCast(self.ptr));
                    ptr.init(self);
                }
            }).init,
            .tick = (struct {
                pub fn tick(self: *EntitySceneComponent, in_delta: f32) void {
                    var ptr: *ComponentType = @ptrCast(@alignCast(self.ptr));
                    ptr.tick(in_delta);
                }
            }).tick,
            .deinit = (struct {
                pub fn deinit(self: *EntitySceneComponent, in_allocator: Allocator) void {
                    var ptr: *ComponentType = @ptrCast(@alignCast(self.ptr));
                    ptr.deinit();
                    in_allocator.destroy(ptr);
                }
            }).deinit,
            .getPosition = (struct {
                pub fn getPosition(self: *EntitySceneComponent) delve.math.Vec3 {
                    const ptr: *ComponentType = @ptrCast(@alignCast(self.ptr));
                    return ptr.getPosition();
                }
            }).getPosition,
            .getBounds = (struct {
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

    position: delve.math.Vec3 = delve.math.Vec3.zero,
    rotation: delve.math.Quaternion = delve.math.Quaternion.zero,

    pub fn init(allocator: Allocator) !*Entity {
        const e = try allocator.create(Entity);
        e.* = Entity{
            .allocator = allocator,
            .components = std.ArrayList(EntityComponent).init(allocator),
            .scene_components = std.ArrayList(EntitySceneComponent).init(allocator),
        };
        return e;
    }

    pub fn deinit(self: *Entity) void {
        for (self.components.items) |*c| {
            c.deinit(c.ptr, self.allocator);
        }
        for (self.scene_components.items) |*c| {
            c.deinit(c, self.allocator);
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
            c.tick(c.ptr, delta);
        }
        for (self.scene_components.items) |*c| {
            c.tick(c, delta);
        }
    }
};

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
};

// EntitySceneComponents are entity components that have a visual representation
pub const EntitySceneComponent = struct {
    ptr: *anyopaque,
    allocator: Allocator,
    typename: []const u8,
    owner: *Entity,

    // lifecycle entity component methods
    init: *const fn (component: *anyopaque) void,
    tick: *const fn (component: *anyopaque, delta: f32) void,
    deinit: *const fn (component: *anyopaque, allocator: Allocator) void,

    // scene component interface
    getPosition: *const fn (component: *anyopaque) delve.math.Vec3,
    getBounds: *const fn (component: *anyopaque) delve.spatial.BoundingBox,

    pub fn createSceneComponent(allocator: Allocator, comptime ComponentType: type, owner: *Entity, props: ComponentType) !EntitySceneComponent {
        const component = try allocator.create(ComponentType);
        component.* = props;

        return EntitySceneComponent{
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
            .getPosition = (struct {
                pub fn getPosition(ec_ptr: *anyopaque) delve.math.Vec3 {
                    const ptr: *ComponentType = @ptrCast(@alignCast(ec_ptr));
                    return ptr.getPosition();
                }
            }).getPosition,
            .getBounds = (struct {
                pub fn getBounds(ec_ptr: *anyopaque) delve.spatial.BoundingBox {
                    const ptr: *ComponentType = @ptrCast(@alignCast(ec_ptr));
                    return ptr.getBounds();
                }
            }).getBounds,
        };
    }
};

pub const Entity = struct {
    allocator: Allocator,
    components: std.ArrayList(EntityComponent), // components that only run logic
    scene_components: std.ArrayList(EntitySceneComponent), // components that can be drawn

    root_scene_component: ?*EntitySceneComponent = null, // the base scene component, holds the actual spatial info

    pub fn init(allocator: Allocator) Entity {
        return Entity{
            .allocator = allocator,
            .components = std.ArrayList(EntityComponent).init(allocator),
            .scene_components = std.ArrayList(EntitySceneComponent).init(allocator),
        };
    }

    pub fn deinit(self: *Entity) void {
        for (self.components.items) |*c| {
            c.deinit(c.ptr, self.allocator);
        }
        for (self.scene_components.items) |*c| {
            c.deinit(c.ptr, self.allocator);
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
        const component = try EntitySceneComponent.createSceneComponent(self.allocator, ComponentType, self, props);

        // init new component
        const comp_ptr: *ComponentType = @ptrCast(@alignCast(component.ptr));
        comp_ptr.init();

        try self.scene_components.append(component);

        // set our root scene component, if not set already
        if (self.root_scene_component == null)
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

    pub fn tick(self: Entity, delta: f32) void {
        // tick scene components after regular components, so draw state can update based on logic state
        for (self.components.items) |*c| {
            c.tick(c.ptr, delta);
        }
        for (self.scene_components.items) |*c| {
            c.tick(c.ptr, delta);
        }
    }
};

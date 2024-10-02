const std = @import("std");
const Allocator = std.mem.Allocator;

pub const EntityComponent = struct {
    ptr: *anyopaque,
    allocator: Allocator,

    tick: *const fn (component: *anyopaque, delta: f32) void,
    draw: ?*const fn (component: *anyopaque) void = null,
    deinit: *const fn (component: *anyopaque, allocator: Allocator) void,

    pub fn createComponent(allocator: Allocator, comptime ComponentType: type, props: ComponentType) !EntityComponent {
        const component = try allocator.create(ComponentType);
        component.* = props;

        return EntityComponent{
            .ptr = component,
            .allocator = allocator,
            .tick = (struct {
                pub fn tick(ec_ptr: *anyopaque, in_delta: f32) void {
                    var ptr: *ComponentType = @ptrCast(@alignCast(ec_ptr));
                    ptr.tick(in_delta);
                }
            }).tick,
            .deinit = (struct {
                pub fn deinit(ec_ptr: *anyopaque, in_allocator: Allocator) void {
                    const ptr: *ComponentType = @ptrCast(@alignCast(ec_ptr));
                    in_allocator.destroy(ptr);
                }
            }).deinit,
        };
    }

    pub fn createSceneComponent(allocator: Allocator, comptime ComponentType: type, props: anytype) !EntityComponent {
        const component = try allocator.create(ComponentType);
        component.* = props;

        return EntityComponent{
            .ptr = component,
            .allocator = allocator,
            .tick = (struct {
                pub fn tick(ec_ptr: *anyopaque, in_delta: f32) void {
                    var ptr: *ComponentType = @ptrCast(@alignCast(ec_ptr));
                    ptr.tick(in_delta);
                }
            }).tick,
            .draw = (struct {
                pub fn draw(ec_ptr: *anyopaque) void {
                    var ptr: *ComponentType = @ptrCast(@alignCast(ec_ptr));
                    ptr.draw();
                }
            }).draw,
            .deinit = (struct {
                pub fn deinit(ec_ptr: *anyopaque, in_allocator: Allocator) void {
                    const ptr: *ComponentType = @ptrCast(@alignCast(ec_ptr));
                    in_allocator.destroy(ptr);
                }
            }).deinit,
        };
    }
};

pub const Entity = struct {
    allocator: Allocator,
    components: std.ArrayList(EntityComponent), // components that only run logic
    scene_components: std.ArrayList(EntityComponent), // components that can be drawn

    pub fn init(allocator: Allocator) Entity {
        return Entity{
            .allocator = allocator,
            .components = std.ArrayList(EntityComponent).init(allocator),
            .scene_components = std.ArrayList(EntityComponent).init(allocator),
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

    pub fn createNewComponent(self: *Entity, comptime Component: type, props: Component) !void {
        const component = try EntityComponent.createComponent(self.allocator, Component, props);
        try self.components.append(component);
    }

    pub fn createNewSceneComponent(self: *Entity, comptime Component: type, props: anytype) !void {
        const component = try EntityComponent.createSceneComponent(self.allocator, Component, props);
        try self.scene_components.append(component);
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

    pub fn draw(self: Entity) void {
        // Only draw scene components
        for (self.scene_components.items) |*c| {
            if (c.draw != null) {
                c.draw.?(c.ptr);
            }
        }
    }
};

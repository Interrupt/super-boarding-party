const std = @import("std");
const delve = @import("delve");
const entities = @import("../game/entities.zig");
const basics = @import("../entities/basics.zig");

const EntityComponent = entities.EntityComponent;

pub fn writeComponent(component: *const EntityComponent, out: anytype) !void {
    try out.beginObject();

    // try out.objectField("id");
    // try out.write(self.id);

    try out.objectField("typename");
    try out.write(component.typename);

    // Write components here
    if (std.mem.eql(u8, component.typename, "entities.basics.TransformComponent")) {
        const ptr: *basics.TransformComponent = @ptrCast(@alignCast(component.impl_ptr));
        try out.objectField("state");
        try out.write(ptr);
    }
    if (std.mem.eql(u8, component.typename, "entities.basics.NameComponent")) {
        const ptr: *basics.NameComponent = @ptrCast(@alignCast(component.impl_ptr));
        try out.objectField("state");
        try out.write(ptr);
    }

    try out.endObject();
}

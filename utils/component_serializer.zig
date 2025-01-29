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
        // try out.objectField("state");
        // try out.write(ptr);
        try write(out, ptr);
    }

    try out.endObject();
}

pub fn write(self: anytype, value: anytype) !void {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .Struct => |S| {
            if (std.meta.hasFn(T, "jsonStringify")) {
                return value.jsonStringify(self);
            }

            inline for (S.fields) |Field| {
                // don't include void fields
                if (Field.type == void) continue;

                var emit_field = true;

                // don't include optional fields that are null when emit_null_optional_fields is set to false
                if (@typeInfo(Field.type) == .optional) {
                    if (self.options.emit_null_optional_fields == false) {
                        if (@field(value, Field.name) == null) {
                            emit_field = false;
                        }
                    }
                }

                if (emit_field) {
                    if (!S.is_tuple) {
                        try self.objectField(Field.name);
                    }
                    try self.write(@field(value, Field.name));
                }
            }
        },
        else => {},
    }
}

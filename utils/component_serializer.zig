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
        // try out.write(ptr);
        try write(out, ptr);
    }

    try out.endObject();
}

pub fn write(self: anytype, value: anytype) !void {
    try self.write(value);

    const T = @TypeOf(value);

    const info = @typeInfo(T);
    delve.debug.log("Type: '{any}'", .{info});

    switch (@typeInfo(T)) {
        .Int => {
            delve.debug.log("Found int", .{});
        },
        else => {
            delve.debug.log("Unknown value!", .{});
        }
    }

    //     .int => {
    //         try self.valueStart();
    //         if (self.options.emit_nonportable_numbers_as_strings and
    //             (value <= -(1 << 53) or value >= (1 << 53)))
    //         {
    //             try self.stream.print("\"{}\"", .{value});
    //         } else {
    //             try self.stream.print("{}", .{value});
    //         }
    //         self.valueDone();
    //         return;
    //     },
    //     .comptime_int => {
    //         return self.write(@as(std.math.IntFittingRange(value, value), value));
    //     },
    //     .float, .comptime_float => {
    //         if (@as(f64, @floatCast(value)) == value) {
    //             try self.valueStart();
    //             try self.stream.print("{}", .{@as(f64, @floatCast(value))});
    //             self.valueDone();
    //             return;
    //         }
    //         try self.valueStart();
    //         try self.stream.print("\"{}\"", .{value});
    //         self.valueDone();
    //         return;
    //     },
    //
    //     .bool => {
    //         try self.valueStart();
    //         try self.stream.writeAll(if (value) "true" else "false");
    //         self.valueDone();
    //         return;
    //     },
    //     .null => {
    //         try self.valueStart();
    //         try self.stream.writeAll("null");
    //         self.valueDone();
    //         return;
    //     },
    //     .optional => {
    //         if (value) |payload| {
    //             return try self.write(payload);
    //         } else {
    //             return try self.write(null);
    //         }
    //     },
    //     .@"enum" => |enum_info| {
    //         if (std.meta.hasFn(T, "jsonStringify")) {
    //             return value.jsonStringify(self);
    //         }
    //
    //         if (!enum_info.is_exhaustive) {
    //             inline for (enum_info.fields) |field| {
    //                 if (value == @field(T, field.name)) {
    //                     break;
    //                 }
    //             } else {
    //                 return self.write(@intFromEnum(value));
    //             }
    //         }
    //
    //         return self.stringValue(@tagName(value));
    //     },
    //     .enum_literal => {
    //         return self.stringValue(@tagName(value));
    //     },
    //     .@"union" => {
    //         if (std.meta.hasFn(T, "jsonStringify")) {
    //             return value.jsonStringify(self);
    //         }
    //
    //         const info = @typeInfo(T).@"union";
    //         if (info.tag_type) |UnionTagType| {
    //             try self.beginObject();
    //             inline for (info.fields) |u_field| {
    //                 if (value == @field(UnionTagType, u_field.name)) {
    //                     try self.objectField(u_field.name);
    //                     if (u_field.type == void) {
    //                         // void value is {}
    //                         try self.beginObject();
    //                         try self.endObject();
    //                     } else {
    //                         try self.write(@field(value, u_field.name));
    //                     }
    //                     break;
    //                 }
    //             } else {
    //                 unreachable; // No active tag?
    //             }
    //             try self.endObject();
    //             return;
    //         } else {
    //             @compileError("Unable to stringify untagged union '" ++ @typeName(T) ++ "'");
    //         }
    //     },
    //     .@"struct" => |S| {
    //         if (std.meta.hasFn(T, "jsonStringify")) {
    //             return value.jsonStringify(self);
    //         }
    //
    //         if (S.is_tuple) {
    //             try self.beginArray();
    //         } else {
    //             try self.beginObject();
    //         }
    //         inline for (S.fields) |Field| {
    //             // don't include void fields
    //             if (Field.type == void) continue;
    //
    //             var emit_field = true;
    //
    //             // don't include optional fields that are null when emit_null_optional_fields is set to false
    //             if (@typeInfo(Field.type) == .optional) {
    //                 if (self.options.emit_null_optional_fields == false) {
    //                     if (@field(value, Field.name) == null) {
    //                         emit_field = false;
    //                     }
    //                 }
    //             }
    //
    //             if (emit_field) {
    //                 if (!S.is_tuple) {
    //                     try self.objectField(Field.name);
    //                 }
    //                 try self.write(@field(value, Field.name));
    //             }
    //         }
    //         if (S.is_tuple) {
    //             try self.endArray();
    //         } else {
    //             try self.endObject();
    //         }
    //         return;
    //     },
    //     .error_set => return self.stringValue(@errorName(value)),
    //     .pointer => |ptr_info| switch (ptr_info.size) {
    //         .one => switch (@typeInfo(ptr_info.child)) {
    //             .array => {
    //                 // Coerce `*[N]T` to `[]const T`.
    //                 const Slice = []const std.meta.Elem(ptr_info.child);
    //                 return self.write(@as(Slice, value));
    //             },
    //             else => {
    //                 return self.write(value.*);
    //             },
    //         },
    //         .many, .slice => {
    //             if (ptr_info.size == .many and ptr_info.sentinel() == null)
    //                 @compileError("unable to stringify type '" ++ @typeName(T) ++ "' without sentinel");
    //             const slice = if (ptr_info.size == .many) std.mem.span(value) else value;
    //
    //             if (ptr_info.child == u8) {
    //                 // This is a []const u8, or some similar Zig string.
    //                 if (!self.options.emit_strings_as_arrays and std.unicode.utf8ValidateSlice(slice)) {
    //                     return self.stringValue(slice);
    //                 }
    //             }
    //
    //             try self.beginArray();
    //             for (slice) |x| {
    //                 try self.write(x);
    //             }
    //             try self.endArray();
    //             return;
    //         },
    //         else => @compileError("Unable to stringify type '" ++ @typeName(T) ++ "'"),
    //     },
    //     .array => {
    //         // Coerce `[N]T` to `*const [N]T` (and then to `[]const T`).
    //         return self.write(&value);
    //     },
    //     .vector => |info| {
    //         const array: [info.len]info.child = value;
    //         return self.write(&array);
    //     },
    //     else => @compileError("Unable to stringify type '" ++ @typeName(T) ++ "'"),
    // }
    // unreachable;
}

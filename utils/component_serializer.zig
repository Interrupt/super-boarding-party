const std = @import("std");
const delve = @import("delve");
const entities = @import("../game/entities.zig");
const basics = @import("../entities/basics.zig");

const EntityComponent = entities.EntityComponent;

// Important! List of all components that can be serialized
// Components not added to this list will not be considered
const registered_types = [_]type{
    basics.TransformComponent,
    basics.NameComponent,
    basics.LifetimeComponent,
    @import("../entities/actor_stats.zig").ActorStats,
    @import("../entities/audio.zig").LoopingSoundComponent,
    @import("../entities/box_collision.zig").BoxCollisionComponent,
    @import("../entities/breakable.zig").BreakableComponent,
    // @import("../entities/character.zig").CharacterMovementComponent,
    @import("../entities/light.zig").LightComponent,
    @import("../entities/mesh.zig").MeshComponent,
    @import("../entities/monster.zig").MonsterController,
    // @import("../entities/mover.zig").MoverComponent,
    @import("../entities/particle_emitter.zig").ParticleEmitterComponent,
    // @import("../entities/player.zig").PlayerController,
    // @import("../entities/quakemap.zig").QuakeMapComponent,
    // @import("../entities/quakesolids.zig").QuakeSolidsComponent,
    @import("../entities/spinner.zig").SpinnerComponent,
    @import("../entities/sprite.zig").SpriteComponent,
    @import("../entities/text.zig").TextComponent,
    @import("../entities/triggers.zig").TriggerComponent,
};

pub fn writeComponent(component: *const EntityComponent, out: anytype) !void {
    try out.beginObject();

    // try out.objectField("id");
    // try out.write(self.id);

    try out.objectField("typename");
    try out.write(component.typename);

    try out.objectField("state");
    try out.beginObject();
    try writeType(component, out);
    try out.endObject();

    try out.endObject();
}

fn writeType(component: *const EntityComponent, out: anytype) !void {
    inline for (registered_types) |t| {
        if (std.mem.eql(u8, component.typename, @typeName(t))) {
            const ptr: *t = @ptrCast(@alignCast(component.impl_ptr));
            try write(out, ptr);
            return;
        }
    }
}

fn write(self: anytype, value: anytype) !void {
    const T = @TypeOf(value.*);
    switch (@typeInfo(T)) {
        .Struct => |S| {
            if (std.meta.hasFn(T, "jsonStringify")) {
                return value.jsonStringify(self);
            }

            const fields = S.fields;

            inline for (fields) |Field| {
                // don't include void fields
                comptime {
                    if (Field.type == void) continue;

                    // Skip computed fields
                    if (std.mem.startsWith(u8, Field.name, "_")) {
                        continue;
                    }

                    // Skip our owner field and interface
                    if (std.mem.eql(u8, Field.name, "owner")) {
                        continue;
                    }
                    if (std.mem.eql(u8, Field.name, "component_interface")) {
                        continue;
                    }

                    // Skip pointers - would have to fix them up later
                    // if (@typeInfo(Field.type) == .Pointer) {
                    //     continue;
                    // }

                    // Skip some types that cannot be serialized
                    switch (Field.type) {
                        // Material
                        ?delve.platform.graphics.Material => {
                            continue;
                        },
                        delve.platform.graphics.Material => {
                            continue;
                        },
                        // Shader
                        ?delve.platform.graphics.Shader => {
                            continue;
                        },
                        delve.platform.graphics.Shader => {
                            continue;
                        },
                        // Mesh
                        ?delve.graphics.mesh.Mesh => {
                            continue;
                        },
                        delve.graphics.mesh.Mesh => {
                            continue;
                        },
                        // Interpolation function
                        ?delve.utils.interpolation.Interpolation => {
                            continue;
                        },
                        delve.utils.interpolation.Interpolation => {
                            continue;
                        },
                        else => {},
                    }
                }

                // Don't include optional fields that are null when emit_null_optional_fields is set to false
                var emit_field = true;
                if (@typeInfo(Field.type) == .Optional) {
                    if (self.options.emit_null_optional_fields == false) {
                        if (@field(value.*, Field.name) == null) {
                            emit_field = false;
                        }
                    }
                }

                if (emit_field) {
                    try self.objectField(Field.name);
                    try self.write(@field(value.*, Field.name));
                } else {
                    // delve.debug.log("Skipping field: {s}", .{Field.name});
                }
            }
        },
        else => {},
    }
}

pub fn readComponent(typename: []const u8, allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !EntityComponent {
    delve.debug.log("Reading component of type {s}", .{typename});

    inline for (registered_types) |t| {
        if (std.mem.eql(u8, typename, @typeName(t))) {
            const found = try innerParse(t, allocator, source, options);
            _ = found;
            // delve.debug.log("Done reading component: {any}", .{found});
            return undefined;
        }
    }

    // No match, skip this next object
    var begin_count: usize = 1;
    var end_count: usize = 0;

    const start_token = try source.next();
    if (.object_begin != start_token) {
        delve.debug.log("No object begin token when skipping!", .{});
        return error.UnexpectedToken;
    }

    // Read until we have ended all matching begins
    while (begin_count != end_count) {
        const next_token = try source.next();
        if (next_token == .object_begin) {
            begin_count += 1;
        } else if (next_token == .object_end) {
            end_count += 1;
        }
    }

    return undefined;
}

// These functions are modified from ones in std.json, to skip the fields and types we want to skip
pub fn innerParse(
    comptime T: type,
    allocator: std.mem.Allocator,
    source: anytype,
    options: std.json.ParseOptions,
) std.json.ParseError(@TypeOf(source.*))!T {
    switch (@typeInfo(T)) {
        .Struct => |structInfo| {
            if (std.meta.hasFn(T, "jsonParse")) {
                return T.jsonParse(allocator, source, options);
            }

            if (.object_begin != try source.next()) {
                delve.debug.log("No object begin token for component state!", .{});
                return error.UnexpectedToken;
            }

            var r: T = undefined;
            var fields_seen = [_]bool{false} ** structInfo.fields.len;

            while (true) {
                var name_token: ?std.json.Token = try source.nextAllocMax(allocator, .alloc_if_needed, options.max_value_len.?);
                const field_name = switch (name_token.?) {
                    inline .string, .allocated_string => |slice| slice,
                    .object_end => { // No more fields.
                        break;
                    },
                    else => {
                        delve.debug.log("No field name found! {any}", .{name_token.?});
                        return error.UnexpectedToken;
                    },
                };

                inline for (structInfo.fields, 0..) |field, i| {
                    // Skip computed fields
                    comptime {
                        // skip void fields
                        if (field.type == void) continue;

                        if (std.mem.startsWith(u8, field.name, "_")) {
                            continue;
                        }
                        // Skip our owner field and interface
                        if (std.mem.eql(u8, field.name, "owner")) {
                            continue;
                        }
                        if (std.mem.eql(u8, field.name, "component_interface")) {
                            continue;
                        }
                        // if (@typeInfo(field.type) == .Pointer) {
                        //     continue;
                        // }

                        // Skip some types that cannot be serialized
                        switch (field.type) {
                            // Material
                            ?delve.platform.graphics.Material => {
                                continue;
                            },
                            delve.platform.graphics.Material => {
                                continue;
                            },
                            // Shader
                            ?delve.platform.graphics.Shader => {
                                continue;
                            },
                            delve.platform.graphics.Shader => {
                                continue;
                            },
                            // Mesh
                            ?delve.graphics.mesh.Mesh => {
                                continue;
                            },
                            delve.graphics.mesh.Mesh => {
                                continue;
                            },
                            // Interpolation function
                            ?delve.utils.interpolation.Interpolation => {
                                continue;
                            },
                            delve.utils.interpolation.Interpolation => {
                                continue;
                            },
                            else => {},
                        }
                    }

                    if (field.is_comptime) @compileError("comptime fields are not supported: " ++ @typeName(T) ++ "." ++ field.name);
                    if (std.mem.eql(u8, field.name, field_name)) {
                        // Free the name token now in case we're using an allocator that optimizes freeing the last allocated object.
                        // (Recursing into innerParse() might trigger more allocations.)
                        freeAllocated(allocator, name_token.?);
                        name_token = null;
                        if (fields_seen[i]) {
                            switch (options.duplicate_field_behavior) {
                                .use_first => {
                                    // Parse and ignore the redundant value.
                                    // We don't want to skip the value, because we want type checking.
                                    // @compileLog(field.type);
                                    _ = try std.json.innerParse(field.type, allocator, source, options);
                                    break;
                                },
                                .@"error" => return error.DuplicateField,
                                .use_last => {},
                            }
                        }

                        delve.debug.log("  reading field: {s} of type {any}", .{ field_name, field.type });
                        @field(r, field.name) = try std.json.innerParse(field.type, allocator, source, options);

                        fields_seen[i] = true;
                        break;
                    }
                } else {
                    // Didn't match anything.
                    freeAllocated(allocator, name_token.?);
                    if (options.ignore_unknown_fields) {
                        try source.skipValue();
                    } else {
                        delve.debug.log("Unknown field!", .{});
                        return error.UnknownField;
                    }
                }
            }
            try fillDefaultStructValues(T, &r, &fields_seen);
            return r;
        },
        else => @compileError("Unable to parse into type '" ++ @typeName(T) ++ "'"),
    }
    unreachable;
}

fn freeAllocated(allocator: std.mem.Allocator, token: std.json.Token) void {
    switch (token) {
        .allocated_number, .allocated_string => |slice| {
            allocator.free(slice);
        },
        else => {},
    }
}

fn fillDefaultStructValues(comptime T: type, r: *T, fields_seen: *[@typeInfo(T).Struct.fields.len]bool) !void {
    inline for (@typeInfo(T).Struct.fields, 0..) |field, i| {
        if (!fields_seen[i]) {
            if (field.default_value) |default_ptr| {
                const default = @as(*align(1) const field.type, @ptrCast(default_ptr)).*;
                @field(r, field.name) = default;
            } else {
                delve.debug.warning("Missing required field for {s}!", .{field.name});
                return error.MissingField;
            }
        }
    }
}

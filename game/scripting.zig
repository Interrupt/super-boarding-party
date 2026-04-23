const delve = @import("delve");
const std = @import("std");

const entities = @import("entities.zig");
const main = @import("../main.zig");
const string = @import("../utils/string.zig");

// components
const all_components = @import("../entities/all_components.zig");

const character = @import("../entities/character.zig");
const spinner = @import("../entities/spinner.zig");
const light = @import("../entities/light.zig");
const item = @import("../entities/item.zig");

const EntityId = entities.EntityId;
const World = entities.World;
const Entity = entities.Entity;

const Lua = delve.scripting.lua.Lua;
const BoundType = delve.scripting.binder.BoundType;

pub const GameScriptApi = struct {
    // Global function to get a World by ID
    pub fn getWorld(world_id: u8) ?*World {
        return entities.getWorld(world_id);
    }

    // Global function to get an Entity by ID
    pub fn getEntity(world_id: u8, entity_id: u24) ?Entity {
        // const id: EntityId = .{ .id = entity_id, .world_id = world_id };
        return entities.getEntity(world_id, entity_id);
    }

    // Global function to get our player
    pub fn getPlayer() ?Entity {
        if (main.game_instance.player_controller) |pc| {
            return pc.owner;
        }
        return null;
    }
};

pub fn ComponentScriptApi(T: type) type {
    return struct {
        const Self = @This();

        pub fn new() T {
            const new_comp: T = undefined;
            return new_comp;
        }

        pub fn createNewComponent(entity: entities.Entity) !*T {
            return entity.createNewComponent(T, new());
        }

        pub fn createNewComponentWithProps(entity: entities.Entity, props: T) !*T {
            return entity.createNewComponent(T, props);
        }

        pub fn getComponent(entity: entities.Entity) ?*T {
            return entity.getComponent(T);
        }

        pub fn getComponentById(entity: entities.Entity, id: u32) ?*T {
            const comp_id: entities.ComponentId = .{ .entity_id = entity.id, .id = id };
            return entity.getComponentById(T, comp_id);
        }

        pub fn setProperties(self: *T, props_to_copy: T) void {
            self.* = props_to_copy;
        }
    };
}

pub fn bindTypes() !void {
    const basic_types = [_]delve.scripting.binder.BoundType{
        .{ .Type = delve.colors.Color, .name = "Color" },
        .{ .Type = delve.math.Vec2, .name = "Vec2" },
        .{ .Type = delve.math.Vec3, .name = "Vec3" },
        .{ .Type = delve.math.Vec3, .name = "Vec4" },
        .{ .Type = delve.math.Quaternion, .name = "Quaternion" },
        .{ .Type = delve.math.Mat4, .name = "Mat4" },
        .{ .Type = delve.utils.interpolation.Interpolation, .name = "Interpolation" },
        .{ .Type = GameScriptApi, .name = "Game" },
        .{
            .Type = string.String,
            .name = "String",
            .ignore_fields = &[_][:0]const u8{
                "storage",
                "toOwnedString",
                "jsonStringify",
                "jsonParse",
            },
        },
    };

    const all_types = basic_types ++ makeComponentBoundTypes();

    // make our registry and bind the types
    const registry = delve.scripting.binder.Registry(.{
        .entries = all_types,
        .ignored_types = &[_]type{
            std.mem.Allocator,
            entities.EntityComponent,
        },
    });
    try registry.bindTypes(delve.scripting.lua.getLua());
}

pub fn makeComponentBoundTypes() []BoundType {
    comptime {
        const all_component_types = all_components.all_component_types;

        var component_types: [all_component_types.len]BoundType = undefined;
        var i: usize = 0;

        for (all_component_types) |t| {
            const new_type: BoundType = .{
                .Type = t.T,
                .name = t.name,
                .ignore_fields = t.ignore_fields,
                .mixin = ComponentScriptApi(t.T),
            };

            component_types[i] = new_type;
            i += 1;
        }

        return &component_types;
    }
}

fn shortTypeName(comptime T: type) [:0]const u8 {
    const full_name = @typeName(T);

    // Split the string backwards by the '.' character
    var iter = std.mem.splitBackwardsScalar(u8, full_name, '.');
    const first_part = iter.first();

    var null_terminated: [first_part.len:0]u8 = undefined;

    for (first_part, 0..) |c, i| {
        null_terminated[i] = c;
    }

    return &null_terminated;
}

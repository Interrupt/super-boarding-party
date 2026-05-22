const delve = @import("delve");
const std = @import("std");

const entities = @import("entities.zig");
const main = @import("../main.zig");
const string = @import("../utils/string.zig");

// components
const basics = @import("../entities/basics.zig");
const all_components = @import("../entities/all_components.zig");

const character = @import("../entities/character.zig");
const spinner = @import("../entities/spinner.zig");
const light = @import("../entities/light.zig");
const item = @import("../entities/item.zig");
const player = @import("../entities/player.zig");

const EntityId = entities.EntityId;
const World = entities.World;
const Entity = entities.Entity;

const Lua = delve.scripting.lua.Lua;
const BoundType = delve.scripting.binder.BoundType;

const basic_types = [_]delve.scripting.binder.BoundType{
    .{ .Type = delve.colors.Color, .name = "Color" },
    .{ .Type = delve.math.Vec2, .name = "Vec2" },
    .{ .Type = delve.math.Vec3, .name = "Vec3" },
    .{ .Type = delve.math.Vec3, .name = "Vec4" },
    .{ .Type = delve.math.Quaternion, .name = "Quaternion" },
    .{ .Type = delve.math.Mat4, .name = "Mat4" },
    .{ .Type = delve.spatial.BoundingBox, .name = "BoundingBox" },
    .{ .Type = delve.utils.interpolation.Interpolation, .name = "Interpolation" },
    .{
        .Type = delve.utils.quakemap.Entity,
        .name = "QuakeEntity",
        .ignore_fields = &[_][:0]const u8{
            "properties",
            "solids",
        },
    },
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

const registry = delve.scripting.binder.Registry(.{
    .entries = all_types,
    .ignored_types = &[_]type{
        std.mem.Allocator,
        entities.EntityComponent,
    },
});

pub const GameScriptApi = struct {
    // Global function to get a World by ID
    pub fn getWorldById(world_id: u8) ?*World {
        return entities.getWorld(world_id);
    }

    // Get the default game world
    pub fn getWorld() *World {
        return main.game_instance.world;
    }

    // Global function to get an Entity by ID
    pub fn getEntity(entity_id: u24) ?Entity {
        const world = getWorld();
        return entities.getEntity(world.id, entity_id);
    }

    // Global function to get an Entity by Name
    pub fn getEntityByName(entity_name: []const u8) ?Entity {
        const world = getWorld();
        return world.getEntityByName(entity_name);
    }

    // Global function to create a new entity
    pub fn createEntity() ?Entity {
        const world = getWorld();
        return world.createEntity(.{}) catch {
            return null;
        };
    }

    pub fn createEntityWithName(entity_name: []const u8) ?Entity {
        const world = getWorld();
        const entity = world.createEntity(.{}) catch {
            return null;
        };
        _ = entity.createNewComponent(basics.NameComponent, .{ .name = string.init(entity_name) }) catch {
            return null;
        };
        return entity;
    }

    // Global function to get our player
    pub fn getPlayer() ?Entity {
        if (main.game_instance.player_controller) |pc| {
            return pc.owner;
        }
        return null;
    }

    // Global function to set our currently controlled player
    pub fn setPlayer(player_controller: ?*player.PlayerController) void {
        main.game_instance.player_controller = player_controller;
    }
};

pub fn ComponentScriptApi(T: type) type {
    return struct {
        const Self = @This();

        pub fn createNewComponent(entity: entities.Entity) !*T {
            return entity.createNewComponent(T, T.default());
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

pub fn resetLuaStack(start_top: i32) void {
    const lua = delve.scripting.lua.getLua();
    const top = lua.getTop();
    lua.pop(top - start_top);
}

pub fn callLuaFunction(name: [:0]const u8, args: anytype) !void {
    const lua = delve.scripting.lua.getLua();
    const top = lua.getTop();
    defer resetLuaStack(top);

    delve.debug.info("Calling lua function '{s}'", .{name});

    // Get the function to call, and push it onto the stack
    _ = lua.getGlobal(name) catch {
        delve.debug.warning("Could not get global '{s}'", .{name});
        return;
    };

    if (!lua.isFunction(-1)) {
        delve.debug.warning("{s} is not a function in Lua!", .{name});
        return;
    }

    const count = registry.pushAny(lua, args);

    // Call the function!
    lua.protectedCall(.{ .args = count }) catch {
        delve.debug.log("Error calling Lua function {s} with arg {s}", .{ name, @typeName(@TypeOf(args)) });
        return;
    };
}

pub fn callLuaFunction2(name: [:0]const u8, arg1: anytype, arg2: anytype) !void {
    const lua = delve.scripting.lua.getLua();
    const top = lua.getTop();
    defer resetLuaStack(top);

    delve.debug.info("Calling lua function '{s}'", .{name});

    // Get the function to call, and push it onto the stack
    _ = lua.getGlobal(name) catch {
        delve.debug.warning("Could not get global '{s}'", .{name});
        return;
    };

    if (!lua.isFunction(-1)) {
        delve.debug.warning("{s} is not a function in Lua!", .{name});
        return;
    }

    const count1 = registry.pushAny(lua, arg1);
    const count2 = registry.pushAny(lua, arg2);
    const total = count1 + count2;

    // Call the function!
    lua.protectedCall(.{ .args = total }) catch {
        delve.debug.log("Error calling Lua function {s} with args {s}, {s}", .{ name, @typeName(@TypeOf(arg1)), @typeName(@TypeOf(arg2)) });
        return;
    };
}

pub fn callLuaFunction3(name: [:0]const u8, arg1: anytype, arg2: anytype, arg3: anytype) !void {
    const lua = delve.scripting.lua.getLua();
    const top = lua.getTop();
    defer resetLuaStack(top);

    delve.debug.info("Calling lua function '{s}'", .{name});

    // Get the function to call, and push it onto the stack
    _ = lua.getGlobal(name) catch {
        delve.debug.warning("Could not get global '{s}'", .{name});
        return;
    };

    if (!lua.isFunction(-1)) {
        delve.debug.warning("{s} is not a function in Lua!", .{name});
        return;
    }

    const count1 = registry.pushAny(lua, arg1);
    const count2 = registry.pushAny(lua, arg2);
    const count3 = registry.pushAny(lua, arg3);
    const total = count1 + count2 + count3;

    // Call the function!
    lua.protectedCall(.{ .args = total }) catch {
        delve.debug.log("Error calling Lua function {s} with args {s}, {s}, {s}", .{ name, @typeName(@TypeOf(arg1)), @typeName(@TypeOf(arg2)), @typeName(@TypeOf(arg3)) });
        return;
    };
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

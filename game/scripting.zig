const delve = @import("delve");
const std = @import("std");
const fs = std.fs;

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
const script = @import("../entities/script.zig");
const options = @import("options.zig");

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
    .{ .Type = DirIterator, .name = "DirIterator" },
    .{
        .Type = Entity,
        .name = "Entity",
        .ignore_fields = &[_][:0]const u8{
            "init",
            "post_load",
            "deinit",
            "createNewComponent",
            "createNewComponentWithConfig",
            "attachNewComponent",
            "getComponent",
            "getComponentById",
            "getComponents",
            "getAllComponents",
            "removeComponent",
            "jsonStringify",
        },
    },
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

pub const registry = delve.scripting.binder.Registry(.{
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

    // Global function to play a music track
    pub fn playMusic(music_path: [:0]const u8) void {
        main.game_instance.music = delve.platform.audio.playSound(music_path, .{
            .volume = options.options.music_volume * 0.5,
            .stream = true,
            .loop = true,
        });
    }

    pub fn showDeathScreen() void {
        main.game_instance.showDeathScreen();
    }

    pub fn showTitleScreen() void {
        main.game_instance.showTitleScreen();
    }

    pub fn listDir(path: []const u8) !DirIterator {
        return try DirIterator.init(path);
    }

    pub fn broadcastMessage(filter: ?entities.EntityId, msg: []const u8, body: anytype) void {
        const world = getWorld();

        var storage = script.getComponentStorage(world);
        var it = storage.iterator();

        while (it.next()) |comp| {
            _ = comp._handleMessage(filter, msg, body);
        }
    }
};

const DirIterator = struct {
    dir: fs.Dir = undefined,
    iterator: fs.Dir.Iterator = undefined,

    pub fn init(path: []const u8) !DirIterator {
        var dir = try fs.cwd().openDir(path, .{ .iterate = true });
        return .{
            .dir = dir,
            .iterator = dir.iterate(),
        };
    }

    pub fn next(self: *DirIterator) ?[]const u8 {
        const entry = self.iterator.next() catch {
            return null;
        };

        if (entry) |e| {
            return e.name;
        }
        return null;
    }

    pub fn destroy(self: *DirIterator) void {
        self.dir.close();
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

        pub fn getComponentByName(entity: entities.Entity, name: []const u8) ?*T {
            // Only works for component types with names
            if (!@hasField(T, "name")) {
                return null;
            }

            var it = entity.getComponents(T);
            while (it.next()) |c| {
                const ptr: *T = @ptrCast(@alignCast(c.impl_ptr));
                if (std.mem.eql(u8, name, ptr.name.get())) {
                    return ptr;
                }
            }

            return null;
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

    delve.debug.info("Calling global lua function '{s}'", .{name});

    // Get the function to call, and push it onto the stack
    _ = lua.getGlobal(name) catch {
        delve.debug.warning("Could not get global '{s}'", .{name});
        return;
    };

    // Now call it
    try callLuaFunctionOnStack(args);
}

pub fn callLuaFunctionOnStack(args: anytype) !void {
    const lua = delve.scripting.lua.getLua();

    if (!lua.isFunction(-1)) {
        delve.debug.warning("Top of stack is not a function in Lua!", .{});
        return;
    }

    // Keep track of how much we are pushing onto the Lua stack
    var count: i32 = 0;

    // Should be an struct tuple, push each field
    const T = @TypeOf(args);
    switch (@typeInfo(T)) {
        .@"struct" => |info| {
            if (!info.is_tuple) {
                @compileError("callLuaFunction: Expected struct tuple!");
            }

            inline for (info.fields) |field| {
                const field_val = @field(args, field.name);
                count = count + registry.pushAny(lua, field_val);
            }
        },
        else => {
            @compileError("callLuaFunction: Expected struct tuple!");
        },
    }

    // Call the function!
    _ = try lua.protectedCall(.{ .args = count });
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

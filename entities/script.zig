const std = @import("std");
const delve = @import("delve");
const zlua = @import("zlua");
const entities = @import("../game/entities.zig");
const string = @import("../utils/string.zig");
const scripting = @import("../game/scripting.zig");

const math = delve.math;
const debug = delve.debug;

const Lua = delve.scripting.lua.Lua;

const lua = delve.scripting.lua;
const REGISTRY_INDEX = zlua.registry_index;

// Start at 100 to not collide with other stuff put in the registry
var next_idx: i64 = 100;

pub const ScriptComponent = struct {
    name: string.String = string.empty,
    script: string.String = string.empty,
    scriptIndex: i64 = undefined,

    // interface
    owner: entities.Entity = entities.InvalidEntity,

    pub fn default() @This() {
        return .{};
    }

    pub fn init(self: *ScriptComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;

        // Set our index into the script registry
        self.scriptIndex = next_idx;
        next_idx = next_idx + 1;

        self.runScript();
        self.callFunction("onInit", .{self});
    }

    pub fn deinit(self: *ScriptComponent) void {
        _ = self;
        // self.callFunction("onDeinit", .{self});

        // cleanup here
    }

    pub fn tick(self: *ScriptComponent, delta: f32) void {
        // run onTick on the script here
        self.callFunction("onTick", .{ self, delta });
    }

    pub fn runScript(self: *ScriptComponent) void {
        const luaState = lua.getLua();
        defer luaState.setTop(0);

        const script = "assets/scripts/test_script_component.lua";

        luaState.doFile(script) catch {
            const lua_error = luaState.toString(-1) catch {
                delve.debug.log("Lua: could not get error string", .{});
                return;
            };

            delve.debug.log("Lua: error running file {s}: {s}", .{ script, lua_error });
            return;
        };

        if (!luaState.isTable(-1)) {
            delve.debug.fatal("Lua component run did not return a table!", .{});
        }

        // Use this as our new state table!
        delve.debug.log("LuaComponent creating state table", .{});

        // set the key
        luaState.pushInteger(self.scriptIndex);

        // Copy our new table to use as the value
        luaState.pushValue(-2);

        // registry[scriptIndex] = new table
        // also reset stack

        luaState.setTable(REGISTRY_INDEX);
        luaState.pop(1);
    }

    pub fn callFunction(self: *ScriptComponent, func_name: [:0]const u8, args: anytype) void {
        const luaState = lua.getLua();
        defer luaState.setTop(0);

        if (!luaState.isTable(REGISTRY_INDEX)) {
            delve.debug.log("Registry index is not a table!", .{});
            return;
        }

        // Get the table from the registry keyed by our scriptIndex
        _ = luaState.rawGetIndex(REGISTRY_INDEX, self.scriptIndex);

        // Our table might not be created yet!
        if (!luaState.isTable(-1)) {
            delve.debug.log("Our script table has not been created yet!", .{});
            return;
        }

        _ = luaState.getField(-1, func_name);

        if (!luaState.isFunction(-1)) {
            delve.debug.log("No function named {s} in script component!", .{func_name});
            return;
        }

        // Keep track of how much we are pushing onto the Lua stack
        var count: i32 = 0;

        // Pass all args
        // Should be an struct tuple, push each field
        const T = @TypeOf(args);
        switch (@typeInfo(T)) {
            .@"struct" => |info| {
                if (!info.is_tuple) {
                    @compileError("callLuaFunction: Expected struct tuple!");
                }

                inline for (info.fields) |field| {
                    const field_val = @field(args, field.name);
                    count = count + scripting.registry.pushAny(luaState, field_val);
                }
            },
            else => {
                @compileError("callLuaFunction: Expected struct tuple!");
            },
        }

        _ = luaState.protectedCall(.{ .args = count }) catch {
            delve.debug.log("Error inside func {s} in script component", .{func_name});
        };
    }

    // __index is called when Lua gets a value from a table
    pub fn __index(self: *ScriptComponent, luaState: *Lua) i32 {
        const key = luaState.toAny([:0]const u8, -1) catch {
            delve.debug.log("ScriptComponent __newindex could not get key!", .{});
            return 0;
        };

        // For some special values, return our own internal properties
        if (std.mem.eql(u8, key, "owner")) {
            return scripting.registry.pushAny(luaState, self.owner);
        }

        if (!luaState.isTable(zlua.registry_index)) {
            delve.debug.log(" > Registry index is not a table!", .{});
            return 0;
        }

        // Get the table from the registry keyed by our scriptIndex
        _ = luaState.rawGetIndex(zlua.registry_index, self.scriptIndex);

        // Our table might not be created yet!
        if (!luaState.isTable(-1)) {
            return 0;
        }

        // Make a duplicate of the key to index
        luaState.pushValue(2);

        // return registry[scriptIndex][key]
        _ = luaState.getTable(-2);

        if (!luaState.isNil(-1)) {
            return 1;
        }

        // pop the nil value
        luaState.pop(1);

        // fallback to our own metatable so that we can still call bound functions like self:ourFunc()

        // get our own metatable
        luaState.getMetatable(1) catch {
            delve.debug.log("ScriptComponent __index could not get metatable!", .{});
            return 0;
        };

        // push the key again
        luaState.pushValue(2);

        // return metatable[key]
        _ = luaState.getTable(-2);

        return 1;
    }

    // __newindex is called when Lua sets a value in a table
    pub fn __newindex(self: *ScriptComponent, luaState: *Lua) i32 {
        // const key = luaState.toAny([:0]const u8, -2) catch {
        //     delve.debug.log("ScriptComponent __newindex could not get key!", .{});
        //     return 0;
        // };

        // delve.debug.log("Lua set (__newindex)", .{});
        // delve.debug.log(" > Key: {s}", .{key});

        // Copy both the key and value to use as lookups
        luaState.pushValue(-2);
        luaState.pushValue(-1);

        // const val = luaState.toAny([:0]const u8, -1) catch {
        //     delve.debug.log("ScriptComponent __newindex could not get value!", .{});
        //     return 0;
        // };
        // delve.debug.log(" > Val: {s}", .{val});

        const top = luaState.getTop();

        // Get the table from the registry keyed by our scriptIndex
        _ = luaState.rawGetIndex(zlua.registry_index, self.scriptIndex);

        if (!luaState.isTable(-1)) {
            delve.debug.fatal("ScriptComponent __newindex has no state table!!!", .{});
        }

        // Make a duplicate of the key
        luaState.pushValue(2);

        // Make a duplicate of the value
        luaState.pushValue(3);

        // registry[scriptIndex][key] = value
        luaState.setTable(-3);

        // remove the table from the stack
        luaState.pop(1);

        if (top != luaState.getTop()) {
            delve.debug.fatal("Lua binding: leaking stack!", .{});
        }

        return 0;
    }
};

pub fn getComponentStorage(world: *entities.World) *entities.ComponentStorage(ScriptComponent) {
    return world.components.getStorageForType(ScriptComponent) catch {
        delve.debug.fatal("Could not get ScriptComponent storage!", .{});
        return undefined;
    };
}

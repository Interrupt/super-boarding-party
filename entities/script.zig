const std = @import("std");
const delve = @import("delve");
const math = delve.math;
const entities = @import("../game/entities.zig");
const debug = delve.debug;
const string = @import("../utils/string.zig");

const Lua = delve.scripting.lua.Lua;

const lua = delve.scripting.lua;
const REGISTRY_INDEX = -1001000;

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
        self.callFunction("onInit");
    }

    pub fn deinit(self: *ScriptComponent) void {
        _ = self;

        // run onDeinit on the script here
        // cleanup here
    }

    pub fn tick(self: *ScriptComponent, delta: f32) void {
        _ = delta;

        // run onTick on the script here
        self.callFunction("onTick");
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

    pub fn callFunction(self: *ScriptComponent, func_name: [:0]const u8) void {
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

        // Call with ourself as the first argument
        _ = luaState.rawGetIndex(REGISTRY_INDEX, self.scriptIndex);

        _ = luaState.protectedCall(.{ .args = 1 }) catch {
            delve.debug.log("Error inside func {s} in script component", .{func_name});
        };
    }
};

pub fn getComponentStorage(world: *entities.World) *entities.ComponentStorage(ScriptComponent) {
    return world.components.getStorageForType(ScriptComponent) catch {
        delve.debug.fatal("Could not get ScriptComponent storage!", .{});
        return undefined;
    };
}

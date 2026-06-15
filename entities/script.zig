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

pub const MessageListener = struct {
    filter: ?entities.EntityId = null,
    msg: []const u8,
};

pub const ScriptComponent = struct {
    name: string.String = string.empty,
    script: string.String = string.empty,
    scriptIndex: i64 = undefined,

    didLoad: bool = false,
    hasInitFunc: bool = false,
    hasDeinitFunc: bool = false,
    hasTickFunc: bool = false,
    hasFixedTickFunc: bool = false,
    hasOnMessageFunc: bool = false,

    _listeners: [16]?MessageListener = [_]?MessageListener{null} ** 16,

    // interface
    owner: entities.Entity = entities.InvalidEntity,

    pub fn default() @This() {
        return .{};
    }

    pub fn new(name: [:0]const u8, script_path: [:0]const u8) ScriptComponent {
        return ScriptComponent{
            .name = string.String.init(name),
            .script = string.String.init(script_path),
        };
    }

    pub fn init(self: *ScriptComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;

        // Set our index into the script registry
        self.scriptIndex = next_idx;
        next_idx = next_idx + 1;

        self.runScript();
        self.checkLifecycleFuncs();

        if (self.hasInitFunc)
            self.callFunction("onInit", .{self});
    }

    pub fn deinit(self: *ScriptComponent) void {
        // TODO: wire into script lifecycle
        // if (self.hasDeinitFunc)
        // self.callFunction("onDeinit", .{self});

        self.name.deinit();
        self.script.deinit();
    }

    pub fn tick(self: *ScriptComponent, delta: f32) void {
        // run onTick on the script here
        if (self.hasTickFunc)
            self.callFunction("onTick", .{ self, delta });
    }

    pub fn physics_tick(self: *ScriptComponent, delta: f32) void {
        // run onFixedTick on the script here
        if (self.hasFixedTickFunc)
            self.callFunction("onFixedTick", .{ self, delta });
    }

    pub fn runScript(self: *ScriptComponent) void {
        const luaState = lua.getLua();
        defer luaState.setTop(0);

        const script = self.script.get();

        // Convert to [:0]u8
        const allocator = delve.mem.getAllocator();
        const pathZ = allocator.dupeZ(u8, script) catch {
            delve.debug.fatal("Out of memory?", .{});
            return;
        };
        defer allocator.free(pathZ);

        luaState.doFile(pathZ) catch {
            const lua_error = luaState.toString(-1) catch {
                delve.debug.warning("Lua: could not get error string", .{});
                return;
            };

            delve.debug.warning("Lua: error running file '{s}': {s}", .{ script, lua_error });
            return;
        };

        if (!luaState.isTable(-1)) {
            delve.debug.warning("Lua: script component '{s}' did not return a table!", .{script});
            return;
        }

        // Use this as our new state table!
        // registry[scriptIndex] = new table

        // set the key
        luaState.pushInteger(self.scriptIndex);

        // Copy our new table to use as the value
        luaState.pushValue(-2);

        luaState.setTable(REGISTRY_INDEX);

        // also reset stack
        luaState.pop(1);

        // Ready to go!
        self.didLoad = true;
    }

    pub fn checkLifecycleFuncs(self: *ScriptComponent) void {
        if (!self.didLoad)
            return;

        const luaState = lua.getLua();
        defer luaState.setTop(0);

        if (!luaState.isTable(REGISTRY_INDEX)) {
            delve.debug.warning("Registry index is not a table!", .{});
            return;
        }

        // Get the table from the registry keyed by our scriptIndex
        _ = luaState.rawGetIndex(REGISTRY_INDEX, self.scriptIndex);

        // Our table might not be created yet!
        if (!luaState.isTable(-1)) {
            delve.debug.warning("Our script table has not been created yet!", .{});
            return;
        }

        // Table on top of stack, can check for lifecycle funcs now
        _ = luaState.getField(-1, "onInit");
        self.hasInitFunc = luaState.isFunction(-1);
        luaState.pop(1);

        _ = luaState.getField(-1, "onTick");
        self.hasTickFunc = luaState.isFunction(-1);
        luaState.pop(1);

        _ = luaState.getField(-1, "onFixedTick");
        self.hasFixedTickFunc = luaState.isFunction(-1);
        luaState.pop(1);

        _ = luaState.getField(-1, "onDeinit");
        self.hasDeinitFunc = luaState.isFunction(-1);
        luaState.pop(1);

        _ = luaState.getField(-1, "onMessage");
        self.hasOnMessageFunc = luaState.isFunction(-1);
        luaState.pop(1);
    }

    pub fn callFunction(self: *ScriptComponent, func_name: [:0]const u8, args: anytype) void {
        if (!self.didLoad)
            return;

        const luaState = lua.getLua();
        defer luaState.setTop(0);

        if (!luaState.isTable(REGISTRY_INDEX)) {
            delve.debug.warning("Registry index is not a table!", .{});
            return;
        }

        // Get the table from the registry keyed by our scriptIndex
        _ = luaState.rawGetIndex(REGISTRY_INDEX, self.scriptIndex);

        // Our table might not be created yet!
        if (!luaState.isTable(-1)) {
            delve.debug.warning("Our script table has not been created yet!", .{});
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
        if (!self.didLoad)
            return 0;

        const key = luaState.toAny([:0]const u8, -1) catch {
            delve.debug.warning("ScriptComponent __newindex could not get key!", .{});
            return 0;
        };

        // For some special values, return our own internal properties
        if (std.mem.eql(u8, key, "owner")) {
            return scripting.registry.pushAny(luaState, self.owner);
        }

        if (!luaState.isTable(zlua.registry_index)) {
            delve.debug.warning(" > Registry index is not a table!", .{});
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
        delve.debug.log("Checking internally", .{});

        // get our own metatable
        luaState.getMetatable(1) catch {
            delve.debug.warning("ScriptComponent __index could not get metatable!", .{});
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
        if (!self.didLoad)
            return 0;

        // Copy both the key and value to use as lookups
        luaState.pushValue(-2);
        luaState.pushValue(-1);

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

    pub fn listenForMessage(self: *ScriptComponent, filter: ?entities.EntityId, msg: []const u8) void {
        delve.debug.log("Listening for message '{s}' with filter '{?}'", .{ msg, filter });

        for (self._listeners, 0..) |val, idx| {
            if (val == null) {
                self._listeners[idx] = MessageListener{
                    .filter = filter,
                    .msg = msg,
                };
                return;
            }
        }

        delve.debug.warning("No more listeners available for Script Component!", .{});
    }

    pub fn _handleMessage(self: *ScriptComponent, filter: ?entities.EntityId, msg: []const u8, body: anytype) bool {
        if (!self.hasOnMessageFunc)
            return false;

        for (self._listeners) |val_opt| {
            if (val_opt) |val| {
                if (filter != null and val.filter != null and val.filter.? != filter) {
                    return false;
                }
                if (std.mem.eql(u8, msg, val.msg)) {
                    self.callFunction("onMessage", .{ self, filter, msg, body });
                    return true;
                }
            }
        }

        return false;
    }
};

pub fn getComponentStorage(world: *entities.World) *entities.ComponentStorage(ScriptComponent) {
    return world.components.getStorageForType(ScriptComponent) catch {
        delve.debug.fatal("Could not get ScriptComponent storage!", .{});
        return undefined;
    };
}

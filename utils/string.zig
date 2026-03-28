const std = @import("std");
const delve = @import("delve");

const Lua = delve.scripting.lua.Lua;
const ArrayList = @import("arraylist.zig").ArrayList;

var string_debug_list: ?ArrayList(String) = null;
var debug_init_count: usize = 0;

var next_string_id: usize = 1;

// "" constant
const empty_str: []const u8 = &[_]u8{};

pub const StringStorage = struct {
    allocator: std.mem.Allocator = undefined,
    str: []u8 = &.{},
    len: usize = 0,
    num: usize = 0,
    id: usize = 0,
    freed: bool = false,
};

/// Helper for a string that owns its memory
pub const String = struct {
    is_set: bool = false,
    storage: *StringStorage = undefined,

    pub fn init(string: []const u8) String {
        return initA(string, delve.mem.getAllocator());
    }

    pub fn initA(string: []const u8, allocator: std.mem.Allocator) String {
        if (string.len == 0)
            return empty;

        const new_buffer = allocator.alloc(u8, string.len) catch {
            // Nothing we can do in this case if we ran out of memory, fatal!
            delve.debug.fatal("Could not init new string!", .{});
            return empty;
        };

        const new_storage = allocator.create(StringStorage) catch {
            delve.debug.fatal("Could not init new string!", .{});
            return empty;
        };

        new_storage.allocator = allocator;
        new_storage.str = new_buffer;
        new_storage.len = string.len;
        new_storage.num = debug_init_count + 1;
        new_storage.id = next_string_id;

        next_string_id = next_string_id + 1;

        debug_init_count += 1;

        @memcpy(new_buffer, string);

        const str: String = .{
            .storage = new_storage,
            .is_set = true,
        };

        if (string_debug_list == null) {
            string_debug_list = ArrayList(String).init(delve.mem.getAllocator());
        }

        if (string_debug_list) |*list| {
            list.append(str) catch {
                delve.debug.fatal("Could not make string_debug_list!", .{});
                return empty;
            };
        }

        // delve.debug.log("New string {d}: '{s}'", .{ new_storage.id, string });
        return str;
    }

    pub fn set(self: *String, string: []const u8) void {
        if (!self.is_set) {
            delve.debug.warning("Cannot set constant string!", .{});
            return;
        }

        if (self.storage.freed) {
            delve.debug.warning("String {d} was already freed!", .{self.storage.id});
        }

        if (self.storage.len > 0 and self.storage.str.len == string.len) {
            for (string, 0..) |c, idx| {
                self.storage.str[idx] = c;
            }
            return;
        }

        // Nothing we can do if we run out of memory, this is fatal!
        if (self.storage.len > 0) {
            if (string.len > 0) {
                self.storage.str = self.storage.allocator.realloc(self.storage.str, string.len) catch {
                    delve.debug.fatal("Could not realloc string!", .{});
                    return;
                };
            } else {
                self.storage.allocator.free(self.storage.str);
                self.storage.freed = true;
                self.storage.len = 0;
            }
        } else {
            self.storage.str = self.storage.allocator.alloc(u8, string.len) catch {
                delve.debug.fatal("Could not alloc string!", .{});
                return;
            };
        }

        self.storage.len = string.len;
        if (string.len == 0)
            return;

        @memcpy(self.storage.str, string);
    }

    pub fn get(self: *const String) []const u8 {
        if (!self.is_set)
            return empty_str;

        return self.storage.str;
    }

    pub fn len(self: *const String) usize {
        if (!self.is_set)
            return 0;

        return self.storage.len;
    }

    pub fn toOwnedString(self: *String, allocator: std.mem.Allocator) ![]u8 {
        var str = ArrayList(u8).init(allocator);
        try str.appendSlice(self.get());
        return try str.toOwnedSlice();
    }

    pub fn deinit(self: *String) void {
        // delve.debug.log("Deinit string: {s}", .{self.str});
        if (self.len() == 0) {
            return;
        }

        self.storage.allocator.free(self.storage.str);

        // keep track that we've been cleared for leak checking
        self.storage.str = &.{};
        self.storage.len = 0;
        self.storage.freed = true;
    }

    pub fn jsonStringify(self: *const String, out: anytype) !void {
        try out.write(self.get());
    }

    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
        const str = try std.json.innerParse([]u8, allocator, source, options);

        if (str.len == 0) {
            return empty;
        }

        return String.init(str);
    }

    // Used when called from Lua
    // pub fn destroy(self: *String) void {
    //     self.deinit();
    // }

    // pub fn toLua(self: String, l: *Lua) void {
    //     delve.debug.log("String toLua: {s}", .{self.str});
    //     _ = l.pushString(self.str);
    // }
    //
    // pub fn fromLua(l: *Lua, allocator: ?std.mem.Allocator, i: i32) !String {
    //     _ = allocator;
    //     const val = try l.toString(i);
    //     delve.debug.log("String fromLua: {s}", .{val});
    //     return String.init(val);
    // }

    // pub fn __newindex(self: *String, l: *Lua) i32 {
    //     _ = self;
    //     _ = l;
    //     delve.debug.log("String __newindex", .{});
    //     return 0;
    // }

    // pub fn __index(self: String, l: *Lua) i32 {
    //     _ = self;
    //     _ = l;
    //     return 0;
    // }
};

pub fn init(string: []const u8) String {
    return String.init(string);
}

// effectively just ""
pub const empty: String = .{};

pub fn deinit() void {
    // Check to see if we leaked any strings!
    if (string_debug_list) |*list| {
        for (list.items) |*s| {
            if (s.storage.len > 0) {
                delve.debug.warning("Leaked string '{s}' (idx: {d})", .{ s.storage.str, s.storage.num });
                s.deinit();
            }

            delve.mem.getAllocator().destroy(s.storage);
        }
        list.deinit();
    }
}

/// Fowler–Noll–Vo string hash. ReturnType should be u32/u64
/// From prime31/zig-ecs
pub fn hashString(comptime str: []const u8) u32 {
    comptime var value: u32 = 2166136261;
    comptime {
        const prime: u32 = 16777619;
        for (str) |c| {
            value = (value ^ @as(u32, @intCast(c))) *% prime;
        }
    }
    return value;
}

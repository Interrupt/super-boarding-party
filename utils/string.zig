const std = @import("std");
const delve = @import("delve");

const ArrayList = @import("arraylist.zig").ArrayList;

var string_debug_list: ?ArrayList(String) = null;
var debug_init_count: usize = 0;

pub const StringStorage = struct {
    str: []u8 = &.{},
    len: usize = 0,
    num: usize = 0,
};

/// Helper for a string that owns its memory
pub const String = struct {
    allocator: std.mem.Allocator = undefined,
    str: []u8 = &.{},
    len: usize = 0,

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
        new_storage.str = new_buffer;
        new_storage.len = string.len;
        new_storage.num = debug_init_count + 1;
        debug_init_count += 1;

        @memcpy(new_buffer, string);

        const str: String = .{
            .allocator = allocator,
            .str = new_buffer,
            .len = string.len,
            .storage = new_storage,
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

        return str;
    }

    pub fn set(self: *String, string: []const u8) void {
        if (self.len > 0 and self.str.len == string.len) {
            for (string, 0..) |c, idx| {
                self.str[idx] = c;
            }
            return;
        }

        // Nothing we can do if we run out of memory, this is fatal!
        if (self.len > 0) {
            if (string.len > 0) {
                self.str = self.allocator.realloc(self.str, string.len) catch {
                    delve.debug.fatal("Could not realloc string!", .{});
                    return;
                };
            } else {
                self.allocator.free(self.str);
            }
        } else {
            self.str = self.allocator.alloc(u8, string.len) catch {
                delve.debug.fatal("Could not alloc string!", .{});
                return;
            };
        }

        self.len = string.len;
        if (string.len == 0)
            return;

        @memcpy(self.str, string);

        self.storage.str = self.str;
        self.storage.len = self.len;
    }

    pub fn toOwnedString(self: *String, allocator: std.mem.Allocator) ![]u8 {
        var str = ArrayList(u8).init(allocator);
        try str.appendSlice(self.str);
        return try str.toOwnedSlice();
    }

    pub fn deinit(self: *String) void {
        if (self.len == 0) {
            return;
        }

        self.allocator.free(self.str);
        self.len = 0;
        self.str = &.{};

        // keep track that we've been cleared for leak checking
        self.storage.str = &.{};
        self.storage.len = 0;
    }

    pub fn jsonStringify(self: *const String, out: anytype) !void {
        try out.write(self.str);
    }

    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
        const str = try std.json.innerParse([]u8, allocator, source, options);

        if (str.len == 0) {
            return empty;
        }

        return String.init(str);
    }
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

const std = @import("std");
const delve = @import("delve");

/// Helper for a string that owns its memory
pub const String = struct {
    allocator: std.mem.Allocator = undefined,
    str: []u8 = &.{},
    len: usize = 0,

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

        @memcpy(new_buffer, string);

        return .{
            .allocator = allocator,
            .str = new_buffer,
            .len = string.len,
        };
    }

    pub fn set(self: *String, string: []const u8) void {
        if (self.len > 0 and self.str.len == string.len) {
            // delve.debug.log("String length matches! '{s}' vs '{s}'", .{ self.str, string });
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

        defer delve.debug.log("New string length: {d}, value: {s}", .{ self.len, self.str });
        self.len = string.len;
        if (string.len == 0)
            return;

        @memcpy(self.str, string);
    }

    pub fn toOwnedString(self: *String, allocator: std.mem.Allocator) ![]u8 {
        var str = std.ArrayList(u8).init(allocator);
        try str.appendSlice(self.str);
        return try str.toOwnedSlice();
    }

    pub fn deinit(self: *String) void {
        if (self.len == 0)
            return;

        self.allocator.free(self.str);
        self.len = 0;
        self.str = &.{};
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

const std = @import("std");
const delve = @import("delve");

pub const String = struct {
    allocator: std.mem.Allocator = undefined,
    str: []u8 = &.{},
    len: usize = 0,

    pub fn init(string: []const u8) String {
        if (string.len == 0)
            return empty;

        var allocator = delve.mem.getAllocator();

        const new_buffer = allocator.alloc(u8, string.len) catch {
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

        if (self.len > 0) {
            self.str = self.allocator.realloc(self.str, string.len) catch {
                delve.debug.fatal("Could not realloc string!", .{});
                return;
            };
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

    pub fn deinit(self: *String) void {
        if (self.len == 0)
            return;

        self.allocator.free(self.str);
        self.len = 0;
        self.str = &.{};
    }
};

pub fn init(string: []const u8) String {
    return String.init(string);
}

// effectively just ""
pub const empty: String = .{};

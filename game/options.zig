pub const std = @import("std");

pub var options: Options = .{};

pub const Options = struct {
    sfx_volume: f32 = 1.0,
    music_volume: f32 = 1.0,
};

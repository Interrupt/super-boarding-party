pub const std = @import("std");

pub var options: Options = .{};

pub const Options = struct {
    sfx_volume: f32 = 0.5,
    music_volume: f32 = 0.075,
};

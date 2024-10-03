pub const std = @import("std");
pub const delve = @import("delve");

pub const PlayerComponent = struct {
    time: f32 = 0.0,
    name: []const u8,

    pub fn init(self: *PlayerComponent) void {
        _ = self;
    }

    pub fn deinit(self: *PlayerComponent) void {
        _ = self;
    }

    pub fn tick(self: *PlayerComponent, delta: f32) void {
        self.time += delta;
    }

    pub fn draw(self: *PlayerComponent) void {
        _ = self;
    }
};

pub const std = @import("std");
pub const delve = @import("delve");

pub const QuakeMapComponent = struct {
    time: f32,

    pub fn tick(self: *QuakeMapComponent, delta: f32) void {
        self.time += delta;
        delve.debug.log("Ticked Player Component! {d} {d}", .{ self.time, delta });
    }

    pub fn draw(self: *QuakeMapComponent) void {
        _ = self;
    }
};

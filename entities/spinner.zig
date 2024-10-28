const std = @import("std");
const delve = @import("delve");
const entities = @import("../game/entities.zig");
const math = delve.math;

/// Spins the owner at a constant rate
pub const SpinnerComponent = struct {
    spin_axis: math.Vec3 = math.Vec3.y_axis,
    spin_speed: f32 = 100.0,

    owner: entities.Entity = entities.InvalidEntity,

    pub fn init(self: *SpinnerComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;
    }

    pub fn deinit(self: *SpinnerComponent) void {
        _ = self;
    }

    pub fn tick(self: *SpinnerComponent, delta: f32) void {
        const owner_rot = self.owner.getRotation();
        const our_rot = delve.math.Quaternion.fromAxisAndAngle(delta * self.spin_speed, self.spin_axis);

        // update the rotation with our start rotation, with our new rotation added onto it
        self.owner.setRotation(owner_rot.mul(our_rot));
    }
};

const std = @import("std");
const delve = @import("delve");
const entities = @import("../game/entities.zig");
const options = @import("../game/options.zig");

const math = delve.math;

/// Adds a looping sound to an entity
pub const LoopingSoundComponent = struct {
    // properties
    sound_path: []const u8,
    looping: bool = true,
    volume: f32 = 5.0,
    start_immediately: bool = false,

    // interface
    owner: entities.Entity = entities.InvalidEntity,

    // calculated
    _sound: ?delve.platform.audio.Sound = null,

    pub fn init(self: *LoopingSoundComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;

        self._sound = delve.platform.audio.loadSound("assets/audio/sfx/mover.wav", true) catch {
            return;
        };

        if (self._sound) |*s| {
            s.setVolume(self.volume * options.options.sfx_volume);
            s.setLooping(self.looping);

            if (self.start_immediately) {
                s.start();
            }
        }
    }

    pub fn deinit(self: *LoopingSoundComponent) void {
        self.stop();
    }

    pub fn tick(self: *LoopingSoundComponent, delta: f32) void {
        _ = delta;

        if (self._sound) |*s| {
            const dir = math.Vec3.x_axis;
            const pos = self.owner.getPosition();
            s.setPosition(.{ pos.x * 0.1, pos.y * 0.1, pos.z * 0.1 }, .{ dir.x, dir.y, dir.z }, .{ 1.0, 0.0, 0.0 });
        }
    }

    pub fn stop(self: *LoopingSoundComponent) void {
        if (self._sound) |*s| {
            s.stop();
        }
    }

    pub fn start(self: *LoopingSoundComponent) void {
        if (self._sound) |*s| {
            s.start();
        }
    }

    pub fn setVolume(self: *LoopingSoundComponent, new_volume: f32) void {
        if (self._sound) |*s| {
            s.setVolume(new_volume * options.options.sfx_volume);
            self.volume = new_volume;
        }
    }
};

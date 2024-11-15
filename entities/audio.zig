const std = @import("std");
const delve = @import("delve");
const entities = @import("../game/entities.zig");
const basics = @import("basics.zig");
const monster = @import("monster.zig");
const character = @import("character.zig");
const player = @import("player.zig");
const emitter = @import("particle_emitter.zig");

const math = delve.math;

/// Adds a looping sound to an entity
pub const LoopingSoundComponent = struct {
    // properties
    sound_path: []const u8,
    looping: bool = true,

    // interface
    owner: entities.Entity = entities.InvalidEntity,

    // calculated
    _sound: ?delve.platform.audio.Sound = null,

    pub fn init(self: *LoopingSoundComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;

        self._sound = delve.platform.audio.playSound("assets/audio/sfx/mover.wav", 0.5);
        if (self._sound) |*s| {
            s.setLooping(self.looping);
            s.setVolume(0.0);
        }
    }

    pub fn deinit(self: *LoopingSoundComponent) void {
        _ = self;
    }

    pub fn tick(self: *LoopingSoundComponent, delta: f32) void {
        _ = delta;

        if (self._sound) |*s| {
            const dir = math.Vec3.x_axis;
            const pos = self.owner.getPosition();
            s.setPosition(.{ pos.x * 0.1, pos.y * 0.1, pos.z * 0.1 }, .{ dir.x, dir.y, dir.z }, .{ 1.0, 0.0, 0.0 });
            s.setVolume(self.owner.getVelocity().len() * 0.1);

            if (self.owner.getVelocity().len() <= 0.001) {
                s.stop();
            } else if (!s.getIsPlaying()) {
                s.start();
            }
        }
    }
};

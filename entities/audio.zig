const std = @import("std");
const delve = @import("delve");
const entities = @import("../game/entities.zig");
const options = @import("../game/options.zig");
const main = @import("../main.zig");
const string = @import("../utils/string.zig");

const math = delve.math;

/// Adds a looping sound to an entity
pub const LoopingSoundComponent = struct {
    // properties
    p_sound_path: string.String,
    p_looping: bool = true,
    p_volume: f32 = 5.0,
    p_start_immediately: bool = true,
    p_range: f32 = 75.0,
    p_is_playing: bool = false,

    // interface
    owner: entities.Entity = entities.InvalidEntity,

    // calculated
    _sound: ?delve.platform.audio.Sound = null,

    pub fn init(self: *LoopingSoundComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;

        var new_path: [64]u8 = std.mem.zeroes([64]u8);
        @memcpy(new_path[0..self.p_sound_path.str.len], self.p_sound_path.str);
        const path = new_path[0..self.p_sound_path.str.len :0];

        self._sound = delve.platform.audio.loadSound(path, true) catch {
            delve.debug.warning("Warning: could not load sound '{s}'", .{path});
            return;
        };

        if (self._sound) |*s| {
            s.setVolume(0.0);
            s.setLooping(self.p_looping);

            if (self.p_start_immediately) {
                self.p_is_playing = true;
            }
        }
    }

    pub fn deinit(self: *LoopingSoundComponent) void {
        self.stop();
        self.p_sound_path.deinit();
    }

    pub fn tick(self: *LoopingSoundComponent, delta: f32) void {
        _ = delta;

        if (self._sound) |*s| {
            if (main.game_instance.player_controller) |player| {
                const player_pos = player.getPosition();

                const pos = self.owner.getPosition();

                if (pos.sub(player_pos).len() > self.p_range) {
                    if (s.getIsPlaying()) {
                        s.stop();
                    }
                } else {
                    if (self.p_is_playing and !s.getIsPlaying()) {
                        s.start();
                    }

                    s.setPosition(pos);
                    s.setDistanceRolloff((1.0 / self.p_range) * 35.0);
                    s.setVolume(self.p_volume * options.options.sfx_volume);
                }
            }
        }
    }

    pub fn stop(self: *LoopingSoundComponent) void {
        if (self._sound) |*s| {
            s.stop();
        }
        self.p_is_playing = false;
    }

    pub fn start(self: *LoopingSoundComponent) void {
        if (self._sound) |*s| {
            s.start();
        }
        self.p_is_playing = true;
    }

    pub fn setVolume(self: *LoopingSoundComponent, new_p_volume: f32) void {
        if (self._sound) |*s| {
            s.setVolume(new_p_volume * options.options.sfx_p_volume);
            self.p_volume = new_p_volume;
        }
    }
};

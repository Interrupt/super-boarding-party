const std = @import("std");
const delve = @import("delve");
const triggers = @import("triggers.zig");
const entities = @import("../game/entities.zig");
const options = @import("../game/options.zig");
const main = @import("../main.zig");
const string = @import("../utils/string.zig");

const math = delve.math;

pub const StartMode = enum {
    Immediately,
    Wait,
    OnTrigger,
};

/// Adds a looping sound to an entity
pub const AudioComponent = struct {
    // properties
    sound_path: string.String,
    looping: bool = true,
    volume: f32 = 5.0,
    start_mode: StartMode = .Immediately,
    range: f32 = 75.0,
    is_playing: bool = false,
    delete_owner_when_done: bool = false, // whether to clean up our owning entity when we are done
    did_start: bool = false,

    // interface
    owner: entities.Entity = entities.InvalidEntity,

    // calculated
    _sound: ?delve.platform.audio.Sound = null,

    pub fn init(self: *AudioComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;

        var new_path: [64]u8 = std.mem.zeroes([64]u8);
        @memcpy(new_path[0..self.sound_path.str.len], self.sound_path.str);
        const path = new_path[0..self.sound_path.str.len :0];

        self._sound = delve.platform.audio.loadSound(path, true) catch {
            delve.debug.warning("Warning: could not load sound '{s}'", .{path});
            return;
        };

        if (self._sound) |*s| {
            s.setVolume(0.0);
            s.setLooping(self.looping);

            if (self.start_mode == .Immediately) {
                self.is_playing = true;
            }
        }
    }

    pub fn deinit(self: *AudioComponent) void {
        self.stop();
        self.sound_path.deinit();
    }

    pub fn tick(self: *AudioComponent, delta: f32) void {
        _ = delta;

        if (self._sound) |*s| {
            if (main.game_instance.player_controller) |player| {
                const player_pos = player.getPosition();

                const pos = self.owner.getPosition();

                if (pos.sub(player_pos).len() > self.range) {
                    if (s.getIsPlaying()) {
                        s.stop();
                    }
                } else {
                    if (self.is_playing and !s.getIsPlaying()) {
                        if (self.looping or !self.did_start)
                            s.start();
                    }

                    s.setPosition(pos);
                    s.setDistanceRolloff((1.0 / self.range) * 35.0);
                    s.setVolume(self.volume * options.options.sfx_volume);
                }
            }
        }
    }

    pub fn stop(self: *AudioComponent) void {
        if (self._sound) |*s| {
            s.stop();
        }
        self.is_playing = false;
    }

    pub fn start(self: *AudioComponent) void {
        if (self._sound) |*s| {
            s.start();
        }
        self.is_playing = true;
        self.did_start = true;
    }

    pub fn setVolume(self: *AudioComponent, new_volume: f32) void {
        if (self._sound) |*s| {
            s.setVolume(new_volume * options.options.sfx_volume);
            self.volume = new_volume;
        }
    }

    /// When triggered, start audio
    pub fn onTrigger(self: *AudioComponent, info: triggers.TriggerFireInfo) void {
        _ = info;

        if (self.start_mode != .OnTrigger)
            return;

        delve.debug.log("Audio triggered! '{s}'", .{self.sound_path.str});

        self.did_start = false;
        self.start();
    }
};

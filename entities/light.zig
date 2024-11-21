const std = @import("std");
const delve = @import("delve");
const basics = @import("basics.zig");
const entities = @import("../game/entities.zig");
const math = delve.math;

pub const LightStyle = enum {
    normal,
    flicker_1,
    pulse_slow_1,
    candle_1,
    strobe_fast,
    pulse_gentle,
    flicker_2,
    candle_2,
    candle_3,
    strobe_slow,
    flicker_flouro,
    pulse_slow_2,
};

pub const light_styles: [12][]const u8 = [_][]const u8{
    "m", // 0 normal
    "mmnmmommommnonmmonqnmmo", // 1 FLICKER (first variety)
    "abcdefghijklmnopqrstuvwxyzyxwvutsrqponmlkjihgfedcba", // 2 SLOW STRONG PULSE
    "mmmmmaaaaammmmmaaaaaabcdefgabcdefg", // 3 CANDLE (first variety)
    "mamamamamama", // 4 FAST STROBE
    "jklmnopqrstuvwxyzyxwvutsrqponmlkj", // 5 GENTLE PULSE 1
    "nmonqnmomnmomomno", // 6 FLICKER (second variety)
    "mmmaaaabcdefgmmmmaaaammmaamm", // 7 CANDLE (second variety)
    "mmmaaammmaaammmabcdefaaaammmmabcdefmmmaaaa", // 8 CANDLE (third variety)
    "aaaaaaaazzzzzzzz", // 9 SLOW STROBE (fourth variety)
    "mmamammmmammamamaaamammma", // 10 FLUORESCENT FLICKER
    "abcdefghijklmnopqrrqponmlkjihgfedcba", // 11 SLOW PULSE NOT FADE TO BLACK
};

/// Adds a dynamic light to this entity
pub const LightComponent = struct {
    // properties
    color: delve.colors.Color = delve.colors.white,
    radius: f32 = 4.0,
    brightness: f32 = 1.0,
    is_directional: bool = false,
    is_on: bool = true,

    position: math.Vec3 = math.Vec3.zero,
    position_offset: math.Vec3 = math.Vec3.zero,

    // interface
    owner: entities.Entity = entities.InvalidEntity,

    // calculated
    world_position: math.Vec3 = undefined,
    world_rotation: math.Quaternion = undefined,

    _starting_brightness: f32 = 1.0,

    style: LightStyle = .normal,
    time: f32 = 0.0,

    pub fn init(self: *LightComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;
        self._starting_brightness = self.brightness;
    }

    pub fn deinit(self: *LightComponent) void {
        _ = self;
    }

    pub fn tick(self: *LightComponent, delta: f32) void {
        if (self.style != .normal) {
            // animate our light styles!
            const light_idx: usize = @intFromEnum(self.style);
            const anim_len: f32 = @floatFromInt(light_styles[light_idx].len);
            const t: f32 = @mod(self.time * 10.0, anim_len); // 1 step = 100ms
            const t_idx: usize = @intFromFloat(std.math.floor(t));

            var new_brightness = @as(f32, @floatFromInt(light_styles[light_idx][t_idx] - 'a')) / 12.0;
            new_brightness *= self._starting_brightness;

            if (self.time != 0.0) {
                // Smooth a bit! Decay down faster than building up - HL: Alyx style
                const exp_val: f32 = if (new_brightness > self.brightness) 24.0 else 30.0;
                self.brightness = expDecay(self.brightness, new_brightness, exp_val, delta);
            } else {
                self.brightness = new_brightness;
            }

            self.time += delta;
        }

        if (!self.is_on) {
            self.brightness = 0.0;
        }

        // cache our final world position
        const owner_rotation = self.owner.getRotation();
        self.world_position = self.owner.getPosition().add(owner_rotation.rotateVec3(self.position)).add(self.position_offset);
        self.world_rotation = owner_rotation;
    }

    /// When triggered, toggle light
    pub fn onTrigger(self: *LightComponent, info: basics.TriggerFireInfo) void {
        _ = info;
        self.is_on = !self.is_on;
    }
};

pub fn expDecay(a: f32, b: f32, decay: f32, delta: f32) f32 {
    return b + (a - b) * @exp(-decay * delta);
}

pub fn getComponentStorage(world: *entities.World) *entities.ComponentStorage(LightComponent) {
    return world.components.getStorageForType(LightComponent) catch {
        delve.debug.fatal("Could not get LightComponent storage!", .{});
        return undefined;
    };
}

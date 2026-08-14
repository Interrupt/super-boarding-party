const std = @import("std");
const delve = @import("delve");

const Allocator = std.mem.Allocator;

var allocator: Allocator = undefined;

// Per-period statistics
var stats: std.StringHashMap(f64) = undefined;

// Cumulative counters until sample
var counters: std.StringHashMap(f64) = undefined;

var sample_rate_s: f32 = 1.0;
var time_since_last_sample: f32 = 0.0;
var ticks_since_last_sample: u64 = 0;

var statistics_enabled: bool = false;

pub fn init() void {
    allocator = delve.mem.getAllocator();
    stats = std.StringHashMap(f64).init(allocator);
    counters = std.StringHashMap(f64).init(allocator);
}

pub fn deinit() void {
    stats.deinit();
    counters.deinit();
}

pub fn incrementCounter(name: []const u8, amount: anytype) void {
    const type_info = @typeInfo(@TypeOf(amount));
    const float_amount: f64 = switch (type_info) {
        .int => @floatFromInt(amount),
        .comptime_int => @floatFromInt(amount),
        .float => amount,
        .comptime_float => amount,
        else => @compileError("Can only increment numeric counters"),
    };

    const cur_val = counters.get(name) orelse 0;
    counters.put(name, cur_val + float_amount) catch unreachable;
}

pub fn toggleStatistics() void {
    statistics_enabled = !statistics_enabled;
}

pub fn onTick(delta: f32) void {
    ticks_since_last_sample += 1;
    time_since_last_sample += delta;

    if (time_since_last_sample > sample_rate_s) {
        sample();
    }
}

pub fn sample() void {
    const f32_ticks_since_sample: f32 = @floatFromInt(ticks_since_last_sample);

    if (statistics_enabled) {
        delve.debug.log("Statistics: (ticks: {d})", .{f32_ticks_since_sample});
    }

    var it = counters.iterator();
    while (it.next()) |kv| {
        const total_val = kv.value_ptr.*;
        const stat_val = total_val / f32_ticks_since_sample;

        stats.put(kv.key_ptr.*, stat_val) catch unreachable;
        counters.put(kv.key_ptr.*, 0) catch unreachable;

        if (statistics_enabled) {
            delve.debug.log(" - {s}: {d:.3}", .{ kv.key_ptr.*, stat_val });
        }
    }

    time_since_last_sample = 0.0;
    ticks_since_last_sample = 0;
}

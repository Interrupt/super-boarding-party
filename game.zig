pub const std = @import("std");
pub const delve = @import("delve");
pub const entities = @import("entities.zig");

pub const PlayerComponent = struct {
    time: f32 = 0.0,
    name: []const u8,

    pub fn tick(self: *PlayerComponent, delta: f32) void {
        self.time += delta;
    }
};

pub const GameInstance = struct {
    allocator: std.mem.Allocator,
    game_entities: std.ArrayList(entities.Entity),

    pub fn init(allocator: std.mem.Allocator) GameInstance {
        return .{
            .allocator = allocator,
            .game_entities = std.ArrayList(entities.Entity).init(allocator),
        };
    }

    pub fn start(self: *GameInstance) !void {
        // Create a new player entity
        var player = entities.Entity.init(self.allocator);
        try player.createNewComponent(PlayerComponent, .{ .name = "Player One Start" });

        // Add to the entities list
        try self.game_entities.append(player);
        self.tick(0.1);
        player.deinit();
        self.game_entities.clearRetainingCapacity();
    }

    pub fn tick(self: *GameInstance, delta: f32) void {
        // Tick our entities list
        for (self.game_entities.items) |*e| {
            e.tick(delta);
        }
    }

    pub fn draw(self: *GameInstance) void {
        // Draw our entities
        for (self.game_entities.items) |*e| {
            e.draw();
        }
    }
};

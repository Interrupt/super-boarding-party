pub const std = @import("std");
pub const delve = @import("delve");
pub const entities = @import("entities.zig");
pub const player_component = @import("player.zig");

pub const GameInstance = struct {
    allocator: std.mem.Allocator,
    game_entities: std.ArrayList(entities.Entity),

    pub fn init(allocator: std.mem.Allocator) GameInstance {
        return .{
            .allocator = allocator,
            .game_entities = std.ArrayList(entities.Entity).init(allocator),
        };
    }

    pub fn deinit(self: *GameInstance) void {
        delve.debug.log("Game instance tearing down", .{});
        for (self.game_entities.items) |*e| {
            e.deinit();
        }
        self.game_entities.deinit();
    }

    pub fn start(self: *GameInstance) !void {
        delve.debug.log("Game instance starting", .{});

        // Create a new player entity
        var player = entities.Entity.init(self.allocator);
        try player.createNewSceneComponent(player_component.PlayerComponent, .{ .name = "Player One Start" });

        if(player.getSceneComponent(player_component.PlayerComponent)) |pc_ptr| {
            delve.debug.log("Found scene component! {s}", .{ pc_ptr.name });
            pc_ptr.name = "Test Player Two";
        }

        if(player.getSceneComponent(player_component.PlayerComponent)) |pc_ptr| {
            delve.debug.log("Found scene component! {s}", .{ pc_ptr.name });
        }

        // Add to the entities list
        try self.game_entities.append(player);
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

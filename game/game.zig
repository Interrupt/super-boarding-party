pub const std = @import("std");
pub const delve = @import("delve");
pub const entities = @import("entities.zig");
pub const player = @import("entities/player.zig");
pub const world = @import("entities/world.zig");

pub const GameInstance = struct {
    allocator: std.mem.Allocator,
    game_entities: std.ArrayList(entities.Entity),

    player: *player.PlayerControllerComponent = undefined,

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
        var player_entity = entities.Entity.init(self.allocator);
        const player_comp = try player_entity.createNewSceneComponent(player.PlayerControllerComponent, .{ .name = "Player One Start" });
        try self.game_entities.append(player_entity);

        // save our player component for use later
        self.player = player_comp;

        // Create a new world entity
        // var level = entities.Entity.init(self.allocator);
        // const map_component = try level.createNewSceneComponent(world.QuakeMapComponent, .{ .filename = "assets/testmap.map", .transform = delve.math.Mat4.identity });
        // try self.game_entities.append(level);
        //
        // // set our starting player pos to the map's player start position
        // self.player.state.pos = map_component.player_start;

        // add some more test maps!
        for (0..3) |x| {
            for (0..3) |y| {
                var level_bit = entities.Entity.init(self.allocator);
                const map_component = try level_bit.createNewSceneComponent(world.QuakeMapComponent, .{
                    .filename = "assets/testmap.map",
                    .transform = delve.math.Mat4.translate(
                        delve.math.Vec3.new(55.0 * @as(f32, @floatFromInt(x)), 0.0, 65.0 * @as(f32, @floatFromInt(y))),
                    ),
                });
                // set our starting player pos to the map's player start position
                self.player.state.pos = map_component.player_start;
                try self.game_entities.append(level_bit);
            }
        }
    }

    pub fn tick(self: *GameInstance, delta: f32) void {
        // Tick our entities list
        for (self.game_entities.items) |*e| {
            e.tick(delta);
        }
    }
};

pub const std = @import("std");
pub const delve = @import("delve");
pub const entities = @import("entities.zig");
pub const player = @import("entities/player.zig");
pub const world = @import("entities/world.zig");
pub const sprites = @import("entities/sprite.zig");

pub const GameInstance = struct {
    allocator: std.mem.Allocator,
    game_entities: std.ArrayList(entities.Entity),

    player_controller: ?*player.PlayerControllerComponent = null,

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
        var player_entity = try entities.Entity.init(self.allocator);
        const player_comp = try player_entity.createNewSceneComponent(player.PlayerControllerComponent, .{ .name = "Player One Start" });
        try self.game_entities.append(player_entity);

        // save our player component for use later
        self.player_controller = player_comp;

        // debug tex!
        const texture = delve.platform.graphics.createDebugTexture();

        // add some test maps!
        for (0..3) |x| {
            for (0..3) |y| {
                var level_bit = try entities.Entity.init(self.allocator);
                const map_component = try level_bit.createNewSceneComponent(world.QuakeMapComponent, .{
                    .filename = "assets/testmap.map",
                    .transform = delve.math.Mat4.translate(
                        delve.math.Vec3.new(55.0 * @as(f32, @floatFromInt(x)), 0.0, 65.0 * @as(f32, @floatFromInt(y))),
                    ),
                });

                // set our starting player pos to the map's player start position
                self.player_controller.?.state.pos = map_component.player_start;
                try self.game_entities.append(level_bit);

                // make some test sprites
                var test_sprite = try entities.Entity.init(self.allocator);
                _ = try test_sprite.createNewSceneComponent(sprites.SpriteComponent, .{ .texture = texture, .pos = map_component.player_start, .color = delve.colors.green });
                try self.game_entities.append(test_sprite);

                for(map_component.lights.items) |light| {
                    var light_sprite = try entities.Entity.init(self.allocator);
                    _ = try light_sprite.createNewSceneComponent(sprites.SpriteComponent, .{ .texture = texture, .pos = light.pos, .color = light.color });
                    try self.game_entities.append(light_sprite);
                }
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

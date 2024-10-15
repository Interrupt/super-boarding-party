pub const std = @import("std");
pub const delve = @import("delve");
pub const entities = @import("entities.zig");
pub const player = @import("entities/player.zig");
pub const world = @import("entities/world.zig");
pub const sprites = @import("entities/sprite.zig");

pub const GameInstance = struct {
    allocator: std.mem.Allocator,
    world: entities.World,

    player_controller: ?*player.PlayerControllerComponent = null,

    pub fn init(allocator: std.mem.Allocator) GameInstance {
        return .{
            .allocator = allocator,
            .world = entities.World.init("game", allocator),
        };
    }

    pub fn deinit(self: *GameInstance) void {
        delve.debug.log("Game instance tearing down", .{});
        self.world.deinit();
    }

    pub fn start(self: *GameInstance) !void {
        delve.debug.log("Game instance starting", .{});

        // Create a new player entity
        var player_entity = try self.world.createEntity();
        const player_comp = try player_entity.createNewSceneComponent(player.PlayerControllerComponent, .{ .name = "Player One Start" });

        // save our player component for use later
        self.player_controller = player_comp;

        // debug tex!
        const texture = delve.platform.graphics.createDebugTexture();

        // add some test maps!
        for (0..3) |x| {
            for (0..3) |y| {
                var level_bit = try self.world.createEntity();
                const map_component = try level_bit.createNewSceneComponent(world.QuakeMapComponent, .{
                    .filename = "assets/testmap.map",
                    .transform = delve.math.Mat4.translate(
                        delve.math.Vec3.new(55.0 * @as(f32, @floatFromInt(x)), 0.0, 65.0 * @as(f32, @floatFromInt(y))),
                    ),
                });

                // set our starting player pos to the map's player start position
                self.player_controller.?.state.pos = map_component.player_start;

                // make some test sprites
                var test_sprite = try self.world.createEntity();
                _ = try test_sprite.createNewSceneComponent(sprites.SpriteComponent, .{ .make_test_child = true, .texture = texture, .position = map_component.player_start, .color = delve.colors.green });

                for(map_component.lights.items) |light| {
                    var light_sprite = try self.world.createEntity();
                    _ = try light_sprite.createNewSceneComponent(sprites.SpriteComponent, .{ .make_test_child = true, .texture = texture, .position = light.pos, .color = light.color });
                }
            }
        }
    }

    pub fn tick(self: *GameInstance, delta: f32) void {
        // Tick our entities list
        self.world.tick(delta);
    }
};

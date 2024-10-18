pub const std = @import("std");
pub const delve = @import("delve");
pub const entities = @import("entities.zig");
pub const player = @import("../entities/player.zig");
pub const character = @import("../entities/character.zig");
pub const basics = @import("../entities/basics.zig");
pub const monster = @import("../entities/monster.zig");
pub const quakemap = @import("../entities/quakemap.zig");
pub const sprites = @import("../entities/sprite.zig");

pub const GameInstance = struct {
    allocator: std.mem.Allocator,
    world: *entities.World,

    player_controller: ?*player.PlayerController = null,

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
        _ = try player_entity.createNewComponent(basics.TransformComponent, .{});
        _ = try player_entity.createNewComponent(character.CharacterMovementComponent, .{ .move_speed = 24.0 });
        const player_comp = try player_entity.createNewComponent(player.PlayerController, .{ .name = "Player One Start" });

        // save our player component for use later
        self.player_controller = player_comp;

        // debug tex!
        const texture = delve.platform.graphics.createDebugTexture();

        // add some test maps!
        for (0..3) |x| {
            for (0..3) |y| {
                var level_bit = try self.world.createEntity();
                const map_component = try level_bit.createNewComponent(quakemap.QuakeMapComponent, .{
                    .filename = "assets/testmap.map",
                    .transform = delve.math.Mat4.translate(
                        delve.math.Vec3.new(55.0 * @as(f32, @floatFromInt(x)), 0.0, 65.0 * @as(f32, @floatFromInt(y))),
                    ),
                });

                // set our starting player pos to the map's player start position
                player_entity.setPosition(map_component.player_start);

                // make some test monsters
                for (map_component.lights.items) |light| {
                    var light_sprite = try self.world.createEntity();
                    _ = try light_sprite.createNewComponent(basics.TransformComponent, .{ .position = light.pos });
                    _ = try light_sprite.createNewComponent(character.CharacterMovementComponent, .{});
                    _ = try light_sprite.createNewComponent(monster.MonsterController, .{});
                    _ = try light_sprite.createNewComponent(sprites.SpriteComponent, .{ .texture = texture, .position = delve.math.Vec3.new(0, 0.5, 0) });
                }
            }
        }
    }

    pub fn tick(self: *GameInstance, delta: f32) void {
        // Tick our entities list
        self.world.tick(delta);
    }
};

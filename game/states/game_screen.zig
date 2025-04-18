const std = @import("std");
const delve = @import("delve");
const imgui = delve.imgui;
const basics = @import("../../entities/basics.zig");
const entities = @import("/game/entities.zig");
const game = @import("../game.zig");
const game_states = @import("../game_states.zig");
const main = @import("../../main.zig");

const player = @import("../../entities/player.zig");
const inventory = @import("../../entities/inventory.zig");
const character = @import("../../entities/character.zig");
const box_collision = @import("../../entities/box_collision.zig");
const quakesolids = @import("../../entities/quakesolids.zig");
const mover = @import("../../entities/mover.zig");
const particles = @import("../../entities/particle_emitter.zig");
const options = @import("../options.zig");
const spinner = @import("../../entities/spinner.zig");
const stats = @import("../../entities/actor_stats.zig");
const weapons = @import("../../entities/weapon.zig");
const quakemap = @import("../../entities/quakemap.zig");

const string = @import("../../utils/string.zig");

pub const GameScreen = struct {
    owner: *game.GameInstance = undefined,

    pub fn init(game_instance: *game.GameInstance) !game_states.GameState {
        const game_screen: *GameScreen = try delve.mem.getAllocator().create(GameScreen);
        game_screen.owner = game_instance;

        return .{
            .impl_ptr = game_screen,
            .typename = @typeName(@This()),
            ._interface_on_start = onStart,
            ._interface_tick = tick,
            ._interface_deinit = deinit,
        };
    }

    pub fn onStart(self_impl: *anyopaque, game_instance: *game.GameInstance) !void {
        _ = self_impl;

        delve.debug.log("----- Game Screen Starting! ------", .{});
        var world = game_instance.world;

        // Start fresh!
        world.clearEntities();

        // Create a new player entity
        var player_entity = try world.createEntity(.{});
        _ = try player_entity.createNewComponent(basics.TransformComponent, .{});
        _ = try player_entity.createNewComponent(character.CharacterMovementComponent, .{});
        const player_comp = try player_entity.createNewComponent(player.PlayerController, .{});
        _ = try player_entity.createNewComponent(inventory.InventoryComponent, .{});
        _ = try player_entity.createNewComponent(box_collision.BoxCollisionComponent, .{});
        _ = try player_entity.createNewComponent(stats.ActorStats, .{ .hp = 100, .speed = 12 });

        // start with the pistol equipped
        // player_comp.switchWeapon(0);

        // save our player component for use later
        game_instance.player_controller = player_comp;

        // add the starting map
        {
            var level_bit = try world.createEntity(.{});
            const map_component = try level_bit.createNewComponent(quakemap.QuakeMapComponent, .{
                .filename = string.init("assets/test.map"),
                // .filename = string.init("assets/levels/starts/1.map"),
                .transform = delve.math.Mat4.translate(delve.math.Vec3.zero),
            });

            // set our starting player pos to the map's player start position
            player_entity.setPosition(map_component.player_start.pos);
            game_instance.player_controller.?.camera.yaw_angle = map_component.player_start.angle - 90;
        }

        // play music!
        game_instance.music = delve.platform.audio.playSound("assets/audio/music/WhiteWolf-Digital-era.mp3", .{
            .volume = options.options.music_volume * 0.5,
            .stream = true,
            .loop = true,
        });
    }

    pub fn tick(self_impl: *anyopaque, delta: f32) void {
        const self = @as(*GameScreen, @ptrCast(@alignCast(self_impl)));
        _ = delta;

        // if we're dead, restart the game!
        if (!self.owner.player_controller.?.isAlive()) {
            delve.debug.log("Player died! Restarting game.", .{});
            onStart(self, self.owner) catch {
                delve.debug.log("Could not restart game!", .{});
                return;
            };
        }
    }

    pub fn deinit(self_impl: *anyopaque) void {
        const self = @as(*GameScreen, @ptrCast(@alignCast(self_impl)));
        delve.mem.getAllocator().destroy(self);
    }
};

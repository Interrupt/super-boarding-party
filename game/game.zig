pub const std = @import("std");
pub const delve = @import("delve");
pub const entities = @import("entities.zig");
pub const basics = @import("../entities/basics.zig");
pub const player = @import("../entities/player.zig");
pub const character = @import("../entities/character.zig");
pub const box_collision = @import("../entities/box_collision.zig");
pub const quakesolids = @import("../entities/quakesolids.zig");
pub const mover = @import("../entities/mover.zig");
pub const options = @import("options.zig");
pub const spinner = @import("../entities/spinner.zig");
pub const stats = @import("../entities/actor_stats.zig");
pub const quakemap = @import("../entities/quakemap.zig");

pub const GameInstance = struct {
    allocator: std.mem.Allocator,
    world: *entities.World,

    player_controller: ?*player.PlayerController = null,
    music: ?delve.platform.audio.Sound = null,

    time: f64 = 0.0,

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

        // debug tex!
        // const texture = delve.platform.graphics.createDebugTexture();

        // Create a new player entity
        var player_entity = try self.world.createEntity(.{});
        _ = try player_entity.createNewComponent(basics.TransformComponent, .{});
        _ = try player_entity.createNewComponent(character.CharacterMovementComponent, .{});
        const player_comp = try player_entity.createNewComponent(player.PlayerController, .{ .name = "Player One Start" });
        _ = try player_entity.createNewComponent(box_collision.BoxCollisionComponent, .{});
        _ = try player_entity.createNewComponent(stats.ActorStats, .{ .hp = 100, .speed = 24 });

        // save our player component for use later
        self.player_controller = player_comp;

        // add some test maps!
        for (0..1) |x| {
            for (0..1) |y| {
                var level_bit = try self.world.createEntity(.{});
                const map_component = try level_bit.createNewComponent(quakemap.QuakeMapComponent, .{
                    .filename = "assets/E1M1.map",
                    .transform = delve.math.Mat4.translate(
                        delve.math.Vec3.new(55.0 * @as(f32, @floatFromInt(x)), 0.0, 65.0 * @as(f32, @floatFromInt(y))),
                    ),
                });

                // set our starting player pos to the map's player start position
                player_entity.setPosition(map_component.player_start);
            }
        }

        // play music!
        self.music = delve.platform.audio.playMusic("assets/audio/music/WhiteWolf-Digital-era.mp3", options.options.music_volume, true);
    }

    pub fn tick(self: *GameInstance, delta: f32) void {
        // Tick our entities list
        self.world.tick(delta);
        self.time += @floatCast(delta);

        if (self.music) |*m| {
            if (self.player_controller) |p| {
                const player_dir = p.camera.direction;
                const player_pos = p.camera.position.add(player_dir.scale(-1));
                m.setPosition(.{ player_pos.x * 0.1, player_pos.y * 0.1, player_pos.z * 0.1 }, .{ player_dir.x, player_dir.y, player_dir.z }, .{ 0.0, 0.0, 0.0 });
            }
        }

        if (delve.platform.input.isKeyJustPressed(.L)) {
            if (self.player_controller) |p| {
                self.addMapCheat("assets/testmap.map", p.getPosition().add(p.camera.direction.scale(50))) catch {
                    return;
                };
            }
        }

        if (delve.platform.input.isKeyJustPressed(.K)) {
            self.saveGame("test_save_game.json") catch |e| {
                delve.debug.warning("Could not write save game to json! {any}", .{e});
            };
        }
    }

    // Physics tick at a fixed rate
    pub fn physics_tick(self: *GameInstance, delta: f32) void {
        box_collision.updateSpatialHash(self.world);
        quakesolids.updateSpatialHash(self.world);

        // Tick our entities for physics
        self.world.physics_tick(delta);
    }

    pub fn saveGame(self: *GameInstance, file_path: []const u8) !void {
        const file = try std.fs.cwd().createFile(file_path, .{});
        defer file.close();

        try std.json.stringify(.{ .game = self }, .{}, file.writer());
    }

    pub fn jsonStringify(self: GameInstance, out: anytype) !void {
        _ = self;
        const json: []const u8 = "hello world 2";
        return out.write(json);
    }

    /// Cheat to test streaming in a map
    pub fn addMapCheat(self: *GameInstance, filename: []const u8, location: delve.math.Vec3) !void {
        var level_bit = try self.world.createEntity(.{});
        _ = try level_bit.createNewComponent(quakemap.QuakeMapComponent, .{
            .filename = filename,
            .transform = delve.math.Mat4.translate(location),
        });
    }
};

const std = @import("std");
const delve = @import("delve");
const entities = @import("entities.zig");
const game_states = @import("game_states.zig");
const basics = @import("../entities/basics.zig");
const player = @import("../entities/player.zig");
const inventory = @import("../entities/inventory.zig");
const character = @import("../entities/character.zig");
const box_collision = @import("../entities/box_collision.zig");
const quakesolids = @import("../entities/quakesolids.zig");
const mover = @import("../entities/mover.zig");
const particles = @import("../entities/particle_emitter.zig");
const options = @import("options.zig");
const spinner = @import("../entities/spinner.zig");
const stats = @import("../entities/actor_stats.zig");
const weapons = @import("../entities/weapon.zig");
const quakemap = @import("../entities/quakemap.zig");
const string = @import("../utils/string.zig");
const title_screen = @import("states/title_screen.zig");
const imgui = delve.imgui;

pub const GameInstance = struct {
    allocator: std.mem.Allocator,
    world: *entities.World,
    states: game_states.GameStateStack = .{},

    player_controller: ?*player.PlayerController = null,
    music: ?delve.platform.audio.Sound = null,

    time: f64 = 0.0,

    pub fn init(allocator: std.mem.Allocator) GameInstance {
        // some components have globals that need to be initialized
        box_collision.init();
        particles.init();

        return .{
            .allocator = allocator,
            .world = entities.World.init("game", allocator),
        };
    }

    pub fn deinit(self: *GameInstance) void {
        delve.debug.log("Game instance tearing down", .{});
        self.world.deinit();

        self.states.deinit();

        // some components have globals that need to be cleaned up
        box_collision.deinit();
        particles.deinit();
        quakesolids.deinit();
        quakemap.deinit();
        string.deinit();
    }

    pub fn start(self: *GameInstance) !void {
        delve.debug.log("Game instance starting", .{});

        // debug tex!
        // const texture = delve.platform.graphics.createDebugTexture();

        // Create a new player entity
        var player_entity = try self.world.createEntity(.{});
        _ = try player_entity.createNewComponent(basics.TransformComponent, .{});
        _ = try player_entity.createNewComponent(character.CharacterMovementComponent, .{});
        const player_comp = try player_entity.createNewComponent(player.PlayerController, .{});
        _ = try player_entity.createNewComponent(inventory.InventoryComponent, .{});
        _ = try player_entity.createNewComponent(box_collision.BoxCollisionComponent, .{});
        _ = try player_entity.createNewComponent(stats.ActorStats, .{ .hp = 100, .speed = 12 });

        // start with the pistol equipped
        // player_comp.switchWeapon(0);

        // save our player component for use later
        self.player_controller = player_comp;

        // add the starting map
        {
            var level_bit = try self.world.createEntity(.{});
            const map_component = try level_bit.createNewComponent(quakemap.QuakeMapComponent, .{
                .filename = string.init("assets/test.map"),
                // .filename = string.init("assets/levels/starts/1.map"),
                .transform = delve.math.Mat4.translate(delve.math.Vec3.zero),
            });

            // set our starting player pos to the map's player start position
            player_entity.setPosition(map_component.player_start.pos);
            self.player_controller.?.camera.yaw_angle = map_component.player_start.angle - 90;
        }

        // play music!
        self.music = delve.platform.audio.playSound("assets/audio/music/WhiteWolf-Digital-era.mp3", .{
            .volume = options.options.music_volume * 0.5,
            .stream = true,
            .loop = true,
        });

        const title_scr = try title_screen.TitleScreen.init();
        self.states.setState(title_scr);
    }

    pub fn stop(self: *GameInstance) void {
        delve.debug.log("Game instance stopping", .{});
        self.world.clearEntities();
        self.music.?.stop();
    }

    pub fn tick(self: *GameInstance, delta: f32) void {
        // Tick our entities list
        self.world.tick(delta);
        self.time += @floatCast(delta);

        // TODO: Testing game states
        self.states.tick(delta);

        if (delve.platform.input.isKeyJustPressed(.K)) {
            self.saveGame("test_save_game.json") catch |e| {
                delve.debug.warning("Could not write save game to json! {any}", .{e});
            };
        }
        if (delve.platform.input.isKeyJustPressed(.L)) {
            self.loadGame("test_save_game.json") catch |e| {
                delve.debug.warning("Could not load save game from json! {any}", .{e});
            };
        }

        // if we're dead, restart the game!
        if (!self.player_controller.?.isAlive()) {
            delve.debug.log("Player died! Restarting game.", .{});
            self.stop();
            self.start() catch {
                delve.debug.log("Could not restart game!", .{});
                return;
            };
            return;
        }

        // imgui.igSetNextWindowPos(.{ .x = 40, .y = 180 }, imgui.ImGuiCond_Once, .{ .x = 0, .y = 0 });
        // imgui.igSetNextWindowSize(.{ .x = 400, .y = 100 }, imgui.ImGuiCond_Once);
        // _ = imgui.igBegin("Hello Dear ImGui!", 0, imgui.ImGuiWindowFlags_None);
        // // _ = imgui.igColorEdit3("Background", &bg_color[0], imgui.ImGuiColorEditFlags_None);
        // imgui.igEnd();
    }

    // Physics tick at a fixed rate
    pub fn physics_tick(self: *GameInstance, delta: f32) void {
        box_collision.updateSpatialHash(self.world);
        quakesolids.updateSpatialHash(self.world);

        // Tick our entities for physics
        self.world.physics_tick(delta);

        // particles tick independently
        particles.physics_tick(self.world, delta);
    }

    pub fn saveGame(self: *GameInstance, file_path: []const u8) !void {
        const file = try std.fs.cwd().createFile(file_path, .{});
        defer file.close();

        try std.json.stringify(.{ .game = self }, .{}, file.writer());
    }

    pub fn loadGame(self: *GameInstance, file_path: []const u8) !void {
        _ = self;
        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        var clear_world = entities.getWorld(0);
        clear_world.?.clearEntities();

        const GameSaveEntity = struct {
            id: u32,
            components: []entities.EntityComponent,

            pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, o: std.json.ParseOptions) !@This() {
                const start_token = try source.next();
                if (.object_begin != start_token) return error.UnexpectedToken;

                _ = try source.next();
                const id = try std.json.innerParse(u32, allocator, source, o);
                _ = id;

                _ = try source.next();
                const comps = try std.json.innerParse([]entities.EntityComponent, allocator, source, o);

                const end_token = try source.next();
                if (.object_end != end_token) return error.UnexpectedToken;

                // var entity_id = entities.EntityId.fromInt(id);

                // fixup the world id
                // entity_id.world_id = new_world_id;

                var world = entities.getWorld(0);
                var new_entity = try world.?.createEntity(.{});

                // entities.EntityComponent.entity_being_read = .{ .id = entity_id };
                entities.EntityComponent.entity_being_read = .{ .id = new_entity.id };
                return .{ .id = new_entity.id.toInt(), .components = comps };
            }
        };

        const GameSaveWorld = struct {
            id: u32,
            entities: []GameSaveEntity,
        };

        const GameSave = struct {
            version: u32,
            world: GameSaveWorld,
        };

        const SaveGame = struct {
            game: GameSave,
        };

        const allocator = delve.mem.getAllocator();

        const f = try file.readToEndAlloc(allocator, 100000000);
        defer allocator.free(f);

        const parsedData = try std.json.parseFromSlice(SaveGame, allocator, f, .{ .ignore_unknown_fields = true });
        defer parsedData.deinit();

        // Find our new player controller!
        var e_it = clear_world.?.entities.valueIterator();
        while (e_it.next()) |e| {
            if (e.getComponent(player.PlayerController)) |found| {
                delve.debug.log("Found new player controller! {d}", .{found.owner.id.id});
                // @import("../main.zig").game_instance.player_controller = found;
            }
        }

        // call our post load function
        e_it = clear_world.?.entities.valueIterator();
        while (e_it.next()) |e| {
            e.post_load();
        }

        delve.debug.log("Done loading from json", .{});
    }

    /// Cheat to test streaming in a map
    pub fn addMapCheat(self: *GameInstance, filename: []const u8, location: delve.math.Vec3) !void {
        var level_bit = try self.world.createEntity(.{});
        _ = try level_bit.createNewComponent(quakemap.QuakeMapComponent, .{
            .filename = string.init(filename),
            .transform = delve.math.Mat4.translate(location),
        });
    }

    pub fn giveAllCheat(self: *GameInstance) !void {
        const player_c = self.player_controller.?;
        if (player_c.owner.getComponent(inventory.InventoryComponent)) |inv| {
            inv.addAllWeapons();
        }
    }

    pub fn jsonStringify(self: *const GameInstance, out: anytype) !void {
        try out.beginObject();

        try out.objectField("version");
        try out.write(1);

        try out.objectField("world");
        try out.write(self.world);

        try out.endObject();
    }
};

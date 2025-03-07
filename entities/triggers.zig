const std = @import("std");
const delve = @import("delve");
const entities = @import("../game/entities.zig");
const main = @import("../main.zig");
const audio = @import("audio.zig");
const basics = @import("basics.zig");
const explosion = @import("explosion.zig");
const mover = @import("mover.zig");
const lights = @import("light.zig");
const quakesolids = @import("quakesolids.zig");
const string = @import("../utils/string.zig");
const box_collision = @import("box_collision.zig");
const breakables = @import("breakable.zig");
const math = delve.math;

pub const TriggerFireInfo = struct {
    value: []const u8 = "",
    instigator: ?entities.Entity,
    from_path_node: bool = false,
};

pub const TriggerState = enum {
    IDLE,
    WAITING_BEFORE_FIRE, // some triggers have a delay before
    WAITING_AFTER_FIRE, // some triggers have a wait time after triggering before triggering again
    DONE, // some triggers only fire once!
};

pub const TriggerType = enum {
    BASIC,
    TELEPORT,
    COUNTER,
    CHANGE_LEVEL,
};

/// Allows this entity to trigger others
pub const TriggerComponent = struct {
    // properties
    trigger_type: TriggerType = .BASIC,
    target: string.String, // target entity to trigger
    value: string.String = string.empty, // value to pass along to target
    killtarget: string.String = string.empty, // target to kill, or for a trigger will disable it
    is_path_node: bool = false, // whether this trigger is actually a path node
    message: string.String = string.empty, // message to show when firing
    delay: f32 = 0.0, // time to wait before firing
    wait: f32 = 0.0, // time to wait between firing
    is_disabled: bool = false, // whether this trigger can be fired
    play_sound: bool = false,
    is_volume: bool = false,
    is_secret: bool = false,
    only_once: bool = false,
    trigger_on_damage: bool = false,
    trigger_count: i32 = 0,
    change_map_target: string.String = string.empty,
    screen_shake_amt: f32 = 0.0,

    // calculated
    state: TriggerState = .IDLE,
    timer: f32 = 0.0,
    fire_info: ?TriggerFireInfo = null,
    counter: i32 = 0,

    // interface
    owner: entities.Entity = entities.InvalidEntity,

    pub fn init(self: *TriggerComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;

        delve.debug.info("Creating trigger targeting '{s}' with value '{s}'", .{ self.target.str, self.value.str });
    }

    pub fn deinit(self: *TriggerComponent) void {
        // cleanup strings
        self.target.deinit();
        self.value.deinit();
        self.killtarget.deinit();
        self.message.deinit();
        self.change_map_target.deinit();
    }

    pub fn tick(self: *TriggerComponent, delta: f32) void {
        // when waiting to fire, tick our timer
        if (self.state == .WAITING_BEFORE_FIRE) {
            self.timer += delta;
            if (self.timer >= self.delay) {
                self.fire(self.fire_info);
            }
        } else if (self.state == .WAITING_AFTER_FIRE) {
            self.timer += delta;
            if (self.timer >= self.delay + self.wait) {
                self.state = .IDLE;
                self.timer = 0.0;
            }
        }

        // Only check for trigger collisions when we are idle
        if (self.state != .IDLE)
            return;

        // If we are a volume, check if the player is touching us
        if (self.is_volume) {
            if (main.game_instance.player_controller == null)
                return;
            const player = main.game_instance.player_controller.?;

            if (self.owner.getComponent(quakesolids.QuakeSolidsComponent)) |solid| {
                if (solid.checkCollision(player.getPosition(), player.getSize())) {
                    // touching! start the trigger process
                    self.onTrigger(.{ .instigator = player.owner });
                }
            }
        }
    }

    /// Fires the trigger, triggering its target and passing on the value
    pub fn fire(self: *TriggerComponent, triggered_by: ?TriggerFireInfo) void {
        // reset trigger state for next time
        if (self.only_once) {
            self.state = .DONE;
        } else if (self.wait == 0.0) {
            self.state = .IDLE;
            self.timer = 0.0;
        } else {
            self.state = .WAITING_AFTER_FIRE;
        }

        const world_opt = entities.getWorld(self.owner.getWorldId());
        if (world_opt == null)
            return;

        self.playSound();

        // If we are disabled, don't actually fire.
        if (self.is_disabled) {
            return;
        }

        const world = world_opt.?;
        var value: []const u8 = self.value.str;

        if (main.game_instance.player_controller) |player| {
            if (self.message.len > 0) {
                player.showMessage(self.message.str);
            }
            if (self.screen_shake_amt > 0.0) {
                player.shakeCamera(self.screen_shake_amt, 0.0);
            }
        }

        // If we are a path node, pass on the entity that triggered us
        if (self.is_path_node and triggered_by != null and triggered_by.?.instigator != null) {
            delve.debug.log("Path Node triggered, path node has value '{s}'", .{value});

            if (value.len == 0 or value.len > 0 and value[0] == 0)
                value = self.target.str;

            if (triggered_by.?.instigator) |instigator| {
                // Check for any components that can trigger
                if (instigator.getComponent(mover.MoverComponent)) |mc| {
                    mc.onTrigger(.{ .value = value, .instigator = self.owner, .from_path_node = true });
                } else if (instigator.getComponent(TriggerComponent)) |tc| {
                    tc.onTrigger(.{ .value = value, .instigator = self.owner, .from_path_node = true });
                }
                return;
            }
        }

        // If we were triggered by something else, pass on that value instead
        // For func_elevator!
        if (triggered_by != null)
            value = triggered_by.?.value;

        delve.debug.log("Trigger fired - target is '{s}'", .{self.target.str});

        var should_fire_trigger: bool = false;

        switch (self.trigger_type) {
            .BASIC => {
                should_fire_trigger = self.target.str.len > 0;
            },
            .TELEPORT => {
                if (triggered_by) |by| {
                    if (by.instigator) |instigator| {
                        const target_entities_opt = world.getEntitiesByName(self.target.str);
                        if (target_entities_opt) |target_entities| {
                            for (target_entities.items) |found_entity_id| {
                                if (world.getEntity(found_entity_id)) |tele_dest| {
                                    instigator.setPosition(tele_dest.getPosition().add(math.Vec3.y_axis.scale(2.0)));
                                    break;
                                }
                            }
                        }
                    }
                }
            },
            .COUNTER => {
                if (self.counter < self.trigger_count) {
                    self.counter += 1;
                    delve.debug.log("Counter trigger incrementing count to '{d}'", .{self.counter});

                    if (self.counter != self.trigger_count) {
                        if (main.game_instance.player_controller) |player| {
                            var counter_buffer: [64]u8 = std.mem.zeroes([64]u8);
                            _ = std.fmt.bufPrint(&counter_buffer, "Only {d} more to go...", .{self.trigger_count - self.counter}) catch {
                                return;
                            };
                            player.showMessage(&counter_buffer);
                        }
                    }

                    // are we done now?
                    if (self.counter == self.trigger_count) {
                        should_fire_trigger = true;
                        self.state = .DONE;

                        if (main.game_instance.player_controller) |player| {
                            player.showMessage("Sequence complete!");
                        }
                    }
                }
            },
            .CHANGE_LEVEL => {
                if (main.game_instance.player_controller) |player| {
                    var msg_buffer: [128]u8 = std.mem.zeroes([128]u8);
                    _ = std.fmt.bufPrint(&msg_buffer, "Level change triggered, new map is {s}", .{self.change_map_target.str}) catch {
                        return;
                    };
                    player.showMessage(&msg_buffer);
                    self.state = .DONE;
                }
            },
        }

        if (!should_fire_trigger)
            return;

        // Get our target entities!
        const target_entities_opt = world.getEntitiesByName(self.target.str);
        if (target_entities_opt) |target_entities| {
            for (target_entities.items) |found_entity_id| {
                if (world.getEntity(found_entity_id)) |to_trigger| {
                    // Check for any components that can trigger
                    if (to_trigger.getComponent(mover.MoverComponent)) |mc| {
                        mc.onTrigger(.{ .value = value, .instigator = self.owner, .from_path_node = self.is_path_node });
                    } else if (to_trigger.getComponent(breakables.BreakableComponent)) |bc| {
                        bc.onTrigger(.{ .value = value, .instigator = self.owner, .from_path_node = self.is_path_node });
                    } else if (to_trigger.getComponent(TriggerComponent)) |tc| {
                        tc.onTrigger(.{ .value = value, .instigator = self.owner, .from_path_node = self.is_path_node });
                    } else if (to_trigger.getComponent(lights.LightComponent)) |lc| {
                        lc.onTrigger(.{ .value = value, .instigator = self.owner, .from_path_node = self.is_path_node });
                    } else if (to_trigger.getComponent(explosion.ExplosionComponent)) |ec| {
                        ec.onTrigger(.{ .value = value, .instigator = self.owner, .from_path_node = self.is_path_node });
                    } else if (to_trigger.getComponent(audio.AudioComponent)) |ac| {
                        ac.onTrigger(.{ .value = value, .instigator = self.owner, .from_path_node = self.is_path_node });
                    }
                } else {
                    delve.debug.log("Could not find entity '{s}' len {d}!", .{ self.target.str, self.target.str.len });
                }
            }
        }

        // kill any entities marked for death
        if (self.killtarget.len > 0) {
            const killtarget_entities_opt = world.getEntitiesByName(self.killtarget.str);
            if (killtarget_entities_opt) |killtarget_entities| {
                for (killtarget_entities.items) |found_entity_id| {
                    delve.debug.log("Trigger killing entity: '{s}'", .{self.killtarget.str});
                    if (world.getEntity(found_entity_id)) |to_kill| {
                        to_kill.deinit();
                    }
                }
            }
        }
    }

    /// Runs when the trigger was triggered by something
    pub fn onTrigger(self: *TriggerComponent, info: ?TriggerFireInfo) void {
        const value = if (info != null) info.?.value else "";
        delve.debug.info("Trigger {any} triggered with value '{s}'", .{ self.trigger_type, value });

        if (self.state != .IDLE) {
            delve.debug.info("Trigger is not idle, skipping this fire", .{});
            return;
        }

        if (self.delay > 0.0) {
            delve.debug.info("Trigger is delaying {d:3} seconds to fire", .{self.delay});
            self.timer = 0.0;
            self.state = .WAITING_BEFORE_FIRE;
            self.fire_info = info;
            return;
        }

        // not waiting, fire immediately!
        self.fire(info);
    }

    pub fn playSound(self: *TriggerComponent) void {
        if (!self.play_sound)
            return;

        const path: [:0]const u8 = if (self.is_secret) "assets/audio/sfx/secret-found.mp3" else if (!self.is_disabled) "assets/audio/sfx/button-beep.wav" else "assets/audio/sfx/button-disabled.mp3";
        var s = delve.platform.audio.loadSound(path, false) catch {
            return;
        };

        const pos = self.owner.getPosition();
        s.setPosition(pos);
        s.setDistanceRolloff(0.1);
        s.start();
    }
};

const std = @import("std");
const delve = @import("delve");
const basics = @import("basics.zig");
const collision = @import("../utils/collision.zig");
const entities = @import("../game/entities.zig");
const box_collision = @import("box_collision.zig");
const character = @import("character.zig");
const quakemap = @import("quakemap.zig");
const sprite = @import("sprite.zig");
const spritesheets = @import("../managers/spritesheets.zig");
const mover = @import("mover.zig");
const triggers = @import("triggers.zig");
const emitter = @import("particle_emitter.zig");
const inventory = @import("inventory.zig");
const stats = @import("actor_stats.zig");
const weapon = @import("weapon.zig");
const string = @import("../utils/string.zig");
const lights = @import("light.zig");
const main = @import("../main.zig");
const options = @import("../game/options.zig");

const math = delve.math;
const interpolation = delve.utils.interpolation;

pub var jump_acceleration: f32 = 20.0;

var rand = std.rand.DefaultPrng.init(0);

pub const PlayerController = struct {
    name: string.String = string.empty,

    camera: delve.graphics.camera.Camera = undefined,
    eyes_in_water: bool = false,

    weapon_flash_timer: f32 = 0.1,
    weapon_flash_time: f32 = 0.1,

    screen_flash_color: ?delve.colors.Color = delve.colors.red,
    screen_flash_time: f32 = 0.0,
    screen_flash_timer: f32 = 0.0,

    did_init: bool = false,

    owner: entities.Entity = entities.InvalidEntity,

    _player_light: *lights.LightComponent = undefined,
    _msg_time: f32 = 0.0,

    _messages: std.ArrayList([]const u8) = undefined,
    _message: [128]u8 = std.mem.zeroes([128]u8),

    _camera_shake_amt: f32 = 0.0,
    _camera_shake_tilt: f32 = 0.0,
    _camera_shake_tilt_mod: f32 = 1.0,
    _camera_strafe_tilt: f32 = 0.0,

    _last_cam_yaw: f32 = 0.0,
    _last_cam_pitch: f32 = 0.0,
    _cam_yaw_lag_amt: f32 = 0.0,
    _cam_pitch_lag_amt: f32 = 0.0,

    _first_tick: bool = true,

    head_bob_amount: f32 = 0.0,

    pub fn init(self: *PlayerController, interface: entities.EntityComponent) void {
        self.owner = interface.owner;
        defer self.did_init = true;

        // Set a default player name, if none was given!
        if (self.name.len == 0)
            self.name = string.init("PlayerOne");

        if (self.did_init == false) {
            self.camera = delve.graphics.camera.Camera.init(90.0, 0.01, 512, math.Vec3.up);
        }

        delve.debug.log("Init new player controller for entity {d}", .{interface.owner.id.id});

        self._player_light = self.owner.createNewComponentWithConfig(
            lights.LightComponent,
            .{ .persists = false },
            .{
                .color = delve.colors.yellow,
                .radius = 15.0,
                .position = delve.math.Vec3.new(0, 1.0, 0),
                .brightness = 0.8,
            },
        ) catch {
            return;
        };

        self._messages = std.ArrayList([]const u8).init(delve.mem.getAllocator());

        // start with the pistol
        self.switchWeapon(0);
    }

    pub fn deinit(self: *PlayerController) void {
        delve.debug.log("Deinitializing player controller: '{s}'", .{self.name.str});
        self.name.deinit();
    }

    pub fn tick(self: *PlayerController, delta: f32) void {
        const time = delve.platform.app.getTime();
        defer self._first_tick = false;

        // accelerate the player from input
        self.acceleratePlayer(delta);

        // set our basic camera position
        self.camera.position = self.owner.getRenderPosition();

        // camera shake!
        var camera_shake: math.Vec3 = math.Vec3.zero;
        if (self._camera_shake_amt > 0.0) {
            const shake_x: f32 = @floatCast(@sin(time * 60.0) * self._camera_shake_amt);
            const shake_y: f32 = @floatCast(@cos(time * 65.25) * self._camera_shake_amt * 0.75);
            const shake_z: f32 = @floatCast(@sin(time * 57.25) * self._camera_shake_amt);
            camera_shake = math.Vec3.new(shake_x, shake_y, shake_z).scale(0.075);
            self.camera.position = self.camera.position.add(camera_shake);
            self._camera_shake_amt -= delta * 0.5;
        }

        // add our damage tilt to the camera roll
        var cam_roll: f32 = 0.0;
        if (self._camera_shake_tilt > 0.0) {
            cam_roll += self._camera_shake_tilt * self._camera_shake_tilt_mod;
            self._camera_shake_tilt -= delta * 15.0;
        }

        // add our strafe velocity to the roll
        const velocity = self.owner.getVelocity();
        const strafe_vec = self.camera.right.mul(velocity);
        cam_roll += std.math.clamp(-0.125 * strafe_vec.dot(self.camera.right), -1.25, 1.25);

        self.camera.setRoll(cam_roll);

        if (self._msg_time > 0.0) {
            self._msg_time -= delta;
        } else {
            if (self._messages.items.len > 0) {
                self._messages.clearRetainingCapacity();
            }
        }

        // lerp our step up, and apply other held weapon bobbing
        const movement_component_opt = self.owner.getComponent(character.CharacterMovementComponent);
        if (movement_component_opt) |movement_component| {
            // smooth the camera when stepping up onto something
            self.camera.position.y = movement_component.getStepLerpToHeight(self.camera.position.y);
            const cam_diff = self.camera.position.y - movement_component.state.pos.y;

            // add eye height
            self.camera.position.y += movement_component.state.size.y * 0.35;

            calcScreenShake(self, delta);
            calcWeaponLag(self, cam_diff);

            // check if our eyes are under water
            self.eyes_in_water = movement_component.state.eyes_in_water;
        }

        // do mouse look
        self.camera.runSimpleCamera(0, 60 * delta, true);

        // Todo: Why is this backwards?
        const camera_ray = self.camera.direction;

        // set our owner's rotation to match our look direction
        const dir_mat = delve.math.Mat4.direction(camera_ray, delve.math.Vec3.y_axis);
        self.owner.setRotation(delve.math.Quaternion.fromMat4(dir_mat));

        // HACK: Why do we keep losing mouse focus on web?
        if (delve.platform.input.isMouseButtonJustPressed(.LEFT)) {
            delve.platform.app.captureMouse(true);
        }

        // Handle input!
        self.handleInput();

        // update weapon flash
        if (self.weapon_flash_timer < self.weapon_flash_time)
            self.weapon_flash_timer += delta;

        self._player_light.brightness = interpolation.EaseQuad.applyIn(1.0, 0.0, self.weapon_flash_timer / self.weapon_flash_time);

        // update screen flash
        if (self.screen_flash_timer > 0.0)
            self.screen_flash_timer = @max(0.0, self.screen_flash_timer - delta);

        // update audio listener
        delve.platform.audio.setListenerPosition(self.camera.position);
        delve.platform.audio.setListenerDirection(camera_ray);
        delve.platform.audio.setListenerWorldUp(delve.math.Vec3.y_axis);
    }

    pub fn handleInput(self: *PlayerController) void {
        // Combat!
        if (delve.platform.input.isMouseButtonPressed(.LEFT)) {
            self.attack();
        }

        if (delve.platform.input.isKeyJustPressed(._1)) {
            self.switchWeapon(0);
        } else if (delve.platform.input.isKeyJustPressed(._2)) {
            self.switchWeapon(1);
        } else if (delve.platform.input.isKeyJustPressed(._3)) {
            self.switchWeapon(2);
        } else if (delve.platform.input.isKeyJustPressed(._4)) {
            self.switchWeapon(3);
        }
    }

    pub fn switchWeapon(self: *PlayerController, slot: usize) void {
        const inventory_opt = self.owner.getComponent(inventory.InventoryComponent);
        if (inventory_opt == null)
            return;

        const weapon_slot = inventory_opt.?.weapon_slots[slot];
        if (!weapon_slot.picked_up) {
            delve.debug.log("Does not have weapon for slot {d}", .{slot});
            return;
        }

        delve.debug.log("Switching weapon to slot {d}", .{slot});

        const weapon_props: weapon.WeaponComponent = switch (weapon_slot.weapon_type) {
            .Pistol => .{
                .weapon_type = .Pistol,
                .attack_type = .SemiAuto,
                .spritesheet_row = slot,
                .attack_sound = "assets/audio/sfx/pistol-shot.mp3",
                .attack_info = .{ .dmg = 3, .knockback = 30.0 },
                .weapon_spread = math.Vec2.new(2.0, 2.0),
                .recoil_spread_mod = 5.0,
            },
            .AssaultRifle => .{
                .weapon_type = .AssaultRifle,
                .attack_type = .Auto,
                .attack_delay_time = 0.025,
                .spritesheet_row = slot,
                .attack_sound = "assets/audio/sfx/rifle-shot.mp3",
                .attack_info = .{ .dmg = 1, .knockback = 15.0 },
                .recoil_amount = 2.0,
            },
            .RocketLauncher => .{
                .weapon_type = .RocketLauncher,
                .attack_type = .SemiAuto,
                .attack_delay_time = 0.45,
                .spritesheet_row = slot,
                .camera_shake_amt = 0.5,
                .attack_sound = "assets/audio/sfx/explode.mp3",
                .attack_info = .{ .dmg = 5, .knockback = 10.0, .projectile_type = .Rockets },
                .recoil_amount = 5.0,
                .weapon_spread = math.Vec2.new(1.0, 0.0),
            },
            .PlasmaRifle => .{
                .weapon_type = .PlasmaRifle,
                .attack_type = .Auto,
                .attack_delay_time = 0.05,
                .spritesheet_row = slot,
                .attack_sound = "assets/audio/sfx/plasma-shot.mp3",
                .attack_info = .{ .dmg = 3, .knockback = 30.0, .projectile_type = .Plasma },
            },
            else => {
                delve.debug.log("Weapon not implemented!", .{});
                return;
            },
        };

        // remove old weapon
        _ = self.owner.removeComponent(weapon.WeaponComponent);
        _ = self.owner.removeComponent(sprite.SpriteComponent);

        // create new one!
        _ = self.owner.createNewComponent(weapon.WeaponComponent, weapon_props) catch {
            delve.debug.log("Could not create new weapon component!", .{});
        };
    }

    pub fn switchToWeapon(self: *PlayerController, weapon_type: weapon.WeaponType) void {
        const inventory_opt = self.owner.getComponent(inventory.InventoryComponent);
        if (inventory_opt == null)
            return;

        for (inventory_opt.?.weapon_slots, 0..) |weapon_slot, idx| {
            if (weapon_slot.weapon_type == weapon_type)
                return self.switchWeapon(idx);
        }

        delve.debug.log("Player does not have weapon {any}", .{weapon_type});
    }

    pub fn calcScreenShake(self: *PlayerController, delta: f32) void {
        const time = delve.platform.app.getTime();

        // camera shake!
        var camera_shake: math.Vec3 = math.Vec3.zero;
        if (self._camera_shake_amt > 0.0) {
            const shake_x: f32 = @floatCast(@sin(time * 60.0) * self._camera_shake_amt);
            const shake_y: f32 = @floatCast(@cos(time * 65.25) * self._camera_shake_amt * 0.75);
            const shake_z: f32 = @floatCast(@sin(time * 57.25) * self._camera_shake_amt);
            camera_shake = math.Vec3.new(shake_x, shake_y, shake_z).scale(0.075);
            self.camera.position = self.camera.position.add(camera_shake);
            self._camera_shake_amt -= delta * 0.5;
        }

        if (self._camera_shake_tilt > 0.0) {
            self.camera.setRoll(self._camera_shake_tilt * self._camera_shake_tilt_mod);
            self._camera_shake_tilt -= delta * 15.0;
        }
    }

    pub fn calcWeaponLag(self: *PlayerController, cam_diff: f32) void {
        // add turn lag to held weapon
        self._cam_yaw_lag_amt += self.camera.yaw_angle - self._last_cam_yaw;
        self._cam_pitch_lag_amt += self.camera.pitch_angle - self._last_cam_pitch;
        self._cam_yaw_lag_amt = self._cam_yaw_lag_amt * 0.9;
        self._cam_pitch_lag_amt = self._cam_pitch_lag_amt * 0.9;

        // add damage screen tilt to the held weapon as well
        self._cam_yaw_lag_amt += self._camera_shake_tilt * self._camera_shake_tilt_mod * 0.25;

        // add stepping up or falling lerp to our held weapon as well
        self._cam_pitch_lag_amt += cam_diff * -10.0;

        // clamp lag amount
        const max_lag = 15.0;
        self._cam_yaw_lag_amt = std.math.clamp(self._cam_yaw_lag_amt, -max_lag, max_lag);
        self._cam_pitch_lag_amt = std.math.clamp(self._cam_pitch_lag_amt, -max_lag, max_lag);

        // keep track of current yaw and pitch for next time
        self._last_cam_yaw = self.camera.yaw_angle;
        self._last_cam_pitch = self.camera.pitch_angle;

        if (self._first_tick) {
            self.resetWeaponLag();
        }
    }

    pub fn resetWeaponLag(self: *PlayerController) void {
        self._last_cam_yaw = self.camera.yaw_angle;
        self._last_cam_pitch = self.camera.pitch_angle;
        self._cam_yaw_lag_amt = 0;
        self._cam_pitch_lag_amt = 0;

        const sprite_opt = self.owner.getComponent(sprite.SpriteComponent);
        if (sprite_opt != null)
            sprite_opt.?.position_offset = math.Vec3.zero;
    }

    pub fn getPosition(self: *PlayerController) delve.math.Vec3 {
        return self.owner.getPosition();
    }

    pub fn getRenderPosition(self: *PlayerController) delve.math.Vec3 {
        return self.owner.getRenderPosition();
    }

    pub fn acceleratePlayer(self: *PlayerController, delta: f32) void {
        const movement_component_opt = self.owner.getComponent(character.CharacterMovementComponent);
        if (movement_component_opt == null)
            return;

        const movement_component = movement_component_opt.?;

        // Collect move direction from input
        var move_dir: math.Vec3 = math.Vec3.zero;
        var cam_walk_dir = self.camera.direction;

        // ignore the camera facing up or down when not flying or swimming
        if (movement_component.state.move_mode == .WALKING and !movement_component.state.in_water)
            cam_walk_dir.y = 0.0;

        cam_walk_dir = cam_walk_dir.norm();

        if (delve.platform.input.isKeyPressed(.W)) {
            move_dir = move_dir.add(cam_walk_dir);
        }
        if (delve.platform.input.isKeyPressed(.S)) {
            move_dir = move_dir.sub(cam_walk_dir);
        }
        if (delve.platform.input.isKeyPressed(.D)) {
            const right_dir = self.camera.getRightDirection();
            move_dir = move_dir.add(right_dir);
        }
        if (delve.platform.input.isKeyPressed(.A)) {
            const right_dir = self.camera.getRightDirection();
            move_dir = move_dir.sub(right_dir);
        }

        // ignore vertical acceleration when walking
        if (movement_component.state.move_mode == .WALKING and !movement_component.state.in_water) {
            move_dir.y = 0;
        }

        // jump and swim!
        if (movement_component.state.move_mode == .WALKING) {
            if (delve.platform.input.isKeyJustPressed(.SPACE) and movement_component.state.on_ground) {
                const vel = self.owner.getVelocity();
                self.owner.setVelocity(math.Vec3.new(vel.x, jump_acceleration, vel.z));

                movement_component.state.on_ground = false;
            } else if (delve.platform.input.isKeyPressed(.SPACE) and movement_component.state.in_water) {
                if (movement_component.state.eyes_in_water) {
                    // if we're under water, just move us up
                    move_dir.y += 1.0;
                } else {
                    // if we're at the top of the water, jump!
                    const vel = self.owner.getVelocity();
                    self.owner.setVelocity(math.Vec3.new(vel.x, jump_acceleration, vel.z));
                }
            }

            // Do some head bob when walking on ground
            if (movement_component.state.on_ground) {
                self.head_bob_amount += 0.1 * delta * move_dir.len();
            }

            // ease the head bob
            self.head_bob_amount = self.head_bob_amount * 0.94;
        } else {
            // when flying, space will move us up
            if (delve.platform.input.isKeyPressed(.SPACE)) {
                move_dir.y += 1.0;
            }
        }

        // can now apply movement based on direction
        move_dir = move_dir.norm();
        movement_component.move_dir = move_dir;
    }

    pub fn attack(self: *PlayerController) void {
        if (self.owner.getComponent(weapon.WeaponComponent)) |w| {
            w.attack();
        }
    }

    pub fn setMoveMode(self: *PlayerController, move_mode: character.CharacterMoveMode) void {
        const movement_component_opt = self.owner.getComponent(character.CharacterMovementComponent);
        if (movement_component_opt) |movement_component| {
            movement_component.state.move_mode = move_mode;
        }
    }

    pub fn getMoveMode(self: *PlayerController) character.CharacterMoveMode {
        const movement_component_opt = self.owner.getComponent(character.CharacterMovementComponent);
        if (movement_component_opt) |movement_component| {
            return movement_component.state.move_mode;
        }
        return .WALKING;
    }

    pub fn getSize(self: *PlayerController) math.Vec3 {
        if (self.owner.getComponent(box_collision.BoxCollisionComponent)) |c| {
            return c.size;
        }
        return math.Vec3.zero;
    }

    pub fn showMessage(self: *PlayerController, message: []const u8) void {
        defer self._msg_time = 3.0;

        // If this message is already shown, do nothing else
        if (self._msg_time >= 0.0 and std.mem.eql(u8, self._message[0..message.len], message))
            return;

        delve.debug.log("Showing message: {s}", .{message});

        for (0..self._message.len) |idx| {
            self._message[idx] = 0;
        }
        std.mem.copyForwards(u8, &self._message, message);
    }

    pub fn shakeCamera(self: *PlayerController, shake_amt: f32, tilt_amt: f32) void {
        self._camera_shake_amt = @max(shake_amt, self._camera_shake_amt);

        if (@abs(self._camera_shake_tilt) < @abs(tilt_amt)) {
            // randomize tilt direction each time!
            const random = rand.random();
            self._camera_shake_tilt = tilt_amt;
            self._camera_shake_tilt_mod = if (random.float(f32) > 0.5) 1.0 else -1.0;
        }
    }
};

pub fn getComponentStorage(world: *entities.World) *entities.ComponentStorage(PlayerController) {
    return world.components.getStorageForType(PlayerController) catch {
        delve.debug.fatal("Could not get PlayerController storage!", .{});
        return undefined;
    };
}

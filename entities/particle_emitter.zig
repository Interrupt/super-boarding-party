const std = @import("std");
const delve = @import("delve");
const entities = @import("../game/entities.zig");
const sprite = @import("sprite.zig");
const string = @import("../utils/string.zig");
const spritesheets = @import("../managers/spritesheets.zig");
const collision = @import("../utils/collision.zig");

const math = delve.math;

// todo: get a better seed!
var rand = std.Random.DefaultPrng.init(0);

const default_spritesheet: []const u8 = "sprites/particles";

pub const ParticleEmitterType = enum {
    ONESHOT,
    CONTINUOUS,
};

pub const BlendMode = sprite.BlendMode;

const ParticleStorageType = std.AutoHashMap(u8, std.SegmentedList(Particle, 64));
pub var particle_storage: ParticleStorageType = undefined;

// A component that spawns sprite particles
pub const ParticleEmitterComponent = struct {
    // properties
    emitter_type: ParticleEmitterType = .ONESHOT,

    spritesheet: ?string.String = null,
    spritesheet_row: usize = 0,
    spritesheet_col: usize = 0,

    scale: f32 = 4.0,
    end_scale: f32 = 0.0,

    collides_world: bool = true, // whether to collide with the world

    num: u32 = 5, // number to spawn
    num_variance: u32 = 5,

    lifetime: f32 = 10.0, // how long to keep around
    lifetime_variance: f32 = 2,

    velocity: math.Vec3 = math.Vec3.new(0.0, 1.0, 0.0),
    velocity_variance: math.Vec3 = math.Vec3.new(10.0, 10.0, 10.0),

    gravity: f32 = -75.0,
    position_offset: math.Vec3 = math.Vec3.zero,
    position_variance: math.Vec3 = math.Vec3.zero,

    color: delve.colors.Color = delve.colors.white,
    end_color: ?delve.colors.Color = null,
    use_lighting: bool = true,

    spawn_interval: f32 = 0.25,
    spawn_interval_variance: f32 = 1.0,

    interp_factor: f32 = 1.0, // how fast to interpolate
    delete_owner_when_done: bool = true, // whether to clean up our owning entity when we are done

    blend_mode: BlendMode = .ALPHA,

    // interface
    owner: entities.Entity = entities.InvalidEntity,
    component_interface: entities.EntityComponent = undefined,

    // calculated
    spawn_timer: f32 = 0.0,
    next_spawn_interval_variance: f32 = 0.0,
    _spritesheet: ?*spritesheets.SpriteSheet = null,
    _world_id: u8 = undefined,

    pub fn init(self: *ParticleEmitterComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;
        self.component_interface = interface;

        self._world_id = self.owner.getOwningWorld().?.id;

        if (self._spritesheet == null) {
            if (self.spritesheet) |*s| {
                self._spritesheet = spritesheets.getSpriteSheet(s.str);
            } else {
                self._spritesheet = spritesheets.getSpriteSheet(default_spritesheet);
            }
        }

        if (particle_storage.getPtr(self._world_id) == null) {
            _ = particle_storage.put(self._world_id, .{}) catch {
                delve.debug.err("Could not create particle storage for world {d}", .{self._world_id});
            };
        }

        self.spawnParticles();
    }

    pub fn deinit(self: *ParticleEmitterComponent) void {
        if (self.spritesheet) |*s| {
            s.deinit();
        }
    }

    pub fn physics_tick(self: *ParticleEmitterComponent, delta: f32) void {
        if (self.emitter_type == .CONTINUOUS) {
            self.spawn_timer += delta;
            if (self.spawn_timer >= self.spawn_interval + self.next_spawn_interval_variance) {
                self.spawn_timer = 0.0;
                self.spawnParticles();
            }

            return;
        }

        // If we are done spawning, can clean ourselves up now!
        if (self.emitter_type == .ONESHOT) {
            if (self.delete_owner_when_done) {
                self.owner.deinit();
                return;
            }

            self.component_interface.deinit();
        }
    }

    pub fn spawnParticles(self: *ParticleEmitterComponent) void {
        var random = rand.random();
        const num_rand = random.intRangeAtMost(usize, 0, self.num_variance);

        const spawn_pos = self.owner.getPosition();

        const allocator = delve.mem.getAllocator();
        for (0..self.num + num_rand) |idx| {
            _ = idx;

            const particle_opt = self.getFreeParticle(allocator);
            if (particle_opt == null)
                continue;

            const new_particle_ptr = particle_opt.?;

            const velocity_rand_x = random.float(f32) - 0.5;
            const velocity_rand_y = random.float(f32) - 0.5;
            const velocity_rand_z = random.float(f32) - 0.5;
            const velocity_rand = math.Vec3.new(velocity_rand_x, velocity_rand_y, velocity_rand_z);

            const pos_rand_x = random.float(f32) - 0.5;
            const pos_rand_y = random.float(f32) - 0.5;
            const pos_rand_z = random.float(f32) - 0.5;
            const pos_rand = math.Vec3.new(pos_rand_x, pos_rand_y, pos_rand_z);

            new_particle_ptr.* = .{
                .sprite = .{
                    .position = spawn_pos.add(self.position_variance.mul(pos_rand)),
                    .position_offset = self.position_offset,
                    ._spritesheet = self._spritesheet,
                    .spritesheet_row = self.spritesheet_row,
                    .spritesheet_col = self.spritesheet_col,
                    .scale = self.scale,
                    .color = self.color,
                    .owner = self.owner,
                    .attach_to_parent = false,
                    .use_lighting = self.use_lighting,
                    .blend_mode = self.blend_mode,
                },
                .start_color = self.color,
                .end_color = if (self.end_color != null) self.end_color.? else self.color,
                .start_scale = self.scale,
                .end_scale = self.end_scale,
                .lifetime = self.lifetime + (random.float(f32) * self.lifetime_variance),
                .velocity = self.velocity.add(self.velocity_variance.mul(velocity_rand)),
                .gravity = self.gravity,
                .collides_world = self.collides_world,
                .interp_factor = self.interp_factor,
                .is_alive = true,
            };

            // tick to set starting values
            new_particle_ptr.tick(0);
        }

        if (self.emitter_type == .CONTINUOUS)
            self.next_spawn_interval_variance = random.float(f32) * self.spawn_interval_variance;
    }

    pub fn getFreeParticle(self: *ParticleEmitterComponent, allocator: std.mem.Allocator) ?*Particle {
        var particles = particle_storage.getPtr(self._world_id).?;
        var iterator = particles.iterator(0);

        // grab a free particle, if we have any
        // TODO: should probably keep another list of free particles
        while (iterator.next()) |value| {
            if (!value.is_alive)
                return value;
        }

        // spawn a new particle
        const new_particle_ptr = particles.addOne(allocator) catch {
            return null;
        };
        return new_particle_ptr;
    }
};

pub fn init() void {
    particle_storage = ParticleStorageType.init(delve.mem.getAllocator());
}

pub fn physics_tick(world: *entities.World, delta: f32) void {
    // tick all spawned particles
    const particles_opt = particle_storage.getPtr(world.id);
    if (particles_opt == null)
        return;

    var it = particles_opt.?.iterator(0);
    while (it.next()) |p| {
        p.tick(delta);
    }
}

pub fn deinit() void {
    const allocator = delve.mem.getAllocator();

    var p_it = particle_storage.valueIterator();
    while (p_it.next()) |particles| {
        particles.deinit(allocator);
    }

    particle_storage.deinit();
}

pub const Particle = struct {
    // properties
    sprite: sprite.SpriteComponent,
    lifetime: f32,
    velocity: math.Vec3,
    gravity: f32,
    collides_world: bool,
    start_scale: f32,
    end_scale: f32,
    start_color: delve.colors.Color,
    end_color: delve.colors.Color,
    interp_factor: f32 = 1.0,

    // calculated
    timer: f32 = 0.0,
    is_alive: bool = true,
    freeze_physics: bool = false,
    num_world_collisions: u32 = 0,

    pub fn tick(self: *Particle, delta: f32) void {
        self.timer += delta;
        self.is_alive = self.timer <= self.lifetime;

        const a = self.timer / self.lifetime;
        self.sprite.color.r = delve.utils.interpolation.EaseExpo.applyOut(self.start_color.r, self.end_color.r, a * self.interp_factor);
        self.sprite.color.g = delve.utils.interpolation.EaseExpo.applyOut(self.start_color.g, self.end_color.g, a * self.interp_factor);
        self.sprite.color.b = delve.utils.interpolation.EaseExpo.applyOut(self.start_color.b, self.end_color.b, a * self.interp_factor);
        self.sprite.color.a = delve.utils.interpolation.EaseExpo.applyOut(self.start_color.a, self.end_color.a, a * self.interp_factor);

        self.sprite.scale = delve.utils.interpolation.EaseExpo.applyIn(self.start_scale, self.end_scale, a * self.interp_factor);

        if (self.is_alive and !self.freeze_physics) {
            self.sprite.tick(delta);
            self.velocity.y += self.gravity * delta;

            if (self.collides_world) {
                // setup our move data for collision checking
                var move = collision.MoveInfo{
                    .pos = self.sprite.position,
                    .vel = self.velocity,
                    .size = math.Vec3.one.scale(0.1),
                    .checking = self.sprite.owner,
                };

                const world_opt = entities.getWorld(self.sprite.owner.getWorldId());
                if (world_opt == null)
                    return;

                const movehit = collision.collidesWithMapWithVelocity(world_opt.?, move.pos, move.size, move.vel.scale(delta), move.checking, false);
                if (movehit) |hit| {
                    // keep track of number of static world hits
                    if (hit.entity == null)
                        self.num_world_collisions += 1;

                    const move_dir = move.vel;
                    const reflect: math.Vec3 = move_dir.sub(hit.normal.scale(2 * move_dir.dot(hit.normal)));

                    // back away from the hit a teeny bit to fix epsilon errors
                    move.pos = hit.pos.add(hit.normal.scale(0.00001));
                    move.vel = reflect.scale(0.6);
                    self.velocity = move.vel;

                    if ((hit.entity == null and self.velocity.len() <= 0.1) or self.num_world_collisions >= 10) {
                        self.freeze_physics = true;
                    }

                    // apply some ground friction
                    applyFriction(self, 0.4, delta);
                    self.sprite.position = move.pos.add(self.velocity.scale(delta));
                    self.sprite.world_position = self.sprite.position;
                    return;
                }
            }

            // no collision, do the easy case
            self.sprite.position = self.sprite.position.add(self.velocity.scale(delta));
            self.sprite.world_position = self.sprite.position;
        }
    }
};

pub fn applyFriction(self: *Particle, friction: f32, delta: f32) void {
    const speed = self.velocity.len();
    if (speed > 0) {
        var velocity_drop = speed * delta;
        const friction_amount = friction;

        // friction_amount = if (self.state.on_ground) friction else if (self.state.in_water) water_friction else air_friction;
        velocity_drop *= friction_amount;

        const newspeed = (speed - velocity_drop) / speed;
        self.velocity = self.velocity.scale(newspeed);
    }
}

pub fn getComponentStorage(world: *entities.World) *entities.ComponentStorage(ParticleEmitterComponent) {
    return world.components.getStorageForType(ParticleEmitterComponent) catch {
        delve.debug.fatal("Could not get ParticleEmitterComponent storage!", .{});
        return undefined;
    };
}

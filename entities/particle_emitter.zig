const std = @import("std");
const delve = @import("delve");
const entities = @import("../game/entities.zig");
const sprite = @import("sprite.zig");
const collision = @import("../utils/collision.zig");

const math = delve.math;

var rand = std.rand.DefaultPrng.init(0);

// A component that spawns sprite particles
pub const ParticleEmitterComponent = struct {
    // properties
    spritesheet: [:0]const u8 = "sprites/blank",
    spritesheet_row: usize = 0,
    spritesheet_col: usize = 0,

    collides_world: bool = true, // whether to collide with the world

    num: u32 = 5, // number to spawn
    num_variance: u32 = 5,

    lifetime: f32 = 10.0, // how long to keep around
    lifetime_variance: f32 = 2,

    velocity: math.Vec3 = math.Vec3.new(0.0, 1.0, 0.0),
    velocity_variance: math.Vec3 = math.Vec3.new(10.0, 10.0, 10.0),

    gravity: f32 = -1.0,
    position_offset: math.Vec3 = math.Vec3.new(0, 0.0, 0),

    color: delve.colors.Color = delve.colors.white,
    end_color: ?delve.colors.Color = null,
    color_interp_factor: f32 = 1.0,

    scale: f32 = 4.0,

    delete_owner_when_done: bool = true, // whether to clean up after ourselves when done

    // interface
    owner: entities.Entity = entities.InvalidEntity,

    // calculated
    particles: std.SegmentedList(Particle, 64) = .{},

    pub fn init(self: *ParticleEmitterComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;

        var random = rand.random();
        const num_rand = random.intRangeAtMost(usize, 0, self.num_variance);

        const allocator = delve.mem.getAllocator();
        for (0..self.num + num_rand) |idx| {
            _ = idx;
            const new_particle_ptr = self.particles.addOne(allocator) catch {
                return;
            };

            const velocity_rand_x = random.float(f32) - 0.5;
            const velocity_rand_y = random.float(f32) - 0.5;
            const velocity_rand_z = random.float(f32) - 0.5;
            const velocity_rand = math.Vec3.new(velocity_rand_x, velocity_rand_y, velocity_rand_z);

            new_particle_ptr.* = .{
                .sprite = .{
                    .position = math.Vec3.zero,
                    .position_offset = self.position_offset,
                    .spritesheet = self.spritesheet,
                    .spritesheet_row = self.spritesheet_row,
                    .spritesheet_col = self.spritesheet_col,
                    .scale = self.scale,
                    .color = self.color,
                    .owner = self.owner,
                },
                .start_color = self.color,
                .end_color = if (self.end_color != null) self.end_color.? else self.color,
                .lifetime = self.lifetime + (random.float(f32) * self.lifetime_variance),
                .velocity = self.velocity.add(self.velocity_variance.mul(velocity_rand)),
                .gravity = self.gravity,
                .collides_world = self.collides_world,
                .color_interp_factor = self.color_interp_factor,
            };
        }
    }

    pub fn deinit(self: *ParticleEmitterComponent) void {
        _ = self;
    }

    pub fn tick(self: *ParticleEmitterComponent, delta: f32) void {
        // tick our particles
        var has_particles: bool = false;

        var it = self.particles.iterator(0);
        while (it.next()) |p| {
            p.tick(delta);
            if (p.is_alive)
                has_particles = true;
        }

        if (!has_particles and self.delete_owner_when_done) {
            self.owner.deinit();
        }
    }
};

pub const Particle = struct {
    // properties
    sprite: sprite.SpriteComponent,
    lifetime: f32,
    velocity: math.Vec3,
    gravity: f32,
    collides_world: bool,
    start_color: delve.colors.Color,
    end_color: delve.colors.Color,
    color_interp_factor: f32 = 1.0,

    // calculated
    timer: f32 = 0.0,
    is_alive: bool = true,
    freeze_physics: bool = false,
    num_world_collisions: u32 = 0,

    pub fn tick(self: *Particle, delta: f32) void {
        self.timer += delta;
        self.is_alive = self.timer <= self.lifetime;

        const a = self.timer / self.lifetime;
        self.sprite.color.r = delve.utils.interpolation.EaseExpo.applyOut(self.start_color.r, self.end_color.r, a * self.color_interp_factor);
        self.sprite.color.g = delve.utils.interpolation.EaseExpo.applyOut(self.start_color.g, self.end_color.g, a * self.color_interp_factor);
        self.sprite.color.b = delve.utils.interpolation.EaseExpo.applyOut(self.start_color.b, self.end_color.b, a * self.color_interp_factor);

        if (self.is_alive and !self.freeze_physics) {
            self.sprite.tick(delta);
            self.velocity.y += self.gravity;

            if (self.collides_world) {
                // setup our move data for collision checking
                var move = collision.MoveInfo{
                    .pos = self.sprite.position.add(self.sprite.owner.getPosition()),
                    .vel = self.velocity,
                    .size = math.Vec3.new(0.1, 0.1, 0.1),
                    .checking = self.sprite.owner,
                };

                const world_opt = entities.getWorld(self.sprite.owner.getWorldId());
                if (world_opt == null)
                    return;

                const movehit = collision.collidesWithMapWithVelocity(world_opt.?, move.pos, move.size, move.vel.scale(delta), move.checking);
                if (movehit) |hit| {
                    // keep track of number of static world hits
                    if (hit.entity == null)
                        self.num_world_collisions += 1;

                    const move_dir = move.vel;
                    const reflect: math.Vec3 = move_dir.sub(hit.normal.scale(2 * move_dir.dot(hit.normal)));

                    // back away from the hit a teeny bit to fix epsilon errors
                    move.pos = hit.pos.add(hit.normal.scale(0.00001));
                    move.vel = reflect.scale(0.5);
                    self.velocity = move.vel;

                    if ((hit.entity == null and self.velocity.len() <= 0.1) or self.num_world_collisions >= 10) {
                        self.freeze_physics = true;
                    }

                    // apply some ground friction
                    applyFriction(self, 0.4, delta);
                    self.sprite.position = move.pos.add(self.velocity.scale(delta)).sub(self.sprite.owner.getPosition());
                    return;
                }
            }

            // no collision, do the easy case
            self.sprite.position = self.sprite.position.add(self.velocity.scale(delta));
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
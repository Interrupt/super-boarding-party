const std = @import("std");
const delve = @import("delve");
const entities = @import("../game/entities.zig");
const sprite = @import("sprite.zig");

const math = delve.math;

var rand = std.rand.DefaultPrng.init(0);

// A component that spawns sprite particles
pub const ParticleEmitterComponent = struct {
    // properties
    spritesheet: [:0]const u8 = "sprites/particles",
    spritesheet_row: usize = 0,
    spritesheet_col: usize = 0,

    collides_world: bool = false, // whether to collide with the world

    num: u32 = 5, // number to spawn
    num_variance: u32 = 5,

    lifetime: f32 = 0.1, // how long to keep around
    lifetime_variance: f32 = 0.5,

    velocity: math.Vec3 = math.Vec3.new(0.0, 1.0, 0.0),
    velocity_variance: math.Vec3 = math.Vec3.new(10.0, 10.0, 10.0),

    gravity: f32 = -1.0,
    position_offset: math.Vec3 = math.Vec3.new(0, 2.0, 0),
    color: delve.colors.Color = delve.colors.white,

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
                    .color = self.color,
                    .owner = self.owner,
                },
                .lifetime = self.lifetime + (random.float(f32) * self.lifetime_variance),
                .velocity = self.velocity.add(self.velocity_variance.mul(velocity_rand)),
                .gravity = self.gravity,
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

    // calculated
    timer: f32 = 0.0,
    is_alive: bool = true,

    pub fn tick(self: *Particle, delta: f32) void {
        self.timer += delta;
        self.is_alive = self.timer <= self.lifetime;

        if (self.is_alive) {
            self.sprite.tick(delta);
            self.velocity.y += self.gravity;
            self.sprite.position = self.sprite.position.add(self.velocity.scale(delta));
        }
    }
};

pub fn getComponentStorage(world: *entities.World) *entities.ComponentStorage(ParticleEmitterComponent) {
    return world.components.getStorageForType(ParticleEmitterComponent) catch {
        delve.debug.fatal("Could not get ParticleEmitterComponent storage!", .{});
        return undefined;
    };
}

const basics = @import("basics.zig");

// A registry of all component types.
// Useful for comptime serialization and scripting

const ComponentType = struct {
    T: type,
    name: [:0]const u8,
    ignore_fields: []const [:0]const u8 = &[_][:0]const u8{},
};

pub const all_component_types = [_]ComponentType{
    .{ .T = basics.TransformComponent, .name = "TransformComponent" },
    .{ .T = basics.NameComponent, .name = "NameComponent" },
    .{ .T = basics.LifetimeComponent, .name = "LifetimeComponent" },
    .{ .T = @import("actor_stats.zig").ActorStats, .name = "ActorStats" },
    .{ .T = @import("audio.zig").AudioComponent, .name = "AudioComponent" },
    .{ .T = @import("box_collision.zig").BoxCollisionComponent, .name = "BoxCollisionComponent" },
    .{ .T = @import("breakable.zig").BreakableComponent, .name = "BreakableComponent" },
    .{ .T = @import("character.zig").CharacterMovementComponent, .name = "CharacterMovementComponent" },
    .{ .T = @import("explosion.zig").ExplosionComponent, .name = "ExplosionComponent" },
    .{ .T = @import("light.zig").LightComponent, .name = "LightComponent" },
    .{ .T = @import("mesh.zig").MeshComponent, .name = "MeshComponent" },
    .{ .T = @import("monster.zig").MonsterController, .name = "MonsterController" },
    .{ .T = @import("mover.zig").MoverComponent, .name = "MoverComponent" },
    .{ .T = @import("particle_emitter.zig").ParticleEmitterComponent, .name = "ParticleEmitterComponent" },
    .{ .T = @import("player.zig").PlayerController, .name = "PlayerController" },
    .{
        .T = @import("quakemap.zig").QuakeMapComponent,
        .name = "QuakeMapComponent",
        .ignore_fields = &[_][:0]const u8{
            "quake_map",
            "map_meshes",
            "entity_meshes",
            "lights",
            "directional_light",
            "solid_spatial_hash",
            "bvh_tree",
            "getTextureAnimFrames",
            "getWorldSolids",
        },
    },
    .{
        .T = @import("quakesolids.zig").QuakeSolidsComponent,
        .name = "QuakeSolidsComponent",
        .ignore_fields = &[_][:0]const u8{
            "quake_map",
            "quake_entity",
            "getEntitySolids",
            "checkCollisionWithVelocity",
            "checkRayCollision",
        },
    },
    .{ .T = @import("spinner.zig").SpinnerComponent, .name = "SpinnerComponent" },
    .{
        .T = @import("sprite.zig").SpriteComponent,
        .name = "SpriteComponent",
        .ignore_fields = &[_][:0]const u8{
            "animation",
        },
    },
    .{ .T = @import("text.zig").TextComponent, .name = "TextComponent" },
    .{ .T = @import("triggers.zig").TriggerComponent, .name = "TriggerComponent" },
    .{ .T = @import("item.zig").ItemComponent, .name = "ItemComponent" },
    .{ .T = @import("weapon.zig").WeaponComponent, .name = "WeaponComponent" },
    .{ .T = @import("projectile.zig").ProjectileComponent, .name = "ProjectileComponent" },
    .{ .T = @import("inventory.zig").InventoryComponent, .name = "InventoryComponent" },
    .{ .T = @import("script.zig").ScriptComponent, .name = "ScriptComponent" },
};

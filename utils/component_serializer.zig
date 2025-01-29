const std = @import("std");
const delve = @import("delve");
const entities = @import("../game/entities.zig");
const basics = @import("../entities/basics.zig");

const EntityComponent = entities.EntityComponent;

// Important! List of all components that can be serialized
// Components not added to this list will not be considered
const registered_types = [_]type{
    basics.TransformComponent,
    basics.NameComponent,
    basics.LifetimeComponent,
    @import("../entities/actor_stats.zig").ActorStats,
    @import("../entities/audio.zig").LoopingSoundComponent,
    @import("../entities/box_collision.zig").BoxCollisionComponent,
    @import("../entities/breakable.zig").BreakableComponent,
    @import("../entities/character.zig").CharacterMovementComponent,
    @import("../entities/light.zig").LightComponent,
    // @import("../entities/mesh.zig").MeshComponent,
    @import("../entities/monster.zig").MonsterController,
    // @import("../entities/mover.zig").MoverComponent,
    // @import("../entities/particle_emitter.zig").ParticleEmitterComponent,
    // @import("../entities/player.zig").PlayerController,
    // @import("../entities/quakemap.zig").QuakeMapComponent,
    // @import("../entities/quakesolids.zig").QuakeSolidsComponent,
    @import("../entities/spinner.zig").SpinnerComponent,
    // @import("../entities/sprite.zig").SpriteComponent,
    @import("../entities/text.zig").TextComponent,
    @import("../entities/triggers.zig").TriggerComponent,
};

pub fn writeComponent(component: *const EntityComponent, out: anytype) !void {
    try out.beginObject();

    // try out.objectField("id");
    // try out.write(self.id);

    try out.objectField("typename");
    try out.write(component.typename);

    try out.objectField("state");
    try out.beginObject();
    try writeType(component, out);
    try out.endObject();

    try out.endObject();
}

fn writeType(component: *const EntityComponent, out: anytype) !void {
    inline for(registered_types) |t| {
        if (std.mem.eql(u8, component.typename, @typeName(t))) {
            const ptr: *t = @ptrCast(@alignCast(component.impl_ptr));
            try write(out, ptr);
            return;
        }
    }
}

fn write(self: anytype, value: anytype) !void {
    const T = @TypeOf(value.*);
    switch (@typeInfo(T)) {
        .Struct => |S| {
            if (std.meta.hasFn(T, "jsonStringify")) {
                return value.jsonStringify(self);
            }

            inline for (S.fields) |Field| {
                // don't include void fields
                if (Field.type == void) continue;
                var emit_field = true;

                // Skip computed fields
                if(std.mem.startsWith(u8, Field.name, "_")) {
                    emit_field = false;
                }

                // Skip our owner field
                if(std.mem.eql(u8, Field.name, "owner")) {
                    emit_field = false;
                }

                // Skip pointers - would have to fix them up later
                if (@typeInfo(Field.type) == .Pointer) {
                    emit_field = false;
                }

                // Don't include optional fields that are null when emit_null_optional_fields is set to false
                if (@typeInfo(Field.type) == .Optional) {
                    if (self.options.emit_null_optional_fields == false) {
                        if (@field(value.*, Field.name) == null) {
                            emit_field = false;
                        }
                    }
                }

                if (emit_field) {
                    try self.objectField(Field.name);
                    try self.write(@field(value.*, Field.name));
                } else {
                    // delve.debug.log("Skipping field: {s}", .{Field.name});
                }
            }
        },
        else => {},
    }
}

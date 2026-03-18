const delve = @import("delve");

const entities = @import("entities.zig");
const main = @import("../main.zig");

const EntityId = entities.EntityId;
const World = entities.World;
const Entity = entities.Entity;

const Lua = delve.scripting.lua.Lua;

pub const GameScriptApi = struct {
    // Global function to get a World by ID
    pub fn getWorld(world_id: u8) ?*World {
        return entities.getWorld(world_id);
    }

    // Global function to get an Entity by ID
    pub fn getEntity(world_id: u8, entity_id: u24) ?Entity {
        // const id: EntityId = .{ .id = entity_id, .world_id = world_id };
        return entities.getEntity(world_id, entity_id);
    }

    // Global function to get our player
    pub fn getPlayer() ?Entity {
        if (main.game_instance.player_controller) |pc| {
            return pc.owner;
        }
        return null;
    }
};

pub fn ComponentScriptApi(T: type) type {
    return struct {
        const Self = @This();

        pub fn new() T {
            return .{};
        }

        pub fn createNewComponent(entity: entities.Entity) !*T {
            return entity.createNewComponent(T, new());
        }

        pub fn createNewComponentWithProps(entity: entities.Entity, props: T) !*T {
            return entity.createNewComponent(T, props);
        }

        pub fn getComponent(entity: entities.Entity) ?*T {
            return entity.getComponent(T);
        }

        pub fn setProperties(self: *T, props_to_copy: T) void {
            self.* = props_to_copy;
        }
    };
}

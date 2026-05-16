local String = require("String")
local Vec3 = require("Vec3")
local TransformComponent = require("TransformComponent")
local QuakeSolidsComponent = require("QuakeSolidsComponent")
local ActorStatsComponent = require("ActorStats")
local BreakableComponent = require("BreakableComponent")
local TriggerComponent = require("TriggerComponent")

local pkg = {}

function pkg.MapSpawn(entity, quake_map, quake_entity_idx)
	-- print("Spawning Func Illusionary", entity, quake_entity_idx)

	-- Default entity setup
	local new_entity = NewEntity(entity, quake_map)

	-- Check if we had an origin (should have a transform if so)
	local transform_comp = TransformComponent.getComponent(new_entity)
	if transform_comp == nil then
		TransformComponent.createNewComponent(new_entity)
	end

	-- Make the quake solid
	local solid = QuakeSolidsComponent.default()
	solid.quake_map_entity_id = quake_map.owner_id
	solid.quake_entity_idx = quake_entity_idx
	solid.transform = quake_map.map_transform
	solid.collides_entities = false
	QuakeSolidsComponent.createNewComponentWithProps(new_entity, solid)
end

return pkg

local String = require("String")
local Vec3 = require("Vec3")
local TransformComponent = require("TransformComponent")
local QuakeSolidsComponent = require("QuakeSolidsComponent")
local ActorStatsComponent = require("ActorStats")
local BreakableComponent = require("BreakableComponent")
local TriggerComponent = require("TriggerComponent")

local pkg = {}

-- Called when packages are discovered
function pkg.Setup()
	QuakeMaps.RegisterEntity("func_wall", pkg.MapSpawn)
end

function pkg.MapSpawn(entity, quake_map, quake_entity_idx)
	-- print("Spawning Func Illusionary", entity, quake_entity_idx)

	-- Default entity setup
	local new_entity = NewEntity(entity, quake_map)
	local collides_entities = entity.classname ~= "func_illusionary"

	-- Make the quake solid
	local solid = QuakeSolidsComponent.default()
	solid.quake_map_entity_id = quake_map.owner_id
	solid.quake_entity_idx = quake_entity_idx
	solid.transform = quake_map.map_transform
	solid.collides_entities = collides_entities
	QuakeSolidsComponent.createNewComponentWithProps(new_entity, solid)
end

return pkg

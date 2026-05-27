local String = require("String")
local Vec3 = require("Vec3")
local TransformComponent = require("TransformComponent")
local QuakeSolidsComponent = require("QuakeSolidsComponent")
local ActorStatsComponent = require("ActorStats")
local BreakableComponent = require("BreakableComponent")
local TriggerComponent = require("TriggerComponent")

local pkg = {}

function pkg.MapSpawn(entity, quake_map, quake_entity_idx)
	print("Spawning Func Breakable", entity, quake_entity_idx)

	-- props
	local target = ValueOrDefault(entity:getStringProperty("target"), "")
	local killtarget = ValueOrDefault(entity:getStringProperty("killtarget"), "")
	local health = ValueOrDefault(entity:getFloatProperty("health"), 5)

	-- Default entity setup
	local new_entity = NewEntity(entity, quake_map)

	BreakableComponent.createNewComponent(new_entity)

	-- Actor stats component
	local stats = ActorStatsComponent.default()
	stats.max_hp = health
	ActorStatsComponent.createNewComponentWithProps(new_entity, stats)

	-- Make the quake solid
	local solid = QuakeSolidsComponent.default()
	solid.quake_map_entity_id = quake_map.owner_id
	solid.quake_entity_idx = quake_entity_idx
	solid.transform = quake_map.map_transform
	solid.collides_entities = true
	QuakeSolidsComponent.createNewComponentWithProps(new_entity, solid)

	-- Make the trigger component if we have a target
	if #target > 0 or #killtarget > 0 then
		local props = TriggerComponent.default()

		if #target > 0 then
			props.target:set(target)
		end

		if killtarget then
			props.killtarget = String.init(killtarget)
		end

		TriggerComponent.createNewComponentWithProps(new_entity, props)
	end
end

return pkg

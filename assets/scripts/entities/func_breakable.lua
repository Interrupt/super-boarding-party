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
	local target = entity:getStringProperty("target")
	local killtarget = entity:getStringProperty("killtarget")
	local health = ValueOrDefault(entity:getFloatProperty("health"), 5)

	-- Default entity setup
	local new_entity = NewEntity(entity, quake_map)

	-- Check if we had an origin (should have a transform if so)
	local transform_comp = TransformComponent.getComponent(new_entity)
	if transform_comp == nil then
		TransformComponent.createNewComponent(new_entity)
	end

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
	if target then
		print("Breakable has a target: " .. target)
		local props = TriggerComponent.default()
		props.target = String.init(target)

		if killtarget then
			props.killtarget = String.init(killtarget)
		end

		TriggerComponent.createNewComponentWithProps(new_entity, props)
	end
end

return pkg

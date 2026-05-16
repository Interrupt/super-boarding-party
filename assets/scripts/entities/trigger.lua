local String = require("String")
local Vec3 = require("Vec3")
local TriggerComponent = require("TriggerComponent")
local TransformComponent = require("TransformComponent")
local QuakeSolidsComponent = require("QuakeSolidsComponent")

local pkg = {}

function pkg.MapSpawn(entity, quake_map, quake_entity_idx)
	-- print("Spawning Env Sprite", entity, map_transform)

	-- props
	local delay = ValueOrDefault(entity:getFloatProperty("delay"), 0)
	local message = ValueOrDefault(entity:getStringProperty("message"), "")
	local target = ValueOrDefault(entity:getStringProperty("target"), "")
	local killtarget = ValueOrDefault(entity:getStringProperty("killtarget"), "")
	local health = ValueOrDefault(entity:getFloatProperty("health"), 0)
	local shake = ValueOrDefault(entity:getFloatProperty("shake"), 0.0)

	-- Default entity setup
	local new_entity = NewEntity(entity, quake_map)

	-- Make the trigger component
	local props = TriggerComponent.default()
	props.only_once = entity.classname == "trigger_once"
	props.delay = delay
	props.message = String.init(message)
	props.target:set(target)
	props.killtarget = String.init(killtarget)
	props.trigger_on_damage = health > 0
	props.screen_shake_amt = shake / 16.0

	TriggerComponent.createNewComponentWithProps(new_entity, props)

	-- Only some triggers make solids
	if entity.classname == "trigger_relay" then
		return
	end

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
	solid.collides_entities = health > 0
	solid.hidden = true
	QuakeSolidsComponent.createNewComponentWithProps(new_entity, solid)

	-- Our solid is a volume!
	local trigger_comp = TriggerComponent.getComponent(new_entity)
	trigger_comp.is_volume = true
end

return pkg

local String = require("String")
local Vec3 = require("Vec3")
local TransformComponent = require("TransformComponent")
local QuakeSolidsComponent = require("QuakeSolidsComponent")
local ActorStatsComponent = require("ActorStats")
local BreakableComponent = require("BreakableComponent")
local TriggerComponent = require("TriggerComponent")
local MoverComponent = require("MoverComponent")

local pkg = {}

function pkg.MapSpawn(entity, quake_map, quake_entity_idx)
	print("Spawning Func Train", entity, quake_entity_idx)

	-- props
	local height = entity:getFloatProperty("height")
	local move_speed = ValueOrDefault(entity:getFloatProperty("speed"), 100)
	local wait_time = ValueOrDefault(entity:getFloatProperty("wait"), 3.0)
	local direction = ValueOrDefault(entity:getVec3Property("direction"), Vec3.y_axis)
	local health = ValueOrDefault(entity:getFloatProperty("health"), 0)
	local lip_amount = ValueOrDefault(entity:getFloatProperty("lip"), 4.0)
	local locked_message = ValueOrDefault(entity:getStringProperty("message"), "")
	local name = entity:getStringProperty("targetname")
	local target_name = ValueOrDefault(entity:getStringProperty("target"), "")

	-- Scale amounts by the map size
	move_speed = move_speed * MapScale
	lip_amount = lip_amount * MapScale
	if height ~= nil then
		height = height * MapScale
	end

	-- Default entity setup
	local new_entity = NewEntity(entity, quake_map)

	-- Make the quake solid
	local solid = QuakeSolidsComponent.default()
	solid.quake_map_entity_id = quake_map.owner_id
	solid.quake_entity_idx = quake_entity_idx
	solid.transform = quake_map.map_transform
	solid.collides_entities = true
	local solid_comp = QuakeSolidsComponent.createNewComponentWithProps(new_entity, solid)

	-- Work out the movement direction
	local move_dir = direction:norm()

	-- Move to the extent of our bounds, in the direction of movement
	local move_amount = 0
	if height == nil then
		-- No height given, use the lip amount
		local solid_size = solid_comp.bounds.max:sub(solid_comp.bounds.min)
		move_amount = solid_size:mul(move_dir)

		-- Remove the lip from the movement
		move_amount = move_amount:sub(move_dir:scale(lip_amount))
	else
		-- Easy case, just use the height
		move_amount = move_dir:scale(height)
	end

	-- Make the trigger component if we have a target
	if #target_name > 0 then
		local trigger_props = TriggerComponent.default()
		trigger_props.target:set(target_name)
		TriggerComponent.createNewComponentWithProps(new_entity, trigger_props)
	end

	-- Platforms with names wait for triggers
	local start_type = "IMMEDIATE"
	if name ~= nil then
		start_type = "WAIT_FOR_TRIGGER"
	end

	-- Trains with health should wait for damage
	if name == nil and (health > 0) then
		start_type = "WAIT_FOR_DAMAGE"
	end

	-- Make the mover component
	local props = MoverComponent.default()
	props.lookup_path_on_start = true -- Find our first path on init!
	props.start_type = start_type
	props.move_amount = move_amount
	props.move_time = move_amount:len() / move_speed
	props.move_speed = move_speed
	props.return_time = props.move_time
	props.returns = false
	props.returns_on_squish = false
	props.return_delay_time = wait_time
	props.start_delay = 0.0
	props.delay_time = 3.0

	if #target_name > 0 then
		props.start_at_target = String.init(target_name)
		print(" - train start target: " .. target_name)
	end

	if #locked_message > 0 then
		props.message = String.init(locked_message)
	end

	MoverComponent.createNewComponentWithProps(new_entity, props)
end

return pkg

local String = require("String")
local Vec3 = require("Vec3")
local TransformComponent = require("TransformComponent")
local QuakeSolidsComponent = require("QuakeSolidsComponent")
local ActorStatsComponent = require("ActorStats")
local BreakableComponent = require("BreakableComponent")
local TriggerComponent = require("TriggerComponent")
local MoverComponent = require("MoverComponent")

local door_flags = {
	[1] = "start_open",
	[4] = "dont_link",
	[8] = "gold_key",
	[16] = "silver_key",
	[32] = "toggle",
}

local secret_door_flags = {
	[1] = "once_only",
	[2] = "left_first",
	[4] = "down_first",
	[8] = "not_shootable",
	[16] = "always_shootable",
}

local pkg = {}

-- Called when packages are discovered
function pkg.Setup()
	QuakeMaps.RegisterEntity("func_door", pkg.MapSpawn)
end

function pkg.MapSpawn(entity, quake_map, quake_entity_idx)
	-- print("Spawning Func Door", entity, quake_entity_idx)

	local is_secret_door = entity.classname == "func_door_secret"

	local flags = ParseSpawnflags(entity.spawnflags, door_flags)
	local secret_flags = ParseSpawnflags(entity.spawnflags, secret_door_flags)

	-- props
	local move_speed = ValueOrDefault(entity:getFloatProperty("speed"), 50)
	local health = ValueOrDefault(entity:getFloatProperty("health"), 0)
	local wait_time = ValueOrDefault(entity:getFloatProperty("wait"), 3.0)
	local lip_amount = ValueOrDefault(entity:getFloatProperty("lip"), 4.0)
	local locked_message = ValueOrDefault(entity:getStringProperty("message"), "")
	local angle = ValueOrDefault(entity:getFloatProperty("angle"), 0)
	local name = entity:getStringProperty("targetname")
	local returns = true
	local starts_open = false

	-- Check spawnflags
	if is_secret_door == false then
		starts_open = flags.start_open
	elseif is_secret_door == true then
		returns = secret_flags.once_only ~= true
	end

	move_speed = move_speed * MapScale
	lip_amount = lip_amount * MapScale

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
	local move_dir = Vec3.x_axis:rotate(angle, Vec3.y_axis):norm()

	-- Special case for vertical up or down
	if angle == -1.0 then
		move_dir = Vec3.y_axis
	elseif angle == -2.0 then
		move_dir = Vec3.y_axis:scale(-1.0)
	end

	-- Move to the extent of our bounds, in the direction of movement
	local solid_size = solid_comp.bounds.max:sub(solid_comp.bounds.min)
	local move_amount = solid_size:mul(move_dir)

	-- Remove the lip from the movement
	move_amount = move_amount:sub(move_dir:scale(lip_amount))

	-- Doors with names wait for triggers
	local start_type = "WAIT_FOR_BUMP"
	if name ~= nil then
		start_type = "WAIT_FOR_TRIGGER"
	end

	-- Doors with health should wait for damage
	if name == nil and (health > 0) then
		start_type = "WAIT_FOR_DAMAGE"
	end

	-- Secret doors not marked as shootable should wait for damage also
	if is_secret_door then
		if secret_door_flags.not_shootable then
			start_type = "WAIT_FOR_TRIGGER"
		else
			start_type = "WAIT_FOR_DAMAGE"
		end
	end

	-- Make the mover component
	local props = MoverComponent.default()
	props.start_type = start_type
	props.move_amount = move_amount
	props.move_time = move_amount:len() / move_speed
	props.move_speed = move_speed
	props.return_time = props.move_time
	props.returns = wait_time ~= -1.0 and returns
	props.return_delay_time = wait_time
	props.start_delay = 0.1
	props.starts_overlapping_movers = flags.dont_link == false
	props.start_moved = starts_open

	if #locked_message > 0 then
		props.message = String.init(locked_message)
	end

	MoverComponent.createNewComponentWithProps(new_entity, props)
end

return pkg

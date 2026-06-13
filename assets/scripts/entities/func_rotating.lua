local Vec3 = require("Vec3")
local QuakeSolidsComponent = require("QuakeSolidsComponent")
local SpinnerComponent = require("SpinnerComponent")
local ScriptComponent = require("ScriptComponent")

local pkg = {}

-- Called when packages are discovered
function pkg.Setup()
	QuakeMaps.RegisterEntity("func_rotating", pkg.MapSpawn)
end

function pkg.MapSpawn(entity, quake_map, quake_entity_idx)
	-- print("Spawning Func Rotating", entity, quake_entity_idx)

	-- props
	local spin_speed = ValueOrDefault(entity:getFloatProperty("maxspeed"), 100.0)
	local spin_axis = ValueOrDefault(entity:getVec3Property("axis"), Vec3.y_axis)

	-- Default entity setup
	local new_entity = NewEntity(entity, quake_map)

	-- Make the quake solid
	local solid = QuakeSolidsComponent.default()
	solid.quake_map_entity_id = quake_map.owner_id
	solid.quake_entity_idx = quake_entity_idx
	solid.transform = quake_map.map_transform
	QuakeSolidsComponent.createNewComponentWithProps(new_entity, solid)

	-- spinner!
	-- local spinner = SpinnerComponent.default()
	-- spinner.spin_speed = spin_speed
	-- spinner.spin_axis = spin_axis
	--
	-- SpinnerComponent.createNewComponentWithProps(new_entity, spinner)

	-- test spinner script component
	local script_props = ScriptComponent.new("spinner", "assets/scripts/components/spinner.lua")
	local script_comp = ScriptComponent.createNewComponentWithProps(new_entity, script_props)
	script_comp.spin_speed = spin_speed
	script_comp.spin_axis = spin_axis
end

return pkg

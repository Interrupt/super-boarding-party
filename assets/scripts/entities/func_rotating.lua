local Vec3 = require("Vec3")
local QuakeSolidsComponent = require("QuakeSolidsComponent")
local SpinnerComponent = require("SpinnerComponent")

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

	local spinner = SpinnerComponent.default()
	spinner.spin_speed = spin_speed
	spinner.spin_axis = spin_axis

	SpinnerComponent.createNewComponentWithProps(new_entity, spinner)
end

return pkg

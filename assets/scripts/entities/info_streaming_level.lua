local String = require("String")
local Vec3 = require("Vec3")
local Mat4 = require("Mat4")
local QuakeMapComponent = require("QuakeMapComponent")

local pkg = {}

-- Called when packages are discovered
function pkg.Setup()
	QuakeMaps.RegisterEntity("info_streaming_level", pkg.MapSpawn)
end

function pkg.MapSpawn(entity, quake_map)
	-- print("Spawning Streaming Level", entity)

	-- props
	local level_path = ValueOrDefault(entity:getStringProperty("level"), "")
	local landmark_name = ValueOrDefault(entity:getFloatProperty("landmark"), "entrance")
	local angle = ValueOrDefault(entity:getFloatProperty("angle"), 0)

	-- save the origin to use for the map transform
	local origin = ValueOrDefault(entity:getVec3Property("origin"), Vec3.zero)
	if origin ~= nil then
		origin = origin:mulMat4(quake_map.map_transform)
	end

	-- Default entity setup
	local new_entity = NewEntity(entity, quake_map)

	local map_props = QuakeMapComponent.default()
	map_props.filename:set(level_path)
	map_props.transform = Mat4.translate(origin)
	map_props.transform_landmark_name = String.init(landmark_name)
	map_props.transform_landmark_angle = angle
	map_props.check_for_space = false

	QuakeMapComponent.createNewComponentWithProps(new_entity, map_props)
end

return pkg

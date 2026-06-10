local String = require("String")
local TriggerComponent = require("TriggerComponent")

local pkg = {}

-- Called when packages are discovered
function pkg.Setup()
	QuakeMaps.RegisterEntity("path_corner", pkg.MapSpawn)
end

function pkg.MapSpawn(entity, quake_map, quake_entity_idx)
	-- print("Spawning Path Node", entity, map_transform)

	-- props
	local message = ValueOrDefault(entity:getStringProperty("message"), "")
	local target = ValueOrDefault(entity:getStringProperty("target"), "")
	local path_target = ValueOrDefault(entity:getStringProperty("pathtarget"), "")

	-- Default entity setup
	local new_entity = NewEntity(entity, quake_map)

	-- Make the trigger component
	local props = TriggerComponent.default()
	props.is_path_node = true

	if #message > 0 then
		props.message = String.init(message)
	end

	if #target > 0 then
		props.target:set(target)
	else
		props.target = String.init("")
	end

	if #path_target > 0 then
		props.value = String.init(path_target)
	end

	TriggerComponent.createNewComponentWithProps(new_entity, props)
end

return pkg

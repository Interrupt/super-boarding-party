local Vec3 = require("Vec3")
local Quaternion = require("Quaternion")
local TextComponent = require("TextComponent")
local TransformComponent = require("TransformComponent")

local pkg = {}

-- Called when packages are discovered
function pkg.Setup()
	QuakeMaps.RegisterEntity("prop_text", pkg.MapSpawn)
end

function pkg.MapSpawn(entity, quake_map)
	-- print("Spawning Prop Text", entity, map_transform)

	-- Default entity setup
	local new_entity = NewEntity(entity, quake_map)

	-- Props
	local text = ValueOrDefault(entity:getStringProperty("text"), "Null Prop_Text")
	local angle = ValueOrDefault(entity:getFloatProperty("angle"), 0)
	local scale = ValueOrDefault(entity:getFloatProperty("scale"), 1.0 / MapScale)
	local unlit = ValueOrDefault(entity:getFloatProperty("unlit"), 0)

	-- Make Text Component
	local text_comp = TextComponent.newFromString(text)
	text_comp.scale = scale * MapScale
	text_comp.unlit = unlit > 0.99
	TextComponent.createNewComponentWithProps(new_entity, text_comp)

	-- Set angle
	local transform = TransformComponent.getComponent(new_entity)
	local rot_quat = Quaternion.fromAxisAndAngle(angle + 90, Vec3.y_axis)
	transform.rotation = rot_quat
end

return pkg

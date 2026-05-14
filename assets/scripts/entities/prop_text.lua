local Game = require("Game")
local Color = require("Color")
local Vec2 = require("Vec2")
local Vec3 = require("Vec3")
local Quaternion = require("Quaternion")

local BoxCollisionComponent = require("BoxCollisionComponent")
local TextComponent = require("TextComponent")
local MeshComponent = require("MeshComponent")
local ItemComponent = require("ItemComponent")
local NameComponent = require("NameComponent")
local SpriteComponent = require("SpriteComponent")
local TransformComponent = require("TransformComponent")
local StatsComponent = require("ActorStats")
local String = require("String")

local pkg = {}

function pkg.Spawn(entity, map_transform)
	-- print("Spawning Prop Text", entity, map_transform)

	-- Default entity setup
	local new_entity = NewEntity(entity, map_transform)

	local text = entity:getStringProperty("text")
	if text == nil then
		text = "NULL Prop_Text"
	end

	-- Set default light props
	local text_comp = TextComponent.newFromString(text)
	text_comp.scale = 1.0
	-- text_comp.rotation_offset = Quaternion.fromAxisAndAngle(-90, Vec3.z_axis)
	TextComponent.createNewComponentWithProps(new_entity, text_comp)

	-- Set rotation
	local angle = entity:getFloatProperty("angle")
	if angle == nil then
		angle = 0
	end

	local transform = TransformComponent.getComponent(new_entity)
	local rot_quat = Quaternion.fromAxisAndAngle(angle + 90, Vec3.y_axis)
	transform.rotation = rot_quat
end

return pkg

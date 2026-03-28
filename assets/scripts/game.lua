local Game = require("Game")
local Vec2 = require("Vec2")
local Vec3 = require("Vec3")
local Quaternion = require("Quaternion")

local LightComponent = require("LightComponent")
local TextComponent = require("TextComponent")
local MeshComponent = require("MeshComponent")
local SpriteComponent = require("SpriteComponent")
local TransformComponent = require("TransformComponent")
local StatsComponent = require("ActorStats")
local String = require("String")

local time = 0.0
function _update()
	time = time + 0.05

	-- local str = String.init("Hello World")
	-- print(str:get())
	-- str:set("Another String!")
	-- print(str:get())

	-- Get the player entity
	local player = Game.getPlayer()
	if player == nil then
		return
	end

	local transform = TransformComponent.getComponent(player)
	local stats = StatsComponent.getComponent(player)

	-- Get our light component
	local light = LightComponent.getComponent(player)
	if light ~= nil then
		-- Try updating some values on it
		light.brightness = (math.sin(time) + 1.0) * 2.0
		light.position = Vec3.new(0.0, math.sin(time * 0.9) * 2.0, 4.0)
		light.radius = 4.0
	end

	-- mesh test
	local mesh = MeshComponent.getComponent(player)
	if mesh == nil then
		local mesh_props = MeshComponent.default()
		MeshComponent.createNewComponentWithProps(player, mesh_props)
		mesh = MeshComponent.getComponent(player)
	end
	mesh.position_offset = Vec3.new(-2.0, math.sin(time * 0.5) * 0.2, 6.0)
	mesh.scale = (math.sin(time * 0.2) + 1.2) * 0.2
	mesh.rotation_offset = Quaternion.fromAxisAndAngle(time * 20.0, Vec3.y_axis)

	-- sprite test
	local sprite = SpriteComponent.getComponent(player)
	if sprite == nil then
		local props = SpriteComponent.default()
		SpriteComponent.createNewComponentWithProps(player, props)
		sprite = SpriteComponent.getComponent(player)
	end
	sprite.position_offset = Vec3.new(0.0, math.sin(time * 0.5) * 0.2, 4.0)
	sprite.scale = 1.0 + (math.sin(time * 0.2) * 0.2)
	sprite.rotation_offset = Quaternion.fromAxisAndAngle(time * 20.0, Vec3.y_axis)

	-- text test
	local text = TextComponent.getComponent(player)
	if text == nil then
		local new_text = TextComponent.newFromString("Original String")
		TextComponent.createNewComponentWithProps(player, new_text)
	else
		text.scale = 0.5
		text.position_offset = Vec3.new(5.0, math.sin(time * 0.5) * 0.2, 6.0)
		text.rotation_offset = Quaternion.fromAxisAndAngle(180, Vec3.y_axis)
		-- text.rotation_offset = text.rotation_offset:mul(Quaternion.fromAxisAndAngle(time * 50, Vec3.x_axis))

		local debugtext = "pos: "
			.. string.format("%.2f %.2f %.2f", transform.position.x, transform.position.y, transform.position.z)
			.. "\nhp: "
			.. stats.hp
			.. "/"
			.. stats.max_hp

		text:setText(debugtext)
	end

	-- LightComponent.createNewComponent(player, light)
end

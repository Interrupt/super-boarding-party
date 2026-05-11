local Game = require("Game")
local Color = require("Color")
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

local debug_mode = true

function SpawnLight(entity, map_transform)
	print("Spawning light!")
	local location = entity:getVec3Property("origin"):mulMat4(map_transform)

	local new_entity = Game.createEntity()

	local transform = TransformComponent.createNewComponent(new_entity)
	transform.position = location

	local light = LightComponent.default()
	light.radius = 10

	-- light
	local light_prop = entity:getFloatProperty("light")
	if light_prop ~= nil then
		light.radius = light_prop * 0.125
	end

	-- radius
	local radius_prop = entity:getFloatProperty("radius")
	if radius_prop ~= nil then
		light.radius = radius_prop
	end

	-- brightness
	local brightness_prop = entity:getFloatProperty("brightness")
	if brightness_prop ~= nil then
		light.brightness = brightness_prop
	end

	-- color
	local color_prop = entity:getVec3Property("_color")
	if color_prop ~= nil then
		light.color = Color.new(color_prop.x / 255.0, color_prop.y / 255.0, color_prop.z / 255.0, 1.0)
	end

	-- off / on
	if entity.spawnflags & 0x01 ~= 0 then
		light.is_on = false
	end

	-- style
	-- local style_prop = entity:getFloatProperty("style")
	-- if style_prop ~= nil then
	-- 	light.style = style_prop
	-- end

	LightComponent.createNewComponentWithProps(new_entity, light)

	local props = SpriteComponent.default()
	props.spritesheet = String.init("sprites/sprites")
	props.use_lighting = false
	props.scale = 0.75
	props.spritesheet_row = 2
	props.color = light.color

	SpriteComponent.createNewComponentWithProps(new_entity, props)

	-- Debug Text
	if debug_mode then
		local text_comp = TextComponent.newFromString(entity.classname)
		text_comp.scale = 0.25
		text_comp.rotation_offset = Quaternion.fromAxisAndAngle(-90, Vec3.z_axis)

		TextComponent.createNewComponentWithProps(new_entity, text_comp)
	end

	print("Location: [" .. location.x .. ", " .. location.y .. ", " .. location.z .. "]")
	print(entity:getFloatProperty("light"))
	print(entity:getFloatProperty("radius"))
	print(entity:getFloatProperty("brightness"))
	print(entity:getFloatProperty("style"))
	print(entity:getVec3Property("_color"))
	print(entity:getStringProperty("name"))
	print(entity.spawnflags)
end

function SpawnFallback(entity, map_transform)
	print("Spawning fallback for " .. entity.classname)
	local location = entity:getVec3Property("origin"):mulMat4(map_transform)

	local new_entity = Game.createEntity()

	local transform = TransformComponent.createNewComponent(new_entity)
	transform.position = location

	-- TODO: Need a missing entity icon
	-- local props = SpriteComponent.default()
	-- props.spritesheet = String.init("sprites/sprites")
	-- props.use_lighting = false
	-- props.scale = 0.75
	-- props.spritesheet_row = 2
	--
	-- SpriteComponent.createNewComponentWithProps(new_entity, props)

	-- Debug Text
	if debug_mode then
		local text_comp = TextComponent.newFromString(entity.classname)
		text_comp.scale = 0.25
		text_comp.rotation_offset = Quaternion.fromAxisAndAngle(-90, Vec3.z_axis)

		TextComponent.createNewComponentWithProps(new_entity, text_comp)
	end
end

local quakemap_functions = {
	light = SpawnLight,
	light_fluorospark = SpawnLight,
	light_fluoro = SpawnLight,
}

function DebugPrintEntity(entity)
	local classname = entity.classname

	-- Print some debug info
	print("- Spawning quake entity: " .. classname)

	local entity_name = entity:getStringProperty("targetname")
	if entity_name ~= nil then
		print("   - name: " .. entity_name)
	end

	local target = entity:getStringProperty("target")
	if target ~= nil then
		print("   - target: " .. target)
	end
end

local SpawnEntity = function(entity, transform)
	-- DebugPrintEntity(entity)

	local classname = entity.classname

	-- Lookup the spawn function for this classname, call it if it exists
	-- local spawn_fn = quakemap_functions[classname]
	local spawn_fn = quakemap_functions[classname]
	if spawn_fn ~= nil then
		spawn_fn(entity, transform)
	else
		SpawnFallback(entity, transform)
	end
end

-- Export our library!
local library = {}
library.SpawnEntity = SpawnEntity
library.quakemap_functions = quakemap_functions

return library

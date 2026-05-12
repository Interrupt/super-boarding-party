local Game = require("Game")
local Color = require("Color")
local Vec2 = require("Vec2")
local Vec3 = require("Vec3")
local Quaternion = require("Quaternion")

local LightComponent = require("LightComponent")
local TextComponent = require("TextComponent")
local MeshComponent = require("MeshComponent")
local NameComponent = require("NameComponent")
local SpriteComponent = require("SpriteComponent")
local TransformComponent = require("TransformComponent")
local StatsComponent = require("ActorStats")
local String = require("String")

local debug_mode = false

-- Keep this in sync with the light.zig styles enum in zig
local LightStyles = {
	"normal",
	"flicker_1",
	"pulse_slow_1",
	"candle_1",
	"strobe_fast",
	"pulse_gentle",
	"flicker_2",
	"candle_2",
	"candle_3",
	"strobe_slow",
	"flicker_flouro",
	"pulse_slow_2",
}

function NewEntity(entity, map_transform)
	local new_entity = Game.createEntity()

	local origin = entity:getVec3Property("origin")
	if origin ~= nil then
		local location = origin:mulMat4(map_transform)

		local transform = TransformComponent.createNewComponent(new_entity)
		transform.position = location
	end

	local entity_name = entity:getStringProperty("targetname")
	if entity_name ~= nil then
		local new_name_comp_props = NameComponent.new(entity_name)
		NameComponent.createNewComponentWithProps(new_entity, new_name_comp_props)
	end

	return new_entity
end

function SpawnLight(entity, map_transform)
	-- Default entity setup
	local new_entity = NewEntity(entity, map_transform)

	-- Set default light props
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
	local style_prop = entity:getFloatProperty("style")
	if style_prop ~= nil then
		if style_prop > 0 and style_prop <= #LightStyles then
			light.style = LightStyles[style_prop + 1]
		else
			print("Invalid light style: " .. style_prop)
		end
	end

	LightComponent.createNewComponentWithProps(new_entity, light)
end

function SpawnFallback(entity, map_transform)
	print("Unknown quake entity: '" .. entity.classname .. "'")

	local origin = entity:getVec3Property("origin")
	if origin == nil then
		-- No location, just return
		return
	end

	local location = origin:mulMat4(map_transform)

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
	local text_comp = TextComponent.newFromString(entity.classname)
	text_comp.scale = 0.25
	text_comp.rotation_offset = Quaternion.fromAxisAndAngle(-90, Vec3.z_axis)

	TextComponent.createNewComponentWithProps(new_entity, text_comp)
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

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

function SpawnLight(entity, map_transform)
	print("Spawning light!")
	local location = entity:getVec3Property("origin"):mulMat4(map_transform)

	local new_entity = Game.createEntity()

	local transform = TransformComponent.createNewComponent(new_entity)
	transform.position = location

	local light = LightComponent.createNewComponent(new_entity)
	light.radius = 30
	light.brightness = 20
	light.position = Vec3.zero

	light.color.r = 1.0
	light.color.g = 1.0
	light.color.b = 1.0

	local props = SpriteComponent.default()
	props.spritesheet = String.init("sprites/sprites")
	props.use_lighting = false
	props.scale = 0.75
	props.spritesheet_row = 0

	SpriteComponent.createNewComponentWithProps(new_entity, props)

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

	local props = SpriteComponent.default()
	props.spritesheet = String.init("sprites/sprites")
	props.use_lighting = false
	props.scale = 0.75
	props.spritesheet_row = 2

	SpriteComponent.createNewComponentWithProps(new_entity, props)
end

local quakemap_functions = {
	light = SpawnLight,
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

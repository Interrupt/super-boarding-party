local Game = require("Game")
local Vec3 = require("Vec3")
local Quaternion = require("Quaternion")

local TextComponent = require("TextComponent")
local NameComponent = require("NameComponent")
local SpriteComponent = require("SpriteComponent")
local TransformComponent = require("TransformComponent")
local QuakeSolidsComponent = require("QuakeSolidsComponent")

local debug_mode = false

-- Entities
local ItemEntity = require("assets/scripts/entities/item")
local LightEntity = require("assets/scripts/entities/lights")
local PropTextEntity = require("assets/scripts/entities/prop_text")
local PropStaticEntity = require("assets/scripts/entities/prop_static")
local EnvSpriteEntity = require("assets/scripts/entities/env_sprite")
local MonsterEntity = require("assets/scripts/entities/monster")
local TriggerEntity = require("assets/scripts/entities/trigger")
local FuncBreakable = require("assets/scripts/entities/func_breakable")
local FuncWall = require("assets/scripts/entities/func_wall")
local FuncButton = require("assets/scripts/entities/func_button")
local FuncDoor = require("assets/scripts/entities/func_door")
local FuncPlat = require("assets/scripts/entities/func_plat")

MapScale = 0.03

-- Helper to get a value or a default
function ValueOrDefault(value, default)
	if value ~= nil then
		return value
	end
	return default
end

-- Helper to handle some of the default entity setup
function NewEntity(entity, quake_map)
	local new_entity = Game.createEntity()
	local map_transform = quake_map.map_transform

	local origin = entity:getVec3Property("origin")
	if origin ~= nil then
		local location = origin:mulMat4(map_transform)

		local transform = TransformComponent.createNewComponent(new_entity)
		transform.position = location
	else
		local transform = TransformComponent.createNewComponent(new_entity)
		transform.position = Vec3.zero
	end

	local entity_name = entity:getStringProperty("targetname")
	if entity_name ~= nil then
		print("Making new name component: " .. entity_name)
		local new_name_comp_props = NameComponent.new(entity_name)
		NameComponent.createNewComponentWithProps(new_entity, new_name_comp_props)
		print("done making name")
	end

	return new_entity
end

function SpawnFallback(entity, quake_map)
	print("Unknown quake entity: '" .. entity.classname .. "'")
	local map_transform = quake_map.map_transform

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
	-- text_comp.rotation_offset = Quaternion.fromAxisAndAngle(-90, Vec3.z_axis)

	TextComponent.createNewComponentWithProps(new_entity, text_comp)
end

function FuncFallback(entity, quake_map, quake_entity_idx)
	print("Unknown quake func entity: '" .. entity.classname .. "'")

	local new_entity = NewEntity(entity, quake_map)

	TransformComponent.createNewComponent(new_entity)

	local solid = QuakeSolidsComponent.default()
	solid.quake_entity_idx = quake_entity_idx
	solid.quake_map_entity_id = quake_map.owner_id
	solid.transform = quake_map.map_transform
	solid.hidden = false
	QuakeSolidsComponent.createNewComponentWithProps(new_entity, solid)
end

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

-- Register our spawn handlers
local quakemap_functions = {
	{ "light", LightEntity.MapSpawn },
	{ "item_", ItemEntity.MapSpawn },
	{ "prop_text", PropTextEntity.MapSpawn },
	{ "prop_static", PropStaticEntity.MapSpawn },
	{ "env_sprite", EnvSpriteEntity.MapSpawn },
	{ "monster_", MonsterEntity.MapSpawn },
	{ "trigger_", TriggerEntity.MapSpawn },
	{ "func_breakable", FuncBreakable.MapSpawn },
	{ "func_detail", FuncWall.MapSpawn },
	{ "func_illusionary", FuncWall.MapSpawn },
	{ "func_wall", FuncWall.MapSpawn },
	{ "func_button", FuncButton.MapSpawn },
	{ "func_door", FuncDoor.MapSpawn },
	{ "func_plat", FuncPlat.MapSpawn },
	{ "func_", FuncFallback },
}

local SpawnEntity = function(quake_entity, quake_map, quake_entity_idx)
	-- DebugPrintEntity(entity)
	local classname = quake_entity.classname

	-- Route the entity to our handlers using some fuzzy matching
	for index, route_def in ipairs(quakemap_functions) do
		local route = route_def[1]
		local handler = route_def[2]

		if classname:match("^" .. route) then
			-- print("Found spawn handler for " .. classname)
			handler(quake_entity, quake_map, quake_entity_idx)
			return
		end
	end

	-- Not found! Fallback.
	SpawnFallback(quake_entity, quake_map)
end

-- Export our library!
local library = {}
library.SpawnEntity = SpawnEntity
library.quakemap_functions = quakemap_functions

return library

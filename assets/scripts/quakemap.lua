local Game = require("Game")
local Vec3 = require("Vec3")
local Quaternion = require("Quaternion")

local TextComponent = require("TextComponent")
local NameComponent = require("NameComponent")
local SpriteComponent = require("SpriteComponent")
local TransformComponent = require("TransformComponent")

local debug_mode = false

-- Entities
local ItemEntity = require("assets/scripts/entities/item")
local LightEntity = require("assets/scripts/entities/lights")
local PropTextEntity = require("assets/scripts/entities/prop_text")

-- Helper to handle some of the default entity setup
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

function HandleFunc(entity, map_transform)
	-- for a func, the classname is the function
	local func_name = entity.classname
	local success, result = pcall(func_name, entity, map_transform)

	if success ~= true then
		print("Error calling quakemap function: " .. func_name)
	end
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
	light = LightEntity.Spawn,
	item_ = ItemEntity.Spawn,
	func_ = HandleFunc,
	prop_text = PropTextEntity.Spawn,
}

local SpawnEntity = function(entity, transform)
	-- DebugPrintEntity(entity)
	local classname = entity.classname

	-- Route the entity to our handlers using some fuzzy matching
	for index, value in pairs(quakemap_functions) do
		if classname:match("^" .. index) then
			print("Found spawn handler for " .. classname)
			value(entity, transform)
			return
		end
	end

	-- Not found! Fallback.
	SpawnFallback(entity, transform)
end

-- Export our library!
local library = {}
library.SpawnEntity = SpawnEntity
library.quakemap_functions = quakemap_functions

return library

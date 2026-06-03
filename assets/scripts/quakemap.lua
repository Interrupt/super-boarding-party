local Game = require("Game")
local Vec3 = require("Vec3")
local Quaternion = require("Quaternion")

local TextComponent = require("TextComponent")
local NameComponent = require("NameComponent")
local SpriteComponent = require("SpriteComponent")
local TransformComponent = require("TransformComponent")
local QuakeSolidsComponent = require("QuakeSolidsComponent")

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

-- Register our default spawn handlers
local quakemap_functions = {
	{ "func_", FuncFallback },
}

local RegisterEntity = function(entity_route, handler)
	-- add the route to the handlers
	table.insert(quakemap_functions, { entity_route, handler })

	-- sort the table so that longer routes get matched first
	table.sort(quakemap_functions, function(a, b)
		return #a[1] > #b[1]
	end)
end

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

-- Global function called when a Quake Map wants to spawn a new entity
function QuakemapSpawnEntity(entity, transform, quake_entity_idx)
	SpawnEntity(entity, transform, quake_entity_idx)
end

-- Parse spawnflags into a table, by bits and (optionally) by name
function ParseSpawnflags(flags, names)
	local result = { bits = {} }

	for bit = 0, 23 do
		local idx = bit + 1 -- 1-based index

		-- actual bit. 1, 2, 4, 8, 16, ... etc
		local bit_val = 1 << bit

		local flag_value = flags & bit_val ~= 0
		result.bits[bit_val] = flag_value

		-- If there was a name lookup table, set those as well
		if names and names[bit_val] then
			-- print(names[bit_val], flag_value)
			result[names[bit_val]] = flag_value
		end
	end

	return result
end

-- Export our library!
local library = {}
library.SpawnEntity = SpawnEntity
library.RegisterEntity = RegisterEntity
library.ParseSpawnflags = ParseSpawnflags
library.quakemap_functions = quakemap_functions

-- Make this library available globally
QuakeMaps = library

return library

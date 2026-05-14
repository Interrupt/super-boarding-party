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

local debug_mode = false

-- Entities
local LightEntity = require("assets/scripts/entities/lights")
local PropTextEntity = require("assets/scripts/entities/prop_text")

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

local weapons = {
	item_weapon_pistol = {
		type = "Pistol",
		sprite_row = 0,
		sprite_col = 0,
	},
	item_weapon_rifle = {
		type = "AssaultRifle",
		sprite_row = 1,
		sprite_col = 0,
	},
	item_weapon_rockets = {
		type = "RocketLauncher",
		sprite_row = 2,
		sprite_col = 0,
	},
	item_weapon_plasma = {
		type = "PlasmaRifle",
		sprite_row = 3,
		sprite_col = 0,
	},
}

local ammos = {
	item_ammo_pistol = {
		type = "PistolBullets",
		sprite_row = 4,
		sprite_col = 0,
	},
	item_ammo_rifle = {
		type = "RifleBullets",
		sprite_row = 4,
		sprite_col = 3,
	},
	item_ammo_plasma = {
		type = "BatteryCells",
		sprite_row = 4,
		sprite_col = 2,
	},
	item_ammo_rockets = {
		type = "Rockets",
		sprite_row = 4,
		sprite_col = 1,
	},
}

function SpawnItem(entity, map_transform)
	print("Spawning item: " .. entity.classname)

	-- Default entity setup
	local new_entity = NewEntity(entity, map_transform)

	-- setup the sprite
	local sprite_props = SpriteComponent.default()
	sprite_props.spritesheet = String.init("sprites/items")
	sprite_props.use_lighting = false
	sprite_props.scale = 0.75

	local item_comp = ItemComponent.default()

	local classname = entity.classname
	if classname:match("^" .. "item_ammo") then
		sprite_props.spritesheet_col = 1
		sprite_props.spritesheet_row = 4

		local ammo = ammos[classname]
		if ammo ~= nil then
			sprite_props.spritesheet_col = ammo.sprite_col
			sprite_props.spritesheet_row = ammo.sprite_row

			item_comp.item_type = "Ammo"
			item_comp.item_subtype_ammo = ammo.type
		else
			print("Ammo " .. classname .. " not found")
		end
	end

	if classname:match("^" .. "item_weapon") then
		local weapon = weapons[classname]
		if weapon ~= nil then
			sprite_props.spritesheet_col = weapon.sprite_col
			sprite_props.spritesheet_row = weapon.sprite_row

			item_comp.item_type = "Weapon"
			item_comp.item_subtype_weapon = weapon.type
		else
			print("Weapon " .. classname .. " not found")
		end
	end

	if classname:match("^" .. "item_medkit") then
		sprite_props.spritesheet_col = 0
		sprite_props.spritesheet_row = 5
		item_comp.item_type = "Medkit"
	end

	SpriteComponent.createNewComponentWithProps(new_entity, sprite_props)
	ItemComponent.createNewComponentWithProps(new_entity, item_comp)

	local collision_comp = BoxCollisionComponent.default()
	collision_comp.size = Vec3.new(1.5, 2.5, 1.5)
	collision_comp.collides_entities = false

	BoxCollisionComponent.createNewComponentWithProps(new_entity, collision_comp)
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
	item_ = SpawnItem,
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

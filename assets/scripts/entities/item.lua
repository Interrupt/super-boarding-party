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

-- Called when packages are discovered
function pkg.Setup()
	QuakeMaps.RegisterEntity("item_", pkg.MapSpawn)
end

function pkg.MapSpawn(entity, quake_map)
	-- print("Spawning item: " .. entity.classname)

	-- Default entity setup
	local new_entity = NewEntity(entity, quake_map)

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

return pkg

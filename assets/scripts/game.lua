local Game = require("Game")
local Vec2 = require("Vec2")
local Vec3 = require("Vec3")
local Quaternion = require("Quaternion")

local LightComponent = require("LightComponent")
local PlayerController = require("PlayerController")
local TextComponent = require("TextComponent")
local MeshComponent = require("MeshComponent")
local SpriteComponent = require("SpriteComponent")
local TransformComponent = require("TransformComponent")
local StatsComponent = require("ActorStats")
local BoxCollisionComponent = require("BoxCollisionComponent")
local CharacterMovementComponent = require("CharacterMovementComponent")
local InventoryComponent = require("InventoryComponent")
local QuakeMapComponent = require("QuakeMapComponent")

local QuakeMap = require("assets/scripts/quakemap") -- Quake Map helper
local String = require("String")

local TestPlayerSprite = nil

local time = 0.0

function _init()
	-- Called once when the app starts
end

function OnGameStart(game_instance)
	-- Called when the game state starts
	print("------ Game.lua OnGameStart! ---------")

	print("Creating player")
	local new_entity = Game.createEntity()
	local player_transform = TransformComponent.createNewComponent(new_entity)
	CharacterMovementComponent.createNewComponent(new_entity)
	local player_controller = PlayerController.createNewComponent(new_entity)
	InventoryComponent.createNewComponent(new_entity)
	BoxCollisionComponent.createNewComponent(new_entity)

	-- Player stats
	local stats = StatsComponent.default()
	stats.max_hp = 100
	stats.hp = stats.max_hp
	stats.speed = 12

	StatsComponent.createNewComponentWithProps(new_entity, stats)

	-- Set this as our player for the game
	Game.setPlayer(player_controller)

	print("Creating map")
	local map_entity = Game.createEntity()
	local map_props = QuakeMapComponent.default()
	map_props.filename:set("assets/standards.map")

	local map_comp = QuakeMapComponent.createNewComponentWithProps(map_entity, map_props)

	print("Setting player start position")
	local temp_pos = map_comp.player_start.pos
	local start_pos = Vec3.new(temp_pos.x, temp_pos.y, temp_pos.z) -- not a bound type, have to do a dance
	player_controller:resetPositionAndAngle(start_pos, map_comp.player_start.angle - 90)

	print("Playing music")
	Game.playMusic("assets/audio/music/WhiteWolf-Digital-era.mp3")

	print("------- Game.lua OnGameStart end ------")
end

function _update()
	time = time + 0.05

	-- DebugEntities()
end

function DebugEntities()
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
	mesh.position_offset = Vec3.new(-2.0, math.sin(time * 0.5) * 0.2, 4.0)
	mesh.scale = (math.sin(time * 0.2) + 1.2) * 0.2
	mesh.rotation_offset = Quaternion.fromAxisAndAngle(time * 20.0, Vec3.y_axis)

	-- sprite test
	if TestPlayerSprite == nil then
		local props = SpriteComponent.default()
		props.spritesheet = String.init("sprites/sprites")
		TestPlayerSprite = SpriteComponent.createNewComponentWithProps(player, props)
	end

	TestPlayerSprite.position_offset = Vec3.new(0.0, math.sin(time * 0.5) * 0.2, 2.0)
	TestPlayerSprite.scale = 1.0 + (math.sin(time * 0.2) * 0.2)
	TestPlayerSprite.rotation_offset = Quaternion.fromAxisAndAngle(time * 20.0, Vec3.y_axis)
	TestPlayerSprite.spritesheet_row = math.floor(time % 5)
	TestPlayerSprite.spritesheet_col = math.floor(time * 2.0 % 4)

	-- text test
	local text = TextComponent.getComponent(player)
	if text == nil then
		local new_text = TextComponent.newFromString("Original String")
		TextComponent.createNewComponentWithProps(player, new_text)
	else
		text.scale = 0.3
		text.position_offset = Vec3.new(3.0, math.sin(time * 0.5) * 0.2, 4.0)
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
end

-- Called when a Quake Map wants to spawn a new entity
function QuakemapSpawnEntity(entity, transform, quake_entity_idx)
	QuakeMap.SpawnEntity(entity, transform, quake_entity_idx)
end

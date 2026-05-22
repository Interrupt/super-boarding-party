local Game = require("Game")
local Vec2 = require("Vec2")
local Vec3 = require("Vec3")
local Color = require("Color")
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

local game_state = {
	death_timer = 0.0,
}

function _init()
	-- Called once when the app starts
end

local player_controller = nil

function OnGameStart(game_instance)
	-- Called when the game state starts
	print("------ Game.lua OnGameStart! ---------")
	game_state.death_timer = 0.0

	print("Creating player")
	local new_entity = Game.createEntity()
	local player_transform = TransformComponent.createNewComponent(new_entity)
	CharacterMovementComponent.createNewComponent(new_entity)
	player_controller = PlayerController.createNewComponent(new_entity)
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

	-- Fade in on start!
	local fade_in_time = 2.0
	player_controller.screen_flash_timer = fade_in_time
	player_controller.screen_flash_time = fade_in_time
	player_controller.screen_flash_color = Color.new(0.0, 0.0, 0.0, 1.0)

	print("------- Game.lua OnGameStart end ------")
end

function OnGameTick(delta)
	-- print("Game tick", delta)

	if player_controller == nil then
		return
	end

	if player_controller:isAlive() ~= true then
		-- Fade out on death
		game_state.death_timer = game_state.death_timer + delta * 0.25
		player_controller.screen_flash_timer = 1000.0
		player_controller.screen_flash_time = 1000.0
		player_controller.screen_flash_color = Color.new(1.0, 0.0, 0.0, game_state.death_timer)

		if game_state.death_timer >= 1.0 then
			print("Player is dead! Showing death screen")
			Game.showDeathScreen()
		end
	end
end

-- Simple Lua lifecycle update func, not used for now
function _update() end

-- Called when a Quake Map wants to spawn a new entity
function QuakemapSpawnEntity(entity, transform, quake_entity_idx)
	QuakeMap.SpawnEntity(entity, transform, quake_entity_idx)
end

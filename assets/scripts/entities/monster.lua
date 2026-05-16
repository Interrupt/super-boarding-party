local String = require("String")
local Vec3 = require("Vec3")
local SpriteComponent = require("SpriteComponent")
local ActorStatsComponent = require("ActorStats")
local BoxCollisionComponent = require("BoxCollisionComponent")
local CharacterMovementComponent = require("CharacterMovementComponent")
local MonsterControllerComponent = require("MonsterController")

local pkg = {}

function pkg.MapSpawn(entity, quake_map)
	-- print("Spawning Env Sprite", entity, map_transform)

	-- props
	local hostile = ValueOrDefault(entity:getStringProperty("hostile"), "true")

	local spritesheet_path = ValueOrDefault(entity:getStringProperty("spritesheet"), "sprites/entities")
	local spritesheet_row = ValueOrDefault(entity:getFloatProperty("spritesheet_row"), 0)
	local spritesheet_col = ValueOrDefault(entity:getFloatProperty("spritesheet_col"), 0)
	local blend = ValueOrDefault(entity:getFloatProperty("blend"), 0)
	local scale = ValueOrDefault(entity:getFloatProperty("scale"), 1.0)

	-- Default entity setup
	local new_entity = NewEntity(entity, quake_map)

	-- Make the sprite component
	local sprite_props = SpriteComponent.default()
	sprite_props.spritesheet = String.init(spritesheet_path)
	sprite_props.spritesheet_col = spritesheet_col
	sprite_props.spritesheet_row = spritesheet_row
	sprite_props.use_lighting = true
	sprite_props.scale = scale * 3.0
	sprite_props.billboard_type = "XZ"
	sprite_props.position = Vec3.new(0, 0.25, 0)

	if blend > 0 then
		sprite_props.blend_mode = "ALPHA"
	end

	SpriteComponent.createNewComponentWithProps(new_entity, sprite_props)

	-- Movement component
	CharacterMovementComponent.createNewComponent(new_entity)

	-- Collision component
	local col_props = BoxCollisionComponent.default()
	col_props.size = Vec3.new(1.5, 2.5, 1.5)
	col_props.can_step_up_on = false
	BoxCollisionComponent.createNewComponentWithProps(new_entity, col_props)

	-- Monster controller
	local monster_controller = MonsterControllerComponent.default()
	monster_controller.hostile = hostile == "true"
	MonsterControllerComponent.createNewComponentWithProps(new_entity, monster_controller)

	-- Actor stats component
	local stats = ActorStatsComponent.default()
	stats.max_hp = 5
	ActorStatsComponent.createNewComponentWithProps(new_entity, stats)
end

return pkg

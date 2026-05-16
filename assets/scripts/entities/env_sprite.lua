local String = require("String")
local SpriteComponent = require("SpriteComponent")

local pkg = {}

function pkg.MapSpawn(entity, quake_map)
	-- print("Spawning Env Sprite", entity, map_transform)

	-- props
	local spritesheet_path = ValueOrDefault(entity:getStringProperty("spritesheet"), "sprites/sprites")
	local spritesheet_row = ValueOrDefault(entity:getFloatProperty("spritesheet_row"), 0)
	local spritesheet_col = ValueOrDefault(entity:getFloatProperty("spritesheet_col"), 0)
	local texture_path = entity:getStringProperty("model")
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

	if texture_path ~= nil then
		sprite_props.texture_path = String.init("assets/" .. texture_path)
	end

	if blend > 0 then
		sprite_props.blend_mode = "ALPHA"
	end

	SpriteComponent.createNewComponentWithProps(new_entity, sprite_props)
end

return pkg

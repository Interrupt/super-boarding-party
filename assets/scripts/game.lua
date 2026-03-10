local Game = require("Game")
local Vec2 = require("Vec2")
local Vec3 = require("Vec3")

local LightComponent = require("LightComponent")

local time = 0.0
function _update()
	time = time + 0.05

	-- Get the player entity
	local player = Game.getPlayer()
	if player == nil then
		return
	end

	-- Get our light component
	local light = LightComponent.getComponent(player)
	if light ~= nil then
		-- Try updating some values on it
		light.brightness = (math.sin(time) + 1.0) * 2.0
		light.position = Vec3.new(0.0, math.sin(time * 0.9) * 2.0, 4.0)
		light.radius = 4.0
	end

	-- LightComponent.createNewComponent(player, light)
end

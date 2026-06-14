print("Monster controller component script running!")

local Game = require("Game")
local Quaternion = require("Quaternion")
local Vec3 = require("Vec3")
local ScriptComponent = require("ScriptComponent")
local MovementComponent = require("CharacterMovementComponent")
local SpriteComponent = require("SpriteComponent")
local ActorStats = require("ActorStats")

-- Components need a table returned with their lifecycle functions in it
local component = {
	alerted = false,
	hostile = true,
}

component.onInit = function(self)
	-- onInit is called when the component is created on an Entity
end

component.onFixedTick = function(self, delta)
	local player = Game.getPlayer()
	if player == nil then
		return
	end

	local stats = ActorStats.getComponent(self.owner)
	if stats == nil then
		return
	end

	if stats:isAlive() ~= true then
		-- don't move when dead!
		return
	end

	-- Move towards our target when alerted
	if self.hostile == true and self.alerted ~= true then
		if self:canSeePlayer(player) then
			self.alerted = true
		end
	end

	-- Stop if idle
	if self.alerted ~= true then
		return
	end

	local movement_comp = MovementComponent.getComponent(self.owner)
	if movement_comp == nil then
		return
	end

	self:moveTowardsTarget(player:getPosition())

	-- local sprite_comp = SpriteComponent.getComponent(self.owner)
	-- if sprite_comp.animation == nil then
	-- 	sprite_comp:playAnimation(0, 0, 2, true, 8.0)
	-- end
end

component.moveTowardsTarget = function(self, target_vec)
	local movement_comp = MovementComponent.getComponent(self.owner)
	if movement_comp == nil then
		return
	end

	local vec_to_target = target_vec:sub(self.owner:getPosition())
	local distance_to_target = vec_to_target:len()

	-- Stop when too close to the target
	if distance_to_target < 0.25 then
		movement_comp.move_dir = Vec3.zero
		return
	end

	movement_comp.move_dir = vec_to_target:norm()
end

component.canSeePlayer = function(self, player)
	local our_pos = self.owner:getPosition()
	local player_pos = player:getPosition()
	local distance = player_pos:sub(our_pos):len()

	if distance > 50.0 then
		return false
	end

	return true
end

component.onMessage = function(self, message, body)
	-- Message received!

	-- TODO: make ourselves alerted when shot!
end

return component

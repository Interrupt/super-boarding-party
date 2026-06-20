print("Spinner component script running!")

local Quaternion = require("Quaternion")
local Vec3 = require("Vec3")
local Game = require("Game")
local ScriptComponent = require("ScriptComponent")

-- Components need a table returned with their lifecycle functions in it
local component = {
	spin_speed = 500.0,
	spin_axis = Vec3.x_axis,
}

component.onInit = function(self)
	-- onInit is called when the component is created on an Entity
	ScriptComponent.listenForMessage(self, nil, "PrintDebug")

	Game.broadcastMessage(nil, "PrintDebug", { "blah" })
end

component.onTick = function(self, delta)
	-- onTick is called every frame
	self:spin(delta)
end

component.onMessage = function(self, filter, message, body)
	-- Message received!
	print("Spinner message received: ", message, body[1])
end

-- spin ourself by our spin speed and axis
component.spin = function(self, delta)
	local owner_rot = self.owner:getRotation()
	local our_rot = Quaternion.fromAxisAndAngle(self.spin_speed * delta, self.spin_axis)
	self.owner:setRotation(owner_rot:mul(our_rot))
end

return component

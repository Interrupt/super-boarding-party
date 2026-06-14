print("Spinner component script running!")

local Quaternion = require("Quaternion")
local Vec3 = require("Vec3")
local ScriptComponent = require("ScriptComponent")

-- Components need a table returned with their lifecycle functions in it
local component = {
	spin_speed = 500.0,
	spin_axis = Vec3.x_axis,
}

component.onInit = function(self)
	-- onInit is called when the component is created on an Entity

	-- ScriptComponent.broadcastMessage(self.owner:getOwningWorld(), "*", "PrintDebug")
end

component.onTick = function(self, delta)
	-- onTick is called every frame
	self:spin(delta)
end

component.onMessage = function(self, message, body)
	-- Message received!
end

-- spin ourself by our spin speed and axis
component.spin = function(self, delta)
	local owner_rot = self.owner:getRotation()
	local our_rot = Quaternion.fromAxisAndAngle(self.spin_speed * delta, self.spin_axis)
	self.owner:setRotation(owner_rot:mul(our_rot))
end

return component

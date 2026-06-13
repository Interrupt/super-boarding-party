print("New component script running!")

local SpinnerComponent = require("SpinnerComponent")

-- Components need a table returned with their lifecycle functions in it
local componentTable = {
	print_timer = 0.0,
}

componentTable.onInit = function(self)
	-- print("Test script component onInit called!", self.run_num)
	self.name = "Test Scripted Component"
end

componentTable.onTick = function(self, delta)
	-- print("  > lua: test script onTick called", self.run_num)

	-- Spin friction
	local spinner = SpinnerComponent.getComponent(self.owner)
	if spinner ~= nil then
		spinner.spin_speed = spinner.spin_speed / 1.01
	end

	-- Print a hello world per second
	self.print_timer = self.print_timer + delta
	if self.print_timer > 1.0 then
		self:helloWorld()
		self.print_timer = 0.0
	end
end

componentTable.helloWorld = function(self)
	print("Hello world!", self.name)

	local spinner = SpinnerComponent.getComponent(self.owner)
	if spinner ~= nil then
		spinner.spin_speed = math.random() * 1000.0
	else
		print("Could not find spinner component!")
	end
end

return componentTable

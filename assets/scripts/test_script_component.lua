print("New component script running!")

if SCRIPT_RUN == nil then
	SCRIPT_RUN = 0
end

SCRIPT_RUN = SCRIPT_RUN + 1

-- Components need a table returned with their lifecycle functions in it
local componentTable = {
	run_num = SCRIPT_RUN,
}

componentTable.onInit = function(self)
	print("Test script component onInit called!", self)
	print("Script run number: ", self.run_num)
end

componentTable.onTick = function(self)
	print("  > lua: test script onTick called", self.run_num)

	-- print(self)
	-- print(componentTable.state.tick)
	-- print("Script Component Update called on component!", idx)
end

return componentTable

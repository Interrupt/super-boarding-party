local Game = require("Game")

print("Registering Quake Map Entities")

-- Discover our quake entity lua packages!
local dir_iterator = Game.listDir("assets/scripts/entities")

local dir_name = nil
repeat
	dir_name = dir_iterator:next()

	-- Check if this is a lua file
	if dir_name ~= nil and string.match(dir_name, ".+%.lua$") then
		-- Strip off the extension
		dir_name = string.sub(dir_name, 0, -5)

		-- Load the package
		local pkg = require("assets/scripts/entities/" .. dir_name)

		-- Run the setup function if it exists
		if type(pkg.Setup) == "function" then
			if DEBUG_MODE then
				print("Found entity package: " .. dir_name)
			end

			pkg.Setup()
		end
	end

-- Repeat until there are no more
until dir_name == nil

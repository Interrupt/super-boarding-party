local Game = require("Game")

local packages = {}

-- Loads all lua packages in a given directory
-- If a package has a Setup function, it will be called
function packages.LoadPackages(search_path)
	print("Searching for lua packages in " .. search_path)

	-- Discover our quake entity lua packages!
	local dir_iterator = Game.listDir(search_path)

	-- stop if directory was not found
	if dir_iterator == nil then
		return
	end

	local file_name = nil
	repeat
		file_name = dir_iterator:next()

		-- Check if this is a lua file
		if file_name ~= nil and string.match(file_name, ".+%.lua$") then
			-- Strip off the extension
			local pkg_name = string.sub(file_name, 0, -5)

			if DEBUG_MODE then
				print("Loading package: " .. file_name)
			end

			-- Load the package
			local pkg = require(search_path .. "/" .. pkg_name)

			-- Run the setup function if it exists
			if type(pkg.Setup) == "function" then
				pkg.Setup()
			end
		end

	-- Repeat until there are no more files
	until file_name == nil
end

return packages

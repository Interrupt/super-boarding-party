local pkg = {}

-- Called when packages are discovered
function pkg.Setup()
	-- Ignore a couple of info entities
	QuakeMaps.RegisterEntity("info_player_start", pkg.MapSpawn)
	QuakeMaps.RegisterEntity("info_landmark", pkg.MapSpawn)
end

function pkg.MapSpawn(entity, quake_map)
	-- print("Spawning Info Entity", entity)
end

return pkg

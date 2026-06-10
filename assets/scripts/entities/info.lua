local pkg = {}

-- Called when packages are discovered
function pkg.Setup()
	-- maybe register all info_* entities instead?
	QuakeMaps.RegisterEntity("info_player_start", pkg.MapSpawn)
	QuakeMaps.RegisterEntity("info_teleport_destination", pkg.MapSpawn)
	QuakeMaps.RegisterEntity("info_landmark", pkg.MapSpawn)
end

function pkg.MapSpawn(entity, quake_map)
	-- print("Spawning Info Entity", entity)

	-- Should make an entity with a name and a transform only
	NewEntity(entity, quake_map)

	-- todo -- add a quake entity component that can store the classname for filtering?
end

return pkg

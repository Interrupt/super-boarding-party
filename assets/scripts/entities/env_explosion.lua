local String = require("String")
local ExplosionComponent = require("ExplosionComponent")

local pkg = {}

-- Called when packages are discovered
function pkg.Setup()
	QuakeMaps.RegisterEntity("env_explosion", pkg.MapSpawn)
end

function pkg.MapSpawn(entity, quake_map)
	-- print("Spawning Env Explosion", entity)

	-- props
	local do_damage = ValueOrDefault(entity:getFloatProperty("do_damage"), 0)

	-- Default entity setup
	local new_entity = NewEntity(entity, quake_map)

	-- Make the sprite component
	local props = ExplosionComponent.default()
	props.state = "WaitingForTrigger"

	if do_damage <= 0 then
		props.range = 0
	end

	ExplosionComponent.createNewComponentWithProps(new_entity, props)
end

return pkg

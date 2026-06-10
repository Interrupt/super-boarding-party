local String = require("String")
local AudioComponent = require("AudioComponent")

local pkg = {}

-- Called when packages are discovered
function pkg.Setup()
	QuakeMaps.RegisterEntity("env_audio", pkg.MapSpawn)

	-- also wire up for quake style ambient_* classes
	QuakeMaps.RegisterEntity("ambient_", pkg.MapSpawn)
end

function pkg.MapSpawn(entity, quake_map)
	-- print("Spawning Env Sprite", entity, map_transform)

	-- props
	local start_silent = ValueOrDefault(entity:getFloatProperty("start_silent"), 0.0) > 0
	local looping = ValueOrDefault(entity:getFloatProperty("loops"), 1.0) > 0
	local audio_path = ValueOrDefault(entity:getStringProperty("path"), "")
	local volume = ValueOrDefault(entity:getFloatProperty("volume"), 1.0)

	local start_mode = "Immediately"
	if start_silent then
		start_mode = "OnTrigger"
	end

	-- handle ambient classes
	if entity.classname == "ambient_comp_hum" then
		audio_path = "assets/audio/sfx/computer-hum.mp3"
	end

	-- Default entity setup
	local new_entity = NewEntity(entity, quake_map)

	-- Make the audio component
	local props = AudioComponent.default()
	props.start_mode = start_mode
	props.sound_path = String.init(audio_path)
	props.looping = looping
	props.volume = volume

	AudioComponent.createNewComponentWithProps(new_entity, props)
end

return pkg

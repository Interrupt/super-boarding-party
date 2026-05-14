local Color = require("Color")
local LightComponent = require("LightComponent")

local pkg = {}

-- Keep this in sync with the light.zig styles enum in zig
local LightStyles = {
	"normal",
	"flicker_1",
	"pulse_slow_1",
	"candle_1",
	"strobe_fast",
	"pulse_gentle",
	"flicker_2",
	"candle_2",
	"candle_3",
	"strobe_slow",
	"flicker_flouro",
	"pulse_slow_2",
}

function pkg.MapSpawn(entity, map_transform)
	-- print("Spawning Light", entity, map_transform)

	-- Default entity setup
	local new_entity = NewEntity(entity, map_transform)

	-- Set default light props
	local light = LightComponent.default()
	light.radius = 10

	-- light
	local light_prop = entity:getFloatProperty("light")
	if light_prop ~= nil then
		light.radius = light_prop * 0.125
	end

	-- radius
	local radius_prop = entity:getFloatProperty("radius")
	if radius_prop ~= nil then
		light.radius = radius_prop
	end

	-- brightness
	local brightness_prop = entity:getFloatProperty("brightness")
	if brightness_prop ~= nil then
		light.brightness = brightness_prop
	end

	-- color
	local color_prop = entity:getVec3Property("_color")
	if color_prop ~= nil then
		light.color = Color.new(color_prop.x / 255.0, color_prop.y / 255.0, color_prop.z / 255.0, 1.0)
	end

	-- off / on
	if entity.spawnflags & 0x01 ~= 0 then
		light.is_on = false
	end

	-- style
	local style_prop = entity:getFloatProperty("style")
	if style_prop ~= nil then
		if style_prop > 0 and style_prop <= #LightStyles then
			light.style = LightStyles[style_prop + 1]
		else
			print("Invalid light style: " .. style_prop)
		end
	end

	LightComponent.createNewComponentWithProps(new_entity, light)
end

return pkg

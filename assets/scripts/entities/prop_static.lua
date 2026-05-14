local Vec3 = require("Vec3")
local Quaternion = require("Quaternion")
local String = require("String")
local MeshComponent = require("MeshComponent")
local TransformComponent = require("TransformComponent")

local pkg = {}

function pkg.MapSpawn(entity, map_transform)
	-- print("Spawning Prop Static Mesh", entity, map_transform)

	-- mesh defaults
	local mesh_path = "assets/meshes/SciFiHelmet.gltf"
	local texture_diffuse = "assets/meshes/SciFiHelmet_BaseColor_512.png"
	local texture_emissive = "assets/meshes/black.png"

	-- Default entity setup
	local new_entity = NewEntity(entity, map_transform)
	local mesh_comp = MeshComponent.default()

	-- Angle
	local angle = entity:getFloatProperty("angle")
	if angle == nil then
		angle = 0
	end

	-- Scale
	local scale = entity:getFloatProperty("scale")
	if scale == nil then
		scale = 1.0
	else
		scale = scale * MapScale
	end

	mesh_comp.scale = scale
	mesh_comp.mesh_path = String.init(mesh_path)
	mesh_comp.texture_diffuse_path = String.init(texture_diffuse)
	mesh_comp.texture_emissive_path = String.init(texture_emissive)
	MeshComponent.createNewComponentWithProps(new_entity, mesh_comp)

	-- set angle
	local transform = TransformComponent.getComponent(new_entity)
	local rot_quat = Quaternion.fromAxisAndAngle(angle, Vec3.y_axis)
	transform.rotation = rot_quat
end

return pkg

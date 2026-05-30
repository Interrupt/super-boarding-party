local Vec3 = require("Vec3")
local Quaternion = require("Quaternion")
local String = require("String")
local MeshComponent = require("MeshComponent")
local TransformComponent = require("TransformComponent")

local pkg = {}

-- Called when packages are discovered
function pkg.Setup()
	QuakeMaps.RegisterEntity("prop_static", pkg.MapSpawn)
end

function pkg.MapSpawn(entity, quake_map)
	-- print("Spawning Prop Static Mesh", entity, map_transform)

	-- mesh defaults
	local mesh_path = "assets/meshes/SciFiHelmet.gltf"
	local texture_diffuse = "assets/meshes/SciFiHelmet_BaseColor_512.png"
	local texture_emissive = "assets/meshes/black.png"

	-- Default entity setup
	local new_entity = NewEntity(entity, quake_map)

	-- Props
	local angle = ValueOrDefault(entity:getFloatProperty("angle"), 0)
	local scale = ValueOrDefault(entity:getFloatProperty("scale"), 1.0 / MapScale)

	-- Make mesh component
	local mesh_comp = MeshComponent.default()
	mesh_comp.scale = scale * MapScale
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

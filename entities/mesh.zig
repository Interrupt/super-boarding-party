const std = @import("std");
const delve = @import("delve");
const math = delve.math;
const entities = @import("../game/entities.zig");
const textures = @import("../managers/textures.zig");

const graphics = delve.platform.graphics;
const debug = delve.debug;

const emissive_shader_builtin = delve.shaders.default_basic_lighting;

pub const MeshComponent = struct {
    position: math.Vec3 = math.Vec3.zero,
    scale: f32 = 1.0,
    color: delve.colors.Color = delve.colors.white,
    position_offset: math.Vec3 = math.Vec3.zero,
    rotation_offset: math.Quaternion = math.Quaternion.identity,

    mesh_path: [:0]const u8 = "assets/meshes/SciFiHelmet.gltf",
    texture_diffuse_path: [:0]const u8 = "assets/meshes/SciFiHelmet_BaseColor_512.png",
    texture_emissive_path: [:0]const u8 = "assets/meshes/SciFiHelmet_Emissive_512.png",

    mesh: ?delve.graphics.mesh.Mesh = null,

    attach_to_parent: bool = true,

    // interface
    owner: entities.Entity = entities.InvalidEntity,

    // calculated
    world_position: math.Vec3 = undefined,

    pub fn init(self: *MeshComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;

        // If we've been given a mesh, just stop here
        if (self.mesh != null)
            return;

        // Load the base color texture for the mesh
        const tex_base = textures.getOrLoadTexture(self.texture_diffuse_path);

        // Load the emissive texture for the mesh
        const tex_emissive = textures.getOrLoadTexture(self.texture_emissive_path);

        // Make our emissive shader from one that is pre-compiled
        const shader = graphics.Shader.initFromBuiltin(.{ .vertex_attributes = delve.graphics.mesh.getShaderAttributes() }, emissive_shader_builtin) catch {
            debug.log("Error creating shader for mesh component", .{});
            return;
        };

        // Create a material out of our shader and textures
        const material = graphics.Material.init(.{
            .shader = shader,
            .texture_0 = tex_base.texture,
            .texture_1 = tex_emissive.texture,
            .samplers = &[_]graphics.FilterMode{.NEAREST},

            // use the FS layout that supports lighting
            .default_fs_uniform_layout = delve.platform.graphics.default_lit_fs_uniforms,
        }) catch {
            debug.log("Error creating material for mesh component", .{});
            return;
        };

        // now we can make our mesh
        self.mesh = delve.graphics.mesh.Mesh.initFromFile(delve.mem.getAllocator(), self.mesh_path, .{ .material = material });
    }

    pub fn deinit(self: *MeshComponent) void {
        if (self.mesh) |*mesh| {
            mesh.material.deinit();
            mesh.deinit();
        }
    }

    pub fn tick(self: *MeshComponent, delta: f32) void {
        _ = delta;

        // cache our final world position
        if (self.attach_to_parent) {
            const owner_rotation = self.owner.getRotation();
            self.world_position = self.owner.getRenderPosition().add(owner_rotation.rotateVec3(self.position));
        } else {
            self.world_position = self.position;
        }
    }
};

pub fn getComponentStorage(world: *entities.World) *entities.ComponentStorage(MeshComponent) {
    return world.components.getStorageForType(MeshComponent) catch {
        delve.debug.fatal("Could not get MeshComponent storage!", .{});
        return undefined;
    };
}

const std = @import("std");
const delve = @import("delve");
const math = delve.math;
const entities = @import("../game/entities.zig");
const textures = @import("../managers/textures.zig");
const string = @import("../utils/string.zig");

const graphics = delve.platform.graphics;
const debug = delve.debug;

const emissive_shader_builtin = delve.shaders.default_basic_lighting;

const default_mesh_path: [:0]const u8 = "assets/meshes/SciFiHelmet.gltf";
const default_diffuse_tex_path: []const u8 = "assets/meshes/SciFiHelmet_BaseColor_512.png";
const default_emissive_tex_path: []const u8 = "assets/meshes/SciFiHelmet_Emissive_512.png";

pub const MeshComponent = struct {
    position: math.Vec3 = math.Vec3.zero,
    scale: f32 = 1.0,
    color: delve.colors.Color = delve.colors.white,
    position_offset: math.Vec3 = math.Vec3.zero,
    rotation_offset: math.Quaternion = math.Quaternion.identity,

    mesh_path: ?string.String = null,
    texture_diffuse_path: ?string.String = null,
    texture_emissive_path: ?string.String = null,

    attach_to_parent: bool = true,

    // calculated
    _mesh: ?delve.graphics.mesh.Mesh = null,

    // interface
    owner: entities.Entity = entities.InvalidEntity,

    // calculated
    world_position: math.Vec3 = undefined,
    _shader: ?delve.platform.graphics.Shader = null,

    pub fn init(self: *MeshComponent, interface: entities.EntityComponent) void {
        self.owner = interface.owner;

        // If we've been given a mesh, just stop here
        if (self._mesh != null)
            return;

        const mesh_path = if (self.mesh_path != null) self.mesh_path.?.str else default_mesh_path;
        const diffuse_path = if (self.texture_diffuse_path != null) self.texture_diffuse_path.?.str else default_diffuse_tex_path;
        const emissive_path = if (self.texture_emissive_path != null) self.texture_emissive_path.?.str else default_emissive_tex_path;

        // Load the base color texture for the mesh
        const tex_base = textures.getOrLoadTexture(diffuse_path);

        // Load the emissive texture for the mesh
        const tex_emissive = textures.getOrLoadTexture(emissive_path);

        // Make our emissive shader from one that is pre-compiled
        // TODO: Get a common shader from somewhere!
        self._shader = graphics.Shader.initFromBuiltin(.{ .vertex_attributes = delve.graphics.mesh.getShaderAttributes() }, emissive_shader_builtin) catch {
            debug.log("Error creating shader for mesh component", .{});
            return;
        };

        // Create a material out of our shader and textures
        const material = graphics.Material.init(.{
            .shader = self._shader,
            .texture_0 = tex_base.texture,
            .texture_1 = tex_emissive.texture,
            .samplers = &[_]graphics.FilterMode{.NEAREST},

            // use the FS layout that supports lighting
            .default_fs_uniform_layout = delve.platform.graphics.default_lit_fs_uniforms,
        }) catch {
            debug.log("Error creating material for mesh component", .{});
            return;
        };

        self.loadAndSetMesh(mesh_path, material) catch {
            debug.warning("Could not load mesh in mesh component!", .{});
        };
    }

    pub fn loadAndSetMesh(self: *MeshComponent, mesh_path: []const u8, material: graphics.Material) !void {
        var allocator = delve.mem.getAllocator();

        // clear out the old mesh
        if (self._mesh) |*mesh| {
            mesh.deinit();
        }

        // build our sentinel terminated mesh path
        var final_mesh_path = std.ArrayList(u8).init(allocator);
        try final_mesh_path.appendSlice(mesh_path);

        const mesh_path_z = try final_mesh_path.toOwnedSliceSentinel(0);
        defer allocator.free(mesh_path_z);

        const mesh = delve.graphics.mesh.Mesh.initFromFile(allocator, mesh_path_z, .{ .material = material });
        self._mesh = mesh;
    }

    pub fn deinit(self: *MeshComponent) void {
        if (self._mesh) |*mesh| {
            mesh.material.deinit();
            mesh.deinit();
        }

        if (self._shader) |*s| {
            s.destroy();
        }

        if (self.mesh_path) |*str| {
            str.deinit();
        }
        if (self.texture_diffuse_path) |*str| {
            str.deinit();
        }
        if (self.texture_emissive_path) |*str| {
            str.deinit();
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

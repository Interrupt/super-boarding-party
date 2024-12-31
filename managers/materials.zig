const std = @import("std");
const delve = @import("delve");
const math = delve.math;
const graphics = delve.platform.graphics;

const Material = graphics.Material;

pub const lit_shader = delve.shaders.default_basic_lighting;
pub const basic_lighting_fs_uniforms: []const delve.platform.graphics.MaterialUniformDefaults = &[_]delve.platform.graphics.MaterialUniformDefaults{ .CAMERA_POSITION, .COLOR_OVERRIDE, .ALPHA_CUTOFF, .AMBIENT_LIGHT, .DIRECTIONAL_LIGHT, .POINT_LIGHTS_16, .FOG_DATA };

pub var world_shader: graphics.Shader = undefined;

var cached_materials: std.StringHashMap(Material) = undefined;
var missing_material: Material = undefined;

pub fn init() !void {
    // our global world shader. maybe load this in the renderer?
    world_shader = try graphics.Shader.initFromBuiltin(.{ .vertex_attributes = delve.graphics.mesh.getShaderAttributes() }, lit_shader);

    cached_materials = std.StringHashMap(Material).init(delve.mem.getAllocator());

    // create a fallback material
    const fallback_tex = graphics.createDebugTexture();
    const black_tex = delve.platform.graphics.createSolidTexture(0x00000000);

    missing_material = try graphics.Material.init(.{
        .shader = world_shader,
        .texture_0 = fallback_tex,
        .texture_1 = black_tex,
        .samplers = &[_]graphics.FilterMode{.NEAREST},
        .default_fs_uniform_layout = basic_lighting_fs_uniforms,
    });
}

pub fn getMaterial(material_name: [:0]const u8) ?Material {
    if (cached_materials.get(material_name)) |mat| {
        return mat;
    }

    return null;
}

pub fn cacheMaterial(material_name: [:0]const u8, material: Material) void {
    cached_materials.put(material_name, material) catch {
        delve.debug.log("Could not cache material '{s}'", .{material_name});
    };
}

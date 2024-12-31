const std = @import("std");
const delve = @import("delve");
const math = delve.math;
const graphics = delve.platform.graphics;

pub const LoadedTexture = struct {
    texture: graphics.Texture,
    size: math.Vec2,
};

var loaded_textures: std.StringHashMap(LoadedTexture) = undefined;
var missing_texture: LoadedTexture = undefined;

pub fn init() !void {
    loaded_textures = std.StringHashMap(LoadedTexture).init(delve.mem.getAllocator());
    missing_texture = .{
        .texture = graphics.createDebugTexture(),
        .size = math.Vec2.new(1, 1),
    };
}

pub fn getOrLoadTexture(texture_path: [:0]const u8) LoadedTexture {
    if (loaded_textures.get(texture_path)) |tex| {
        return tex;
    }

    var tex_img: delve.images.Image = delve.images.loadFile(texture_path) catch {
        delve.debug.log("Could not load image: {s}", .{texture_path});
        return missing_texture;
    };
    defer tex_img.deinit();

    const tex = graphics.Texture.init(tex_img);

    const loaded_tex: LoadedTexture = .{
        .texture = tex,
        .size = math.Vec2.new(@floatFromInt(tex_img.width), @floatFromInt(tex_img.height)),
    };

    // cache the new texture
    loaded_textures.put(texture_path, loaded_tex) catch {
        delve.debug.log("Could not cache texture", .{});
        return missing_texture;
    };

    return loaded_tex;
}

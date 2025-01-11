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

pub fn deinit() void {
    delve.debug.log("Texture manager tearing down", .{});
    const allocator = delve.mem.getAllocator();

    missing_texture.texture.destroy();

    var it = loaded_textures.iterator();
    while (it.next()) |t| {
        t.value_ptr.texture.destroy();
        allocator.free(t.key_ptr.*);
    }
    loaded_textures.deinit();
}

pub fn getOrLoadTexture(texture_path: []const u8) LoadedTexture {
    return tryGetOrLoadTexture(texture_path) catch {
        return missing_texture;
    };
}

pub fn tryGetOrLoadTexture(texture_path: []const u8) !LoadedTexture {
    if (loaded_textures.get(texture_path)) |tex| {
        return tex;
    }

    const allocator = delve.mem.getAllocator();

    // for loading the file
    var tex_path_null = std.ArrayList(u8).init(allocator);
    try tex_path_null.appendSlice(texture_path);
    try tex_path_null.append(0);
    defer tex_path_null.deinit();

    var tex_img: delve.images.Image = delve.images.loadFile(tex_path_null.items[0 .. tex_path_null.items.len - 1 :0]) catch {
        delve.debug.warning("Could not load image: {s}", .{texture_path});
        return missing_texture;
    };
    defer tex_img.deinit();

    const tex = graphics.Texture.init(tex_img);
    const loaded_tex: LoadedTexture = .{
        .texture = tex,
        .size = math.Vec2.new(@floatFromInt(tex_img.width), @floatFromInt(tex_img.height)),
    };

    // own our textures key
    var tex_path = std.ArrayList(u8).init(allocator);
    try tex_path.appendSlice(texture_path);

    // cache the new texture
    try loaded_textures.put(try tex_path.toOwnedSlice(), loaded_tex);

    return loaded_tex;
}

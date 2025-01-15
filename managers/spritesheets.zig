const std = @import("std");
const delve = @import("delve");
const textures = @import("../managers/textures.zig");

const lit_sprite_shader = @import("../shaders/lit-sprites.glsl.zig");

const sprites = delve.graphics.sprites;

pub const SpriteSheet = struct {
    allocator: std.mem.Allocator,

    texture: delve.platform.graphics.Texture,
    animations: std.StringHashMap(sprites.SpriteAnimation),
    rows: std.ArrayList(sprites.SpriteAnimation),

    // spritesheets all hold a number of basic materials for convenience
    material: delve.platform.graphics.Material,
    material_blend: delve.platform.graphics.Material,
    material_flash: delve.platform.graphics.Material,
    material_unlit: delve.platform.graphics.Material,
    material_blend_unlit: delve.platform.graphics.Material,

    unlit_shader: delve.platform.graphics.Shader,
    lit_shader: delve.platform.graphics.Shader,

    pub fn init(allocator: std.mem.Allocator, texture: delve.platform.graphics.Texture) !SpriteSheet {
        const lit_shader = try delve.platform.graphics.Shader.initFromBuiltin(.{}, lit_sprite_shader);
        const default_shader = try delve.platform.graphics.Shader.initDefault(.{});

        const material = try delve.platform.graphics.Material.init(.{
            .shader = lit_shader,
            .texture_0 = texture,
            .cull_mode = .NONE,
            .blend_mode = .NONE,
            .samplers = &[_]delve.platform.graphics.FilterMode{.NEAREST},

            .default_fs_uniform_layout = delve.platform.graphics.default_lit_fs_uniforms,
        });

        const material_unlit = try delve.platform.graphics.Material.init(.{
            .shader = default_shader,
            .texture_0 = texture,
            .cull_mode = .NONE,
            .blend_mode = .NONE,
            .samplers = &[_]delve.platform.graphics.FilterMode{.NEAREST},
        });

        const material_blend = try delve.platform.graphics.Material.init(.{
            .shader = lit_shader,
            .texture_0 = texture,
            .cull_mode = .NONE,
            .blend_mode = .BLEND,
            .depth_write_enabled = false,
            .samplers = &[_]delve.platform.graphics.FilterMode{.NEAREST},

            .default_fs_uniform_layout = delve.platform.graphics.default_lit_fs_uniforms,
        });

        const material_blend_unlit = try delve.platform.graphics.Material.init(.{
            .shader = default_shader,
            .texture_0 = texture,
            .cull_mode = .NONE,
            .blend_mode = .BLEND,
            .depth_write_enabled = false,
            .samplers = &[_]delve.platform.graphics.FilterMode{.NEAREST},
        });

        var material_flash = try delve.platform.graphics.Material.init(.{
            .shader = lit_shader,
            .texture_0 = texture,
            .cull_mode = .NONE,
            .blend_mode = .NONE,
            .samplers = &[_]delve.platform.graphics.FilterMode{.NEAREST},

            .default_fs_uniform_layout = delve.platform.graphics.default_lit_fs_uniforms,
        });
        material_flash.state.params = .{ .color_override = delve.colors.Color.new(1.0, 0.8, 0.8, 1.0) };

        return SpriteSheet{
            .allocator = allocator,
            .texture = texture,
            .animations = std.StringHashMap(sprites.SpriteAnimation).init(allocator),
            .rows = std.ArrayList(sprites.SpriteAnimation).init(allocator),
            .material = material,
            .material_unlit = material_unlit,
            .material_blend = material_blend,
            .material_blend_unlit = material_blend_unlit,
            .material_flash = material_flash,
            .unlit_shader = default_shader,
            .lit_shader = lit_shader,
        };
    }

    pub fn deinit(self: *SpriteSheet) void {
        // Cleanup SpriteAnimation entries
        var it = self.animations.valueIterator();
        while (it.next()) |sprite_anim_ptr| {
            self.allocator.free(sprite_anim_ptr.frames);
        }

        // Also cleanup the key names that we allocated
        var key_it = self.animations.keyIterator();
        while (key_it.next()) |key_ptr| {
            self.allocator.free(key_ptr.*);
        }

        self.material.deinit();
        self.material_unlit.deinit();
        self.material_blend.deinit();
        self.material_blend_unlit.deinit();
        self.material_flash.deinit();

        self.lit_shader.destroy();
        self.unlit_shader.destroy();

        self.texture.destroy();
        self.animations.deinit();
        self.rows.deinit();
    }

    /// Play the animation under the given animation name
    pub fn playAnimation(self: *SpriteSheet, animation_name: [:0]const u8) ?sprites.PlayingAnimation {
        const entry = self.getAnimation(animation_name);
        if (entry == null)
            return null;

        return entry.?.play();
    }

    // Get the animation under the given animation name
    pub fn getAnimation(self: *SpriteSheet, animation_name: [:0]const u8) ?sprites.SpriteAnimation {
        return self.entries.get(animation_name);
    }

    /// Get a sprite frame by row and column indices
    pub fn getSprite(self: *SpriteSheet, row: usize, column: usize) ?sprites.AnimationFrame {
        if (row >= self.rows.items.len) {
            delve.debug.log("Sprite row {d} out of bounds! len {d}", .{ row, self.rows.items.len });
            return null;
        }

        const row_entry = self.rows.items[row];
        if (column >= row_entry.frames.len) {
            delve.debug.log("Sprite column {d} out of bounds! len {d}", .{ column, row_entry.frames.len });
            return null;
        }

        return row_entry.frames[column];
    }

    /// Get the first sprite under the given name
    pub fn getSpriteFromRowName(self: *SpriteSheet, anim_name: [:0]const u8, sprite_idx: usize) ?sprites.AnimationFrame {
        const entry = self.animations.get(anim_name);
        if (entry == null)
            return null;

        if (entry.frames == 0 or entry.frames.len >= sprite_idx)
            return null;

        return entry.frames[sprite_idx];
    }

    pub fn playAnimationByIndex(self: *SpriteSheet, idx: usize) ?sprites.PlayingAnimation {
        if (idx >= self.rows.items.len)
            return null;

        return self.rows.items[idx].play();
    }

    /// Creates a series of animations: one per row in a grid where the columns are frames
    pub fn initFromGrid(texture: delve.platform.graphics.Texture, rows: u32, cols: u32, anim_name_prefix: [:0]const u8) !SpriteSheet {
        const allocator = delve.mem.getAllocator();
        var sheet = try SpriteSheet.init(allocator, texture);
        const rows_f: f32 = @floatFromInt(rows);
        const cols_f: f32 = @floatFromInt(cols);

        for (0..rows) |row_idx| {
            const row_idx_f: f32 = @floatFromInt(row_idx);
            const reg_v = row_idx_f / rows_f;
            const reg_v_2 = (row_idx_f + 1) / rows_f;

            var frames = try std.ArrayList(sprites.AnimationFrame).initCapacity(allocator, cols);
            errdefer frames.deinit();

            for (0..cols) |col_idx| {
                const col_idx_f: f32 = @floatFromInt(col_idx);
                const reg_u = col_idx_f / cols_f;
                const reg_u_2 = (col_idx_f + 1) / cols_f;

                try frames.append(sprites.AnimationFrame{ .region = sprites.TextureRegion{
                    .u = reg_u,
                    .v = reg_v,
                    .u_2 = reg_u_2,
                    .v_2 = reg_v_2,
                } });
            }

            // when converting an ArrayList to an owned slice, we don't need to deinit it
            const animation = sprites.SpriteAnimation{ .frames = try frames.toOwnedSlice() };

            var string_writer = std.ArrayList(u8).init(allocator);
            errdefer string_writer.deinit();

            try string_writer.writer().print("{s}{d}", .{ anim_name_prefix, row_idx });
            const anim_name = try string_writer.toOwnedSlice();

            try sheet.animations.put(anim_name, animation);
            try sheet.rows.append(animation);
        }

        return sheet;
    }
};

// Sprite sheet asset management
pub var sprite_sheets: std.StringHashMap(SpriteSheet) = undefined;

pub fn init() !void {
    sprite_sheets = std.StringHashMap(SpriteSheet).init(delve.mem.getAllocator());
}

pub fn deinit() void {
    var it = sprite_sheets.valueIterator();
    while (it.next()) |sprite_sheet_ptr| {
        sprite_sheet_ptr.deinit();
    }
    sprite_sheets.deinit();
}

pub fn loadSpriteSheet(sheet_name: [:0]const u8, texture_path: [:0]const u8, columns: usize, rows: usize) !*SpriteSheet {
    // don't stomp over an existing spritesheet!
    if (getSpriteSheet(sheet_name)) |s| {
        return s;
    }

    // make the texture
    const spritesheet_texture = textures.getOrLoadTexture(texture_path).texture;

    const new_sheet = try SpriteSheet.initFromGrid(spritesheet_texture, @intCast(rows), @intCast(columns), "");

    try sprite_sheets.put(sheet_name, new_sheet);
    return sprite_sheets.getPtr(sheet_name).?;
}

pub fn getSpriteSheet(sheet_name: []const u8) ?*SpriteSheet {
    return sprite_sheets.getPtr(sheet_name);
}

pub fn getSpriteSheetZ(sheet_name: [:0]const u8) ?*SpriteSheet {
    return sprite_sheets.getPtr(sheet_name);
}

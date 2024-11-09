const std = @import("std");
const delve = @import("delve");

const sprites = delve.graphics.sprites;

pub const SpriteSheet = struct {
    texture: delve.platform.graphics.Texture,
    animations: std.StringHashMap(sprites.SpriteAnimation),
    rows: std.ArrayList(sprites.SpriteAnimation),

    material: delve.platform.graphics.Material,
    material_blend: delve.platform.graphics.Material,
    material_flash: delve.platform.graphics.Material,

    pub fn init(allocator: std.mem.Allocator, texture: delve.platform.graphics.Texture) !SpriteSheet {
        const material = try delve.platform.graphics.Material.init(.{
            .texture_0 = texture,
            .cull_mode = .BACK,
            .blend_mode = .NONE,
            .samplers = &[_]delve.platform.graphics.FilterMode{.NEAREST},
        });

        const material_blend = try delve.platform.graphics.Material.init(.{
            .texture_0 = texture,
            .cull_mode = .BACK,
            .blend_mode = .BLEND,
            .samplers = &[_]delve.platform.graphics.FilterMode{.NEAREST},
        });

        var material_flash = try delve.platform.graphics.Material.init(.{
            .texture_0 = texture,
            .cull_mode = .BACK,
            .blend_mode = .NONE,
            .samplers = &[_]delve.platform.graphics.FilterMode{.NEAREST},
        });
        material_flash.state.params = .{ .color_override = delve.colors.Color.new(1.0, 0.8, 0.8, 1.0) };

        return SpriteSheet{
            .texture = texture,
            .animations = std.StringHashMap(sprites.SpriteAnimation).init(allocator),
            .rows = std.ArrayList(sprites.SpriteAnimation).init(allocator),
            .material = material,
            .material_blend = material_blend,
            .material_flash = material_flash,
        };
    }

    pub fn deinit(self: *SpriteSheet) void {
        // Cleanup SpriteAnimation entries
        var it = self.entries.valueIterator();
        while (it.next()) |sprite_anim_ptr| {
            self.allocator.free(sprite_anim_ptr.frames);
        }

        // Also cleanup the key names that we allocated
        var key_it = self.entries.keyIterator();
        while (key_it.next()) |key_ptr| {
            self.allocator.free(key_ptr.*);
        }

        self.entries.deinit();
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
// TODO: Move this to some common assets place!

var sprite_sheets: ?std.StringHashMap(SpriteSheet) = null;

pub fn loadSpriteSheet(sheet_name: [:0]const u8, texture_path: [:0]const u8, columns: usize, rows: usize) !*SpriteSheet {
    var spritesheet_image = try delve.images.loadFile(texture_path);
    defer spritesheet_image.deinit();

    // make the texture
    const spritesheet_texture = delve.platform.graphics.Texture.init(spritesheet_image);

    if (sprite_sheets == null)
        sprite_sheets = std.StringHashMap(SpriteSheet).init(delve.mem.getAllocator());

    const new_sheet = try SpriteSheet.initFromGrid(spritesheet_texture, @intCast(rows), @intCast(columns), "");

    try sprite_sheets.?.put(sheet_name, new_sheet);
    return sprite_sheets.?.getPtr(sheet_name).?;
}

pub fn getSpriteSheet(sheet_name: [:0]const u8) ?*SpriteSheet {
    if (sprite_sheets == null) {
        delve.debug.log("SpriteSheets is null!", .{});
        return null;
    }

    return sprite_sheets.?.getPtr(sheet_name);
}

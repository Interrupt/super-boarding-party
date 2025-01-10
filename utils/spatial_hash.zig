pub const delve = @import("delve");
pub const std = @import("std");

pub const math = delve.math;
pub const spatial = delve.spatial;

pub const SpatialHashLoc = struct {
    x_cell: i32,
    y_cell: i32,
    z_cell: i32,
};

pub fn Cell(comptime SpatialHashType: type) type {
    return struct {
        entries: std.ArrayList(*SpatialHashType),
    };
}

pub fn SpatialHash(comptime SpatialHashType: type) type {
    const SpatialHashCell = Cell(SpatialHashType);
    return struct {
        cell_size: f32,
        allocator: std.mem.Allocator,
        cells: std.AutoHashMap(SpatialHashLoc, SpatialHashCell),

        bounds: spatial.BoundingBox = undefined,
        scratch: std.ArrayList(*SpatialHashType),

        const Self = @This();

        /// Creates a new spatial hash
        pub fn init(cell_size: f32, allocator: std.mem.Allocator) Self {
            const floatMax = std.math.floatMax(f32);
            const floatMin = std.math.floatMin(f32);

            return .{
                .cell_size = cell_size,
                .allocator = allocator,
                .cells = std.AutoHashMap(SpatialHashLoc, SpatialHashCell).init(allocator),
                .scratch = std.ArrayList(*SpatialHashType).init(allocator),
                .bounds = spatial.BoundingBox.init(math.Vec3.new(floatMax, floatMax, floatMax), math.Vec3.new(floatMin, floatMin, floatMin)),
            };
        }

        /// Clears any existing buckets in the spatial hash, retaining capacity
        pub fn clear(self: *Self) void {
            var it = self.cells.valueIterator();
            while (it.next()) |cell| {
                cell.entries.clearRetainingCapacity();
            }
        }

        pub fn deinit(self: *Self) void {
            self.scratch.deinit();

            var it = self.cells.valueIterator();
            while (it.next()) |cell| {
                cell.entries.deinit();
            }

            self.cells.deinit();
        }

        pub fn locToCellSpace(self: *Self, loc: delve.math.Vec3) SpatialHashLoc {
            return .{
                .x_cell = @intFromFloat(@floor(loc.x / self.cell_size)),
                .y_cell = @intFromFloat(@floor(loc.y / self.cell_size)),
                .z_cell = @intFromFloat(@floor(loc.z / self.cell_size)),
            };
        }

        pub fn locToCellSpaceVec3(self: *Self, loc: delve.math.Vec3) delve.math.Vec3 {
            return .{
                .x = loc.x / self.cell_size,
                .y = loc.y / self.cell_size,
                .z = loc.z / self.cell_size,
            };
        }

        /// Gathers all entries near a bounding box
        pub fn getEntriesNear(self: *Self, bounds: spatial.BoundingBox) []*SpatialHashType {
            self.scratch.clearRetainingCapacity();

            // This is not always exact, so add a bit of an epsilon here!
            const area = bounds.inflate(0.01);

            if (!self.bounds.intersects(area)) {
                return self.scratch.items;
            }

            const min = self.locToCellSpace(area.min);
            const max = self.locToCellSpace(area.max);

            // const log_center = self.locToCellSpace(area.center);
            // delve.debug.log("Loc: {d} {d} {d}", .{ log_center.x_cell, log_center.y_cell, log_center.z_cell });

            const num_x: usize = @intCast(max.x_cell - min.x_cell);
            const num_y: usize = @intCast(max.y_cell - min.y_cell);
            const num_z: usize = @intCast(max.z_cell - min.z_cell);

            for (0..num_x + 1) |x| {
                for (0..num_y + 1) |y| {
                    for (0..num_z + 1) |z| {
                        const hash_key = .{ .x_cell = min.x_cell + @as(i32, @intCast(x)), .y_cell = min.y_cell + @as(i32, @intCast(y)), .z_cell = min.z_cell + @as(i32, @intCast(z)) };
                        self.addUniqueEntriesFromCell(&self.scratch, hash_key);
                    }
                }
            }

            return self.scratch.items;
        }

        /// Gets all entries found along a ray segment
        pub fn getEntriesAlong(self: *Self, ray_start: math.Vec3, ray_end: math.Vec3) []*SpatialHashType {
            self.scratch.clearRetainingCapacity();

            // Use the DDA algorithm to collect entries from all encountered cells for this ray segment

            const ray = ray_end.sub(ray_start);
            const ray_len = ray.len();
            const ray_dir = ray.norm();

            // first, check if we have anything to do here at all
            // const check_ray = delve.spatial.Ray.init(ray_start, ray);
            // if (check_ray.intersectBoundingBox(self.bounds) == null) {
            //     return self.scratch.items;
            // }

            // find the starting and ending cells
            const ray_start_cell: SpatialHashLoc = self.locToCellSpace(ray_start);
            const ray_end_cell: SpatialHashLoc = self.locToCellSpace(ray_end);

            const step_x: i32 = if (ray_dir.x >= 0) 1 else -1;
            const step_y: i32 = if (ray_dir.y >= 0) 1 else -1;
            const step_z: i32 = if (ray_dir.z >= 0) 1 else -1;

            const step_x_f: f32 = @floatFromInt(step_x);
            const step_y_f: f32 = @floatFromInt(step_y);
            const step_z_f: f32 = @floatFromInt(step_z);

            // distance along the ray to the next cell boundary
            const next_cell_boundary_x: f32 = @as(f32, @floatFromInt(ray_start_cell.x_cell + step_x)) * self.cell_size;
            const next_cell_boundary_y: f32 = @as(f32, @floatFromInt(ray_start_cell.y_cell + step_y)) * self.cell_size;
            const next_cell_boundary_z: f32 = @as(f32, @floatFromInt(ray_start_cell.z_cell + step_z)) * self.cell_size;

            // distance until the next vertical cell boundary
            var t_max_x = if (ray_dir.x != 0) (next_cell_boundary_x - ray_start.x) / ray_dir.x else std.math.floatMax(f32);
            var t_max_y = if (ray_dir.y != 0) (next_cell_boundary_y - ray_start.y) / ray_dir.y else std.math.floatMax(f32);
            var t_max_z = if (ray_dir.z != 0) (next_cell_boundary_z - ray_start.z) / ray_dir.z else std.math.floatMax(f32);

            // how far the ray needs to travel to equal the width of a cell
            const t_delta_x = if (ray_dir.x != 0) self.cell_size / ray_dir.x * step_x_f else std.math.floatMax(f32);
            const t_delta_y = if (ray_dir.y != 0) self.cell_size / ray_dir.y * step_y_f else std.math.floatMax(f32);
            const t_delta_z = if (ray_dir.z != 0) self.cell_size / ray_dir.z * step_z_f else std.math.floatMax(f32);

            var diff_vec = math.Vec3.new(0, 0, 0);
            var negative_ray = false;
            if (ray_start_cell.x_cell != ray_end_cell.x_cell and ray_dir.x < 0) {
                diff_vec.x = -1;
                negative_ray = true;
            }
            if (ray_start_cell.y_cell != ray_end_cell.y_cell and ray_dir.y < 0) {
                diff_vec.y = -1;
                negative_ray = true;
            }
            if (ray_start_cell.z_cell != ray_end_cell.z_cell and ray_dir.z < 0) {
                diff_vec.z = -1;
                negative_ray = true;
            }

            var current_cell = ray_start_cell;

            if (negative_ray) {
                current_cell.x_cell += @intFromFloat(diff_vec.x);
                current_cell.y_cell += @intFromFloat(diff_vec.y);
                current_cell.z_cell += @intFromFloat(diff_vec.z);
            }

            // delve.debug.log("Visited cell: {d} {d} {d}", .{ current_cell.x_cell, current_cell.y_cell, current_cell.z_cell });
            self.addUniqueEntriesFromCell(&self.scratch, current_cell);

            // guard against looping forever!
            const max_hops: i32 = @as(i32, @intFromFloat(ray_len / self.cell_size)) * 2;
            var cur_hops: i32 = 0;
            while (current_cell.x_cell != ray_end_cell.x_cell or current_cell.y_cell != ray_end_cell.y_cell or current_cell.z_cell != ray_end_cell.z_cell) {
                if (t_max_x < t_max_y) {
                    if (t_max_x < t_max_z) {
                        current_cell.x_cell += step_x;
                        t_max_x += t_delta_x;
                    } else {
                        current_cell.z_cell += step_z;
                        t_max_z += t_delta_z;
                    }
                } else {
                    if (t_max_y < t_max_z) {
                        current_cell.y_cell += step_y;
                        t_max_y += t_delta_y;
                    } else {
                        current_cell.z_cell += step_z;
                        t_max_z += t_delta_z;
                    }
                }

                // delve.debug.log("Visited cell: {d} {d} {d}", .{ current_cell.x_cell, current_cell.y_cell, current_cell.z_cell });
                self.addUniqueEntriesFromCell(&self.scratch, current_cell);

                cur_hops += 1;
                if (cur_hops > max_hops)
                    break;
            }

            return self.scratch.items;
        }

        pub fn addUniqueEntriesFromCell(self: *Self, add_to_list: *std.ArrayList(*SpatialHashType), loc: SpatialHashLoc) void {
            if (self.cells.getPtr(loc)) |cell| {
                // Only return unique entries!
                for (cell.entries.items) |entry| {
                    var existing = false;
                    for (add_to_list.items) |existing_entry| {
                        if (entry == existing_entry) {
                            existing = true;
                            break;
                        }
                    }

                    if (existing)
                        continue;

                    add_to_list.append(entry) catch {};
                }
            }
        }

        /// Adds a single entry into the spatial hash
        pub fn addEntry(self: *Self, entry: *SpatialHashType, entry_bounds: spatial.BoundingBox, check_duplicates: bool) !void {
            const bounds = entry_bounds;
            const cell_min = self.locToCellSpace(bounds.min);
            const cell_max = self.locToCellSpace(bounds.max);

            const num_x: usize = @intCast(cell_max.x_cell - cell_min.x_cell);
            const num_y: usize = @intCast(cell_max.y_cell - cell_min.y_cell);
            const num_z: usize = @intCast(cell_max.z_cell - cell_min.z_cell);

            for (0..num_x + 1) |x| {
                for (0..num_y + 1) |y| {
                    for (0..num_z + 1) |z| {
                        const hash_key = .{ .x_cell = cell_min.x_cell + @as(i32, @intCast(x)), .y_cell = cell_min.y_cell + @as(i32, @intCast(y)), .z_cell = cell_min.z_cell + @as(i32, @intCast(z)) };
                        var hash_cell = self.cells.getPtr(hash_key);

                        if (hash_cell != null) {
                            // This cell existed already, just add to it
                            // Don't add duplicates!
                            var exists_already = false;
                            if (check_duplicates) {
                                for (hash_cell.?.entries.items) |existing| {
                                    if (existing == entry) {
                                        exists_already = true;
                                        break;
                                    }
                                }
                            }

                            if (!exists_already)
                                try hash_cell.?.entries.append(entry);

                            // delve.debug.log("Added solid to existing list {any}", .{hash_key});
                        } else {
                            // This cell is new, create it first!
                            var cell_entries = std.ArrayList(*SpatialHashType).init(self.allocator);
                            try cell_entries.append(entry);
                            try self.cells.put(hash_key, .{ .entries = cell_entries });
                            // delve.debug.log("Created new cells list at {any}", .{hash_key});
                        }
                    }
                }
            }

            // Update our bounds to include the new solid
            self.bounds.min = math.Vec3.min(self.bounds.min, bounds.min);
            self.bounds.max = math.Vec3.max(self.bounds.max, bounds.max);
        }
    };
}

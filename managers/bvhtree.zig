pub const std = @import("std");
pub const delve = @import("delve");
pub const collision = @import("../entities/box_collision.zig");

pub const SplitCount = 8;

pub const Solid = delve.utils.quakemap.Solid;
pub const BoundingBox = delve.spatial.BoundingBox;

// Based on https://www.tesseractcat.com/article/5
const BVHTree = struct {
    node_pool: std.ArrayList(BVHNode),
    solids: std.ArrayList(Solid),

    pub fn init() BVHTree {
        return .{
            std.ArrayList(BVHNode).init(delve.mem.getAllocator(), 250),
            std.ArrayList(Solid).init(delve.mem.getAllocator()),
        };
    }

    // Update the tree, split the solids into tree nodes
    pub fn update(self: *BVHTree) void {
        const root = &self.node_pool.items[0];
        root.solids = self.solids.items;
        root.makeRecursive(root.solids, 0, self.node_pool.items, 8);
    }

    // Add a solid into the tree. Call 'update' when done adding solids
    pub fn addSolid(self: *BVHTree, solid: Solid) !void {
        try self.solids.append(solid);
    }

    // Walk the tree, adding all found solids to the found array list
    pub fn getCollidingSolids(self: *BVHTree, check_bounds: BoundingBox, found: std.ArrayList(Solid)) !void {
        const root = &self.node_pool.items[0];
        return try root.getCollidingSolids(self.node_pool.items, check_bounds, found);
    }
};

const BVHNode = struct {
    pub var node_index: u32 = 0;

    solids: []Solid,
    left: usize, // left node idx in node_pool
    right: usize, // right node idx in node_pool
    bounds: BoundingBox,

    // Walk the tree, adding all found solids to the found array list
    pub fn getCollidingSolids(self: *BVHNode, node_pool: []BVHNode, check_bounds: BoundingBox, found: std.ArrayList(Solid)) !void {
        if (self.bounds.intersects(check_bounds)) {
            if (self.solids.len > 0) {
                try found.appendSlice(self.solids);
            }

            try getCollidingSolids(node_pool[self.left], node_pool, check_bounds, found);
            try getCollidingSolids(node_pool[self.right], node_pool, check_bounds, found);
        }
    }

    // split ourself into left and right
    // left will be everything strictly smaller than the middle
    pub fn makeRecursive(solids: []Solid, axis: u32, node_pool: []BVHNode, ct: u32) u32 {
        const root_index = node_index;
        const root = &node_pool[root_index];
        node_index += 1;

        root.solids = solids;
        root.bounds = getBounds(root.solids);
        root.right = std.math.maxInt(u32);
        root.left = std.math.maxInt(u32);

        const bounds_min = root.bounds.min.toArray();
        const bounds_max = root.bounds.max.toArray();

        if (solids.len > 5) {
            const mid_index: u32 = @intCast(partition(root.geoms, (bounds_max[axis] + bounds_min[axis]) / 2, axis) + 1);
            root.left = makeRecursive(solids[0..mid_index], (axis + 1) % 3, node_pool, ct);

            if (mid_index == 0) {
                if (ct >= 3) return root_index;
                root.right = makeRecursive(solids[mid_index..], (axis + 1) % 3, node_pool, ct + 1);
            } else {
                root.right = makeRecursive(solids[mid_index..], (axis + 1) % 3, node_pool, ct);
            }
        }
    }

    // return the last index of the left partition
    pub fn partition(solids: []Solid, mid: f32, axis: u32) i64 {
        var small_index: i64 = -1;
        for (solids, 0..) |s, i| {
            const bounds_max = s.bounds.max.toArray();
            if (bounds_max[axis] < mid) {
                small_index += 1;
                std.mem.swap(Solid, &solids[i], &solids[@intCast(small_index)]);
            }
        }
        return small_index;
    }

    // get the bounds of our solids
    pub fn getBounds(solids: []Solid) BoundingBox {
        var solid_bounds: BoundingBox = undefined;

        // We have children, so calculate our bounds based on that
        for (solids, 0..) |solid, i| {
            if (i == 0) {
                solid_bounds = solid.bounds;
                continue;
            }

            // expand our bounding box by the new face bounds
            solid_bounds.min = delve.math.Vec3.min(solid_bounds.min, solid.bounds.min);
            solid_bounds.max = delve.math.Vec3.max(solid_bounds.max, solid.bounds.max);
        }

        return solid_bounds;
    }
};

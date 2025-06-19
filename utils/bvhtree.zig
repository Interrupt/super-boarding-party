const std = @import("std");
const delve = @import("delve");
const main = @import("../main.zig");

const Solid = delve.utils.quakemap.Solid;
const BoundingBox = delve.spatial.BoundingBox;
const Ray = delve.spatial.Ray;
const Vec3 = delve.math.Vec3;

const MAX_SOLIDS = 16;

pub const BVHNode = struct {
    bounds: BoundingBox,
    is_leaf: bool,
    data: union(enum) {
        children: struct { left: usize, right: usize },
        solids: std.ArrayListUnmanaged(*const Solid),
    },

    pub fn debugDraw(self: *BVHNode) void {
        if (self.is_leaf) {
            const bounds = self.bounds;
            const size = bounds.max.sub(bounds.min);
            main.render_instance.drawDebugWireframeCube(bounds.center, delve.math.Vec3.zero, size, delve.math.Vec3.y_axis, delve.colors.red);
        }
    }
};

pub const BVHTree = struct {
    allocator: std.mem.Allocator,
    nodes: std.SegmentedList(BVHNode, 32),

    scratch: std.ArrayList(*const Solid),

    pub fn init(allocator: std.mem.Allocator) BVHTree {
        return .{
            .allocator = allocator,
            .nodes = .{},
            .scratch = std.ArrayList(*const Solid).init(allocator),
        };
    }

    pub fn deinit(self: *BVHTree) void {
        var it = self.nodes.iterator(0);
        while (it.next()) |node| {
            if (node.is_leaf) {
                node.data.solids.deinit(self.allocator);
            }
        }
        self.nodes.deinit(self.allocator);
        self.scratch.deinit();
    }

    pub fn debugDraw(self: *BVHTree) void {
        var it = self.nodes.iterator(0);
        while (it.next()) |node| {
            node.debugDraw();
        }
    }

    pub fn insert(self: *BVHTree, solid: *const Solid) !void {
        if (self.nodes.count() == 0) {
            try self.createRoot(solid);
            return;
        }
        try self.insertRecursive(0, solid);
    }

    fn createRoot(self: *BVHTree, solid: *const Solid) !void {
        var mut_list = std.ArrayListUnmanaged(*const Solid){};
        try mut_list.append(self.allocator, solid);

        const root = BVHNode{
            .bounds = solid.bounds,
            .is_leaf = true,
            .data = .{ .solids = mut_list },
        };
        try self.nodes.append(self.allocator, root);
    }

    fn insertRecursive(self: *BVHTree, index: usize, solid: *const Solid) !void {
        const node = self.nodes.at(index);
        const solid_bounds = getBoundsForSolid(solid);
        node.bounds = mergeBounds(node.*.bounds, solid_bounds);

        if (node.is_leaf) {
            try node.data.solids.append(self.allocator, solid);
            if (node.data.solids.items.len > MAX_SOLIDS) {
                try self.splitLeaf(index);
            }
        } else {
            const left = node.data.children.left;
            const right = node.data.children.right;

            const left_bounds = self.nodes.at(left).bounds;
            const right_bounds = self.nodes.at(right).bounds;

            const left_merged = mergeBounds(left_bounds, solid_bounds);
            const right_merged = mergeBounds(right_bounds, solid_bounds);

            const left_growth = volume(left_merged) - volume(left_bounds);
            const right_growth = volume(right_merged) - volume(right_bounds);

            if (left_growth < right_growth) {
                try self.insertRecursive(left, solid);
            } else {
                try self.insertRecursive(right, solid);
            }
        }
    }

    fn splitLeaf(self: *BVHTree, index: usize) !void {
        const old_node = self.nodes.at(index);
        const solids = old_node.data.solids.items;

        var left_solids = std.ArrayListUnmanaged(*const Solid){};
        var right_solids = std.ArrayListUnmanaged(*const Solid){};

        const bounds = old_node.bounds;
        const min = bounds.min.toArray();
        const max = bounds.max.toArray();
        const size = .{
            max[0] - min[0],
            max[1] - min[1],
            max[2] - min[2],
        };

        const axis: u32 = if (size[0] >= size[1] and size[0] >= size[2]) 0 else if (size[1] >= size[2]) 1 else 2;

        const center = (min[axis] + max[axis]) * 0.5;

        for (solids) |s| {
            const solid_min = s.bounds.min.toArray();
            const solid_max = s.bounds.max.toArray();
            const c = (solid_min[axis] + solid_max[axis]) * 0.5;

            if (c < center) {
                try left_solids.append(self.allocator, s);
            } else {
                try right_solids.append(self.allocator, s);
            }
        }

        if (left_solids.items.len == 0 or right_solids.items.len == 0) {
            left_solids.clearRetainingCapacity();
            right_solids.clearRetainingCapacity();
            for (solids, 0..) |s, i| {
                if (i % 2 == 0)
                    try left_solids.append(self.allocator, s)
                else
                    try right_solids.append(self.allocator, s);
            }
        }

        const left_node = try self.nodes.addOne(self.allocator);
        left_node.* = try self.createLeafFromList(left_solids);
        const left_index: usize = self.nodes.count() - 1;

        const right_node = try self.nodes.addOne(self.allocator);
        right_node.* = try self.createLeafFromList(right_solids);
        const right_index: usize = self.nodes.count() - 1;

        old_node.is_leaf = false;
        old_node.data.solids.deinit(self.allocator);
        old_node.data = .{ .children = .{ .left = left_index, .right = right_index } };
    }

    fn createLeafFromList(self: *BVHTree, list: std.ArrayListUnmanaged(*const Solid)) !BVHNode {
        _ = self;

        var bounds = list.items[0].bounds;
        for (list.items[1..]) |s| {
            bounds = mergeBounds(bounds, s.bounds);
        }

        return BVHNode{
            .bounds = bounds,
            .is_leaf = true,
            .data = .{ .solids = list },
        };
    }

    // Add solids in bounds to results list
    pub fn getEntriesNear(self: *BVHTree, box: BoundingBox) []*const Solid {
        self.scratch.clearRetainingCapacity();

        if (self.nodes.count() == 0) return self.scratch.items;
        self.queryBoundsRecursive(0, &box, &self.scratch) catch {
            delve.debug.log("Error querying bounds", .{});
        };
        return self.scratch.items;
    }

    fn queryBoundsRecursive(self: *const BVHTree, index: usize, box: *const BoundingBox, results: *std.ArrayList(*const Solid)) !void {
        const node = self.nodes.at(index);

        if (!box.intersects(node.bounds)) return;

        if (node.is_leaf) {
            for (node.data.solids.items) |solid| {
                if (!box.intersects(solid.bounds)) continue;
                try results.append(solid);
            }
        } else {
            try self.queryBoundsRecursive(node.data.children.left, box, results);
            try self.queryBoundsRecursive(node.data.children.right, box, results);
        }
    }

    // Add solids along Ray to results list
    pub fn getEntriesAlong(self: *BVHTree, ray: Ray) []*const Solid {
        self.scratch.clearRetainingCapacity();

        if (self.nodes.count() == 0) return self.scratch.items;
        self.queryRayRecursive(0, &ray, &self.scratch) catch {
            delve.debug.log("Error querying ray", .{});
        };

        return self.scratch.items;
    }

    fn queryRayRecursive(
        self: *const BVHTree,
        index: usize,
        ray: *const Ray,
        results: *std.ArrayList(*const Solid),
    ) !void {
        const node = self.nodes.at(index);

        if (ray.intersectBoundingBox(node.bounds) == null) return;

        if (node.is_leaf) {
            for (node.data.solids.items) |solid| {
                if (ray.intersectBoundingBox(solid.bounds) == null) continue;
                try results.append(solid);
            }
        } else {
            try self.queryRayRecursive(node.data.children.left, ray, results);
            try self.queryRayRecursive(node.data.children.right, ray, results);
        }
    }
};

fn volume(box: BoundingBox) f32 {
    const min = box.min.toArray();
    const max = box.max.toArray();
    const dx = max[0] - min[0];
    const dy = max[1] - min[1];
    const dz = max[2] - min[2];
    return dx * dy * dz;
}

fn mergeBounds(a: BoundingBox, b: BoundingBox) BoundingBox {
    const min = Vec3.min(a.min, b.min);
    const max = Vec3.max(a.max, b.max);

    return BoundingBox{
        .center = Vec3.new(min.x + (max.x - min.x) * 0.5, min.y + (max.y - min.y) * 0.5, min.z + (max.z - min.z) * 0.5),
        .min = min,
        .max = max,
    };
}

pub fn getBoundsForSolid(solid: *const delve.utils.quakemap.Solid) BoundingBox {
    if (solid.faces.items.len == 0)
        return BoundingBox{ .center = Vec3.zero, .min = Vec3.zero, .max = Vec3.zero };

    var min = solid.faces.items[0].vertices[0];
    var max = min;

    for (solid.faces.items) |*face| {
        const face_bounds = BoundingBox.initFromPositions(face.vertices);
        min = Vec3.min(min, face_bounds.min);
        max = Vec3.max(max, face_bounds.max);
    }

    return BoundingBox{
        .center = Vec3.new(min.x + (max.x - min.x) * 0.5, min.y + (max.y - min.y) * 0.5, min.z + (max.z - min.z) * 0.5),
        .min = min,
        .max = max,
    };
}

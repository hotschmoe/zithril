// Layout types for zithril TUI framework
// Constraint-based layout system inspired by ratatui

const std = @import("std");

/// Direction for layout: how children are arranged.
pub const Direction = enum {
    horizontal,
    vertical,
};

/// Constraints describe how space should be allocated among layout children.
///
/// The constraint solver allocates space in this order:
/// 1. Fixed constraints (length): Allocate exact requested size
/// 2. Minimum constraints (min): Allocate at least requested size
/// 3. Maximum constraints (max): Allocate at most requested size
/// 4. Ratio constraints (ratio): Allocate fraction of total space
/// 5. Flex constraints (flex): Distribute remaining space proportionally
///
/// When space is insufficient:
/// - Fixed/min constraints take priority
/// - Flex items shrink to zero before fixed items shrink
/// - No negative sizes (saturating arithmetic)
pub const Constraint = union(enum) {
    /// Exactly n cells.
    length: u16,

    /// At least n cells.
    min: u16,

    /// At most n cells.
    max: u16,

    /// Fraction of available space (numerator, denominator).
    /// Example: ratio(1, 3) means 1/3 of available space.
    ratio: Ratio,

    /// Proportional share (like CSS flex-grow).
    /// flex(1) and flex(1) = 50/50 split
    /// flex(1) and flex(2) = 33/67 split
    flex: u16,

    pub const Ratio = struct {
        num: u16,
        den: u16,
    };

    /// Create a length constraint (exactly n cells).
    pub fn len(n: u16) Constraint {
        return .{ .length = n };
    }

    /// Create a minimum constraint (at least n cells).
    pub fn minSize(n: u16) Constraint {
        return .{ .min = n };
    }

    /// Create a maximum constraint (at most n cells).
    pub fn maxSize(n: u16) Constraint {
        return .{ .max = n };
    }

    /// Create a ratio constraint (num/den of available space).
    pub fn fractional(num: u16, den: u16) Constraint {
        return .{ .ratio = .{ .num = num, .den = den } };
    }

    /// Create a flex constraint (proportional share).
    pub fn flexible(n: u16) Constraint {
        return .{ .flex = n };
    }

    /// Apply this constraint to resolve a concrete size given available space.
    /// Returns the size this constraint requests, which may exceed available space.
    /// The caller is responsible for ensuring the total doesn't exceed available.
    pub fn apply(self: Constraint, available: u16) u16 {
        return switch (self) {
            .length => |n| n,
            .min => |n| n,
            .max => |n| @min(n, available),
            .ratio => |r| blk: {
                if (r.den == 0) break :blk 0;
                const result = (@as(u32, available) * r.num) / r.den;
                break :blk @intCast(@min(result, available));
            },
            .flex => available,
        };
    }

    /// Check if two constraints are equal.
    pub fn eql(self: Constraint, other: Constraint) bool {
        return switch (self) {
            .length => |n| other == .length and other.length == n,
            .min => |n| other == .min and other.min == n,
            .max => |n| other == .max and other.max == n,
            .ratio => |r| other == .ratio and other.ratio.num == r.num and other.ratio.den == r.den,
            .flex => |n| other == .flex and other.flex == n,
        };
    }
};

// ============================================================
// SANITY TESTS - Basic functionality
// ============================================================

test "sanity: Constraint.len creates correct constraint" {
    const c = Constraint.len(10);
    try std.testing.expect(c == .length);
    try std.testing.expectEqual(@as(u16, 10), c.length);
}

test "sanity: Constraint.minSize creates correct constraint" {
    const c = Constraint.minSize(20);
    try std.testing.expect(c == .min);
    try std.testing.expectEqual(@as(u16, 20), c.min);
}

test "sanity: Constraint.maxSize creates correct constraint" {
    const c = Constraint.maxSize(30);
    try std.testing.expect(c == .max);
    try std.testing.expectEqual(@as(u16, 30), c.max);
}

test "sanity: Constraint.fractional creates correct constraint" {
    const c = Constraint.fractional(1, 3);
    try std.testing.expect(c == .ratio);
    try std.testing.expectEqual(@as(u16, 1), c.ratio.num);
    try std.testing.expectEqual(@as(u16, 3), c.ratio.den);
}

test "sanity: Constraint.flexible creates correct constraint" {
    const c = Constraint.flexible(2);
    try std.testing.expect(c == .flex);
    try std.testing.expectEqual(@as(u16, 2), c.flex);
}

test "sanity: Direction enum values" {
    try std.testing.expect(@intFromEnum(Direction.horizontal) != @intFromEnum(Direction.vertical));
}

// ============================================================
// BEHAVIOR TESTS - Constraint application
// ============================================================

test "behavior: Constraint length apply returns exact size" {
    const c = Constraint.len(50);
    try std.testing.expectEqual(@as(u16, 50), c.apply(100));
    try std.testing.expectEqual(@as(u16, 50), c.apply(30));
}

test "behavior: Constraint min apply returns minimum size" {
    const c = Constraint.minSize(30);
    try std.testing.expectEqual(@as(u16, 30), c.apply(100));
    try std.testing.expectEqual(@as(u16, 30), c.apply(20));
}

test "behavior: Constraint max apply caps at available" {
    const c = Constraint.maxSize(50);
    try std.testing.expectEqual(@as(u16, 50), c.apply(100));
    try std.testing.expectEqual(@as(u16, 30), c.apply(30));
}

test "behavior: Constraint ratio apply calculates fraction" {
    const c = Constraint.fractional(1, 4);
    try std.testing.expectEqual(@as(u16, 25), c.apply(100));
    try std.testing.expectEqual(@as(u16, 50), c.apply(200));
}

test "behavior: Constraint ratio apply handles zero denominator" {
    const c = Constraint.fractional(1, 0);
    try std.testing.expectEqual(@as(u16, 0), c.apply(100));
}

test "behavior: Constraint flex apply returns full available" {
    const c = Constraint.flexible(1);
    try std.testing.expectEqual(@as(u16, 100), c.apply(100));
    try std.testing.expectEqual(@as(u16, 0), c.apply(0));
}

test "behavior: Constraint eql checks equality" {
    try std.testing.expect(Constraint.len(10).eql(Constraint.len(10)));
    try std.testing.expect(!Constraint.len(10).eql(Constraint.len(20)));
    try std.testing.expect(!Constraint.len(10).eql(Constraint.minSize(10)));

    try std.testing.expect(Constraint.fractional(1, 3).eql(Constraint.fractional(1, 3)));
    try std.testing.expect(!Constraint.fractional(1, 3).eql(Constraint.fractional(2, 3)));
}

// ============================================================
// REGRESSION TESTS - Edge cases
// ============================================================

test "regression: Constraint ratio with large values doesn't overflow" {
    const c = Constraint.fractional(65535, 2);
    const result = c.apply(65535);
    try std.testing.expect(result <= 65535);
}

test "regression: Constraint max with zero available" {
    const c = Constraint.maxSize(100);
    try std.testing.expectEqual(@as(u16, 0), c.apply(0));
}

// ============================================================
// LAYOUT SOLVER
// ============================================================

const Rect = @import("geometry.zig").Rect;

/// Shrink sizes for constraints matching the given tag. Returns remaining amount to shrink.
fn shrinkByTag(
    constraints: []const Constraint,
    sizes: *[max_constraints]u16,
    amount: u32,
    target_tag: std.meta.Tag(Constraint),
) u32 {
    var remaining = amount;
    for (constraints, 0..) |c, i| {
        if (remaining == 0) break;
        if (c == target_tag) {
            const shrink: u16 = @intCast(@min(remaining, sizes[i]));
            sizes[i] -= shrink;
            remaining -= shrink;
        }
    }
    return remaining;
}

/// Split an area according to constraints in the given direction.
///
/// The constraint solver allocates space in this order:
/// 1. Fixed constraints (length): Allocate exact requested size
/// 2. Minimum constraints (min): Allocate at least requested size
/// 3. Maximum constraints (max): Allocate at most requested size
/// 4. Ratio constraints (ratio): Allocate fraction of total space
/// 5. Flex constraints (flex): Distribute remaining space proportionally
///
/// When space is insufficient:
/// - Flex items shrink to zero before fixed items shrink
/// - No negative sizes (saturating arithmetic)
///
/// Returns a bounded array of Rects matching the constraint count.
pub fn layout(
    area: Rect,
    direction: Direction,
    constraints: []const Constraint,
) BoundedRects {
    const total_space: u16 = switch (direction) {
        .horizontal => area.width,
        .vertical => area.height,
    };

    var result = BoundedRects.init();

    if (constraints.len == 0) {
        return result;
    }

    var sizes: [max_constraints]u16 = [_]u16{0} ** max_constraints;
    const count = @min(constraints.len, max_constraints);

    var allocated: u32 = 0;
    var flex_total: u32 = 0;

    // Phase 1: Calculate base allocations and track flex total
    for (constraints[0..count], 0..count) |c, i| {
        switch (c) {
            .length => |n| {
                sizes[i] = n;
                allocated += n;
            },
            .min => |n| {
                sizes[i] = n;
                allocated += n;
            },
            .max => |n| {
                sizes[i] = @min(n, total_space);
                allocated += sizes[i];
            },
            .ratio => |r| {
                if (r.den > 0) {
                    const size: u16 = @intCast(@min(
                        (@as(u32, total_space) * r.num) / r.den,
                        total_space,
                    ));
                    sizes[i] = size;
                    allocated += size;
                }
            },
            .flex => |weight| {
                flex_total += weight;
            },
        }
    }

    // Phase 2: Distribute remaining space to flex items
    if (flex_total > 0) {
        const remaining: u16 = if (allocated >= total_space) 0 else total_space -| @as(u16, @intCast(allocated));
        var flex_used: u32 = 0;

        for (constraints[0..count], 0..count) |c, i| {
            if (c == .flex) {
                const weight = c.flex;
                const share: u16 = @intCast((@as(u32, remaining) * weight) / flex_total);
                sizes[i] = share;
                flex_used += share;
            }
        }

        // Handle rounding remainder: give extra to first flex
        if (remaining > flex_used) {
            const extra: u16 = remaining -| @as(u16, @intCast(flex_used));
            for (constraints[0..count], 0..count) |c, i| {
                if (c == .flex) {
                    sizes[i] +|= extra;
                    break;
                }
            }
        }
    }

    // Phase 3: Handle insufficient space by shrinking
    var total_allocated: u32 = 0;
    for (sizes[0..count]) |s| {
        total_allocated += s;
    }

    if (total_allocated > total_space) {
        var to_shrink: u32 = total_allocated - total_space;
        // Shrink in priority order: flex, max, ratio, length, min
        const shrink_order = [_]std.meta.Tag(Constraint){ .flex, .max, .ratio, .length, .min };
        for (shrink_order) |target_tag| {
            to_shrink = shrinkByTag(constraints[0..count], &sizes, to_shrink, target_tag);
            if (to_shrink == 0) break;
        }
    }

    // Phase 4: Build result rects
    var pos: u16 = 0;
    for (sizes[0..count]) |size| {
        const rect: Rect = switch (direction) {
            .horizontal => .{
                .x = area.x +| pos,
                .y = area.y,
                .width = size,
                .height = area.height,
            },
            .vertical => .{
                .x = area.x,
                .y = area.y +| pos,
                .width = area.width,
                .height = size,
            },
        };
        result.appendAssumeCapacity(rect);
        pos +|= size;
    }

    return result;
}

/// Maximum number of constraints supported in a single layout call.
pub const max_constraints = 32;

/// Bounded array of Rects for layout results.
pub const BoundedRects = struct {
    buffer: [max_constraints]Rect = undefined,
    len: usize = 0,

    pub fn init() BoundedRects {
        return .{};
    }

    pub fn appendAssumeCapacity(self: *BoundedRects, rect: Rect) void {
        self.buffer[self.len] = rect;
        self.len += 1;
    }

    pub fn get(self: BoundedRects, index: usize) Rect {
        return self.buffer[index];
    }

    pub fn constSlice(self: *const BoundedRects) []const Rect {
        return self.buffer[0..self.len];
    }

    pub fn slice(self: *BoundedRects) []Rect {
        return self.buffer[0..self.len];
    }
};

// ============================================================
// LAYOUT SOLVER SANITY TESTS
// ============================================================

test "sanity: layout with empty constraints returns empty" {
    const area = Rect.init(0, 0, 100, 50);
    const result = layout(area, .horizontal, &.{});
    try std.testing.expectEqual(@as(usize, 0), result.len);
}

test "sanity: layout with single flex fills area" {
    const area = Rect.init(0, 0, 100, 50);
    const result = layout(area, .horizontal, &.{Constraint.flexible(1)});
    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqual(@as(u16, 100), result.get(0).width);
}

test "sanity: layout with single length allocates exact size" {
    const area = Rect.init(0, 0, 100, 50);
    const result = layout(area, .horizontal, &.{Constraint.len(30)});
    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqual(@as(u16, 30), result.get(0).width);
}

// ============================================================
// LAYOUT SOLVER BEHAVIOR TESTS
// ============================================================

test "behavior: layout distributes flex space proportionally" {
    const area = Rect.init(0, 0, 100, 50);
    const result = layout(area, .horizontal, &.{
        Constraint.flexible(1),
        Constraint.flexible(2),
    });
    try std.testing.expectEqual(@as(usize, 2), result.len);
    try std.testing.expectEqual(@as(u16, 34), result.get(0).width);
    try std.testing.expectEqual(@as(u16, 66), result.get(1).width);
}

test "behavior: layout fixed takes priority over flex" {
    const area = Rect.init(0, 0, 100, 50);
    const result = layout(area, .horizontal, &.{
        Constraint.len(30),
        Constraint.flexible(1),
    });
    try std.testing.expectEqual(@as(usize, 2), result.len);
    try std.testing.expectEqual(@as(u16, 30), result.get(0).width);
    try std.testing.expectEqual(@as(u16, 70), result.get(1).width);
}

test "behavior: layout respects min constraint" {
    const area = Rect.init(0, 0, 100, 50);
    const result = layout(area, .horizontal, &.{
        Constraint.minSize(40),
        Constraint.flexible(1),
    });
    try std.testing.expectEqual(@as(u16, 40), result.get(0).width);
    try std.testing.expectEqual(@as(u16, 60), result.get(1).width);
}

test "behavior: layout respects max constraint" {
    const area = Rect.init(0, 0, 100, 50);
    const result = layout(area, .horizontal, &.{
        Constraint.maxSize(30),
        Constraint.flexible(1),
    });
    try std.testing.expectEqual(@as(u16, 30), result.get(0).width);
    try std.testing.expectEqual(@as(u16, 70), result.get(1).width);
}

test "behavior: layout respects ratio constraint" {
    const area = Rect.init(0, 0, 100, 50);
    const result = layout(area, .horizontal, &.{
        Constraint.fractional(1, 4),
        Constraint.flexible(1),
    });
    try std.testing.expectEqual(@as(u16, 25), result.get(0).width);
    try std.testing.expectEqual(@as(u16, 75), result.get(1).width);
}

test "behavior: layout vertical direction" {
    const area = Rect.init(10, 20, 100, 50);
    const result = layout(area, .vertical, &.{
        Constraint.len(10),
        Constraint.flexible(1),
    });
    try std.testing.expectEqual(@as(usize, 2), result.len);
    try std.testing.expectEqual(@as(u16, 10), result.get(0).height);
    try std.testing.expectEqual(@as(u16, 40), result.get(1).height);
    try std.testing.expectEqual(@as(u16, 10), result.get(0).x);
    try std.testing.expectEqual(@as(u16, 20), result.get(0).y);
    try std.testing.expectEqual(@as(u16, 30), result.get(1).y);
}

test "behavior: layout horizontal positions correctly" {
    const area = Rect.init(10, 20, 100, 50);
    const result = layout(area, .horizontal, &.{
        Constraint.len(30),
        Constraint.len(40),
    });
    try std.testing.expectEqual(@as(u16, 10), result.get(0).x);
    try std.testing.expectEqual(@as(u16, 40), result.get(1).x);
    try std.testing.expectEqual(@as(u16, 20), result.get(0).y);
    try std.testing.expectEqual(@as(u16, 20), result.get(1).y);
}

// ============================================================
// LAYOUT SOLVER REGRESSION TESTS
// ============================================================

test "regression: layout insufficient space shrinks flex first" {
    const area = Rect.init(0, 0, 50, 50);
    const result = layout(area, .horizontal, &.{
        Constraint.len(40),
        Constraint.flexible(1),
    });
    try std.testing.expectEqual(@as(u16, 40), result.get(0).width);
    try std.testing.expectEqual(@as(u16, 10), result.get(1).width);
}

test "regression: layout insufficient space flex shrinks to zero" {
    const area = Rect.init(0, 0, 30, 50);
    const result = layout(area, .horizontal, &.{
        Constraint.len(40),
        Constraint.flexible(1),
    });
    try std.testing.expectEqual(@as(u16, 30), result.get(0).width);
    try std.testing.expectEqual(@as(u16, 0), result.get(1).width);
}

test "regression: layout never returns negative sizes" {
    const area = Rect.init(0, 0, 10, 50);
    const result = layout(area, .horizontal, &.{
        Constraint.len(30),
        Constraint.len(30),
    });
    var total: u32 = 0;
    for (result.constSlice()) |r| {
        total += r.width;
    }
    try std.testing.expectEqual(@as(u32, 10), total);
}

test "regression: layout with zero-area produces zero-size rects" {
    const area = Rect.init(0, 0, 0, 0);
    const result = layout(area, .horizontal, &.{
        Constraint.len(10),
        Constraint.flexible(1),
    });
    try std.testing.expectEqual(@as(u16, 0), result.get(0).width);
    try std.testing.expectEqual(@as(u16, 0), result.get(1).width);
}

test "regression: layout ratio with zero denominator" {
    const area = Rect.init(0, 0, 100, 50);
    const result = layout(area, .horizontal, &.{
        Constraint.fractional(1, 0),
        Constraint.flexible(1),
    });
    try std.testing.expectEqual(@as(u16, 0), result.get(0).width);
    try std.testing.expectEqual(@as(u16, 100), result.get(1).width);
}

test "regression: layout all fixed with overflow distributes reduction" {
    const area = Rect.init(0, 0, 50, 50);
    const result = layout(area, .horizontal, &.{
        Constraint.len(30),
        Constraint.len(40),
    });
    var total: u32 = 0;
    for (result.constSlice()) |r| {
        total += r.width;
    }
    try std.testing.expectEqual(@as(u32, 50), total);
}

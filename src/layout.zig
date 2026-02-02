// Layout types for zithril TUI framework
// Constraint-based layout system inspired by ratatui

const std = @import("std");

/// Direction for layout: how children are arranged.
pub const Direction = enum {
    horizontal,
    vertical,
};

/// Flex alignment mode controls how excess space is distributed in layouts.
/// When constraints don't fill the available area, Flex determines where the
/// remaining space goes.
pub const Flex = enum {
    /// Content at start, all excess space at end (default).
    start,
    /// Content at end, all excess space at start.
    end_,
    /// Content centered, excess space split evenly on sides.
    center,
    /// Space distributed between items, none at edges.
    space_between,
    /// Equal space around each item (half-space at edges).
    space_around,
    /// Equal gaps everywhere including edges.
    space_evenly,
    /// Legacy: excess space goes to last flex element.
    /// This is the pre-Flex behavior where remaining space is absorbed
    /// by flex-weighted constraints.
    legacy,
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

    /// Percentage of available space (0-100).
    /// Values >100 are clamped to 100.
    /// Example: percentage(50) means 50% of available space.
    percentage: u8,

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

    /// Create a percentage constraint (0-100% of available space).
    /// Values >100 are clamped to 100.
    pub fn percent(n: u8) Constraint {
        return .{ .percentage = @min(n, 100) };
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
            .percentage => |p| blk: {
                const clamped = @min(p, 100);
                const result = (@as(u32, available) * clamped) / 100;
                break :blk @intCast(@min(result, available));
            },
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
            .percentage => |p| other == .percentage and other.percentage == p,
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

test "sanity: Constraint.percent creates correct constraint" {
    const c = Constraint.percent(50);
    try std.testing.expect(c == .percentage);
    try std.testing.expectEqual(@as(u8, 50), c.percentage);
}

test "sanity: Constraint.percent clamps values above 100" {
    const c = Constraint.percent(150);
    try std.testing.expectEqual(@as(u8, 100), c.percentage);
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

test "behavior: Constraint percentage apply calculates percentage" {
    const c25 = Constraint.percent(25);
    try std.testing.expectEqual(@as(u16, 25), c25.apply(100));
    try std.testing.expectEqual(@as(u16, 50), c25.apply(200));

    const c50 = Constraint.percent(50);
    try std.testing.expectEqual(@as(u16, 50), c50.apply(100));

    const c100 = Constraint.percent(100);
    try std.testing.expectEqual(@as(u16, 100), c100.apply(100));
}

test "behavior: Constraint percentage apply handles zero" {
    const c = Constraint.percent(0);
    try std.testing.expectEqual(@as(u16, 0), c.apply(100));
}

test "behavior: Constraint eql checks equality" {
    try std.testing.expect(Constraint.len(10).eql(Constraint.len(10)));
    try std.testing.expect(!Constraint.len(10).eql(Constraint.len(20)));
    try std.testing.expect(!Constraint.len(10).eql(Constraint.minSize(10)));

    try std.testing.expect(Constraint.fractional(1, 3).eql(Constraint.fractional(1, 3)));
    try std.testing.expect(!Constraint.fractional(1, 3).eql(Constraint.fractional(2, 3)));

    try std.testing.expect(Constraint.percent(50).eql(Constraint.percent(50)));
    try std.testing.expect(!Constraint.percent(50).eql(Constraint.percent(75)));
    try std.testing.expect(!Constraint.percent(50).eql(Constraint.fractional(50, 100)));
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
/// The flex parameter controls how excess space is distributed when constraints
/// don't fill the available area. See Flex enum for available modes.
///
/// Returns a bounded array of Rects matching the constraint count.
pub fn layout(
    area: Rect,
    direction: Direction,
    constraints: []const Constraint,
) BoundedRects {
    return layoutWithFlex(area, direction, constraints, .legacy);
}

/// Split an area according to constraints with explicit flex alignment.
/// See layout() for constraint resolution details. The flex parameter
/// controls how excess space is distributed.
pub fn layoutWithFlex(
    area: Rect,
    direction: Direction,
    constraints: []const Constraint,
    flex: Flex,
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
            .percentage => |p| {
                const clamped = @min(p, 100);
                const size: u16 = @intCast(@min(
                    (@as(u32, total_space) * clamped) / 100,
                    total_space,
                ));
                sizes[i] = size;
                allocated += size;
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
        // Shrink in priority order: flex, max, percentage, ratio, length, min
        const shrink_order = [_]std.meta.Tag(Constraint){ .flex, .max, .percentage, .ratio, .length, .min };
        for (shrink_order) |target_tag| {
            to_shrink = shrinkByTag(constraints[0..count], &sizes, to_shrink, target_tag);
            if (to_shrink == 0) break;
        }
        // Recalculate total after shrinking
        total_allocated = 0;
        for (sizes[0..count]) |s| {
            total_allocated += s;
        }
    }

    // Phase 4: Calculate excess space and apply Flex alignment
    const excess: u16 = if (total_allocated >= total_space)
        0
    else
        total_space -| @as(u16, @intCast(total_allocated));

    // Calculate starting position and gap based on Flex mode
    const spacing = calculateFlexSpacing(flex, excess, count);

    // Phase 5: Build result rects with proper positioning
    var pos: u16 = spacing.start_offset;
    for (sizes[0..count], 0..count) |size, i| {
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

        // Add gap after this item (not after the last one)
        if (i + 1 < count) {
            pos +|= spacing.gap;
            // Handle fractional remainder distribution (left-to-right)
            if (i < spacing.remainder) {
                pos +|= 1;
            }
        }
    }

    return result;
}

/// Spacing parameters calculated from Flex mode.
const FlexSpacing = struct {
    start_offset: u16,
    gap: u16,
    remainder: usize,
};

/// Calculate spacing parameters based on Flex mode, excess space, and item count.
fn calculateFlexSpacing(flex: Flex, excess: u16, count: usize) FlexSpacing {
    if (excess == 0 or count == 0) {
        return .{ .start_offset = 0, .gap = 0, .remainder = 0 };
    }

    return switch (flex) {
        .start, .legacy => .{
            .start_offset = 0,
            .gap = 0,
            .remainder = 0,
        },
        .end_ => .{
            .start_offset = excess,
            .gap = 0,
            .remainder = 0,
        },
        .center => .{
            .start_offset = excess / 2,
            .gap = 0,
            .remainder = 0,
        },
        .space_between => blk: {
            if (count <= 1) {
                // Single item: center it
                break :blk .{
                    .start_offset = excess / 2,
                    .gap = 0,
                    .remainder = 0,
                };
            }
            const gaps = count - 1;
            const gap_size: u16 = @intCast(excess / gaps);
            const remainder = excess % @as(u16, @intCast(gaps));
            break :blk .{
                .start_offset = 0,
                .gap = gap_size,
                .remainder = remainder,
            };
        },
        .space_around => blk: {
            // Space around: each item gets equal space around it
            // Edge gaps are half of inner gaps
            // Total gaps = N items * 2 half-gaps = N full gaps worth
            const total_gaps = count;
            const gap_size: u16 = @intCast(excess / total_gaps);
            const remainder = excess % @as(u16, @intCast(total_gaps));
            // Start offset is half a gap
            break :blk .{
                .start_offset = gap_size / 2,
                .gap = gap_size,
                .remainder = remainder,
            };
        },
        .space_evenly => blk: {
            // Space evenly: equal gaps everywhere including edges
            // Total gaps = N + 1 (before first, between each, after last)
            const total_gaps = count + 1;
            const gap_size: u16 = @intCast(excess / total_gaps);
            const remainder = excess % @as(u16, @intCast(total_gaps));
            break :blk .{
                .start_offset = gap_size,
                .gap = gap_size,
                .remainder = remainder,
            };
        },
    };
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

test "behavior: layout respects percentage constraint" {
    const area = Rect.init(0, 0, 100, 50);
    const result = layout(area, .horizontal, &.{
        Constraint.percent(25),
        Constraint.flexible(1),
    });
    try std.testing.expectEqual(@as(u16, 25), result.get(0).width);
    try std.testing.expectEqual(@as(u16, 75), result.get(1).width);
}

test "behavior: layout percentage 50/50 split" {
    const area = Rect.init(0, 0, 100, 50);
    const result = layout(area, .horizontal, &.{
        Constraint.percent(50),
        Constraint.percent(50),
    });
    try std.testing.expectEqual(@as(u16, 50), result.get(0).width);
    try std.testing.expectEqual(@as(u16, 50), result.get(1).width);
}

test "behavior: layout percentage 0 yields no space" {
    const area = Rect.init(0, 0, 100, 50);
    const result = layout(area, .horizontal, &.{
        Constraint.percent(0),
        Constraint.flexible(1),
    });
    try std.testing.expectEqual(@as(u16, 0), result.get(0).width);
    try std.testing.expectEqual(@as(u16, 100), result.get(1).width);
}

test "behavior: layout percentage 100 takes all space" {
    const area = Rect.init(0, 0, 100, 50);
    const result = layout(area, .horizontal, &.{
        Constraint.percent(100),
        Constraint.flexible(1),
    });
    try std.testing.expectEqual(@as(u16, 100), result.get(0).width);
    try std.testing.expectEqual(@as(u16, 0), result.get(1).width);
}

test "behavior: layout percentage mixed with other constraints" {
    const area = Rect.init(0, 0, 100, 50);
    const result = layout(area, .horizontal, &.{
        Constraint.len(20),
        Constraint.percent(50),
        Constraint.flexible(1),
    });
    try std.testing.expectEqual(@as(u16, 20), result.get(0).width);
    try std.testing.expectEqual(@as(u16, 50), result.get(1).width);
    try std.testing.expectEqual(@as(u16, 30), result.get(2).width);
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

// ============================================================
// FLEX ALIGNMENT TESTS
// ============================================================

test "sanity: Flex enum has all modes" {
    const modes = [_]Flex{ .start, .end_, .center, .space_between, .space_around, .space_evenly, .legacy };
    try std.testing.expectEqual(@as(usize, 7), modes.len);
}

test "behavior: Flex.start places items at start with excess at end" {
    const area = Rect.init(0, 0, 100, 10);
    const result = layoutWithFlex(area, .horizontal, &.{
        Constraint.len(20),
        Constraint.len(30),
    }, .start);
    try std.testing.expectEqual(@as(u16, 0), result.get(0).x);
    try std.testing.expectEqual(@as(u16, 20), result.get(1).x);
}

test "behavior: Flex.end_ places items at end with excess at start" {
    const area = Rect.init(0, 0, 100, 10);
    const result = layoutWithFlex(area, .horizontal, &.{
        Constraint.len(20),
        Constraint.len(30),
    }, .end_);
    // Total items = 50, excess = 50
    // First item should start at 50
    try std.testing.expectEqual(@as(u16, 50), result.get(0).x);
    try std.testing.expectEqual(@as(u16, 70), result.get(1).x);
}

test "behavior: Flex.center centers items" {
    const area = Rect.init(0, 0, 100, 10);
    const result = layoutWithFlex(area, .horizontal, &.{
        Constraint.len(20),
        Constraint.len(30),
    }, .center);
    // Total items = 50, excess = 50, start offset = 25
    try std.testing.expectEqual(@as(u16, 25), result.get(0).x);
    try std.testing.expectEqual(@as(u16, 45), result.get(1).x);
}

test "behavior: Flex.space_between distributes gaps between items" {
    const area = Rect.init(0, 0, 100, 10);
    const result = layoutWithFlex(area, .horizontal, &.{
        Constraint.len(20),
        Constraint.len(20),
        Constraint.len(20),
    }, .space_between);
    // Total items = 60, excess = 40, 2 gaps = 20 each
    try std.testing.expectEqual(@as(u16, 0), result.get(0).x);
    try std.testing.expectEqual(@as(u16, 40), result.get(1).x);
    try std.testing.expectEqual(@as(u16, 80), result.get(2).x);
}

test "behavior: Flex.space_between with single item centers it" {
    const area = Rect.init(0, 0, 100, 10);
    const result = layoutWithFlex(area, .horizontal, &.{
        Constraint.len(20),
    }, .space_between);
    // Single item: center it (excess = 80, start = 40)
    try std.testing.expectEqual(@as(u16, 40), result.get(0).x);
}

test "behavior: Flex.space_around distributes space around items" {
    const area = Rect.init(0, 0, 100, 10);
    const result = layoutWithFlex(area, .horizontal, &.{
        Constraint.len(20),
        Constraint.len(20),
    }, .space_around);
    // Total items = 40, excess = 60
    // 2 items = 2 gaps worth of space total
    // Gap = 60/2 = 30, edge offset = 15
    try std.testing.expectEqual(@as(u16, 15), result.get(0).x);
    try std.testing.expectEqual(@as(u16, 65), result.get(1).x);
}

test "behavior: Flex.space_evenly distributes equal gaps everywhere" {
    const area = Rect.init(0, 0, 100, 10);
    const result = layoutWithFlex(area, .horizontal, &.{
        Constraint.len(20),
        Constraint.len(20),
    }, .space_evenly);
    // Total items = 40, excess = 60
    // 3 gaps (before, between, after) = 60/3 = 20 each
    try std.testing.expectEqual(@as(u16, 20), result.get(0).x);
    try std.testing.expectEqual(@as(u16, 60), result.get(1).x);
}

test "behavior: Flex.legacy behaves like default layout" {
    const area = Rect.init(0, 0, 100, 10);
    const result_legacy = layoutWithFlex(area, .horizontal, &.{
        Constraint.len(20),
        Constraint.len(30),
    }, .legacy);
    const result_default = layout(area, .horizontal, &.{
        Constraint.len(20),
        Constraint.len(30),
    });
    try std.testing.expectEqual(result_default.get(0).x, result_legacy.get(0).x);
    try std.testing.expectEqual(result_default.get(1).x, result_legacy.get(1).x);
}

test "behavior: Flex works with vertical direction" {
    const area = Rect.init(0, 0, 10, 100);
    const result = layoutWithFlex(area, .vertical, &.{
        Constraint.len(20),
        Constraint.len(30),
    }, .center);
    // Total items = 50, excess = 50, start offset = 25
    try std.testing.expectEqual(@as(u16, 25), result.get(0).y);
    try std.testing.expectEqual(@as(u16, 45), result.get(1).y);
}

test "regression: Flex with no excess space behaves normally" {
    const area = Rect.init(0, 0, 100, 10);
    const result = layoutWithFlex(area, .horizontal, &.{
        Constraint.len(50),
        Constraint.len(50),
    }, .center);
    // No excess, so items are placed consecutively
    try std.testing.expectEqual(@as(u16, 0), result.get(0).x);
    try std.testing.expectEqual(@as(u16, 50), result.get(1).x);
}

test "regression: Flex with empty constraints returns empty" {
    const area = Rect.init(0, 0, 100, 10);
    const result = layoutWithFlex(area, .horizontal, &.{}, .center);
    try std.testing.expectEqual(@as(usize, 0), result.len);
}

test "regression: Flex handles fractional gap remainder" {
    const area = Rect.init(0, 0, 100, 10);
    const result = layoutWithFlex(area, .horizontal, &.{
        Constraint.len(10),
        Constraint.len(10),
        Constraint.len(10),
    }, .space_between);
    // Total items = 30, excess = 70, 2 gaps
    // 70 / 2 = 35 per gap
    // First at 0, second at 10+35=45, third at 55+35=90
    try std.testing.expectEqual(@as(u16, 0), result.get(0).x);
    try std.testing.expectEqual(@as(u16, 45), result.get(1).x);
    try std.testing.expectEqual(@as(u16, 90), result.get(2).x);
}

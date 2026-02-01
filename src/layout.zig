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

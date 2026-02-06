// Measurement protocol wrapper for zithril TUI framework
// Wraps rich_zig's Measurement type and adds zithril-specific conveniences

const std = @import("std");
const rich_zig = @import("rich_zig");
const layout_mod = @import("layout.zig");

pub const Constraint = layout_mod.Constraint;

/// Measurement represents the minimum and maximum widths a renderable can occupy.
/// This is a direct re-export of rich_zig's Measurement type, which layout
/// containers use for smarter sizing decisions.
pub const Measurement = rich_zig.Measurement;

/// Convert a zithril layout Constraint to a Measurement given available space.
///
/// Mapping:
///   length(n)      -> exact: {n, n}
///   min(n)         -> at least n, up to available: {n, available}
///   max(n)         -> zero to n (capped at available): {0, min(n, available)}
///   flex(weight)   -> fills available: {0, available}
///   ratio(a, b)    -> exact fraction: {result, result}
///   percentage(p)  -> exact percentage: {result, result}
pub fn fromConstraint(constraint: Constraint, available: u16) Measurement {
    return switch (constraint) {
        .length => |n| Measurement.init(n, n),
        .min => |n| Measurement.init(n, available),
        .max => |n| Measurement.init(0, @min(n, available)),
        .flex => Measurement.init(0, available),
        .ratio => |r| blk: {
            if (r.den == 0) break :blk Measurement.zero;
            const result: usize = (@as(u32, available) * r.num) / r.den;
            const clamped = @min(result, available);
            break :blk Measurement.init(clamped, clamped);
        },
        .percentage => |p| blk: {
            const clamped = @min(p, 100);
            const result: usize = (@as(u32, available) * clamped) / 100;
            const final = @min(result, available);
            break :blk Measurement.init(final, final);
        },
    };
}

// ============================================================
// TESTS - Measurement basics (verifying rich_zig re-export)
// ============================================================

test "sanity: Measurement.init creates correct min/max" {
    const m = Measurement.init(5, 20);
    try std.testing.expectEqual(@as(usize, 5), m.minimum);
    try std.testing.expectEqual(@as(usize, 20), m.maximum);
}

test "sanity: Measurement.init ensures min <= max" {
    const m = Measurement.init(20, 5);
    try std.testing.expectEqual(@as(usize, 20), m.minimum);
    try std.testing.expectEqual(@as(usize, 20), m.maximum);
}

test "sanity: Measurement.zero is {0, 0}" {
    try std.testing.expectEqual(@as(usize, 0), Measurement.zero.minimum);
    try std.testing.expectEqual(@as(usize, 0), Measurement.zero.maximum);
}

test "behavior: Measurement.clamp reduces maximum but not below minimum" {
    const m = Measurement.init(5, 20).clamp(10);
    try std.testing.expectEqual(@as(usize, 5), m.minimum);
    try std.testing.expectEqual(@as(usize, 10), m.maximum);
}

test "behavior: Measurement.clamp reduces both when max_width < minimum" {
    const m = Measurement.init(5, 20).clamp(3);
    try std.testing.expectEqual(@as(usize, 3), m.minimum);
    try std.testing.expectEqual(@as(usize, 3), m.maximum);
}

test "behavior: Measurement.union_ takes widest bounds" {
    const a = Measurement.init(3, 10);
    const b = Measurement.init(5, 8);
    const u = Measurement.union_(a, b);
    try std.testing.expectEqual(@as(usize, 5), u.minimum);
    try std.testing.expectEqual(@as(usize, 10), u.maximum);
}

test "behavior: Measurement.intersection takes narrowest bounds" {
    const a = Measurement.init(3, 10);
    const b = Measurement.init(5, 8);
    const i = Measurement.intersection(a, b);
    try std.testing.expectEqual(@as(usize, 5), i.minimum);
    try std.testing.expectEqual(@as(usize, 8), i.maximum);
}

test "behavior: Measurement.pad increases both by 2*amount" {
    const m = Measurement.init(5, 20).pad(3);
    try std.testing.expectEqual(@as(usize, 11), m.minimum);
    try std.testing.expectEqual(@as(usize, 26), m.maximum);
}

test "behavior: Measurement.fromText with single word" {
    const m = Measurement.fromText("Hello");
    try std.testing.expectEqual(@as(usize, 5), m.minimum);
    try std.testing.expectEqual(@as(usize, 5), m.maximum);
}

test "behavior: Measurement.fromText with multi-word line" {
    const m = Measurement.fromText("Hello World");
    try std.testing.expectEqual(@as(usize, 5), m.minimum);
    try std.testing.expectEqual(@as(usize, 11), m.maximum);
}

test "behavior: Measurement.fromText with empty string" {
    const m = Measurement.fromText("");
    try std.testing.expectEqual(@as(usize, 0), m.minimum);
    try std.testing.expectEqual(@as(usize, 0), m.maximum);
}

// ============================================================
// TESTS - fromConstraint
// ============================================================

test "behavior: fromConstraint length gives exact measurement" {
    const m = fromConstraint(Constraint.len(30), 100);
    try std.testing.expectEqual(@as(usize, 30), m.minimum);
    try std.testing.expectEqual(@as(usize, 30), m.maximum);
}

test "behavior: fromConstraint min gives min to available" {
    const m = fromConstraint(Constraint.minSize(20), 100);
    try std.testing.expectEqual(@as(usize, 20), m.minimum);
    try std.testing.expectEqual(@as(usize, 100), m.maximum);
}

test "behavior: fromConstraint max gives zero to capped max" {
    const m = fromConstraint(Constraint.maxSize(50), 100);
    try std.testing.expectEqual(@as(usize, 0), m.minimum);
    try std.testing.expectEqual(@as(usize, 50), m.maximum);
}

test "behavior: fromConstraint max caps at available" {
    const m = fromConstraint(Constraint.maxSize(200), 100);
    try std.testing.expectEqual(@as(usize, 0), m.minimum);
    try std.testing.expectEqual(@as(usize, 100), m.maximum);
}

test "behavior: fromConstraint flex gives zero to available" {
    const m = fromConstraint(Constraint.flexible(1), 80);
    try std.testing.expectEqual(@as(usize, 0), m.minimum);
    try std.testing.expectEqual(@as(usize, 80), m.maximum);
}

test "behavior: fromConstraint ratio gives exact fraction" {
    const m = fromConstraint(Constraint.fractional(1, 4), 100);
    try std.testing.expectEqual(@as(usize, 25), m.minimum);
    try std.testing.expectEqual(@as(usize, 25), m.maximum);
}

test "behavior: fromConstraint ratio with zero denominator gives zero" {
    const m = fromConstraint(Constraint.fractional(1, 0), 100);
    try std.testing.expectEqual(@as(usize, 0), m.minimum);
    try std.testing.expectEqual(@as(usize, 0), m.maximum);
}

test "behavior: fromConstraint percentage gives exact percentage" {
    const m = fromConstraint(Constraint.percent(50), 200);
    try std.testing.expectEqual(@as(usize, 100), m.minimum);
    try std.testing.expectEqual(@as(usize, 100), m.maximum);
}

test "behavior: fromConstraint percentage clamps above 100" {
    const m = fromConstraint(Constraint.percent(100), 80);
    try std.testing.expectEqual(@as(usize, 80), m.minimum);
    try std.testing.expectEqual(@as(usize, 80), m.maximum);
}

// zithril - Zig TUI framework
// Built on rich_zig for terminal rendering primitives

const std = @import("std");
pub const rich_zig = @import("rich_zig");

// Geometry types
pub const geometry = @import("geometry.zig");
pub const Rect = geometry.Rect;
pub const Position = geometry.Position;

// Style types (wrapper around rich_zig)
pub const style_mod = @import("style.zig");
pub const Style = style_mod.Style;
pub const Color = style_mod.Color;
pub const StyleAttribute = style_mod.StyleAttribute;

// Layout types
pub const layout = @import("layout.zig");
pub const Constraint = layout.Constraint;
pub const Direction = layout.Direction;

test "style wrapper" {
    const style = Style.init().bold().fg(.red);
    try std.testing.expect(style.hasAttribute(.bold));

    const base = Style.init().fg(.green);
    const merged = base.patch(style);
    try std.testing.expect(merged.hasAttribute(.bold));
}

test "geometry re-export" {
    const rect = Rect.init(0, 0, 80, 24);
    try std.testing.expectEqual(@as(u32, 1920), rect.area());

    const pos = Position.init(10, 20);
    try std.testing.expectEqual(@as(u16, 10), pos.x);
}

test "layout re-export" {
    const c1 = Constraint.len(10);
    const c2 = Constraint.minSize(20);
    const c3 = Constraint.maxSize(30);
    const c4 = Constraint.fractional(1, 3);
    const c5 = Constraint.flexible(2);

    try std.testing.expectEqual(@as(u16, 10), c1.apply(100));
    try std.testing.expectEqual(@as(u16, 20), c2.apply(100));
    try std.testing.expectEqual(@as(u16, 30), c3.apply(100));
    try std.testing.expectEqual(@as(u16, 33), c4.apply(100));
    try std.testing.expectEqual(@as(u16, 100), c5.apply(100));

    try std.testing.expect(Direction.horizontal != Direction.vertical);
}

// Geometry types for zithril TUI framework
// Represents terminal coordinates and rectangular regions

const std = @import("std");

/// Simple x,y coordinate pair in terminal space.
/// Origin (0,0) is top-left of terminal/region.
pub const Position = struct {
    x: u16,
    y: u16,

    pub fn init(x: u16, y: u16) Position {
        return .{ .x = x, .y = y };
    }
};

/// Represents a rectangular region in terminal coordinates.
/// Origin (0,0) is top-left. Coordinates increase right and down.
pub const Rect = struct {
    x: u16,
    y: u16,
    width: u16,
    height: u16,

    pub fn init(x: u16, y: u16, width: u16, height: u16) Rect {
        return .{ .x = x, .y = y, .width = width, .height = height };
    }

    /// Returns a new Rect inset by `margin` on all sides.
    /// Uses saturating subtraction to prevent underflow.
    /// Position shifts inward; dimensions shrink by 2*margin (or to zero).
    pub fn inner(self: Rect, margin: u16) Rect {
        const double_margin = @as(u32, margin) * 2;

        return .{
            .x = self.x +| margin,
            .y = self.y +| margin,
            .width = if (double_margin >= self.width) 0 else self.width - @as(u16, @intCast(double_margin)),
            .height = if (double_margin >= self.height) 0 else self.height - @as(u16, @intCast(double_margin)),
        };
    }

    /// Returns area (width * height) as u32 to prevent overflow.
    pub fn area(self: Rect) u32 {
        return @as(u32, self.width) * @as(u32, self.height);
    }

    /// Returns true if rect has zero area.
    pub fn isEmpty(self: Rect) bool {
        return self.width == 0 or self.height == 0;
    }

    /// Clamp a point to be within this rect (inclusive of boundaries).
    /// Returns the closest point inside the rect.
    pub fn clamp(self: Rect, x: u16, y: u16) Position {
        const max_x = self.x +| (self.width -| 1);
        const max_y = self.y +| (self.height -| 1);

        return .{
            .x = std.math.clamp(x, self.x, max_x),
            .y = std.math.clamp(y, self.y, max_y),
        };
    }

    /// Returns the right edge x coordinate (exclusive).
    pub fn right(self: Rect) u16 {
        return self.x +| self.width;
    }

    /// Returns the bottom edge y coordinate (exclusive).
    pub fn bottom(self: Rect) u16 {
        return self.y +| self.height;
    }

    /// Returns true if the given point is within this rect (inclusive).
    pub fn contains(self: Rect, x: u16, y: u16) bool {
        return x >= self.x and
            x < self.right() and
            y >= self.y and
            y < self.bottom();
    }
};

// ============================================================
// SANITY TESTS - Basic functionality
// ============================================================

test "sanity: Position init" {
    const pos = Position.init(10, 20);
    try std.testing.expectEqual(@as(u16, 10), pos.x);
    try std.testing.expectEqual(@as(u16, 20), pos.y);
}

test "sanity: Rect init" {
    const rect = Rect.init(5, 10, 100, 50);
    try std.testing.expectEqual(@as(u16, 5), rect.x);
    try std.testing.expectEqual(@as(u16, 10), rect.y);
    try std.testing.expectEqual(@as(u16, 100), rect.width);
    try std.testing.expectEqual(@as(u16, 50), rect.height);
}

test "sanity: Rect area calculation" {
    const rect = Rect.init(0, 0, 80, 24);
    try std.testing.expectEqual(@as(u32, 1920), rect.area());
}

test "sanity: Rect isEmpty" {
    const normal = Rect.init(0, 0, 10, 10);
    const zero_width = Rect.init(0, 0, 0, 10);
    const zero_height = Rect.init(0, 0, 10, 0);
    const zero_both = Rect.init(0, 0, 0, 0);

    try std.testing.expect(!normal.isEmpty());
    try std.testing.expect(zero_width.isEmpty());
    try std.testing.expect(zero_height.isEmpty());
    try std.testing.expect(zero_both.isEmpty());
}

// ============================================================
// BEHAVIOR TESTS - Document edge cases
// ============================================================

test "behavior: Rect.inner with normal margin" {
    const rect = Rect.init(10, 20, 100, 50);
    const inner_rect = rect.inner(5);

    try std.testing.expectEqual(@as(u16, 15), inner_rect.x);
    try std.testing.expectEqual(@as(u16, 25), inner_rect.y);
    try std.testing.expectEqual(@as(u16, 90), inner_rect.width);
    try std.testing.expectEqual(@as(u16, 40), inner_rect.height);
}

test "behavior: Rect.inner with margin larger than dimensions returns zero-size rect" {
    const rect = Rect.init(10, 10, 5, 5);
    const inner_rect = rect.inner(10);

    try std.testing.expectEqual(@as(u16, 0), inner_rect.width);
    try std.testing.expectEqual(@as(u16, 0), inner_rect.height);
}

test "behavior: Rect.inner with margin equal to half dimension returns zero-size" {
    const rect = Rect.init(0, 0, 10, 10);
    const inner_rect = rect.inner(5);

    try std.testing.expectEqual(@as(u16, 0), inner_rect.width);
    try std.testing.expectEqual(@as(u16, 0), inner_rect.height);
}

test "behavior: Rect.clamp constrains point to boundaries" {
    const rect = Rect.init(10, 20, 100, 50);

    const inside = rect.clamp(50, 40);
    try std.testing.expectEqual(@as(u16, 50), inside.x);
    try std.testing.expectEqual(@as(u16, 40), inside.y);

    const left = rect.clamp(0, 40);
    try std.testing.expectEqual(@as(u16, 10), left.x);

    const top = rect.clamp(50, 0);
    try std.testing.expectEqual(@as(u16, 20), top.y);

    const right = rect.clamp(200, 40);
    try std.testing.expectEqual(@as(u16, 109), right.x);

    const bottom = rect.clamp(50, 100);
    try std.testing.expectEqual(@as(u16, 69), bottom.y);
}

test "behavior: Rect.contains checks point membership" {
    const rect = Rect.init(10, 20, 100, 50);

    try std.testing.expect(rect.contains(10, 20));
    try std.testing.expect(rect.contains(50, 40));
    try std.testing.expect(rect.contains(109, 69));

    try std.testing.expect(!rect.contains(9, 20));
    try std.testing.expect(!rect.contains(10, 19));
    try std.testing.expect(!rect.contains(110, 40));
    try std.testing.expect(!rect.contains(50, 70));
}

test "behavior: Rect.right and Rect.bottom" {
    const rect = Rect.init(10, 20, 100, 50);

    try std.testing.expectEqual(@as(u16, 110), rect.right());
    try std.testing.expectEqual(@as(u16, 70), rect.bottom());
}

// ============================================================
// REGRESSION TESTS - Overflow protection
// ============================================================

test "regression: area calculation does not overflow" {
    const rect = Rect.init(0, 0, 65535, 65535);
    const area_val = rect.area();
    try std.testing.expectEqual(@as(u32, 4294836225), area_val);
}

test "regression: saturating operations prevent underflow/overflow" {
    const rect = Rect.init(65535, 65535, 10, 10);
    const inner_rect = rect.inner(2);

    try std.testing.expectEqual(@as(u16, 65535), inner_rect.x);
    try std.testing.expectEqual(@as(u16, 65535), inner_rect.y);
    try std.testing.expectEqual(@as(u16, 6), inner_rect.width);
    try std.testing.expectEqual(@as(u16, 6), inner_rect.height);
}

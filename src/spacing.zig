// Spacing types for zithril TUI framework
// Padding, Margin, and Spacing for layout configuration

const std = @import("std");
const geometry = @import("geometry.zig");
const Rect = geometry.Rect;

/// Padding for interior spacing within a widget (e.g., Block content inset).
/// All values represent cells/characters.
pub const Padding = struct {
    top: u16 = 0,
    right: u16 = 0,
    bottom: u16 = 0,
    left: u16 = 0,

    pub fn all(value: u16) Padding {
        return .{ .top = value, .right = value, .bottom = value, .left = value };
    }

    pub fn symmetric(h: u16, v: u16) Padding {
        return .{ .top = v, .right = h, .bottom = v, .left = h };
    }

    pub fn horizontal(value: u16) Padding {
        return .{ .left = value, .right = value };
    }

    pub fn vertical(value: u16) Padding {
        return .{ .top = value, .bottom = value };
    }

    pub fn leftOnly(value: u16) Padding {
        return .{ .left = value };
    }

    pub fn rightOnly(value: u16) Padding {
        return .{ .right = value };
    }

    pub fn topOnly(value: u16) Padding {
        return .{ .top = value };
    }

    pub fn bottomOnly(value: u16) Padding {
        return .{ .bottom = value };
    }

    pub fn apply(self: Padding, rect: Rect) Rect {
        const new_x = rect.x +| self.left;
        const new_y = rect.y +| self.top;
        const h_total = @as(u32, self.left) + @as(u32, self.right);
        const v_total = @as(u32, self.top) + @as(u32, self.bottom);
        const new_w: u16 = if (h_total >= rect.width) 0 else rect.width -| @as(u16, @intCast(h_total));
        const new_h: u16 = if (v_total >= rect.height) 0 else rect.height -| @as(u16, @intCast(v_total));
        return Rect.init(new_x, new_y, new_w, new_h);
    }

    pub fn isZero(self: Padding) bool {
        return self.top == 0 and self.right == 0 and self.bottom == 0 and self.left == 0;
    }

    pub fn totalHorizontal(self: Padding) u16 {
        return self.left +| self.right;
    }

    pub fn totalVertical(self: Padding) u16 {
        return self.top +| self.bottom;
    }
};

/// Margin for exterior spacing around a widget (layout-level).
/// All values represent cells/characters.
pub const Margin = struct {
    top: u16 = 0,
    right: u16 = 0,
    bottom: u16 = 0,
    left: u16 = 0,

    pub fn all(value: u16) Margin {
        return .{ .top = value, .right = value, .bottom = value, .left = value };
    }

    pub fn symmetric(h: u16, v: u16) Margin {
        return .{ .top = v, .right = h, .bottom = v, .left = h };
    }

    pub fn horizontal(value: u16) Margin {
        return .{ .left = value, .right = value };
    }

    pub fn vertical(value: u16) Margin {
        return .{ .top = value, .bottom = value };
    }

    pub fn leftOnly(value: u16) Margin {
        return .{ .left = value };
    }

    pub fn rightOnly(value: u16) Margin {
        return .{ .right = value };
    }

    pub fn topOnly(value: u16) Margin {
        return .{ .top = value };
    }

    pub fn bottomOnly(value: u16) Margin {
        return .{ .bottom = value };
    }

    pub fn apply(self: Margin, rect: Rect) Rect {
        const new_x = rect.x +| self.left;
        const new_y = rect.y +| self.top;
        const h_total = @as(u32, self.left) + @as(u32, self.right);
        const v_total = @as(u32, self.top) + @as(u32, self.bottom);
        const new_w: u16 = if (h_total >= rect.width) 0 else rect.width -| @as(u16, @intCast(h_total));
        const new_h: u16 = if (v_total >= rect.height) 0 else rect.height -| @as(u16, @intCast(v_total));
        return Rect.init(new_x, new_y, new_w, new_h);
    }

    pub fn isZero(self: Margin) bool {
        return self.top == 0 and self.right == 0 and self.bottom == 0 and self.left == 0;
    }

    pub fn totalHorizontal(self: Margin) u16 {
        return self.left +| self.right;
    }

    pub fn totalVertical(self: Margin) u16 {
        return self.top +| self.bottom;
    }
};

/// Spacing for gaps between layout elements.
pub const Spacing = struct {
    value: u16,

    /// Create spacing with the given gap value.
    pub fn init(value: u16) Spacing {
        return .{ .value = value };
    }

    /// No spacing (zero gap).
    pub const none: Spacing = .{ .value = 0 };
};

// ============================================================
// SANITY TESTS - Padding
// ============================================================

test "sanity: Padding default is zero" {
    const p = Padding{};
    try std.testing.expectEqual(@as(u16, 0), p.top);
    try std.testing.expectEqual(@as(u16, 0), p.right);
    try std.testing.expectEqual(@as(u16, 0), p.bottom);
    try std.testing.expectEqual(@as(u16, 0), p.left);
    try std.testing.expect(p.isZero());
}

test "sanity: Padding.all creates equal padding" {
    const p = Padding.all(5);
    try std.testing.expectEqual(@as(u16, 5), p.top);
    try std.testing.expectEqual(@as(u16, 5), p.right);
    try std.testing.expectEqual(@as(u16, 5), p.bottom);
    try std.testing.expectEqual(@as(u16, 5), p.left);
}

test "sanity: Padding.symmetric creates horizontal/vertical padding" {
    const p = Padding.symmetric(10, 5);
    try std.testing.expectEqual(@as(u16, 5), p.top);
    try std.testing.expectEqual(@as(u16, 10), p.right);
    try std.testing.expectEqual(@as(u16, 5), p.bottom);
    try std.testing.expectEqual(@as(u16, 10), p.left);
}

test "sanity: Padding.horizontal creates left/right padding" {
    const p = Padding.horizontal(8);
    try std.testing.expectEqual(@as(u16, 0), p.top);
    try std.testing.expectEqual(@as(u16, 8), p.right);
    try std.testing.expectEqual(@as(u16, 0), p.bottom);
    try std.testing.expectEqual(@as(u16, 8), p.left);
}

test "sanity: Padding.vertical creates top/bottom padding" {
    const p = Padding.vertical(3);
    try std.testing.expectEqual(@as(u16, 3), p.top);
    try std.testing.expectEqual(@as(u16, 0), p.right);
    try std.testing.expectEqual(@as(u16, 3), p.bottom);
    try std.testing.expectEqual(@as(u16, 0), p.left);
}

test "sanity: Padding single-side constructors" {
    const left = Padding.leftOnly(2);
    try std.testing.expectEqual(@as(u16, 2), left.left);
    try std.testing.expectEqual(@as(u16, 0), left.right);

    const right = Padding.rightOnly(3);
    try std.testing.expectEqual(@as(u16, 3), right.right);
    try std.testing.expectEqual(@as(u16, 0), right.left);

    const top = Padding.topOnly(4);
    try std.testing.expectEqual(@as(u16, 4), top.top);
    try std.testing.expectEqual(@as(u16, 0), top.bottom);

    const bottom = Padding.bottomOnly(5);
    try std.testing.expectEqual(@as(u16, 5), bottom.bottom);
    try std.testing.expectEqual(@as(u16, 0), bottom.top);
}

// ============================================================
// BEHAVIOR TESTS - Padding.apply
// ============================================================

test "behavior: Padding.apply shrinks rect correctly" {
    const p = Padding.all(2);
    const rect = Rect.init(10, 20, 100, 50);
    const result = p.apply(rect);

    try std.testing.expectEqual(@as(u16, 12), result.x);
    try std.testing.expectEqual(@as(u16, 22), result.y);
    try std.testing.expectEqual(@as(u16, 96), result.width);
    try std.testing.expectEqual(@as(u16, 46), result.height);
}

test "behavior: Padding.apply with asymmetric values" {
    const p = Padding{ .top = 1, .right = 2, .bottom = 3, .left = 4 };
    const rect = Rect.init(0, 0, 20, 10);
    const result = p.apply(rect);

    try std.testing.expectEqual(@as(u16, 4), result.x);
    try std.testing.expectEqual(@as(u16, 1), result.y);
    try std.testing.expectEqual(@as(u16, 14), result.width); // 20 - 4 - 2
    try std.testing.expectEqual(@as(u16, 6), result.height); // 10 - 1 - 3
}

test "behavior: Padding.apply with zero padding returns original position" {
    const p = Padding{};
    const rect = Rect.init(5, 10, 50, 30);
    const result = p.apply(rect);

    try std.testing.expectEqual(rect.x, result.x);
    try std.testing.expectEqual(rect.y, result.y);
    try std.testing.expectEqual(rect.width, result.width);
    try std.testing.expectEqual(rect.height, result.height);
}

test "behavior: Padding.totalHorizontal and totalVertical" {
    const p = Padding{ .top = 1, .right = 2, .bottom = 3, .left = 4 };
    try std.testing.expectEqual(@as(u16, 6), p.totalHorizontal()); // 4 + 2
    try std.testing.expectEqual(@as(u16, 4), p.totalVertical()); // 1 + 3
}

// ============================================================
// REGRESSION TESTS - Padding edge cases
// ============================================================

test "regression: Padding.apply with padding larger than rect returns zero-size" {
    const p = Padding.all(50);
    const rect = Rect.init(0, 0, 20, 10);
    const result = p.apply(rect);

    try std.testing.expectEqual(@as(u16, 0), result.width);
    try std.testing.expectEqual(@as(u16, 0), result.height);
}

test "regression: Padding.apply handles max u16 values" {
    const p = Padding.all(100);
    const rect = Rect.init(65535, 65535, 50, 50);
    const result = p.apply(rect);

    // x and y should saturate at u16 max
    try std.testing.expectEqual(@as(u16, 65535), result.x);
    try std.testing.expectEqual(@as(u16, 65535), result.y);
    // width and height should be reduced or zero
    try std.testing.expectEqual(@as(u16, 0), result.width);
    try std.testing.expectEqual(@as(u16, 0), result.height);
}

// ============================================================
// SANITY TESTS - Margin
// ============================================================

test "sanity: Margin default is zero" {
    const m = Margin{};
    try std.testing.expectEqual(@as(u16, 0), m.top);
    try std.testing.expectEqual(@as(u16, 0), m.right);
    try std.testing.expectEqual(@as(u16, 0), m.bottom);
    try std.testing.expectEqual(@as(u16, 0), m.left);
    try std.testing.expect(m.isZero());
}

test "sanity: Margin.all creates equal margin" {
    const m = Margin.all(3);
    try std.testing.expectEqual(@as(u16, 3), m.top);
    try std.testing.expectEqual(@as(u16, 3), m.right);
    try std.testing.expectEqual(@as(u16, 3), m.bottom);
    try std.testing.expectEqual(@as(u16, 3), m.left);
}

test "sanity: Margin.symmetric creates horizontal/vertical margin" {
    const m = Margin.symmetric(5, 2);
    try std.testing.expectEqual(@as(u16, 2), m.top);
    try std.testing.expectEqual(@as(u16, 5), m.right);
    try std.testing.expectEqual(@as(u16, 2), m.bottom);
    try std.testing.expectEqual(@as(u16, 5), m.left);
}

// ============================================================
// BEHAVIOR TESTS - Margin.apply
// ============================================================

test "behavior: Margin.apply shrinks rect correctly" {
    const m = Margin.all(2);
    const rect = Rect.init(10, 20, 100, 50);
    const result = m.apply(rect);

    try std.testing.expectEqual(@as(u16, 12), result.x);
    try std.testing.expectEqual(@as(u16, 22), result.y);
    try std.testing.expectEqual(@as(u16, 96), result.width);
    try std.testing.expectEqual(@as(u16, 46), result.height);
}

test "behavior: Margin.totalHorizontal and totalVertical" {
    const m = Margin{ .top = 5, .right = 10, .bottom = 15, .left = 20 };
    try std.testing.expectEqual(@as(u16, 30), m.totalHorizontal()); // 20 + 10
    try std.testing.expectEqual(@as(u16, 20), m.totalVertical()); // 5 + 15
}

// ============================================================
// SANITY TESTS - Spacing
// ============================================================

test "sanity: Spacing.init creates spacing" {
    const s = Spacing.init(10);
    try std.testing.expectEqual(@as(u16, 10), s.value);
}

test "sanity: Spacing.none is zero" {
    try std.testing.expectEqual(@as(u16, 0), Spacing.none.value);
}

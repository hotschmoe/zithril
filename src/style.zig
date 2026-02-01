// Style types for zithril TUI framework
// Re-exports and extends rich_zig's Style with zithril-specific conveniences

const std = @import("std");
pub const rich_zig = @import("rich_zig");

/// Re-export rich_zig's Color for convenience.
pub const Color = rich_zig.Color;

/// Re-export rich_zig's StyleAttribute for convenience.
pub const StyleAttribute = rich_zig.StyleAttribute;

/// Style represents visual attributes for text cells.
///
/// Wraps rich_zig.Style with zithril-specific conveniences.
/// Supports:
/// - Foreground and background colors (via Color)
/// - Text attributes: bold, italic, underline, dim, blink, reverse, strikethrough
/// - Method chaining for building styles
/// - Merging styles via patch() (called combine() in rich_zig)
///
/// Example:
/// ```
/// const highlight = Style.init().bold().fg(.yellow).bg(.blue);
/// const merged = base_style.patch(highlight);
/// ```
pub const Style = struct {
    inner: rich_zig.Style,

    /// Empty style with all defaults.
    pub const empty: Style = .{ .inner = rich_zig.Style.empty };

    /// Initialize an empty style.
    pub fn init() Style {
        return empty;
    }

    /// Set foreground color.
    pub fn fg(self: Style, c: Color) Style {
        return .{ .inner = self.inner.fg(c) };
    }

    /// Set foreground color (alias for fg).
    pub fn foreground(self: Style, c: Color) Style {
        return self.fg(c);
    }

    /// Set background color.
    pub fn bg(self: Style, c: Color) Style {
        return .{ .inner = self.inner.bg(c) };
    }

    /// Set background color (alias for bg).
    pub fn background(self: Style, c: Color) Style {
        return self.bg(c);
    }

    /// Enable bold.
    pub fn bold(self: Style) Style {
        return .{ .inner = self.inner.bold() };
    }

    /// Disable bold.
    pub fn notBold(self: Style) Style {
        return .{ .inner = self.inner.notBold() };
    }

    /// Enable italic.
    pub fn italic(self: Style) Style {
        return .{ .inner = self.inner.italic() };
    }

    /// Disable italic.
    pub fn notItalic(self: Style) Style {
        return .{ .inner = self.inner.notItalic() };
    }

    /// Enable underline.
    pub fn underline(self: Style) Style {
        return .{ .inner = self.inner.underline() };
    }

    /// Disable underline.
    pub fn notUnderline(self: Style) Style {
        return .{ .inner = self.inner.notUnderline() };
    }

    /// Enable dim.
    pub fn dim(self: Style) Style {
        return .{ .inner = self.inner.dim() };
    }

    /// Disable dim.
    pub fn notDim(self: Style) Style {
        return .{ .inner = self.inner.notDim() };
    }

    /// Enable blink.
    pub fn blink(self: Style) Style {
        return .{ .inner = self.inner.blink() };
    }

    /// Disable blink.
    pub fn notBlink(self: Style) Style {
        return .{ .inner = self.inner.notBlink() };
    }

    /// Enable reverse video.
    pub fn reverse(self: Style) Style {
        return .{ .inner = self.inner.reverse() };
    }

    /// Disable reverse video.
    pub fn notReverse(self: Style) Style {
        return .{ .inner = self.inner.notReverse() };
    }

    /// Enable strikethrough.
    pub fn strikethrough(self: Style) Style {
        return .{ .inner = self.inner.strikethrough() };
    }

    /// Disable strikethrough.
    pub fn notStrikethrough(self: Style) Style {
        return .{ .inner = self.inner.notStrike() };
    }

    /// Enable strikethrough (alias).
    pub fn strike(self: Style) Style {
        return self.strikethrough();
    }

    /// Merge another style on top of this one.
    /// Non-default values in `other` override values in `self`.
    pub fn patch(self: Style, other: Style) Style {
        return .{ .inner = self.inner.combine(other.inner) };
    }

    /// Merge another style on top of this one (alias for patch).
    pub fn combine(self: Style, other: Style) Style {
        return self.patch(other);
    }

    /// Check if style has a specific attribute enabled.
    pub fn hasAttribute(self: Style, attr: StyleAttribute) bool {
        return self.inner.hasAttribute(attr);
    }

    /// Check if this style has no attributes or colors set.
    pub fn isEmpty(self: Style) bool {
        return self.inner.isEmpty();
    }

    /// Check equality with another style.
    pub fn eql(self: Style, other: Style) bool {
        return self.inner.eql(other.inner);
    }

    /// Access the underlying rich_zig style for advanced operations.
    pub fn toRichStyle(self: Style) rich_zig.Style {
        return self.inner;
    }

    /// Create from a rich_zig style.
    pub fn fromRichStyle(rich_style: rich_zig.Style) Style {
        return .{ .inner = rich_style };
    }
};

// ============================================================
// SANITY TESTS - Basic functionality
// ============================================================

test "sanity: Style.init creates empty style" {
    const style = Style.init();
    try std.testing.expect(style.isEmpty());
}

test "sanity: Style.empty is empty" {
    try std.testing.expect(Style.empty.isEmpty());
}

test "sanity: Style with attribute is not empty" {
    const style = Style.init().bold();
    try std.testing.expect(!style.isEmpty());
}

test "sanity: Style with color is not empty" {
    const style = Style.init().fg(.red);
    try std.testing.expect(!style.isEmpty());
}

// ============================================================
// BEHAVIOR TESTS - Attribute chaining and patching
// ============================================================

test "behavior: Style attribute chaining" {
    const style = Style.init().bold().italic().underline().fg(.green);
    try std.testing.expect(style.hasAttribute(.bold));
    try std.testing.expect(style.hasAttribute(.italic));
    try std.testing.expect(style.hasAttribute(.underline));
}

test "behavior: Style.patch merges styles" {
    const base = Style.init().bold().fg(.red);
    const overlay = Style.init().italic().fg(.blue);

    const merged = base.patch(overlay);
    try std.testing.expect(merged.hasAttribute(.bold));
    try std.testing.expect(merged.hasAttribute(.italic));
}

test "behavior: Style.patch overlay wins for conflicts" {
    const base = Style.init().bold().fg(.red);
    const overlay = Style.init().notBold().fg(.blue);

    const merged = base.patch(overlay);
    try std.testing.expect(!merged.hasAttribute(.bold));
}

test "behavior: Style equality" {
    const s1 = Style.init().bold().fg(.red);
    const s2 = Style.init().bold().fg(.red);
    const s3 = Style.init().bold().fg(.blue);

    try std.testing.expect(s1.eql(s2));
    try std.testing.expect(!s1.eql(s3));
}

test "behavior: Style all attributes" {
    const style = Style.init()
        .bold()
        .italic()
        .underline()
        .dim()
        .blink()
        .reverse()
        .strikethrough();

    try std.testing.expect(style.hasAttribute(.bold));
    try std.testing.expect(style.hasAttribute(.italic));
    try std.testing.expect(style.hasAttribute(.underline));
    try std.testing.expect(style.hasAttribute(.dim));
    try std.testing.expect(style.hasAttribute(.blink));
    try std.testing.expect(style.hasAttribute(.reverse));
    try std.testing.expect(style.hasAttribute(.strike));
}

test "behavior: Style disable attributes" {
    const style = Style.init().bold().notBold();
    try std.testing.expect(!style.hasAttribute(.bold));
}

// ============================================================
// INTEGRATION TESTS - rich_zig interop
// ============================================================

test "integration: Style to/from rich_zig" {
    const zithril_style = Style.init().bold().fg(.red);
    const rich_style = zithril_style.toRichStyle();

    try std.testing.expect(rich_style.hasAttribute(.bold));

    const back = Style.fromRichStyle(rich_style);
    try std.testing.expect(back.eql(zithril_style));
}

// ============================================================
// COLOR TESTS - Verify Color type matches SPEC.md
// ============================================================

test "sanity: Color.default exists" {
    const c = Color.default;
    try std.testing.expect(c.eql(Color.default));
}

test "sanity: Color basic 8 colors exist" {
    const colors = [_]Color{
        Color.black,
        Color.red,
        Color.green,
        Color.yellow,
        Color.blue,
        Color.magenta,
        Color.cyan,
        Color.white,
    };
    for (colors, 0..) |color, i| {
        try std.testing.expect(color.number.? == i);
    }
}

test "sanity: Color bright variants exist" {
    const bright_colors = [_]Color{
        Color.bright_black,
        Color.bright_red,
        Color.bright_green,
        Color.bright_yellow,
        Color.bright_blue,
        Color.bright_magenta,
        Color.bright_cyan,
        Color.bright_white,
    };
    for (bright_colors, 0..) |color, i| {
        try std.testing.expect(color.number.? == i + 8);
    }
}

test "sanity: Color.from256 for 256-color palette" {
    const c = Color.from256(196);
    try std.testing.expect(c.number.? == 196);
    try std.testing.expect(c.color_type == .eight_bit);
}

test "sanity: Color.fromRgb for true color" {
    const c = Color.fromRgb(255, 128, 64);
    try std.testing.expect(c.triplet.?.r == 255);
    try std.testing.expect(c.triplet.?.g == 128);
    try std.testing.expect(c.triplet.?.b == 64);
    try std.testing.expect(c.color_type == .truecolor);
}

test "behavior: Color used in Style.fg and Style.bg" {
    const style = Style.init()
        .fg(Color.fromRgb(255, 0, 0))
        .bg(Color.from256(21));

    try std.testing.expect(!style.isEmpty());
}

test "behavior: Color equality" {
    const c1 = Color.fromRgb(100, 100, 100);
    const c2 = Color.fromRgb(100, 100, 100);
    const c3 = Color.fromRgb(100, 100, 101);

    try std.testing.expect(c1.eql(c2));
    try std.testing.expect(!c1.eql(c3));
}

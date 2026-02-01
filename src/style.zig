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

    /// Render this style as ANSI escape codes to a writer.
    /// Uses rich_zig's ANSI rendering for proper color and attribute output.
    pub fn renderAnsi(self: Style, color_system: ColorSystem, writer: anytype) !void {
        try self.inner.renderAnsi(color_system, writer);
    }

    /// Write the ANSI reset sequence to restore default styling.
    pub fn renderReset(writer: anytype) !void {
        try rich_zig.Style.renderReset(writer);
    }

    /// Get the foreground color if set.
    pub fn getForeground(self: Style) ?Color {
        return self.inner.color;
    }

    /// Get the background color if set.
    pub fn getBackground(self: Style) ?Color {
        return self.inner.bgcolor;
    }
};

/// Re-export rich_zig's ColorSystem for color capability detection.
pub const ColorSystem = rich_zig.ColorSystem;

/// Re-export rich_zig's ColorType for color type identification.
pub const ColorType = rich_zig.ColorType;

/// Re-export rich_zig's ColorTriplet for RGB values.
pub const ColorTriplet = rich_zig.ColorTriplet;

/// Re-export rich_zig's Segment for styled text spans.
pub const Segment = rich_zig.Segment;

/// Re-export rich_zig's ControlCode for terminal control sequences.
pub const ControlCode = rich_zig.ControlCode;

/// Re-export rich_zig's ControlType for control code classification.
pub const ControlType = rich_zig.ControlType;

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

// ============================================================
// ANSI RENDERING TESTS - rich_zig integration
// ============================================================

test "behavior: Style.renderAnsi produces valid ANSI" {
    var buf: [128]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const style = Style.init().bold().fg(.red);
    try style.renderAnsi(.truecolor, stream.writer());

    const written = stream.getWritten();
    // Should start with ESC[ and end with 'm'
    try std.testing.expect(written.len > 2);
    try std.testing.expect(written[0] == 0x1b);
    try std.testing.expect(written[1] == '[');
    try std.testing.expect(written[written.len - 1] == 'm');
}

test "behavior: Style.renderReset produces reset sequence" {
    var buf: [16]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try Style.renderReset(stream.writer());

    try std.testing.expectEqualStrings("\x1b[0m", stream.getWritten());
}

test "behavior: Style.renderAnsi truecolor RGB" {
    var buf: [128]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const style = Style.init().fg(Color.fromRgb(255, 128, 64));
    try style.renderAnsi(.truecolor, stream.writer());

    const written = stream.getWritten();
    try std.testing.expectEqualStrings("\x1b[38;2;255;128;64m", written);
}

test "behavior: Style.getForeground returns color" {
    const style = Style.init().fg(.red);
    const fg = style.getForeground();
    try std.testing.expect(fg != null);
    try std.testing.expect(fg.?.eql(.red));
}

test "behavior: Style.getBackground returns color" {
    const style = Style.init().bg(.blue);
    const bg = style.getBackground();
    try std.testing.expect(bg != null);
    try std.testing.expect(bg.?.eql(.blue));
}

// ============================================================
// COLOR SYSTEM TESTS
// ============================================================

test "sanity: ColorSystem supports comparison" {
    try std.testing.expect(ColorSystem.truecolor.supports(.standard));
    try std.testing.expect(ColorSystem.truecolor.supports(.eight_bit));
    try std.testing.expect(ColorSystem.truecolor.supports(.truecolor));
    try std.testing.expect(!ColorSystem.standard.supports(.truecolor));
}

// ============================================================
// SEGMENT TESTS - styled text spans
// ============================================================

test "sanity: Segment.plain creates unstyled segment" {
    const seg = Segment.plain("Hello");
    try std.testing.expectEqualStrings("Hello", seg.text);
    try std.testing.expect(seg.style == null);
}

test "sanity: Segment.styled creates styled segment" {
    const style = Style.init().bold();
    const seg = Segment.styled("World", style.inner);
    try std.testing.expectEqualStrings("World", seg.text);
    try std.testing.expect(seg.style != null);
    try std.testing.expect(seg.style.?.hasAttribute(.bold));
}

test "behavior: Segment.cellLength returns correct width" {
    const seg = Segment.plain("Hello");
    try std.testing.expectEqual(@as(usize, 5), seg.cellLength());
}

test "behavior: Segment.render outputs styled text" {
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const style = Style.init().bold();
    const seg = Segment.styled("Hi", style.inner);
    try seg.render(stream.writer(), .truecolor);

    const written = stream.getWritten();
    // Should contain the text "Hi" and styling codes
    try std.testing.expect(std.mem.indexOf(u8, written, "Hi") != null);
}

// ============================================================
// CONTROL CODE TESTS
// ============================================================

test "sanity: ControlCode cursor movement" {
    var buf: [64]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const ctrl = ControlCode{ .cursor_move_to = .{ .x = 10, .y = 5 } };
    try ctrl.toEscapeSequence(stream.writer());

    try std.testing.expectEqualStrings("\x1b[5;10H", stream.getWritten());
}

test "sanity: ControlCode clear screen" {
    var buf: [16]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const ctrl = ControlCode{ .clear = {} };
    try ctrl.toEscapeSequence(stream.writer());

    try std.testing.expectEqualStrings("\x1b[2J", stream.getWritten());
}

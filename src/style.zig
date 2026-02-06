const std = @import("std");
pub const rich_zig = @import("rich_zig");

pub const Color = rich_zig.Color;
pub const StyleAttribute = rich_zig.StyleAttribute;

/// Visual attributes for text cells. Wraps rich_zig.Style with method chaining.
pub const Style = struct {
    inner: rich_zig.Style,

    pub const empty: Style = .{ .inner = rich_zig.Style.empty };

    pub fn init() Style {
        return empty;
    }

    pub fn fg(self: Style, c: Color) Style {
        return .{ .inner = self.inner.fg(c) };
    }

    pub fn bg(self: Style, c: Color) Style {
        return .{ .inner = self.inner.bg(c) };
    }

    pub fn bold(self: Style) Style {
        return .{ .inner = self.inner.bold() };
    }

    pub fn notBold(self: Style) Style {
        return .{ .inner = self.inner.notBold() };
    }

    pub fn italic(self: Style) Style {
        return .{ .inner = self.inner.italic() };
    }

    pub fn notItalic(self: Style) Style {
        return .{ .inner = self.inner.notItalic() };
    }

    pub fn underline(self: Style) Style {
        return .{ .inner = self.inner.underline() };
    }

    pub fn notUnderline(self: Style) Style {
        return .{ .inner = self.inner.notUnderline() };
    }

    pub fn dim(self: Style) Style {
        return .{ .inner = self.inner.dim() };
    }

    pub fn notDim(self: Style) Style {
        return .{ .inner = self.inner.notDim() };
    }

    pub fn blink(self: Style) Style {
        return .{ .inner = self.inner.blink() };
    }

    pub fn notBlink(self: Style) Style {
        return .{ .inner = self.inner.notBlink() };
    }

    pub fn reverse(self: Style) Style {
        return .{ .inner = self.inner.reverse() };
    }

    pub fn notReverse(self: Style) Style {
        return .{ .inner = self.inner.notReverse() };
    }

    pub fn strikethrough(self: Style) Style {
        return .{ .inner = self.inner.strikethrough() };
    }

    pub fn notStrikethrough(self: Style) Style {
        return .{ .inner = self.inner.notStrike() };
    }

    /// SGR 8 -- hidden text takes up space but is not visible.
    pub fn hidden(self: Style) Style {
        return .{ .inner = self.inner.conceal() };
    }

    pub fn notHidden(self: Style) Style {
        return .{ .inner = self.inner.notConceal() };
    }

    /// SGR 21 -- double underline.
    pub fn underline2(self: Style) Style {
        return .{ .inner = self.inner.underline2() };
    }

    pub fn notUnderline2(self: Style) Style {
        return .{ .inner = self.inner.notUnderline2() };
    }

    /// SGR 51.
    pub fn frame(self: Style) Style {
        return .{ .inner = self.inner.frame() };
    }

    pub fn notFrame(self: Style) Style {
        return .{ .inner = self.inner.notFrame() };
    }

    /// SGR 52.
    pub fn encircle(self: Style) Style {
        return .{ .inner = self.inner.encircle() };
    }

    pub fn notEncircle(self: Style) Style {
        return .{ .inner = self.inner.notEncircle() };
    }

    /// SGR 53.
    pub fn overline(self: Style) Style {
        return .{ .inner = self.inner.overline() };
    }

    pub fn notOverline(self: Style) Style {
        return .{ .inner = self.inner.notOverline() };
    }

    /// Non-default values in `other` override values in `self`.
    pub fn patch(self: Style, other: Style) Style {
        return .{ .inner = self.inner.combine(other.inner) };
    }

    pub fn hasAttribute(self: Style, attr: StyleAttribute) bool {
        return self.inner.hasAttribute(attr);
    }

    pub fn isEmpty(self: Style) bool {
        return self.inner.isEmpty();
    }

    pub fn eql(self: Style, other: Style) bool {
        return self.inner.eql(other.inner);
    }

    pub fn toRichStyle(self: Style) rich_zig.Style {
        return self.inner;
    }

    pub fn fromRichStyle(rich_style: rich_zig.Style) Style {
        return .{ .inner = rich_style };
    }

    pub fn renderAnsi(self: Style, color_system: ColorSystem, writer: anytype) !void {
        try self.inner.renderAnsi(color_system, writer);
    }

    pub fn renderReset(writer: anytype) !void {
        try rich_zig.Style.renderReset(writer);
    }

    pub fn getForeground(self: Style) ?Color {
        return self.inner.color;
    }

    pub fn getBackground(self: Style) ?Color {
        return self.inner.bgcolor;
    }
};

pub const ColorSystem = rich_zig.ColorSystem;
pub const ColorType = rich_zig.ColorType;
pub const ColorTriplet = rich_zig.ColorTriplet;
pub const Segment = rich_zig.Segment;
pub const ControlCode = rich_zig.ControlCode;
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
        .strikethrough()
        .hidden();

    try std.testing.expect(style.hasAttribute(.bold));
    try std.testing.expect(style.hasAttribute(.italic));
    try std.testing.expect(style.hasAttribute(.underline));
    try std.testing.expect(style.hasAttribute(.dim));
    try std.testing.expect(style.hasAttribute(.blink));
    try std.testing.expect(style.hasAttribute(.reverse));
    try std.testing.expect(style.hasAttribute(.strike));
    try std.testing.expect(style.hasAttribute(.conceal));
}

test "behavior: Style.hidden enables conceal attribute" {
    const style = Style.init().hidden();
    try std.testing.expect(style.hasAttribute(.conceal));
    try std.testing.expect(!style.isEmpty());
}

test "behavior: Style.notHidden disables conceal attribute" {
    const style = Style.init().hidden().notHidden();
    try std.testing.expect(!style.hasAttribute(.conceal));
}

test "behavior: Style.hidden maps to conceal attribute" {
    const style = Style.init().hidden();
    try std.testing.expect(style.hasAttribute(.conceal));
}

test "behavior: Style.patch merges hidden attribute" {
    const base = Style.init().bold();
    const overlay = Style.init().hidden();

    const merged = base.patch(overlay);
    try std.testing.expect(merged.hasAttribute(.bold));
    try std.testing.expect(merged.hasAttribute(.conceal));
}

test "behavior: Style.hidden renders correct ANSI code" {
    var buf: [128]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const style = Style.init().hidden();
    try style.renderAnsi(.truecolor, stream.writer());

    const written = stream.getWritten();
    // SGR 8 is the conceal/hidden code
    try std.testing.expectEqualStrings("\x1b[8m", written);
}

test "behavior: Style disable attributes" {
    const style = Style.init().bold().notBold();
    try std.testing.expect(!style.hasAttribute(.bold));
}

test "behavior: Style.underline2 enables double underline" {
    const style = Style.init().underline2();
    try std.testing.expect(style.hasAttribute(.underline2));
    try std.testing.expect(!style.isEmpty());
}

test "behavior: Style.notUnderline2 disables double underline" {
    const style = Style.init().underline2().notUnderline2();
    try std.testing.expect(!style.hasAttribute(.underline2));
}

test "behavior: Style.underline2 renders correct ANSI code" {
    var buf: [128]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const style = Style.init().underline2();
    try style.renderAnsi(.truecolor, stream.writer());

    try std.testing.expectEqualStrings("\x1b[21m", stream.getWritten());
}

test "behavior: Style.frame enables frame attribute" {
    const style = Style.init().frame();
    try std.testing.expect(style.hasAttribute(.frame));
    try std.testing.expect(!style.isEmpty());
}

test "behavior: Style.notFrame disables frame attribute" {
    const style = Style.init().frame().notFrame();
    try std.testing.expect(!style.hasAttribute(.frame));
}

test "behavior: Style.frame renders correct ANSI code" {
    var buf: [128]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const style = Style.init().frame();
    try style.renderAnsi(.truecolor, stream.writer());

    try std.testing.expectEqualStrings("\x1b[51m", stream.getWritten());
}

test "behavior: Style.encircle enables encircle attribute" {
    const style = Style.init().encircle();
    try std.testing.expect(style.hasAttribute(.encircle));
    try std.testing.expect(!style.isEmpty());
}

test "behavior: Style.notEncircle disables encircle attribute" {
    const style = Style.init().encircle().notEncircle();
    try std.testing.expect(!style.hasAttribute(.encircle));
}

test "behavior: Style.encircle renders correct ANSI code" {
    var buf: [128]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const style = Style.init().encircle();
    try style.renderAnsi(.truecolor, stream.writer());

    try std.testing.expectEqualStrings("\x1b[52m", stream.getWritten());
}

test "behavior: Style.overline enables overline attribute" {
    const style = Style.init().overline();
    try std.testing.expect(style.hasAttribute(.overline));
    try std.testing.expect(!style.isEmpty());
}

test "behavior: Style.notOverline disables overline attribute" {
    const style = Style.init().overline().notOverline();
    try std.testing.expect(!style.hasAttribute(.overline));
}

test "behavior: Style.overline renders correct ANSI code" {
    var buf: [128]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const style = Style.init().overline();
    try style.renderAnsi(.truecolor, stream.writer());

    try std.testing.expectEqualStrings("\x1b[53m", stream.getWritten());
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

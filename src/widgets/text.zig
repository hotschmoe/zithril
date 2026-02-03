// Text widget for zithril TUI framework
// Single-line styled text with alignment

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const geometry = @import("../geometry.zig");
const style_mod = @import("../style.zig");

pub const Buffer = buffer_mod.Buffer;
pub const Rect = geometry.Rect;
pub const Style = style_mod.Style;

/// Text alignment options
pub const Alignment = enum {
    left,
    center,
    right,
};

/// Single-line styled text widget.
///
/// Renders text content with a given style and alignment within the provided area.
/// Text is clipped if it exceeds the available width. Only renders on the first
/// row of the area (single-line).
pub const Text = struct {
    /// The text content to display
    content: []const u8,

    /// Style applied to the text
    style: Style = Style.empty,

    /// Text alignment within the area
    alignment: Alignment = .left,

    /// Render the text into the buffer at the given area.
    /// Only uses the first row of the area. Text is clipped at area boundaries.
    pub fn render(self: Text, area: Rect, buf: *Buffer) void {
        if (area.isEmpty()) return;
        if (self.content.len == 0) return;

        // Calculate visible text length (capped by area width)
        const text_len = textDisplayWidth(self.content);
        const visible_len = @min(text_len, area.width);

        if (visible_len == 0) return;

        // Calculate x position based on alignment
        const x_offset: u16 = switch (self.alignment) {
            .left => 0,
            .center => (area.width -| visible_len) / 2,
            .right => area.width -| visible_len,
        };

        const x = area.x +| x_offset;

        // Write the text (setString handles clipping)
        buf.setString(x, area.y, self.content, self.style);
    }
};

/// Calculate the display width of a string (counting grapheme columns).
/// Simple implementation: counts codepoints, treating wide chars as width 2.
fn textDisplayWidth(str: []const u8) u16 {
    var width: u16 = 0;
    var iter = std.unicode.Utf8View.initUnchecked(str).iterator();
    while (iter.nextCodepoint()) |cp| {
        width +|= if (isWideCodepoint(cp)) 2 else 1;
    }
    return width;
}

/// Check if a codepoint is a wide character (CJK, etc.)
fn isWideCodepoint(cp: u21) bool {
    // CJK ranges (simplified)
    return (cp >= 0x4E00 and cp <= 0x9FFF) or // CJK Unified Ideographs
        (cp >= 0x3400 and cp <= 0x4DBF) or // CJK Extension A
        (cp >= 0x20000 and cp <= 0x2A6DF) or // CJK Extension B
        (cp >= 0xF900 and cp <= 0xFAFF) or // CJK Compatibility
        (cp >= 0xFF00 and cp <= 0xFF60) or // Fullwidth forms
        (cp >= 0xFFE0 and cp <= 0xFFE6) or // Fullwidth symbols
        (cp >= 0x3000 and cp <= 0x303F) or // CJK Punctuation
        (cp >= 0x1100 and cp <= 0x11FF); // Hangul Jamo
}

// ============================================================
// SANITY TESTS - Basic Text functionality
// ============================================================

test "sanity: Text with default values" {
    const text = Text{ .content = "Hello" };
    try std.testing.expectEqualStrings("Hello", text.content);
    try std.testing.expect(text.style.isEmpty());
    try std.testing.expect(text.alignment == .left);
}

test "sanity: Text with custom style" {
    const text = Text{
        .content = "Styled",
        .style = Style.init().bold().fg(.red),
    };
    try std.testing.expect(text.style.hasAttribute(.bold));
}

test "sanity: Text with alignment" {
    const left = Text{ .content = "L", .alignment = .left };
    const center = Text{ .content = "C", .alignment = .center };
    const right = Text{ .content = "R", .alignment = .right };

    try std.testing.expect(left.alignment == .left);
    try std.testing.expect(center.alignment == .center);
    try std.testing.expect(right.alignment == .right);
}

// ============================================================
// BEHAVIOR TESTS - Rendering
// ============================================================

test "behavior: Text renders left-aligned" {
    var buf = try Buffer.init(std.testing.allocator, 20, 3);
    defer buf.deinit();

    const text = Text{ .content = "Hello", .alignment = .left };
    text.render(Rect.init(0, 0, 20, 1), &buf);

    try std.testing.expectEqual(@as(u21, 'H'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 'e'), buf.get(1, 0).char);
    try std.testing.expectEqual(@as(u21, 'l'), buf.get(2, 0).char);
    try std.testing.expectEqual(@as(u21, 'l'), buf.get(3, 0).char);
    try std.testing.expectEqual(@as(u21, 'o'), buf.get(4, 0).char);
}

test "behavior: Text renders center-aligned" {
    var buf = try Buffer.init(std.testing.allocator, 20, 3);
    defer buf.deinit();

    const text = Text{ .content = "Hi", .alignment = .center };
    text.render(Rect.init(0, 0, 20, 1), &buf);

    // "Hi" (2 chars) centered in 20 = offset 9
    try std.testing.expectEqual(@as(u21, 'H'), buf.get(9, 0).char);
    try std.testing.expectEqual(@as(u21, 'i'), buf.get(10, 0).char);
}

test "behavior: Text renders right-aligned" {
    var buf = try Buffer.init(std.testing.allocator, 20, 3);
    defer buf.deinit();

    const text = Text{ .content = "End", .alignment = .right };
    text.render(Rect.init(0, 0, 20, 1), &buf);

    // "End" (3 chars) right-aligned in 20 = starts at 17
    try std.testing.expectEqual(@as(u21, 'E'), buf.get(17, 0).char);
    try std.testing.expectEqual(@as(u21, 'n'), buf.get(18, 0).char);
    try std.testing.expectEqual(@as(u21, 'd'), buf.get(19, 0).char);
}

test "behavior: Text applies style" {
    var buf = try Buffer.init(std.testing.allocator, 20, 3);
    defer buf.deinit();

    const text = Text{
        .content = "Bold",
        .style = Style.init().bold(),
    };
    text.render(Rect.init(0, 0, 20, 1), &buf);

    try std.testing.expect(buf.get(0, 0).style.hasAttribute(.bold));
    try std.testing.expect(buf.get(1, 0).style.hasAttribute(.bold));
    try std.testing.expect(buf.get(2, 0).style.hasAttribute(.bold));
    try std.testing.expect(buf.get(3, 0).style.hasAttribute(.bold));
}

test "behavior: Text renders at area offset" {
    var buf = try Buffer.init(std.testing.allocator, 30, 10);
    defer buf.deinit();

    const text = Text{ .content = "Offset" };
    text.render(Rect.init(5, 3, 10, 1), &buf);

    try std.testing.expectEqual(@as(u21, 'O'), buf.get(5, 3).char);
    try std.testing.expectEqual(@as(u21, 'f'), buf.get(6, 3).char);
}

test "behavior: Text clips long content" {
    var buf = try Buffer.init(std.testing.allocator, 10, 3);
    defer buf.deinit();

    const text = Text{ .content = "This is a very long text" };
    text.render(Rect.init(0, 0, 5, 1), &buf);

    // Only first 5 chars should be written
    try std.testing.expectEqual(@as(u21, 'T'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 'h'), buf.get(1, 0).char);
    try std.testing.expectEqual(@as(u21, 'i'), buf.get(2, 0).char);
    try std.testing.expectEqual(@as(u21, 's'), buf.get(3, 0).char);
    try std.testing.expectEqual(@as(u21, ' '), buf.get(4, 0).char);
}

// ============================================================
// REGRESSION TESTS - Edge cases
// ============================================================

test "regression: Text handles empty area" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const text = Text{ .content = "Test" };
    text.render(Rect.init(0, 0, 0, 0), &buf);

    // Buffer should be unchanged
    for (buf.cells) |cell| {
        try std.testing.expect(cell.isDefault());
    }
}

test "regression: Text handles empty content" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const text = Text{ .content = "" };
    text.render(Rect.init(0, 0, 10, 1), &buf);

    // Buffer should be unchanged
    for (buf.cells) |cell| {
        try std.testing.expect(cell.isDefault());
    }
}

test "regression: Text center alignment with odd width" {
    var buf = try Buffer.init(std.testing.allocator, 11, 3);
    defer buf.deinit();

    const text = Text{ .content = "AB", .alignment = .center };
    text.render(Rect.init(0, 0, 11, 1), &buf);

    // "AB" (2 chars) centered in 11 = offset 4 (rounds down)
    try std.testing.expectEqual(@as(u21, 'A'), buf.get(4, 0).char);
    try std.testing.expectEqual(@as(u21, 'B'), buf.get(5, 0).char);
}

test "regression: Text right alignment exact fit" {
    var buf = try Buffer.init(std.testing.allocator, 5, 3);
    defer buf.deinit();

    const text = Text{ .content = "ABCDE", .alignment = .right };
    text.render(Rect.init(0, 0, 5, 1), &buf);

    try std.testing.expectEqual(@as(u21, 'A'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 'E'), buf.get(4, 0).char);
}

test "regression: textDisplayWidth handles ASCII" {
    const w = textDisplayWidth("Hello");
    try std.testing.expectEqual(@as(u16, 5), w);
}

test "regression: textDisplayWidth handles wide chars" {
    // Chinese character (width 2)
    const w = textDisplayWidth("\u{4E2D}");
    try std.testing.expectEqual(@as(u16, 2), w);
}

test "regression: textDisplayWidth handles mixed" {
    // "A" + Chinese char = 1 + 2 = 3
    const w = textDisplayWidth("A\u{4E2D}");
    try std.testing.expectEqual(@as(u16, 3), w);
}

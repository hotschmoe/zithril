// Paragraph widget for zithril TUI framework
// Multi-line text with wrapping and alignment

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const geometry = @import("../geometry.zig");
const style_mod = @import("../style.zig");
const text_mod = @import("../text.zig");

pub const Buffer = buffer_mod.Buffer;
pub const Rect = geometry.Rect;
pub const Style = style_mod.Style;

/// Text wrapping modes
pub const Wrap = enum {
    /// No wrapping, clip at boundary
    none,
    /// Wrap at any character position
    char,
    /// Wrap at word boundaries (spaces)
    word,
};

/// Text alignment options
pub const Alignment = enum {
    left,
    center,
    right,
};

/// Multi-line text widget with optional wrapping.
///
/// Renders text content across multiple lines with configurable wrapping
/// behavior and alignment. Lines beyond the area height are not rendered.
pub const Paragraph = struct {
    /// The text content to display
    text: []const u8,

    /// Style applied to the text
    style: Style = Style.empty,

    /// Text wrapping mode
    wrap: Wrap = .none,

    /// Text alignment within each line
    alignment: Alignment = .left,

    /// Render the paragraph into the buffer at the given area.
    /// Text is split into lines (either by newlines or wrapping) and rendered
    /// until the area height is filled.
    pub fn render(self: Paragraph, area: Rect, buf: *Buffer) void {
        if (area.isEmpty()) return;
        if (self.text.len == 0) return;

        var y = area.y;
        const max_y = area.bottom();

        // Process text line by line (split by newlines first)
        var line_iter = std.mem.splitScalar(u8, self.text, '\n');
        while (line_iter.next()) |logical_line| {
            if (y >= max_y) break;

            // Apply wrapping to this logical line
            switch (self.wrap) {
                .none => {
                    self.renderLine(logical_line, area.x, y, area.width, buf);
                    y += 1;
                },
                .char => {
                    var remaining = logical_line;
                    while (remaining.len > 0 and y < max_y) {
                        const chunk_len = @min(remaining.len, area.width);
                        const chunk = remaining[0..chunk_len];
                        self.renderLine(chunk, area.x, y, area.width, buf);
                        remaining = remaining[chunk_len..];
                        y += 1;
                    }
                    // Empty line should still take a row
                    if (logical_line.len == 0) {
                        y += 1;
                    }
                },
                .word => {
                    if (logical_line.len == 0) {
                        y += 1;
                        continue;
                    }
                    var line_start: usize = 0;
                    while (line_start < logical_line.len and y < max_y) {
                        const wrap_end = findWordWrapEnd(logical_line[line_start..], area.width);
                        const line = logical_line[line_start .. line_start + wrap_end];
                        self.renderLine(line, area.x, y, area.width, buf);
                        line_start += wrap_end;
                        // Skip leading spaces on next line
                        while (line_start < logical_line.len and logical_line[line_start] == ' ') {
                            line_start += 1;
                        }
                        y += 1;
                    }
                },
            }
        }
    }

    /// Render a single line of text with alignment
    fn renderLine(self: Paragraph, line: []const u8, x: u16, y: u16, width: u16, buf: *Buffer) void {
        if (line.len == 0) return;

        const text_len = text_mod.displayWidth(line);
        const visible_len = @min(text_len, width);

        if (visible_len == 0) return;

        const x_offset: u16 = switch (self.alignment) {
            .left => 0,
            .center => (width -| visible_len) / 2,
            .right => width -| visible_len,
        };

        buf.setString(x +| x_offset, y, line, self.style);
    }
};

/// Find the end index for word wrapping within a max width.
/// Returns the number of characters to include on this line.
fn findWordWrapEnd(text: []const u8, max_width: u16) usize {
    if (text.len == 0) return 0;

    const width: usize = @intCast(max_width);
    if (text.len <= width) return text.len;

    // Find the last space within the width limit
    var last_space: ?usize = null;
    for (0..width) |i| {
        if (text[i] == ' ') {
            last_space = i;
        }
    }

    // If we found a space, wrap there (include the space in this line)
    if (last_space) |space_pos| {
        // Return position including the space, so next line starts after it
        return space_pos + 1;
    }

    // No space found - break at max width (hard wrap)
    return width;
}

// ============================================================
// SANITY TESTS - Basic Paragraph functionality
// ============================================================

test "sanity: Paragraph with default values" {
    const para = Paragraph{ .text = "Hello\nWorld" };
    try std.testing.expectEqualStrings("Hello\nWorld", para.text);
    try std.testing.expect(para.style.isEmpty());
    try std.testing.expect(para.wrap == .none);
    try std.testing.expect(para.alignment == .left);
}

test "sanity: Paragraph with custom style" {
    const para = Paragraph{
        .text = "Styled",
        .style = Style.init().bold().fg(.red),
    };
    try std.testing.expect(para.style.hasAttribute(.bold));
}

test "sanity: Paragraph with wrap modes" {
    const none_wrap = Paragraph{ .text = "T", .wrap = .none };
    const char_wrap = Paragraph{ .text = "T", .wrap = .char };
    const word_wrap = Paragraph{ .text = "T", .wrap = .word };

    try std.testing.expect(none_wrap.wrap == .none);
    try std.testing.expect(char_wrap.wrap == .char);
    try std.testing.expect(word_wrap.wrap == .word);
}

test "sanity: Paragraph with alignment" {
    const left = Paragraph{ .text = "L", .alignment = .left };
    const center = Paragraph{ .text = "C", .alignment = .center };
    const right = Paragraph{ .text = "R", .alignment = .right };

    try std.testing.expect(left.alignment == .left);
    try std.testing.expect(center.alignment == .center);
    try std.testing.expect(right.alignment == .right);
}

// ============================================================
// BEHAVIOR TESTS - Rendering
// ============================================================

test "behavior: Paragraph renders single line" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const para = Paragraph{ .text = "Hello" };
    para.render(Rect.init(0, 0, 20, 5), &buf);

    try std.testing.expectEqual(@as(u21, 'H'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 'e'), buf.get(1, 0).char);
    try std.testing.expectEqual(@as(u21, 'l'), buf.get(2, 0).char);
    try std.testing.expectEqual(@as(u21, 'l'), buf.get(3, 0).char);
    try std.testing.expectEqual(@as(u21, 'o'), buf.get(4, 0).char);
}

test "behavior: Paragraph renders multiple lines with newlines" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const para = Paragraph{ .text = "Line1\nLine2\nLine3" };
    para.render(Rect.init(0, 0, 20, 5), &buf);

    try std.testing.expectEqual(@as(u21, 'L'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, '1'), buf.get(4, 0).char);
    try std.testing.expectEqual(@as(u21, 'L'), buf.get(0, 1).char);
    try std.testing.expectEqual(@as(u21, '2'), buf.get(4, 1).char);
    try std.testing.expectEqual(@as(u21, 'L'), buf.get(0, 2).char);
    try std.testing.expectEqual(@as(u21, '3'), buf.get(4, 2).char);
}

test "behavior: Paragraph with char wrap" {
    var buf = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf.deinit();

    const para = Paragraph{
        .text = "ABCDEFGHIJKLMNOP",
        .wrap = .char,
    };
    para.render(Rect.init(0, 0, 10, 5), &buf);

    // First 10 chars on row 0
    try std.testing.expectEqual(@as(u21, 'A'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 'J'), buf.get(9, 0).char);
    // Next 6 chars on row 1
    try std.testing.expectEqual(@as(u21, 'K'), buf.get(0, 1).char);
    try std.testing.expectEqual(@as(u21, 'P'), buf.get(5, 1).char);
}

test "behavior: Paragraph with word wrap" {
    var buf = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf.deinit();

    const para = Paragraph{
        .text = "Hello World Today",
        .wrap = .word,
    };
    para.render(Rect.init(0, 0, 10, 5), &buf);

    // "Hello " should be on row 0
    try std.testing.expectEqual(@as(u21, 'H'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 'o'), buf.get(4, 0).char);
    // "World " should be on row 1
    try std.testing.expectEqual(@as(u21, 'W'), buf.get(0, 1).char);
    try std.testing.expectEqual(@as(u21, 'd'), buf.get(4, 1).char);
    // "Today" should be on row 2
    try std.testing.expectEqual(@as(u21, 'T'), buf.get(0, 2).char);
}

test "behavior: Paragraph center alignment" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const para = Paragraph{
        .text = "Hi",
        .alignment = .center,
    };
    para.render(Rect.init(0, 0, 20, 5), &buf);

    // "Hi" (2 chars) centered in 20 = offset 9
    try std.testing.expectEqual(@as(u21, 'H'), buf.get(9, 0).char);
    try std.testing.expectEqual(@as(u21, 'i'), buf.get(10, 0).char);
}

test "behavior: Paragraph right alignment" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const para = Paragraph{
        .text = "End",
        .alignment = .right,
    };
    para.render(Rect.init(0, 0, 20, 5), &buf);

    // "End" (3 chars) right-aligned in 20 = starts at 17
    try std.testing.expectEqual(@as(u21, 'E'), buf.get(17, 0).char);
    try std.testing.expectEqual(@as(u21, 'd'), buf.get(19, 0).char);
}

test "behavior: Paragraph applies style" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const para = Paragraph{
        .text = "Bold",
        .style = Style.init().bold(),
    };
    para.render(Rect.init(0, 0, 20, 5), &buf);

    try std.testing.expect(buf.get(0, 0).style.hasAttribute(.bold));
    try std.testing.expect(buf.get(1, 0).style.hasAttribute(.bold));
}

test "behavior: Paragraph renders at area offset" {
    var buf = try Buffer.init(std.testing.allocator, 30, 10);
    defer buf.deinit();

    const para = Paragraph{ .text = "Offset\nTest" };
    para.render(Rect.init(5, 3, 10, 5), &buf);

    try std.testing.expectEqual(@as(u21, 'O'), buf.get(5, 3).char);
    try std.testing.expectEqual(@as(u21, 'T'), buf.get(5, 4).char);
}

// ============================================================
// REGRESSION TESTS - Edge cases
// ============================================================

test "regression: Paragraph handles empty area" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const para = Paragraph{ .text = "Test" };
    para.render(Rect.init(0, 0, 0, 0), &buf);

    // Buffer should be unchanged
    for (buf.cells) |cell| {
        try std.testing.expect(cell.isDefault());
    }
}

test "regression: Paragraph handles empty text" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const para = Paragraph{ .text = "" };
    para.render(Rect.init(0, 0, 10, 5), &buf);

    // Buffer should be unchanged
    for (buf.cells) |cell| {
        try std.testing.expect(cell.isDefault());
    }
}

test "regression: Paragraph clips lines beyond height" {
    var buf = try Buffer.init(std.testing.allocator, 20, 2);
    defer buf.deinit();

    const para = Paragraph{ .text = "Line1\nLine2\nLine3\nLine4" };
    para.render(Rect.init(0, 0, 20, 2), &buf);

    // Only first 2 lines should be rendered
    try std.testing.expectEqual(@as(u21, 'L'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, '1'), buf.get(4, 0).char);
    try std.testing.expectEqual(@as(u21, 'L'), buf.get(0, 1).char);
    try std.testing.expectEqual(@as(u21, '2'), buf.get(4, 1).char);
}

test "regression: Paragraph word wrap handles long words" {
    var buf = try Buffer.init(std.testing.allocator, 5, 5);
    defer buf.deinit();

    // Word longer than width - should hard wrap
    const para = Paragraph{
        .text = "ABCDEFGH",
        .wrap = .word,
    };
    para.render(Rect.init(0, 0, 5, 5), &buf);

    // Should hard wrap at width since no spaces
    try std.testing.expectEqual(@as(u21, 'A'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 'E'), buf.get(4, 0).char);
    try std.testing.expectEqual(@as(u21, 'F'), buf.get(0, 1).char);
}

test "regression: Paragraph handles trailing newline" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const para = Paragraph{ .text = "Line1\n" };
    para.render(Rect.init(0, 0, 20, 5), &buf);

    try std.testing.expectEqual(@as(u21, 'L'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, '1'), buf.get(4, 0).char);
}

test "regression: Paragraph handles consecutive newlines" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const para = Paragraph{ .text = "A\n\nB" };
    para.render(Rect.init(0, 0, 20, 5), &buf);

    // A on row 0, empty row 1, B on row 2
    try std.testing.expectEqual(@as(u21, 'A'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 'B'), buf.get(0, 2).char);
}

test "regression: findWordWrapEnd handles empty text" {
    const result = findWordWrapEnd("", 10);
    try std.testing.expectEqual(@as(usize, 0), result);
}

test "regression: findWordWrapEnd handles short text" {
    const result = findWordWrapEnd("Hi", 10);
    try std.testing.expectEqual(@as(usize, 2), result);
}

test "regression: findWordWrapEnd breaks at space" {
    const result = findWordWrapEnd("Hello World", 7);
    // Should break after "Hello " (6 chars including space)
    try std.testing.expectEqual(@as(usize, 6), result);
}

test "regression: findWordWrapEnd hard breaks long word" {
    const result = findWordWrapEnd("Supercalifragilistic", 5);
    // No space found, hard break at width
    try std.testing.expectEqual(@as(usize, 5), result);
}

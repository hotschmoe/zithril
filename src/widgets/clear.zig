// Clear widget for zithril TUI framework
// Fills an area with a style, useful for clearing regions before popups

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const geometry = @import("../geometry.zig");
const style_mod = @import("../style.zig");

pub const Buffer = buffer_mod.Buffer;
pub const Cell = buffer_mod.Cell;
pub const Rect = geometry.Rect;
pub const Style = style_mod.Style;

/// Clear widget that fills an area with a style.
///
/// Useful for:
/// - Clearing a region before rendering a popup or overlay
/// - Drawing a solid background area
/// - Erasing content in a specific region
pub const Clear = struct {
    /// Style to fill the area with.
    /// The background color of this style determines the fill color.
    style: Style = Style.empty,

    /// Character to fill with. Defaults to space.
    char: u21 = ' ',

    /// Render the clear widget into the buffer at the given area.
    /// Fills the entire area with the style and character.
    pub fn render(self: Clear, area: Rect, buf: *Buffer) void {
        if (area.isEmpty()) return;

        const fill_cell = Cell.styled(self.char, self.style);
        buf.fill(area, fill_cell);
    }

    /// Create a clear widget with a background color.
    pub fn withBackground(color: style_mod.Color) Clear {
        return .{
            .style = Style.init().bg(color),
        };
    }
};

// ============================================================
// SANITY TESTS - Basic Clear functionality
// ============================================================

test "sanity: Clear with default values" {
    const clear = Clear{};
    try std.testing.expect(clear.style.isEmpty());
    try std.testing.expectEqual(@as(u21, ' '), clear.char);
}

test "sanity: Clear with style" {
    const clear = Clear{
        .style = Style.init().bg(.blue),
    };
    try std.testing.expect(!clear.style.isEmpty());
}

test "sanity: Clear.withBackground creates styled clear" {
    const clear = Clear.withBackground(.green);
    const bg = clear.style.getBackground();
    try std.testing.expect(bg != null);
    try std.testing.expect(bg.?.eql(.green));
}

// ============================================================
// BEHAVIOR TESTS - Rendering
// ============================================================

test "behavior: Clear fills entire area with style" {
    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    const clear = Clear{
        .style = Style.init().bg(.blue),
    };
    clear.render(Rect.init(5, 2, 10, 5), &buf);

    // Inside the area should have the style
    const inside_cell = buf.get(10, 4);
    try std.testing.expect(inside_cell.style.getBackground() != null);
    try std.testing.expect(inside_cell.style.getBackground().?.eql(.blue));

    // Outside should be default
    try std.testing.expect(buf.get(0, 0).isDefault());
    try std.testing.expect(buf.get(15, 4).isDefault());
}

test "behavior: Clear uses specified character" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const clear = Clear{
        .char = '#',
    };
    clear.render(Rect.init(0, 0, 5, 5), &buf);

    try std.testing.expectEqual(@as(u21, '#'), buf.get(2, 2).char);
}

test "behavior: Clear overwrites existing content" {
    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    // Write some content first
    buf.setString(0, 0, "Hello World", Style.init().bold());

    // Clear over it
    const clear = Clear{
        .style = Style.init().bg(.red),
    };
    clear.render(Rect.init(0, 0, 20, 10), &buf);

    // Content should be cleared
    const cell = buf.get(0, 0);
    try std.testing.expectEqual(@as(u21, ' '), cell.char);
    try std.testing.expect(cell.style.getBackground() != null);
}

// ============================================================
// REGRESSION TESTS - Edge cases
// ============================================================

test "regression: Clear handles empty area" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const clear = Clear{ .style = Style.init().bg(.blue) };
    clear.render(Rect.init(0, 0, 0, 0), &buf);

    // Buffer should be unchanged
    for (buf.cells) |cell| {
        try std.testing.expect(cell.isDefault());
    }
}

test "regression: Clear handles area larger than buffer" {
    var buf = try Buffer.init(std.testing.allocator, 5, 5);
    defer buf.deinit();

    const clear = Clear{ .style = Style.init().bg(.blue) };
    clear.render(Rect.init(0, 0, 100, 100), &buf);

    // All cells should be filled
    for (buf.cells) |cell| {
        try std.testing.expect(cell.style.getBackground() != null);
    }
}

test "regression: Clear handles area outside buffer" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const clear = Clear{ .style = Style.init().bg(.blue) };
    clear.render(Rect.init(20, 20, 10, 10), &buf);

    // Buffer should be unchanged (area is outside)
    for (buf.cells) |cell| {
        try std.testing.expect(cell.isDefault());
    }
}

test "regression: Clear at non-zero offset" {
    var buf = try Buffer.init(std.testing.allocator, 20, 20);
    defer buf.deinit();

    const clear = Clear{ .style = Style.init().bg(.green) };
    clear.render(Rect.init(5, 5, 5, 5), &buf);

    // Check boundaries
    try std.testing.expect(buf.get(5, 5).style.getBackground() != null);
    try std.testing.expect(buf.get(9, 9).style.getBackground() != null);
    try std.testing.expect(buf.get(4, 5).isDefault());
    try std.testing.expect(buf.get(10, 5).isDefault());
    try std.testing.expect(buf.get(5, 4).isDefault());
    try std.testing.expect(buf.get(5, 10).isDefault());
}

test "regression: Clear with empty style fills with spaces" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    // Set some content
    buf.setString(0, 0, "Test", Style.init().bold());

    // Clear with empty style
    const clear = Clear{};
    clear.render(Rect.init(0, 0, 10, 1), &buf);

    // Characters should be spaces, style should be empty
    try std.testing.expectEqual(@as(u21, ' '), buf.get(0, 0).char);
    try std.testing.expect(buf.get(0, 0).style.isEmpty());
}

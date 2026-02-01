// Block widget for zithril TUI framework
// Draws borders and optional title

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const geometry = @import("../geometry.zig");
const style_mod = @import("../style.zig");

pub const Buffer = buffer_mod.Buffer;
pub const Cell = buffer_mod.Cell;
pub const Rect = geometry.Rect;
pub const Style = style_mod.Style;

/// Text alignment for titles
pub const Alignment = enum {
    left,
    center,
    right,
};

/// Border style variants
pub const BorderType = enum {
    none,
    plain, // ASCII: +-|
    rounded, // Unicode: rounded corners
    double, // Unicode: double lines
    thick, // Unicode: thick lines

    /// Get the border character set for this border type
    pub fn chars(self: BorderType) BorderChars {
        return switch (self) {
            .none => BorderChars{
                .top_left = ' ',
                .top_right = ' ',
                .bottom_left = ' ',
                .bottom_right = ' ',
                .horizontal = ' ',
                .vertical = ' ',
            },
            .plain => BorderChars{
                .top_left = '+',
                .top_right = '+',
                .bottom_left = '+',
                .bottom_right = '+',
                .horizontal = '-',
                .vertical = '|',
            },
            .rounded => BorderChars{
                .top_left = 0x256D, // Box Drawings Light Arc Down and Right
                .top_right = 0x256E, // Box Drawings Light Arc Down and Left
                .bottom_left = 0x2570, // Box Drawings Light Arc Up and Right
                .bottom_right = 0x256F, // Box Drawings Light Arc Up and Left
                .horizontal = 0x2500, // Box Drawings Light Horizontal
                .vertical = 0x2502, // Box Drawings Light Vertical
            },
            .double => BorderChars{
                .top_left = 0x2554, // Box Drawings Double Down and Right
                .top_right = 0x2557, // Box Drawings Double Down and Left
                .bottom_left = 0x255A, // Box Drawings Double Up and Right
                .bottom_right = 0x255D, // Box Drawings Double Up and Left
                .horizontal = 0x2550, // Box Drawings Double Horizontal
                .vertical = 0x2551, // Box Drawings Double Vertical
            },
            .thick => BorderChars{
                .top_left = 0x250F, // Box Drawings Heavy Down and Right
                .top_right = 0x2513, // Box Drawings Heavy Down and Left
                .bottom_left = 0x2517, // Box Drawings Heavy Up and Right
                .bottom_right = 0x251B, // Box Drawings Heavy Up and Left
                .horizontal = 0x2501, // Box Drawings Heavy Horizontal
                .vertical = 0x2503, // Box Drawings Heavy Vertical
            },
        };
    }
};

/// Character set for drawing borders
pub const BorderChars = struct {
    top_left: u21,
    top_right: u21,
    bottom_left: u21,
    bottom_right: u21,
    horizontal: u21,
    vertical: u21,
};

/// Block widget that draws borders and optional title.
/// Use inner() on the Rect to get the interior area for child content.
pub const Block = struct {
    /// Optional title displayed at the top of the block
    title: ?[]const u8 = null,

    /// Alignment of the title within the top border
    title_alignment: Alignment = .left,

    /// Border style (none, plain, rounded, double, thick)
    border: BorderType = .none,

    /// Style applied to border characters
    border_style: Style = Style.empty,

    /// Background style applied to the interior of the block
    style: Style = Style.empty,

    /// Render the block into the buffer at the given area.
    /// Draws the border and title, fills interior with background style.
    pub fn render(self: Block, area: Rect, buf: *Buffer) void {
        if (area.isEmpty()) return;

        // Fill interior with background style if we have one
        if (!self.style.isEmpty()) {
            const fill_cell = Cell.styled(' ', self.style);
            buf.fill(area, fill_cell);
        }

        // Draw border if we have one
        if (self.border != .none) {
            self.drawBorder(area, buf);
        }

        // Draw title if we have one
        if (self.title) |title| {
            self.drawTitle(title, area, buf);
        }
    }

    /// Draw the border around the area
    fn drawBorder(self: Block, area: Rect, buf: *Buffer) void {
        const chars = self.border.chars();
        const style = self.border_style;

        const left = area.x;
        const right = area.right() -| 1;
        const top = area.y;
        const bottom_y = area.bottom() -| 1;

        // Only draw if we have at least 1x1 area
        if (area.width < 1 or area.height < 1) return;

        // Draw corners
        buf.set(left, top, Cell.styled(chars.top_left, style));

        if (area.width > 1) {
            buf.set(right, top, Cell.styled(chars.top_right, style));
        }

        if (area.height > 1) {
            buf.set(left, bottom_y, Cell.styled(chars.bottom_left, style));

            if (area.width > 1) {
                buf.set(right, bottom_y, Cell.styled(chars.bottom_right, style));
            }
        }

        // Draw horizontal lines (top and bottom)
        if (area.width > 2) {
            var x = left + 1;
            while (x < right) : (x += 1) {
                buf.set(x, top, Cell.styled(chars.horizontal, style));
                if (area.height > 1) {
                    buf.set(x, bottom_y, Cell.styled(chars.horizontal, style));
                }
            }
        }

        // Draw vertical lines (left and right sides)
        if (area.height > 2) {
            var y = top + 1;
            while (y < bottom_y) : (y += 1) {
                buf.set(left, y, Cell.styled(chars.vertical, style));
                if (area.width > 1) {
                    buf.set(right, y, Cell.styled(chars.vertical, style));
                }
            }
        }
    }

    /// Draw the title in the top border
    fn drawTitle(self: Block, title: []const u8, area: Rect, buf: *Buffer) void {
        // Need at least 3 width to show any title (border + 1 char + border)
        if (area.width < 3) return;

        // Calculate available space for title (inside the corners)
        const available_width = area.width - 2;
        const title_len = @min(available_width, @as(u16, @intCast(title.len)));

        // Calculate x position based on alignment
        const title_x: u16 = switch (self.title_alignment) {
            .left => area.x + 1,
            .center => area.x + 1 + (available_width -| title_len) / 2,
            .right => area.x + 1 + (available_width -| title_len),
        };

        // Draw the title with border style (title inherits border style)
        buf.setString(title_x, area.y, title[0..title_len], self.border_style);
    }

    /// Get the interior area (inside the border).
    /// Returns a Rect with margin 1 if there's a border, otherwise the full area.
    pub fn inner(self: Block, area: Rect) Rect {
        if (self.border == .none) {
            return area;
        }
        return area.inner(1);
    }
};

// ============================================================
// SANITY TESTS - Basic Block functionality
// ============================================================

test "sanity: Block with default values" {
    const block = Block{};
    try std.testing.expect(block.title == null);
    try std.testing.expect(block.border == .none);
    try std.testing.expect(block.style.isEmpty());
}

test "sanity: Block with title and border" {
    const block = Block{
        .title = "Test",
        .border = .rounded,
    };
    try std.testing.expectEqualStrings("Test", block.title.?);
    try std.testing.expect(block.border == .rounded);
}

test "sanity: Block.inner returns correct interior area" {
    const block = Block{ .border = .plain };
    const area = Rect.init(0, 0, 20, 10);
    const interior = block.inner(area);

    try std.testing.expectEqual(@as(u16, 1), interior.x);
    try std.testing.expectEqual(@as(u16, 1), interior.y);
    try std.testing.expectEqual(@as(u16, 18), interior.width);
    try std.testing.expectEqual(@as(u16, 8), interior.height);
}

test "sanity: Block.inner with no border returns full area" {
    const block = Block{ .border = .none };
    const area = Rect.init(0, 0, 20, 10);
    const interior = block.inner(area);

    try std.testing.expectEqual(@as(u16, 0), interior.x);
    try std.testing.expectEqual(@as(u16, 0), interior.y);
    try std.testing.expectEqual(@as(u16, 20), interior.width);
    try std.testing.expectEqual(@as(u16, 10), interior.height);
}

// ============================================================
// BEHAVIOR TESTS - Rendering
// ============================================================

test "behavior: Block renders plain border corners" {
    var buf = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf.deinit();

    const block = Block{ .border = .plain };
    block.render(Rect.init(0, 0, 10, 5), &buf);

    try std.testing.expectEqual(@as(u21, '+'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, '+'), buf.get(9, 0).char);
    try std.testing.expectEqual(@as(u21, '+'), buf.get(0, 4).char);
    try std.testing.expectEqual(@as(u21, '+'), buf.get(9, 4).char);
}

test "behavior: Block renders plain border horizontal lines" {
    var buf = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf.deinit();

    const block = Block{ .border = .plain };
    block.render(Rect.init(0, 0, 10, 5), &buf);

    try std.testing.expectEqual(@as(u21, '-'), buf.get(1, 0).char);
    try std.testing.expectEqual(@as(u21, '-'), buf.get(5, 0).char);
    try std.testing.expectEqual(@as(u21, '-'), buf.get(8, 0).char);

    try std.testing.expectEqual(@as(u21, '-'), buf.get(1, 4).char);
    try std.testing.expectEqual(@as(u21, '-'), buf.get(5, 4).char);
}

test "behavior: Block renders plain border vertical lines" {
    var buf = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf.deinit();

    const block = Block{ .border = .plain };
    block.render(Rect.init(0, 0, 10, 5), &buf);

    try std.testing.expectEqual(@as(u21, '|'), buf.get(0, 1).char);
    try std.testing.expectEqual(@as(u21, '|'), buf.get(0, 2).char);
    try std.testing.expectEqual(@as(u21, '|'), buf.get(0, 3).char);

    try std.testing.expectEqual(@as(u21, '|'), buf.get(9, 1).char);
    try std.testing.expectEqual(@as(u21, '|'), buf.get(9, 2).char);
    try std.testing.expectEqual(@as(u21, '|'), buf.get(9, 3).char);
}

test "behavior: Block renders rounded border" {
    var buf = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf.deinit();

    const block = Block{ .border = .rounded };
    block.render(Rect.init(0, 0, 10, 5), &buf);

    try std.testing.expectEqual(@as(u21, 0x256D), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 0x256E), buf.get(9, 0).char);
    try std.testing.expectEqual(@as(u21, 0x2570), buf.get(0, 4).char);
    try std.testing.expectEqual(@as(u21, 0x256F), buf.get(9, 4).char);
}

test "behavior: Block renders double border" {
    var buf = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf.deinit();

    const block = Block{ .border = .double };
    block.render(Rect.init(0, 0, 10, 5), &buf);

    try std.testing.expectEqual(@as(u21, 0x2554), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 0x2557), buf.get(9, 0).char);
    try std.testing.expectEqual(@as(u21, 0x255A), buf.get(0, 4).char);
    try std.testing.expectEqual(@as(u21, 0x255D), buf.get(9, 4).char);
}

test "behavior: Block renders thick border" {
    var buf = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf.deinit();

    const block = Block{ .border = .thick };
    block.render(Rect.init(0, 0, 10, 5), &buf);

    try std.testing.expectEqual(@as(u21, 0x250F), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 0x2513), buf.get(9, 0).char);
    try std.testing.expectEqual(@as(u21, 0x2517), buf.get(0, 4).char);
    try std.testing.expectEqual(@as(u21, 0x251B), buf.get(9, 4).char);
}

test "behavior: Block renders title left-aligned" {
    var buf = try Buffer.init(std.testing.allocator, 15, 5);
    defer buf.deinit();

    const block = Block{
        .title = "Test",
        .title_alignment = .left,
        .border = .plain,
    };
    block.render(Rect.init(0, 0, 15, 5), &buf);

    try std.testing.expectEqual(@as(u21, 'T'), buf.get(1, 0).char);
    try std.testing.expectEqual(@as(u21, 'e'), buf.get(2, 0).char);
    try std.testing.expectEqual(@as(u21, 's'), buf.get(3, 0).char);
    try std.testing.expectEqual(@as(u21, 't'), buf.get(4, 0).char);
}

test "behavior: Block renders title right-aligned" {
    var buf = try Buffer.init(std.testing.allocator, 15, 5);
    defer buf.deinit();

    const block = Block{
        .title = "Test",
        .title_alignment = .right,
        .border = .plain,
    };
    block.render(Rect.init(0, 0, 15, 5), &buf);

    // Title "Test" (4 chars) should end at position 13 (15-2 = 13 interior right edge)
    // So it starts at 13 - 4 + 1 = 10
    try std.testing.expectEqual(@as(u21, 'T'), buf.get(10, 0).char);
    try std.testing.expectEqual(@as(u21, 'e'), buf.get(11, 0).char);
    try std.testing.expectEqual(@as(u21, 's'), buf.get(12, 0).char);
    try std.testing.expectEqual(@as(u21, 't'), buf.get(13, 0).char);
}

test "behavior: Block renders title center-aligned" {
    var buf = try Buffer.init(std.testing.allocator, 15, 5);
    defer buf.deinit();

    const block = Block{
        .title = "Test",
        .title_alignment = .center,
        .border = .plain,
    };
    block.render(Rect.init(0, 0, 15, 5), &buf);

    // Available width = 13, title = 4, center offset = (13-4)/2 = 4
    // Position = 1 + 4 = 5
    try std.testing.expectEqual(@as(u21, 'T'), buf.get(5, 0).char);
    try std.testing.expectEqual(@as(u21, 'e'), buf.get(6, 0).char);
    try std.testing.expectEqual(@as(u21, 's'), buf.get(7, 0).char);
    try std.testing.expectEqual(@as(u21, 't'), buf.get(8, 0).char);
}

test "behavior: Block with border_style applies style to border" {
    var buf = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf.deinit();

    const block = Block{
        .border = .plain,
        .border_style = Style.init().bold().fg(.red),
    };
    block.render(Rect.init(0, 0, 10, 5), &buf);

    try std.testing.expect(buf.get(0, 0).style.hasAttribute(.bold));
    try std.testing.expect(buf.get(5, 0).style.hasAttribute(.bold));
}

test "behavior: Block with background style fills interior" {
    var buf = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf.deinit();

    const block = Block{
        .border = .plain,
        .style = Style.init().bg(.blue),
    };
    block.render(Rect.init(0, 0, 10, 5), &buf);

    // Interior cell should have background style
    const interior_cell = buf.get(5, 2);
    try std.testing.expect(interior_cell.style.getBackground() != null);
}

// ============================================================
// REGRESSION TESTS - Edge cases
// ============================================================

test "regression: Block handles empty area" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const block = Block{ .border = .plain };
    block.render(Rect.init(0, 0, 0, 0), &buf);

    // Buffer should be unchanged
    for (buf.cells) |cell| {
        try std.testing.expect(cell.isDefault());
    }
}

test "regression: Block handles 1x1 area" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const block = Block{ .border = .plain };
    block.render(Rect.init(0, 0, 1, 1), &buf);

    // Should just draw the top-left corner
    try std.testing.expectEqual(@as(u21, '+'), buf.get(0, 0).char);
}

test "regression: Block handles 2x2 area" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const block = Block{ .border = .plain };
    block.render(Rect.init(0, 0, 2, 2), &buf);

    // All four corners
    try std.testing.expectEqual(@as(u21, '+'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, '+'), buf.get(1, 0).char);
    try std.testing.expectEqual(@as(u21, '+'), buf.get(0, 1).char);
    try std.testing.expectEqual(@as(u21, '+'), buf.get(1, 1).char);
}

test "regression: Block title truncated when too long" {
    var buf = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf.deinit();

    const block = Block{
        .title = "This is a very long title",
        .border = .plain,
    };
    block.render(Rect.init(0, 0, 10, 5), &buf);

    // Title should be truncated to fit (8 chars available)
    try std.testing.expectEqual(@as(u21, 'T'), buf.get(1, 0).char);
    try std.testing.expectEqual(@as(u21, 'h'), buf.get(2, 0).char);
}

test "regression: Block no border still renders background" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const block = Block{
        .border = .none,
        .style = Style.init().bg(.green),
    };
    block.render(Rect.init(2, 2, 5, 5), &buf);

    // Interior should have background
    const cell = buf.get(4, 4);
    try std.testing.expect(cell.style.getBackground() != null);
}

test "regression: BorderType.chars returns correct chars for all types" {
    const plain = BorderType.plain.chars();
    try std.testing.expectEqual(@as(u21, '+'), plain.top_left);

    const rounded = BorderType.rounded.chars();
    try std.testing.expectEqual(@as(u21, 0x256D), rounded.top_left);

    const double = BorderType.double.chars();
    try std.testing.expectEqual(@as(u21, 0x2554), double.top_left);

    const thick = BorderType.thick.chars();
    try std.testing.expectEqual(@as(u21, 0x250F), thick.top_left);
}

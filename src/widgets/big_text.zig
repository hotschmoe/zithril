// BigText widget for zithril TUI framework
// Renders large decorative text using bitmap font glyphs

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const geometry = @import("../geometry.zig");
const style_mod = @import("../style.zig");
const font8x8 = @import("font8x8.zig");

pub const Buffer = buffer_mod.Buffer;
pub const Cell = buffer_mod.Cell;
pub const Rect = geometry.Rect;
pub const Style = style_mod.Style;
pub const Font8x8 = font8x8.Font8x8;

/// Pixel rendering size for BigText.
pub const PixelSize = enum {
    /// Full block character per pixel (8 rows height)
    full,
    /// Half block characters for 2x vertical resolution (4 rows height)
    half,
    /// Quarter block characters for 2x2 resolution (4 rows, half width)
    quarter,
};

/// BigText widget for rendering large decorative text using bitmap fonts.
///
/// Displays text in large 8x8 pixel font using Unicode block characters.
/// Useful for splash screens, headers, and ASCII art banners.
pub const BigText = struct {
    /// Text to render
    text: []const u8,

    /// Style for the rendered blocks
    style: Style = Style.empty,

    /// Pixel rendering mode
    pixel_size: PixelSize = .full,

    /// Calculate the rendered width for the text in a given mode.
    pub fn renderedWidth(self: BigText) usize {
        const char_count = blk: {
            var count: usize = 0;
            var iter = std.unicode.Utf8View.initUnchecked(self.text).iterator();
            while (iter.nextCodepoint()) |_| count += 1;
            break :blk count;
        };

        return switch (self.pixel_size) {
            .full, .half => char_count * 8,
            .quarter => char_count * 4,
        };
    }

    /// Calculate the rendered height in a given mode.
    pub fn renderedHeight(self: BigText) usize {
        return switch (self.pixel_size) {
            .full => 8,
            .half, .quarter => 4,
        };
    }

    /// Render the big text into the buffer at the given area.
    pub fn render(self: BigText, area: Rect, buf: *Buffer) void {
        if (area.isEmpty()) return;
        if (self.text.len == 0) return;

        switch (self.pixel_size) {
            .full => self.renderFull(area, buf),
            .half => self.renderHalf(area, buf),
            .quarter => self.renderQuarter(area, buf),
        }
    }

    /// Render using full blocks (1 pixel = 1 cell)
    fn renderFull(self: BigText, area: Rect, buf: *Buffer) void {
        const full_block: u21 = 0x2588;
        var char_x: u16 = 0;

        var iter = std.unicode.Utf8View.initUnchecked(self.text).iterator();
        while (iter.nextCodepoint()) |codepoint| {
            if (char_x >= area.width) break;

            if (Font8x8.get(codepoint)) |bitmap| {
                self.renderBitmapFull(bitmap, area, char_x, full_block, buf);
            }
            char_x +|= 8;
        }
    }

    fn renderBitmapFull(self: BigText, bitmap: *const [8]u8, area: Rect, char_x: u16, block_char: u21, buf: *Buffer) void {
        for (bitmap, 0..) |row_byte, row_idx| {
            const y = area.y +| @as(u16, @intCast(row_idx));
            if (y >= area.y +| area.height) break;

            var col: u3 = 0;
            while (true) : (col +|= 1) {
                const x = area.x +| char_x +| col;
                if (x >= area.x +| area.width) break;

                const bit_mask = @as(u8, 0x80) >> col;
                if (row_byte & bit_mask != 0) {
                    buf.set(x, y, Cell.styled(block_char, self.style));
                }

                if (col == 7) break;
            }
        }
    }

    /// Render using half blocks (2 vertical pixels = 1 cell)
    fn renderHalf(self: BigText, area: Rect, buf: *Buffer) void {
        const upper_half: u21 = 0x2580; // Upper half block
        const lower_half: u21 = 0x2584; // Lower half block
        const full_block: u21 = 0x2588; // Full block

        var char_x: u16 = 0;

        var iter = std.unicode.Utf8View.initUnchecked(self.text).iterator();
        while (iter.nextCodepoint()) |codepoint| {
            if (char_x >= area.width) break;

            if (Font8x8.get(codepoint)) |bitmap| {
                self.renderBitmapHalf(bitmap, area, char_x, upper_half, lower_half, full_block, buf);
            }
            char_x +|= 8;
        }
    }

    fn renderBitmapHalf(
        self: BigText,
        bitmap: *const [8]u8,
        area: Rect,
        char_x: u16,
        upper_half: u21,
        lower_half: u21,
        full_block: u21,
        buf: *Buffer,
    ) void {
        // Process 2 rows at a time
        var pair: u3 = 0;
        while (pair < 4) : (pair += 1) {
            const row_top = bitmap[@as(usize, pair) * 2];
            const row_bot = bitmap[@as(usize, pair) * 2 + 1];

            const y = area.y +| pair;
            if (y >= area.y +| area.height) break;

            var col: u3 = 0;
            while (true) : (col +|= 1) {
                const x = area.x +| char_x +| col;
                if (x >= area.x +| area.width) break;

                const bit_mask = @as(u8, 0x80) >> col;
                const top_set = (row_top & bit_mask) != 0;
                const bot_set = (row_bot & bit_mask) != 0;

                const char_to_use: ?u21 = if (top_set and bot_set)
                    full_block
                else if (top_set)
                    upper_half
                else if (bot_set)
                    lower_half
                else
                    null;

                if (char_to_use) |c| {
                    buf.set(x, y, Cell.styled(c, self.style));
                }

                if (col == 7) break;
            }
        }
    }

    /// Render using quarter blocks (2x2 pixels = 1 cell)
    fn renderQuarter(self: BigText, area: Rect, buf: *Buffer) void {
        var char_x: u16 = 0;

        var iter = std.unicode.Utf8View.initUnchecked(self.text).iterator();
        while (iter.nextCodepoint()) |codepoint| {
            if (char_x >= area.width) break;

            if (Font8x8.get(codepoint)) |bitmap| {
                self.renderBitmapQuarter(bitmap, area, char_x, buf);
            }
            char_x +|= 4;
        }
    }

    fn renderBitmapQuarter(
        self: BigText,
        bitmap: *const [8]u8,
        area: Rect,
        char_x: u16,
        buf: *Buffer,
    ) void {
        // Quarter block characters for 2x2 pixel combinations
        // Bit positions: top-left=1, top-right=2, bottom-left=4, bottom-right=8
        const quarter_blocks = [16]u21{
            ' ', // 0000 - empty
            0x2598, // 0001 - upper left
            0x259D, // 0010 - upper right
            0x2580, // 0011 - upper half
            0x2596, // 0100 - lower left
            0x258C, // 0101 - left half
            0x259E, // 0110 - diagonal (upper right + lower left)
            0x259B, // 0111 - inverse lower right
            0x2597, // 1000 - lower right
            0x259A, // 1001 - diagonal (upper left + lower right)
            0x2590, // 1010 - right half
            0x259C, // 1011 - inverse lower left
            0x2584, // 1100 - lower half
            0x2599, // 1101 - inverse upper right
            0x259F, // 1110 - inverse upper left
            0x2588, // 1111 - full block
        };

        // Process 2 rows at a time, 2 columns at a time
        var pair: u3 = 0;
        while (pair < 4) : (pair += 1) {
            const row_top = bitmap[@as(usize, pair) * 2];
            const row_bot = bitmap[@as(usize, pair) * 2 + 1];

            const y = area.y +| pair;
            if (y >= area.y +| area.height) break;

            // Process 2 columns at a time
            var col_pair: u3 = 0;
            while (col_pair < 4) : (col_pair += 1) {
                const x = area.x +| char_x +| col_pair;
                if (x >= area.x +| area.width) break;

                const col = @as(u3, col_pair) * 2;

                // Check all 4 pixels in the 2x2 block
                const mask_left = @as(u8, 0x80) >> col;
                const mask_right = @as(u8, 0x80) >> (col +| 1);

                var index: u4 = 0;
                if (row_top & mask_left != 0) index |= 1; // upper left
                if (row_top & mask_right != 0) index |= 2; // upper right
                if (row_bot & mask_left != 0) index |= 4; // lower left
                if (row_bot & mask_right != 0) index |= 8; // lower right

                if (index != 0) {
                    buf.set(x, y, Cell.styled(quarter_blocks[index], self.style));
                }
            }
        }
    }
};

// ============================================================
// SANITY TESTS - Basic BigText functionality
// ============================================================

test "sanity: BigText with default values" {
    const big_text = BigText{ .text = "Hello" };
    try std.testing.expectEqualStrings("Hello", big_text.text);
    try std.testing.expect(big_text.style.isEmpty());
    try std.testing.expect(big_text.pixel_size == .full);
}

test "sanity: BigText with custom style" {
    const big_text = BigText{
        .text = "Test",
        .style = Style.init().fg(.red),
    };
    try std.testing.expect(!big_text.style.isEmpty());
}

test "sanity: BigText renderedWidth calculation" {
    const text = BigText{ .text = "AB" };
    try std.testing.expectEqual(@as(usize, 16), text.renderedWidth());

    const half = BigText{ .text = "AB", .pixel_size = .half };
    try std.testing.expectEqual(@as(usize, 16), half.renderedWidth());

    const quarter = BigText{ .text = "AB", .pixel_size = .quarter };
    try std.testing.expectEqual(@as(usize, 8), quarter.renderedWidth());
}

test "sanity: BigText renderedHeight calculation" {
    const full = BigText{ .text = "A", .pixel_size = .full };
    try std.testing.expectEqual(@as(usize, 8), full.renderedHeight());

    const half = BigText{ .text = "A", .pixel_size = .half };
    try std.testing.expectEqual(@as(usize, 4), half.renderedHeight());

    const quarter = BigText{ .text = "A", .pixel_size = .quarter };
    try std.testing.expectEqual(@as(usize, 4), quarter.renderedHeight());
}

// ============================================================
// BEHAVIOR TESTS - Rendering
// ============================================================

test "behavior: BigText full mode renders character" {
    var buf = try Buffer.init(std.testing.allocator, 16, 10);
    defer buf.deinit();

    const big_text = BigText{
        .text = "A",
        .pixel_size = .full,
    };
    big_text.render(Rect.init(0, 0, 16, 10), &buf);

    // 'A' should have a pixel at (3, 0) based on the bitmap (0b00011000)
    const full_block: u21 = 0x2588;
    try std.testing.expectEqual(full_block, buf.get(3, 0).char);
    try std.testing.expectEqual(full_block, buf.get(4, 0).char);
}

test "behavior: BigText half mode renders character" {
    var buf = try Buffer.init(std.testing.allocator, 16, 10);
    defer buf.deinit();

    const big_text = BigText{
        .text = "A",
        .pixel_size = .half,
    };
    big_text.render(Rect.init(0, 0, 16, 10), &buf);

    // In half mode, height should be 4 rows
    // Check that some cells are set (non-space)
    var non_empty: usize = 0;
    for (0..4) |y| {
        for (0..8) |x| {
            if (buf.get(@intCast(x), @intCast(y)).char != ' ') {
                non_empty += 1;
            }
        }
    }
    try std.testing.expect(non_empty > 0);
}

test "behavior: BigText quarter mode renders character" {
    var buf = try Buffer.init(std.testing.allocator, 16, 10);
    defer buf.deinit();

    const big_text = BigText{
        .text = "A",
        .pixel_size = .quarter,
    };
    big_text.render(Rect.init(0, 0, 16, 10), &buf);

    // In quarter mode, char width is 4
    var non_empty: usize = 0;
    for (0..4) |y| {
        for (0..4) |x| {
            if (buf.get(@intCast(x), @intCast(y)).char != ' ') {
                non_empty += 1;
            }
        }
    }
    try std.testing.expect(non_empty > 0);
}

test "behavior: BigText renders multiple characters" {
    var buf = try Buffer.init(std.testing.allocator, 32, 10);
    defer buf.deinit();

    const big_text = BigText{
        .text = "AB",
        .pixel_size = .full,
    };
    big_text.render(Rect.init(0, 0, 32, 10), &buf);

    // Both 'A' and 'B' should render
    // 'A' at columns 0-7, 'B' at columns 8-15
    const full_block: u21 = 0x2588;

    // Check 'A' has pixels
    try std.testing.expectEqual(full_block, buf.get(3, 0).char);

    // Check 'B' has pixels (B starts with 0b01111100)
    try std.testing.expectEqual(full_block, buf.get(9, 0).char);
}

test "behavior: BigText applies custom style" {
    var buf = try Buffer.init(std.testing.allocator, 16, 10);
    defer buf.deinit();

    const big_text = BigText{
        .text = "A",
        .style = Style.init().fg(.green),
        .pixel_size = .full,
    };
    big_text.render(Rect.init(0, 0, 16, 10), &buf);

    // Find a rendered cell and check its style
    const cell = buf.get(3, 0);
    try std.testing.expect(cell.style.getForeground() != null);
}

// ============================================================
// REGRESSION TESTS - Edge cases
// ============================================================

test "regression: BigText handles empty area" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const big_text = BigText{ .text = "A" };
    big_text.render(Rect.init(0, 0, 0, 0), &buf);

    // Buffer should be unchanged
    for (buf.cells) |cell| {
        try std.testing.expect(cell.isDefault());
    }
}

test "regression: BigText handles empty text" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const big_text = BigText{ .text = "" };
    big_text.render(Rect.init(0, 0, 10, 10), &buf);

    // Buffer should be unchanged
    for (buf.cells) |cell| {
        try std.testing.expect(cell.isDefault());
    }
}

test "regression: BigText clips to area bounds" {
    var buf = try Buffer.init(std.testing.allocator, 5, 5);
    defer buf.deinit();

    // Text would normally be 16 cells wide
    const big_text = BigText{
        .text = "AB",
        .pixel_size = .full,
    };
    big_text.render(Rect.init(0, 0, 5, 5), &buf);

    // Should not crash, content clipped to 5x5
    try std.testing.expect(true);
}

test "regression: BigText handles unknown characters" {
    var buf = try Buffer.init(std.testing.allocator, 16, 10);
    defer buf.deinit();

    // Unicode character not in font
    const big_text = BigText{ .text = "\u{1234}" };
    big_text.render(Rect.init(0, 0, 16, 10), &buf);

    // Should not crash, unknown char is skipped
    try std.testing.expect(true);
}

test "regression: BigText renders at non-zero offset" {
    var buf = try Buffer.init(std.testing.allocator, 30, 20);
    defer buf.deinit();

    const big_text = BigText{
        .text = "A",
        .pixel_size = .full,
    };
    big_text.render(Rect.init(5, 3, 10, 10), &buf);

    // Should render at offset
    const full_block: u21 = 0x2588;
    try std.testing.expectEqual(full_block, buf.get(8, 3).char); // 5 + 3

    // Origin should be unchanged
    try std.testing.expect(buf.get(0, 0).isDefault());
}

test "regression: BigText space character renders as empty" {
    var buf = try Buffer.init(std.testing.allocator, 16, 10);
    defer buf.deinit();

    const big_text = BigText{
        .text = " ",
        .pixel_size = .full,
    };
    big_text.render(Rect.init(0, 0, 16, 10), &buf);

    // Space should not render any blocks
    for (0..8) |y| {
        for (0..8) |x| {
            try std.testing.expect(buf.get(@intCast(x), @intCast(y)).isDefault());
        }
    }
}

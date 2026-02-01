// Buffer type for zithril TUI framework
// A 2D grid of Cells that widgets render into

const std = @import("std");
const cell_mod = @import("cell.zig");
const geometry = @import("geometry.zig");
const style_mod = @import("style.zig");

pub const Cell = cell_mod.Cell;
pub const Rect = geometry.Rect;
pub const Style = style_mod.Style;

/// Buffer is a 2D grid of Cells representing the terminal screen.
/// Cells are stored in row-major order: cells[y * width + x].
/// Widgets render into the Buffer, which is then diffed and output to the terminal.
pub const Buffer = struct {
    /// Width in terminal columns.
    width: u16,
    /// Height in terminal rows.
    height: u16,
    /// Cell storage in row-major order.
    cells: []Cell,
    /// Allocator used for cell storage.
    allocator: std.mem.Allocator,

    /// Initialize a buffer with the given dimensions.
    /// All cells are initialized to the default (space with empty style).
    pub fn init(allocator: std.mem.Allocator, width: u16, height: u16) !Buffer {
        const size = @as(usize, width) * @as(usize, height);
        const cells = try allocator.alloc(Cell, size);
        @memset(cells, Cell.default);

        return Buffer{
            .width = width,
            .height = height,
            .cells = cells,
            .allocator = allocator,
        };
    }

    /// Free the cell storage.
    pub fn deinit(self: *Buffer) void {
        self.allocator.free(self.cells);
        self.* = undefined;
    }

    /// Reset all cells to default.
    pub fn clear(self: *Buffer) void {
        @memset(self.cells, Cell.default);
    }

    /// Calculate the index for a given (x, y) position.
    /// Returns null if out of bounds.
    fn index(self: Buffer, x: u16, y: u16) ?usize {
        if (x >= self.width or y >= self.height) {
            return null;
        }
        return @as(usize, y) * @as(usize, self.width) + @as(usize, x);
    }

    /// Set a single cell at position (x, y).
    /// Does nothing if position is out of bounds.
    pub fn set(self: *Buffer, x: u16, y: u16, cell: Cell) void {
        if (self.index(x, y)) |idx| {
            self.cells[idx] = cell;
        }
    }

    /// Get a cell at position (x, y).
    /// Returns the default cell if out of bounds.
    pub fn get(self: Buffer, x: u16, y: u16) Cell {
        if (self.index(x, y)) |idx| {
            return self.cells[idx];
        }
        return Cell.default;
    }

    /// Write a string starting at (x, y) with the given style.
    /// Handles wide characters (width 2) by filling the next cell with a placeholder.
    /// Clips at buffer bounds.
    pub fn setString(self: *Buffer, x: u16, y: u16, str: []const u8, style: Style) void {
        if (y >= self.height) return;

        var current_x = x;
        var iter = std.unicode.Utf8View.initUnchecked(str).iterator();

        while (iter.nextCodepoint()) |codepoint| {
            if (current_x >= self.width) break;

            const cell = Cell.styled(codepoint, style);
            self.set(current_x, y, cell);

            // Handle wide characters
            if (cell.isWide()) {
                current_x +|= 1;
                if (current_x < self.width) {
                    // Place a placeholder in the following cell for wide chars
                    self.set(current_x, y, Cell.withWidth(' ', style, 0));
                }
            }

            current_x +|= 1;
        }
    }

    /// Fill a rectangular region with a cell.
    /// Clips to buffer bounds.
    pub fn fill(self: *Buffer, rect: Rect, cell: Cell) void {
        const start_x = rect.x;
        const start_y = rect.y;
        const end_x = @min(rect.right(), self.width);
        const end_y = @min(rect.bottom(), self.height);

        if (start_x >= self.width or start_y >= self.height) return;

        var y = start_y;
        while (y < end_y) : (y += 1) {
            var curr_x = start_x;
            while (curr_x < end_x) : (curr_x += 1) {
                self.set(curr_x, y, cell);
            }
        }
    }

    /// Fill a rectangular region with a style (preserves characters).
    /// Clips to buffer bounds.
    pub fn setStyleArea(self: *Buffer, rect: Rect, style: Style) void {
        const start_x = rect.x;
        const start_y = rect.y;
        const end_x = @min(rect.right(), self.width);
        const end_y = @min(rect.bottom(), self.height);

        if (start_x >= self.width or start_y >= self.height) return;

        var y = start_y;
        while (y < end_y) : (y += 1) {
            var curr_x = start_x;
            while (curr_x < end_x) : (curr_x += 1) {
                if (self.index(curr_x, y)) |idx| {
                    self.cells[idx] = self.cells[idx].setStyle(style);
                }
            }
        }
    }

    /// Get the total number of cells.
    pub fn cellCount(self: Buffer) usize {
        return @as(usize, self.width) * @as(usize, self.height);
    }

    /// Returns the buffer as a Rect covering the entire area.
    pub fn area(self: Buffer) Rect {
        return Rect.init(0, 0, self.width, self.height);
    }

    /// Resize the buffer. Existing content is lost.
    pub fn resize(self: *Buffer, new_width: u16, new_height: u16) !void {
        const new_size = @as(usize, new_width) * @as(usize, new_height);

        if (new_size != self.cellCount()) {
            self.allocator.free(self.cells);
            self.cells = try self.allocator.alloc(Cell, new_size);
        }

        self.width = new_width;
        self.height = new_height;
        @memset(self.cells, Cell.default);
    }
};

// ============================================================
// SANITY TESTS - Basic Buffer functionality
// ============================================================

test "sanity: Buffer.init creates buffer with correct dimensions" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    try std.testing.expectEqual(@as(u16, 80), buf.width);
    try std.testing.expectEqual(@as(u16, 24), buf.height);
    try std.testing.expectEqual(@as(usize, 80 * 24), buf.cells.len);
}

test "sanity: Buffer cells initialized to default" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    for (buf.cells) |cell| {
        try std.testing.expect(cell.isDefault());
    }
}

test "sanity: Buffer.set and Buffer.get" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const cell = Cell.styled('X', Style.init().bold());
    buf.set(5, 5, cell);

    const retrieved = buf.get(5, 5);
    try std.testing.expectEqual(@as(u21, 'X'), retrieved.char);
    try std.testing.expect(retrieved.style.hasAttribute(.bold));
}

// ============================================================
// BEHAVIOR TESTS - Edge cases and clipping
// ============================================================

test "behavior: Buffer.get returns default for out-of-bounds" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const cell = buf.get(100, 100);
    try std.testing.expect(cell.isDefault());
}

test "behavior: Buffer.set ignores out-of-bounds" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    buf.set(100, 100, Cell.init('X'));

    // Should not crash, and buffer should be unchanged
    for (buf.cells) |cell| {
        try std.testing.expect(cell.isDefault());
    }
}

test "behavior: Buffer.setString writes string with style" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    buf.setString(0, 0, "Hello", Style.init().bold());

    try std.testing.expectEqual(@as(u21, 'H'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 'e'), buf.get(1, 0).char);
    try std.testing.expectEqual(@as(u21, 'l'), buf.get(2, 0).char);
    try std.testing.expectEqual(@as(u21, 'l'), buf.get(3, 0).char);
    try std.testing.expectEqual(@as(u21, 'o'), buf.get(4, 0).char);

    for (0..5) |i| {
        try std.testing.expect(buf.get(@intCast(i), 0).style.hasAttribute(.bold));
    }
}

test "behavior: Buffer.setString handles wide characters" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    // CJK character (width 2)
    buf.setString(0, 0, "\u{4E2D}", Style.empty);

    const wide_cell = buf.get(0, 0);
    try std.testing.expectEqual(@as(u21, 0x4E2D), wide_cell.char);
    try std.testing.expectEqual(@as(u8, 2), wide_cell.width);

    // Next cell should be a zero-width placeholder
    const placeholder = buf.get(1, 0);
    try std.testing.expectEqual(@as(u8, 0), placeholder.width);
}

test "behavior: Buffer.setString clips at buffer boundary" {
    var buf = try Buffer.init(std.testing.allocator, 5, 5);
    defer buf.deinit();

    buf.setString(3, 0, "Hello", Style.empty);

    try std.testing.expectEqual(@as(u21, 'H'), buf.get(3, 0).char);
    try std.testing.expectEqual(@as(u21, 'e'), buf.get(4, 0).char);
    // "llo" should be clipped
}

test "behavior: Buffer.setString y out of bounds does nothing" {
    var buf = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf.deinit();

    buf.setString(0, 10, "Hello", Style.empty);

    // Buffer should be unchanged
    for (buf.cells) |cell| {
        try std.testing.expect(cell.isDefault());
    }
}

test "behavior: Buffer.fill fills rectangular area" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const fill_cell = Cell.styled('#', Style.init().fg(.red));
    buf.fill(Rect.init(2, 2, 3, 3), fill_cell);

    // Inside the filled area
    try std.testing.expectEqual(@as(u21, '#'), buf.get(2, 2).char);
    try std.testing.expectEqual(@as(u21, '#'), buf.get(4, 4).char);

    // Outside the filled area
    try std.testing.expect(buf.get(0, 0).isDefault());
    try std.testing.expect(buf.get(5, 5).isDefault());
    try std.testing.expect(buf.get(1, 2).isDefault());
}

test "behavior: Buffer.fill clips to bounds" {
    var buf = try Buffer.init(std.testing.allocator, 5, 5);
    defer buf.deinit();

    buf.fill(Rect.init(3, 3, 10, 10), Cell.init('X'));

    try std.testing.expectEqual(@as(u21, 'X'), buf.get(3, 3).char);
    try std.testing.expectEqual(@as(u21, 'X'), buf.get(4, 4).char);
}

test "behavior: Buffer.setStyleArea preserves characters" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    buf.setString(0, 0, "ABC", Style.empty);
    buf.setStyleArea(Rect.init(0, 0, 3, 1), Style.init().bold());

    try std.testing.expectEqual(@as(u21, 'A'), buf.get(0, 0).char);
    try std.testing.expect(buf.get(0, 0).style.hasAttribute(.bold));
    try std.testing.expectEqual(@as(u21, 'B'), buf.get(1, 0).char);
    try std.testing.expect(buf.get(1, 0).style.hasAttribute(.bold));
}

test "behavior: Buffer.clear resets all cells" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    buf.set(5, 5, Cell.init('X'));
    buf.clear();

    try std.testing.expect(buf.get(5, 5).isDefault());
}

test "behavior: Buffer.area returns correct rect" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const rect = buf.area();
    try std.testing.expectEqual(@as(u16, 0), rect.x);
    try std.testing.expectEqual(@as(u16, 0), rect.y);
    try std.testing.expectEqual(@as(u16, 80), rect.width);
    try std.testing.expectEqual(@as(u16, 24), rect.height);
}

test "behavior: Buffer.resize changes dimensions" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    buf.set(5, 5, Cell.init('X'));

    try buf.resize(20, 20);

    try std.testing.expectEqual(@as(u16, 20), buf.width);
    try std.testing.expectEqual(@as(u16, 20), buf.height);
    // Content is cleared on resize
    try std.testing.expect(buf.get(5, 5).isDefault());
}

// ============================================================
// REGRESSION TESTS - Edge cases
// ============================================================

test "regression: Buffer handles zero dimensions" {
    var buf = try Buffer.init(std.testing.allocator, 0, 0);
    defer buf.deinit();

    try std.testing.expectEqual(@as(usize, 0), buf.cells.len);

    // Operations on empty buffer should not crash
    buf.set(0, 0, Cell.init('X'));
    try std.testing.expect(buf.get(0, 0).isDefault());
}

test "regression: Buffer.setString handles empty string" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    buf.setString(0, 0, "", Style.empty);

    // Buffer should be unchanged
    for (buf.cells) |cell| {
        try std.testing.expect(cell.isDefault());
    }
}

test "regression: Buffer.fill with empty rect does nothing" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    buf.fill(Rect.init(0, 0, 0, 0), Cell.init('X'));

    for (buf.cells) |cell| {
        try std.testing.expect(cell.isDefault());
    }
}

test "regression: Buffer.setStyleArea with empty rect does nothing" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    buf.setString(0, 0, "ABC", Style.empty);
    buf.setStyleArea(Rect.init(0, 0, 0, 0), Style.init().bold());

    // Original cells should not have bold
    try std.testing.expect(!buf.get(0, 0).style.hasAttribute(.bold));
}

test "regression: setString with wide char at boundary" {
    var buf = try Buffer.init(std.testing.allocator, 3, 1);
    defer buf.deinit();

    // Wide char at x=2 should be clipped (needs 2 columns, only 1 available)
    buf.setString(2, 0, "\u{4E2D}", Style.empty);

    // Should still write the wide char but placeholder will be clipped
    const cell = buf.get(2, 0);
    try std.testing.expectEqual(@as(u21, 0x4E2D), cell.char);
}

test "regression: setString handles multi-byte UTF-8" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    // Mix of ASCII and multi-byte characters
    buf.setString(0, 0, "Hi\u{00E9}", Style.empty);

    try std.testing.expectEqual(@as(u21, 'H'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 'i'), buf.get(1, 0).char);
    try std.testing.expectEqual(@as(u21, 0x00E9), buf.get(2, 0).char);
}

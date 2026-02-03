// Cell type for zithril TUI framework
// Represents a single character cell in the terminal buffer

const std = @import("std");
pub const rich_zig = @import("rich_zig");
const style_mod = @import("style.zig");
pub const Style = style_mod.Style;

/// A single cell in the terminal buffer.
/// Each cell represents one character position, with its associated style and display width.
pub const Cell = struct {
    /// Unicode codepoint for the character displayed in this cell.
    /// Defaults to space (U+0020).
    char: u21 = ' ',

    /// Visual style applied to this cell (colors, bold, italic, etc).
    style: Style = Style.empty,

    /// Display width in terminal columns.
    /// - 1 for most characters (ASCII, basic Latin, etc.)
    /// - 2 for wide characters (CJK ideographs, emoji, fullwidth forms)
    /// - 0 for combining marks (handled specially during rendering)
    width: u8 = 1,

    /// The default cell: a space with default style and width 1.
    pub const default: Cell = .{};

    /// Create a cell with a specific character, using default style.
    pub fn init(char: u21) Cell {
        return .{
            .char = char,
            .style = Style.empty,
            .width = charWidth(char),
        };
    }

    /// Create a cell with a character and style.
    pub fn styled(char: u21, s: Style) Cell {
        return .{
            .char = char,
            .style = s,
            .width = charWidth(char),
        };
    }

    /// Create a cell with explicit width override.
    pub fn withWidth(char: u21, s: Style, w: u8) Cell {
        return .{
            .char = char,
            .style = s,
            .width = w,
        };
    }

    /// Update the cell's character, automatically recalculating width.
    pub fn setChar(self: Cell, char: u21) Cell {
        return .{
            .char = char,
            .style = self.style,
            .width = charWidth(char),
        };
    }

    /// Update the cell's style.
    pub fn setStyle(self: Cell, s: Style) Cell {
        return .{
            .char = self.char,
            .style = s,
            .width = self.width,
        };
    }

    /// Merge another style on top of this cell's style.
    pub fn patchStyle(self: Cell, s: Style) Cell {
        return .{
            .char = self.char,
            .style = self.style.patch(s),
            .width = self.width,
        };
    }

    /// Check if this cell is the default (space with empty style).
    pub fn isDefault(self: Cell) bool {
        return self.char == ' ' and self.style.isEmpty() and self.width == 1;
    }

    /// Check equality with another cell.
    pub fn eql(self: Cell, other: Cell) bool {
        return self.char == other.char and
            self.style.eql(other.style) and
            self.width == other.width;
    }

    /// Get the character width using rich_zig's cell width calculation.
    /// Returns 1 for most chars, 2 for wide (CJK/emoji), 0 for combining.
    pub fn charWidth(char: u21) u8 {
        return rich_zig.cells.getCharacterCellSize(char);
    }

    /// Check if this cell contains a wide character (width 2).
    pub fn isWide(self: Cell) bool {
        return self.width == 2;
    }

    /// Check if this cell contains a zero-width character (combining mark).
    pub fn isZeroWidth(self: Cell) bool {
        return self.width == 0;
    }
};

// ============================================================
// SANITY TESTS - Basic Cell functionality
// ============================================================

test "sanity: Cell default is space with default style" {
    const cell = Cell.default;
    try std.testing.expectEqual(@as(u21, ' '), cell.char);
    try std.testing.expect(cell.style.isEmpty());
    try std.testing.expectEqual(@as(u8, 1), cell.width);
}

test "sanity: Cell.init creates cell with correct width" {
    const cell = Cell.init('A');
    try std.testing.expectEqual(@as(u21, 'A'), cell.char);
    try std.testing.expectEqual(@as(u8, 1), cell.width);
    try std.testing.expect(cell.style.isEmpty());
}

test "sanity: Cell.styled creates cell with style" {
    const s = Style.init().bold().fg(.red);
    const cell = Cell.styled('X', s);
    try std.testing.expectEqual(@as(u21, 'X'), cell.char);
    try std.testing.expect(cell.style.hasAttribute(.bold));
}

// ============================================================
// BEHAVIOR TESTS - Wide characters and combining marks
// ============================================================

test "behavior: Cell.init detects CJK as wide" {
    const cell = Cell.init(0x4E2D);
    try std.testing.expectEqual(@as(u8, 2), cell.width);
    try std.testing.expect(cell.isWide());
}

test "behavior: Cell.init detects emoji as wide" {
    const cell = Cell.init(0x1F600);
    try std.testing.expectEqual(@as(u8, 2), cell.width);
    try std.testing.expect(cell.isWide());
}

test "behavior: Cell.init detects combining mark as zero-width" {
    const cell = Cell.init(0x0301);
    try std.testing.expectEqual(@as(u8, 0), cell.width);
    try std.testing.expect(cell.isZeroWidth());
}

test "behavior: Cell.isDefault detects default cell" {
    try std.testing.expect(Cell.default.isDefault());
    try std.testing.expect(!Cell.init('X').isDefault());
    try std.testing.expect(!Cell.styled(' ', Style.init().bold()).isDefault());
}

test "behavior: Cell.setChar updates char and width" {
    const cell = Cell.init('A');
    const updated = cell.setChar(0x4E2D);
    try std.testing.expectEqual(@as(u21, 0x4E2D), updated.char);
    try std.testing.expectEqual(@as(u8, 2), updated.width);
}

test "behavior: Cell.setStyle preserves char and width" {
    const cell = Cell.init(0x4E2D);
    const styled_cell = cell.setStyle(Style.init().bold());
    try std.testing.expectEqual(@as(u21, 0x4E2D), styled_cell.char);
    try std.testing.expectEqual(@as(u8, 2), styled_cell.width);
    try std.testing.expect(styled_cell.style.hasAttribute(.bold));
}

test "behavior: Cell.patchStyle merges styles" {
    const cell = Cell.styled('A', Style.init().bold());
    const patched = cell.patchStyle(Style.init().italic());
    try std.testing.expect(patched.style.hasAttribute(.bold));
    try std.testing.expect(patched.style.hasAttribute(.italic));
}

test "behavior: Cell.eql compares all fields" {
    const c1 = Cell.styled('A', Style.init().bold());
    const c2 = Cell.styled('A', Style.init().bold());
    const c3 = Cell.styled('B', Style.init().bold());
    const c4 = Cell.styled('A', Style.init().italic());

    try std.testing.expect(c1.eql(c2));
    try std.testing.expect(!c1.eql(c3));
    try std.testing.expect(!c1.eql(c4));
}

test "behavior: Cell.withWidth allows explicit width override" {
    const cell = Cell.withWidth('A', Style.empty, 3);
    try std.testing.expectEqual(@as(u8, 3), cell.width);
}

// ============================================================
// REGRESSION TESTS - Edge cases
// ============================================================

test "regression: ASCII characters have width 1" {
    for (0x20..0x7F) |c| {
        const cell = Cell.init(@intCast(c));
        try std.testing.expectEqual(@as(u8, 1), cell.width);
    }
}

test "regression: control characters have width 0" {
    const cell_null = Cell.init(0);
    try std.testing.expectEqual(@as(u8, 0), cell_null.width);

    const cell_newline = Cell.init('\n');
    try std.testing.expectEqual(@as(u8, 0), cell_newline.width);
}

test "regression: zero-width space has width 0" {
    const cell = Cell.init(0x200B);
    try std.testing.expectEqual(@as(u8, 0), cell.width);
}

// Table widget for zithril TUI framework
// Rows and columns with optional header, column widths, and selection

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const geometry = @import("../geometry.zig");
const style_mod = @import("../style.zig");
const layout_mod = @import("../layout.zig");

pub const Buffer = buffer_mod.Buffer;
pub const Cell = buffer_mod.Cell;
pub const Rect = geometry.Rect;
pub const Style = style_mod.Style;
pub const Constraint = layout_mod.Constraint;

/// Table widget displaying rows and columns with optional header.
///
/// Renders a table with configurable column widths (via constraints),
/// optional header row, row selection highlighting, and custom styling.
pub const Table = struct {
    /// Optional header row (column titles)
    header: ?[]const []const u8 = null,

    /// Table rows - each row is an array of cell strings
    rows: []const []const []const u8,

    /// Column width constraints. Length should match column count.
    /// If fewer constraints than columns, remaining columns use flex(1).
    widths: []const Constraint,

    /// Currently selected row index (null for no selection)
    selected: ?usize = null,

    /// Default style for table content
    style: Style = Style.empty,

    /// Style for the header row
    header_style: Style = Style.init().bold(),

    /// Style for the selected row
    highlight_style: Style = Style.init().bg(.blue),

    /// Render the table into the buffer at the given area.
    pub fn render(self: Table, area: Rect, buf: *Buffer) void {
        if (area.isEmpty()) return;
        if (self.rows.len == 0 and self.header == null) return;

        // Calculate column widths
        const col_count = self.columnCount();
        if (col_count == 0) return;

        var col_widths: [layout_mod.max_constraints]u16 = undefined;
        self.calculateColumnWidths(area.width, col_count, &col_widths);

        var current_y = area.y;

        // Render header if present
        if (self.header) |header_row| {
            if (current_y < area.bottom()) {
                self.renderRow(buf, area.x, current_y, area.width, header_row, col_widths[0..col_count], self.header_style);
                current_y += 1;
            }
        }

        // Render data rows
        for (self.rows, 0..) |row, row_idx| {
            if (current_y >= area.bottom()) break;

            const is_selected = self.selected != null and self.selected.? == row_idx;
            const row_style = if (is_selected) self.highlight_style else self.style;

            self.renderRow(buf, area.x, current_y, area.width, row, col_widths[0..col_count], row_style);
            current_y += 1;
        }
    }

    fn renderRow(
        self: Table,
        buf: *Buffer,
        x: u16,
        y: u16,
        total_width: u16,
        cells: []const []const u8,
        col_widths: []const u16,
        row_style: Style,
    ) void {
        _ = self;

        // Fill entire row with style
        buf.fill(Rect.init(x, y, total_width, 1), Cell.styled(' ', row_style));

        var col_x = x;
        for (col_widths, 0..) |col_width, col_idx| {
            if (col_width == 0) continue;
            if (col_x >= x +| total_width) break;

            const cell_text = if (col_idx < cells.len) cells[col_idx] else "";

            // Render cell text, clipped to column width
            if (cell_text.len > 0) {
                buf.setString(col_x, y, cell_text, row_style);
            }

            col_x +|= col_width;
        }
    }

    fn calculateColumnWidths(self: Table, total_width: u16, col_count: usize, out: *[layout_mod.max_constraints]u16) void {
        // Build constraint array, using flex(1) for columns without explicit constraint
        var constraints: [layout_mod.max_constraints]Constraint = undefined;
        const actual_count = @min(col_count, layout_mod.max_constraints);

        for (0..actual_count) |i| {
            constraints[i] = if (i < self.widths.len) self.widths[i] else Constraint.flexible(1);
        }

        // Use the layout solver to calculate widths
        const result = layout_mod.layout(
            Rect.init(0, 0, total_width, 1),
            .horizontal,
            constraints[0..actual_count],
        );

        for (result.constSlice(), 0..) |rect, i| {
            out[i] = rect.width;
        }
    }

    fn columnCount(self: Table) usize {
        // Determine column count from header, rows, or widths
        if (self.header) |h| {
            return h.len;
        }
        if (self.rows.len > 0) {
            return self.rows[0].len;
        }
        return self.widths.len;
    }

    /// Get the number of data rows (excluding header)
    pub fn rowCount(self: Table) usize {
        return self.rows.len;
    }

    /// Check if the table has no data rows
    pub fn isEmpty(self: Table) bool {
        return self.rows.len == 0;
    }
};

// ============================================================
// SANITY TESTS - Basic Table functionality
// ============================================================

test "sanity: Table with default values" {
    const rows = [_][]const []const u8{
        &.{ "a", "b" },
        &.{ "c", "d" },
    };
    const widths = [_]Constraint{ Constraint.flexible(1), Constraint.flexible(1) };
    const table = Table{
        .rows = &rows,
        .widths = &widths,
    };

    try std.testing.expectEqual(@as(usize, 2), table.rowCount());
    try std.testing.expect(table.selected == null);
    try std.testing.expect(table.header == null);
}

test "sanity: Table with header" {
    const rows = [_][]const []const u8{
        &.{ "1", "2" },
    };
    const header = [_][]const u8{ "Col A", "Col B" };
    const widths = [_]Constraint{ Constraint.flexible(1), Constraint.flexible(1) };
    const table = Table{
        .rows = &rows,
        .widths = &widths,
        .header = &header,
    };

    try std.testing.expect(table.header != null);
    try std.testing.expectEqual(@as(usize, 2), table.header.?.len);
}

test "sanity: Table with selection" {
    const rows = [_][]const []const u8{
        &.{"a"},
        &.{"b"},
        &.{"c"},
    };
    const widths = [_]Constraint{Constraint.flexible(1)};
    const table = Table{
        .rows = &rows,
        .widths = &widths,
        .selected = 1,
    };

    try std.testing.expect(table.selected != null);
    try std.testing.expectEqual(@as(usize, 1), table.selected.?);
}

test "sanity: Table with custom styles" {
    const rows = [_][]const []const u8{&.{"x"}};
    const widths = [_]Constraint{Constraint.flexible(1)};
    const table = Table{
        .rows = &rows,
        .widths = &widths,
        .style = Style.init().fg(.white),
        .header_style = Style.init().bold().fg(.yellow),
        .highlight_style = Style.init().bg(.red),
    };

    try std.testing.expect(!table.style.isEmpty());
    try std.testing.expect(table.header_style.hasAttribute(.bold));
}

test "sanity: Table.rowCount and Table.isEmpty" {
    const rows = [_][]const []const u8{&.{"a"}};
    const widths = [_]Constraint{Constraint.flexible(1)};
    const table = Table{ .rows = &rows, .widths = &widths };

    try std.testing.expectEqual(@as(usize, 1), table.rowCount());
    try std.testing.expect(!table.isEmpty());

    const empty_rows = [_][]const []const u8{};
    const empty_table = Table{ .rows = &empty_rows, .widths = &widths };

    try std.testing.expectEqual(@as(usize, 0), empty_table.rowCount());
    try std.testing.expect(empty_table.isEmpty());
}

// ============================================================
// BEHAVIOR TESTS - Rendering
// ============================================================

test "behavior: Table renders rows" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const rows = [_][]const []const u8{
        &.{ "A", "B" },
        &.{ "C", "D" },
    };
    const widths = [_]Constraint{ Constraint.len(5), Constraint.len(5) };
    const table = Table{ .rows = &rows, .widths = &widths };
    table.render(Rect.init(0, 0, 20, 5), &buf);

    try std.testing.expectEqual(@as(u21, 'A'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 'B'), buf.get(5, 0).char);
    try std.testing.expectEqual(@as(u21, 'C'), buf.get(0, 1).char);
    try std.testing.expectEqual(@as(u21, 'D'), buf.get(5, 1).char);
}

test "behavior: Table renders header" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const rows = [_][]const []const u8{&.{ "1", "2" }};
    const header = [_][]const u8{ "X", "Y" };
    const widths = [_]Constraint{ Constraint.len(5), Constraint.len(5) };
    const table = Table{
        .rows = &rows,
        .widths = &widths,
        .header = &header,
        .header_style = Style.init().bold(),
    };
    table.render(Rect.init(0, 0, 20, 5), &buf);

    // Header at row 0
    try std.testing.expectEqual(@as(u21, 'X'), buf.get(0, 0).char);
    try std.testing.expect(buf.get(0, 0).style.hasAttribute(.bold));

    // Data at row 1
    try std.testing.expectEqual(@as(u21, '1'), buf.get(0, 1).char);
    try std.testing.expect(!buf.get(0, 1).style.hasAttribute(.bold));
}

test "behavior: Table renders selected row with highlight" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const rows = [_][]const []const u8{
        &.{"First"},
        &.{"Second"},
        &.{"Third"},
    };
    const widths = [_]Constraint{Constraint.flexible(1)};
    const table = Table{
        .rows = &rows,
        .widths = &widths,
        .selected = 1,
        .highlight_style = Style.init().bold(),
    };
    table.render(Rect.init(0, 0, 20, 5), &buf);

    // Row 1 should have highlight
    try std.testing.expect(buf.get(0, 1).style.hasAttribute(.bold));
    // Row 0 and 2 should not
    try std.testing.expect(!buf.get(0, 0).style.hasAttribute(.bold));
    try std.testing.expect(!buf.get(0, 2).style.hasAttribute(.bold));
}

test "behavior: Table respects column widths" {
    var buf = try Buffer.init(std.testing.allocator, 30, 5);
    defer buf.deinit();

    const rows = [_][]const []const u8{&.{ "AAA", "BBB", "CCC" }};
    const widths = [_]Constraint{
        Constraint.len(10),
        Constraint.len(5),
        Constraint.len(10),
    };
    const table = Table{ .rows = &rows, .widths = &widths };
    table.render(Rect.init(0, 0, 30, 5), &buf);

    // Col 1 starts at x=0
    try std.testing.expectEqual(@as(u21, 'A'), buf.get(0, 0).char);
    // Col 2 starts at x=10
    try std.testing.expectEqual(@as(u21, 'B'), buf.get(10, 0).char);
    // Col 3 starts at x=15
    try std.testing.expectEqual(@as(u21, 'C'), buf.get(15, 0).char);
}

test "behavior: Table renders at area offset" {
    var buf = try Buffer.init(std.testing.allocator, 30, 10);
    defer buf.deinit();

    const rows = [_][]const []const u8{&.{"Test"}};
    const widths = [_]Constraint{Constraint.flexible(1)};
    const table = Table{ .rows = &rows, .widths = &widths };
    table.render(Rect.init(5, 3, 20, 5), &buf);

    try std.testing.expectEqual(@as(u21, 'T'), buf.get(5, 3).char);
}

// ============================================================
// REGRESSION TESTS - Edge cases
// ============================================================

test "regression: Table handles empty rows" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const rows = [_][]const []const u8{};
    const widths = [_]Constraint{Constraint.flexible(1)};
    const table = Table{ .rows = &rows, .widths = &widths };
    table.render(Rect.init(0, 0, 20, 5), &buf);

    for (buf.cells) |cell| {
        try std.testing.expect(cell.isDefault());
    }
}

test "regression: Table handles empty area" {
    var buf = try Buffer.init(std.testing.allocator, 20, 20);
    defer buf.deinit();

    const rows = [_][]const []const u8{&.{"data"}};
    const widths = [_]Constraint{Constraint.flexible(1)};
    const table = Table{ .rows = &rows, .widths = &widths };
    table.render(Rect.init(0, 0, 0, 0), &buf);

    for (buf.cells) |cell| {
        try std.testing.expect(cell.isDefault());
    }
}

test "regression: Table handles selection out of bounds" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const rows = [_][]const []const u8{&.{"a"}};
    const widths = [_]Constraint{Constraint.flexible(1)};
    const table = Table{
        .rows = &rows,
        .widths = &widths,
        .selected = 99,
    };
    table.render(Rect.init(0, 0, 20, 5), &buf);

    // Should render without crash, no row highlighted
    try std.testing.expectEqual(@as(u21, 'a'), buf.get(0, 0).char);
}

test "regression: Table with more columns than widths uses flex" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const rows = [_][]const []const u8{&.{ "A", "B", "C" }};
    const widths = [_]Constraint{Constraint.len(5)};
    const table = Table{ .rows = &rows, .widths = &widths };
    table.render(Rect.init(0, 0, 20, 5), &buf);

    // Should render all columns
    try std.testing.expectEqual(@as(u21, 'A'), buf.get(0, 0).char);
}

test "regression: Table with fewer cells than columns" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const rows = [_][]const []const u8{&.{"Only one"}};
    const widths = [_]Constraint{ Constraint.len(10), Constraint.len(10) };
    const header = [_][]const u8{ "Col1", "Col2" };
    const table = Table{
        .rows = &rows,
        .widths = &widths,
        .header = &header,
    };
    table.render(Rect.init(0, 0, 20, 5), &buf);

    // Should render without crash
    try std.testing.expectEqual(@as(u21, 'O'), buf.get(0, 1).char);
}

test "regression: Table respects area height" {
    var buf = try Buffer.init(std.testing.allocator, 20, 2);
    defer buf.deinit();

    const rows = [_][]const []const u8{
        &.{"R1"},
        &.{"R2"},
        &.{"R3"},
        &.{"R4"},
    };
    const widths = [_]Constraint{Constraint.flexible(1)};
    const table = Table{ .rows = &rows, .widths = &widths };
    table.render(Rect.init(0, 0, 20, 2), &buf);

    // Only first 2 rows should be rendered
    try std.testing.expectEqual(@as(u21, 'R'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, '1'), buf.get(1, 0).char);
    try std.testing.expectEqual(@as(u21, 'R'), buf.get(0, 1).char);
    try std.testing.expectEqual(@as(u21, '2'), buf.get(1, 1).char);
}

test "regression: Table with header and limited height" {
    var buf = try Buffer.init(std.testing.allocator, 20, 2);
    defer buf.deinit();

    const rows = [_][]const []const u8{
        &.{"D1"},
        &.{"D2"},
    };
    const header = [_][]const u8{"Hdr"};
    const widths = [_]Constraint{Constraint.flexible(1)};
    const table = Table{
        .rows = &rows,
        .widths = &widths,
        .header = &header,
    };
    table.render(Rect.init(0, 0, 20, 2), &buf);

    // Header takes row 0, only D1 visible at row 1
    try std.testing.expectEqual(@as(u21, 'H'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 'D'), buf.get(0, 1).char);
    try std.testing.expectEqual(@as(u21, '1'), buf.get(1, 1).char);
}
